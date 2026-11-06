import XCTest
@testable import FreeNote

final class OfficePreviewTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeNotePreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
    }

    @MainActor
    func testDOCXPreviewParsesHeadingsAndParagraphs() async throws {
        let url = rootURL.appendingPathComponent("sample.docx")
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "word/document.xml": """
                <?xml version="1.0" encoding="UTF-8"?>
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:body>
                    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章</w:t></w:r></w:p>
                    <w:p><w:r><w:t>正文 &amp; 内容</w:t></w:r></w:p>
                  </w:body>
                </w:document>
                """
            ]
        )
        let html = try await previewHTML(for: url, name: "sample.docx")
        XCTAssertTrue(html.contains("<h1>第一章</h1>"))
        XCTAssertTrue(html.contains("正文 &amp; 内容"))
    }

    @MainActor
    func testPPTXPreviewUsesSlideNumberOrder() async throws {
        let url = rootURL.appendingPathComponent("sample.pptx")
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "ppt/slides/slide2.xml": slideXML(text: "Second Slide"),
                "ppt/slides/slide1.xml": slideXML(text: "First Slide")
            ]
        )
        let html = try await previewHTML(for: url, name: "sample.pptx")
        let first = try XCTUnwrap(html.range(of: "First Slide"))
        let second = try XCTUnwrap(html.range(of: "Second Slide"))
        XCTAssertLessThan(first.lowerBound, second.lowerBound)
        XCTAssertTrue(html.contains("data-page-index=\"0\""))
        XCTAssertTrue(html.contains("data-page-index=\"1\""))
    }

    @MainActor
    func testXLSXPreviewUsesSharedStringsAndFirstWorksheet() async throws {
        let url = rootURL.appendingPathComponent("sample.xlsx")
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "xl/sharedStrings.xml": """
                <sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <si><t>Name</t></si><si><t>Alice</t></si>
                </sst>
                """,
                "xl/worksheets/sheet1.xml": """
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <sheetData>
                    <row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>
                    <row r="2"><c r="A2"><v>42</v></c></row>
                  </sheetData>
                </worksheet>
                """
            ]
        )
        let html = try await previewHTML(for: url, name: "sample.xlsx")
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("Name"))
        XCTAssertTrue(html.contains("Alice"))
        XCTAssertTrue(html.contains("42"))
    }

    @MainActor
    func testEPUBPreviewReadsSpineAndNavigationTitles() async throws {
        let url = rootURL.appendingPathComponent("sample.epub")
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "META-INF/container.xml": """
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
                </container>
                """,
                "OEBPS/content.opf": """
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                    <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
                </package>
                """,
                "OEBPS/nav.xhtml": """
                <html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
                  <li><a href="chapter1.xhtml">Chapter One</a></li>
                  <li><a href="chapter2.xhtml">Chapter Two</a></li>
                </ol></nav></body></html>
                """,
                "OEBPS/chapter1.xhtml": "<html><body><h1>Chapter One</h1><p>First body.</p></body></html>",
                "OEBPS/chapter2.xhtml": "<html><body><h1>Chapter Two</h1><p>Second body.</p></body></html>"
            ]
        )
        let html = try await previewHTML(for: url, name: "sample.epub")
        XCTAssertTrue(html.contains("Chapter One"))
        XCTAssertTrue(html.contains("Chapter Two"))
        XCTAssertTrue(html.contains("First body."))
        XCTAssertTrue(html.contains("Second body."))
        XCTAssertTrue(html.contains("data-page-index=\"1\""))
    }

    @MainActor
    func testPageIndexedPreviewReturnsOnlyRequestedSlideOrChapterAndRejectsOutOfRange() async throws {
        let pptxURL = rootURL.appendingPathComponent("indexed.pptx")
        try TestArchiveBuilder.createArchive(
            at: pptxURL,
            entries: [
                "ppt/slides/slide1.xml": slideXML(text: "First Slide"),
                "ppt/slides/slide2.xml": slideXML(text: "Second Slide")
            ]
        )
        let epubURL = rootURL.appendingPathComponent("indexed.epub")
        try makeSimpleEPUB(at: epubURL)

        let store = FreeNoteStore(rootURL: rootURL)
        let imported = await store.importFiles([pptxURL, epubURL], destination: .library)
        let pptxID = try XCTUnwrap(imported.first?.itemID)
        let epubID = try XCTUnwrap(imported.last?.itemID)

        let firstSlide = try await store.resourcePreviewHTML(resourceID: pptxID, pageIndex: 0)
        XCTAssertTrue(firstSlide?.contains("First Slide") == true)
        XCTAssertFalse(firstSlide?.contains("Second Slide") == true)
        XCTAssertTrue(firstSlide?.contains("data-page-index=\"0\"") == true)

        let secondSlide = try await store.resourcePreviewHTML(resourceID: pptxID, pageIndex: 1)
        XCTAssertTrue(secondSlide?.contains("Second Slide") == true)
        XCTAssertFalse(secondSlide?.contains("First Slide") == true)
        XCTAssertTrue(secondSlide?.contains("data-page-index=\"1\"") == true)

        let firstChapter = try await store.resourcePreviewHTML(resourceID: epubID, pageIndex: 0)
        XCTAssertTrue(firstChapter?.contains("Chapter One") == true)
        XCTAssertFalse(firstChapter?.contains("Chapter Two") == true)
        XCTAssertTrue(firstChapter?.contains("data-page-index=\"0\"") == true)

        let secondChapter = try await store.resourcePreviewHTML(resourceID: epubID, pageIndex: 1)
        XCTAssertTrue(secondChapter?.contains("Chapter Two") == true)
        XCTAssertFalse(secondChapter?.contains("Chapter One") == true)

        do {
            _ = try await store.resourcePreviewHTML(resourceID: pptxID, pageIndex: 2)
            XCTFail("PPTX 越界页码应抛错")
        } catch {}
        do {
            _ = try await store.resourcePreviewHTML(resourceID: epubID, pageIndex: 2)
            XCTFail("EPUB 越界页码应抛错")
        } catch {}
    }

    @MainActor
    func testDOCXAndXLSXPageIndexOnlySupportsZero() async throws {
        let docxURL = rootURL.appendingPathComponent("single.docx")
        try TestArchiveBuilder.createArchive(
            at: docxURL,
            entries: [
                "word/document.xml": """
                <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
                  <w:body><w:p><w:r><w:t>单页文档</w:t></w:r></w:p></w:body>
                </w:document>
                """
            ]
        )
        let xlsxURL = rootURL.appendingPathComponent("single.xlsx")
        try TestArchiveBuilder.createArchive(
            at: xlsxURL,
            entries: [
                "xl/worksheets/sheet1.xml": """
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <sheetData><row r="1"><c r="A1"><v>7</v></c></row></sheetData>
                </worksheet>
                """
            ]
        )

        let store = FreeNoteStore(rootURL: rootURL)
        let imported = await store.importFiles([docxURL, xlsxURL], destination: .library)
        let docxID = try XCTUnwrap(imported.first?.itemID)
        let xlsxID = try XCTUnwrap(imported.last?.itemID)

        let docxHTML = try await store.resourcePreviewHTML(resourceID: docxID, pageIndex: 0)
        XCTAssertTrue(docxHTML?.contains("单页文档") == true)
        XCTAssertTrue(docxHTML?.contains("data-page-index=\"0\"") == true)
        let xlsxHTML = try await store.resourcePreviewHTML(resourceID: xlsxID, pageIndex: 0)
        XCTAssertTrue(xlsxHTML?.contains("<table>") == true)
        XCTAssertTrue(xlsxHTML?.contains("data-page-index=\"0\"") == true)

        do {
            _ = try await store.resourcePreviewHTML(resourceID: docxID, pageIndex: 1)
            XCTFail("DOCX 只有一个逻辑页，索引 1 应失败")
        } catch {}
        do {
            _ = try await store.resourcePreviewHTML(resourceID: xlsxID, pageIndex: 1)
            XCTFail("XLSX 只有一个逻辑页，索引 1 应失败")
        } catch {}
    }

    @MainActor
    func testLegacyOfficePreviewEitherRendersTextOrReturnsExplicitUnsupportedError() async throws {
        let url = rootURL.appendingPathComponent("legacy.doc")
        try Data("{\\rtf1\\ansi Legacy Office Text}".utf8).write(to: url)
        let store = FreeNoteStore(rootURL: rootURL)
        let results = await store.importFiles([url], destination: .library)
        let resourceID = try XCTUnwrap(results.first?.itemID)

        do {
            let html = try await store.resourcePreviewHTML(resourceID: resourceID)
            XCTAssertTrue(html?.contains("Legacy Office Text") == true)
        } catch let error as FreeNoteError {
            guard case .unsupportedPreview("legacy.doc") = error else {
                XCTFail("旧 Office 预览失败时应返回明确的 unsupportedPreview")
                return
            }
        }
    }

    @MainActor
    private func previewHTML(for url: URL, name: String) async throws -> String {
        let store = FreeNoteStore(rootURL: rootURL)
        let results = await store.importFiles([url], destination: .library)
        let resourceID = try XCTUnwrap(results.first?.itemID)
        XCTAssertEqual(store.resources.first?.fileName, name)
        let html = try await store.resourcePreviewHTML(resourceID: resourceID)
        return try XCTUnwrap(html)
    }

    private func makeSimpleEPUB(at url: URL) throws {
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "META-INF/container.xml": """
                <container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>
                </container>
                """,
                "OEBPS/content.opf": """
                <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
                  <manifest>
                    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                    <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                    <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
                  </manifest>
                  <spine><itemref idref="c1"/><itemref idref="c2"/></spine>
                </package>
                """,
                "OEBPS/nav.xhtml": """
                <html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
                  <li><a href="chapter1.xhtml">Chapter One</a></li>
                  <li><a href="chapter2.xhtml">Chapter Two</a></li>
                </ol></nav></body></html>
                """,
                "OEBPS/chapter1.xhtml": "<html><body><h1>Chapter One</h1><p>First body.</p></body></html>",
                "OEBPS/chapter2.xhtml": "<html><body><h1>Chapter Two</h1><p>Second body.</p></body></html>"
            ]
        )
    }

    private func slideXML(text: String) -> String {
        """
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>\(text)</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
        </p:sld>
        """
    }
}
