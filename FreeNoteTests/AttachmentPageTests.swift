import UIKit
import XCTest
@testable import FreeNote

final class AttachmentPageTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeNoteAttachmentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
    }

    func testAttachmentRefDecodesLegacyJSONWithoutPageIndex() throws {
        let id = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        let resourceID = try XCTUnwrap(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let legacyJSON = """
        {"id":"\(id.uuidString)","resourceID":"\(resourceID.uuidString)"}
        """
        let decoded = try JSONDecoder().decode(
            AttachmentRef.self,
            from: Data(legacyJSON.utf8)
        )
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.resourceID, resourceID)
        XCTAssertNil(decoded.pageIndex)

        let newReference = AttachmentRef(resourceID: resourceID, pageIndex: 3)
        let encoded = try JSONEncoder().encode(newReference)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(object["pageIndex"] as? Int, 3)
    }

    @MainActor
    func testPDFSplitInsertsOrderedPagesAndMigratesOutline() async throws {
        let pdfURL = rootURL.appendingPathComponent("three-pages.pdf")
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 320, height: 480),
            format: UIGraphicsPDFRendererFormat()
        )
        let pdfData = renderer.pdfData { context in
            for _ in 0..<3 {
                context.beginPage()
            }
        }
        try pdfData.write(to: pdfURL)

        let store = FreeNoteStore(rootURL: rootURL)
        let imported = await store.importFiles([pdfURL], destination: .library)
        let resourceID = try XCTUnwrap(imported.first?.itemID)
        let pdfPageCount = try await store.attachmentPageCount(resourceID: resourceID)
        XCTAssertEqual(pdfPageCount, 3)
        let pdfPreview = try await store.resourcePreviewHTML(resourceID: resourceID)
        XCTAssertNil(pdfPreview)

        let notebook = try store.createNotebook(title: "PDF 拆页", kind: .paged, paperStyle: .blank)
        try store.addPage(to: notebook.id)
        try store.addPage(to: notebook.id)
        let original = try XCTUnwrap(store.notebooks.first)
        let firstPage = original.pages[0]
        let secondPage = original.pages[1]
        let thirdPage = original.pages[2]
        try store.updateOutline(
            [OutlineNode(title: "全文", startPage: 1, endPage: 3)],
            forNotebookID: notebook.id
        )

        let inserted = try await store.insertAttachmentPages(
            resourceID: resourceID,
            notebookID: notebook.id,
            afterPageID: firstPage.id
        )

        XCTAssertEqual(inserted.count, 3)
        XCTAssertEqual(inserted.map(\.index), [2, 3, 4])
        XCTAssertEqual(inserted.map { $0.attachments.count }, [1, 1, 1])
        XCTAssertEqual(inserted.map { $0.attachments[0].resourceID }, [resourceID, resourceID, resourceID])
        XCTAssertEqual(inserted.map { $0.attachments[0].pageIndex }, [0, 1, 2] as [Int?])

        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertEqual(updated.pages.count, 6)
        XCTAssertEqual(updated.pages.map(\.index), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(updated.pages[0].id, firstPage.id)
        XCTAssertEqual(updated.pages[1].id, inserted[0].id)
        XCTAssertEqual(updated.pages[4].id, secondPage.id)
        XCTAssertEqual(updated.pages[5].id, thirdPage.id)
        XCTAssertNoThrow(try OutlineEditor.validate(updated.outline, pageCount: 6))
        XCTAssertEqual(updated.outline[0].startPage, 1)
        XCTAssertEqual(updated.outline[0].endPage, 6)
        for page in inserted {
            XCTAssertEqual(
                try store.drawingLoadResult(notebookID: notebook.id, pageID: page.id),
                Data()
            )
        }
    }

    @MainActor
    func testPPTXAndEPUBSplitBySlideAndSpineOrder() async throws {
        let pptxURL = rootURL.appendingPathComponent("two-slides.pptx")
        try TestArchiveBuilder.createArchive(
            at: pptxURL,
            entries: [
                "ppt/slides/slide1.xml": slideXML(text: "First Slide"),
                "ppt/slides/slide2.xml": slideXML(text: "Second Slide")
            ]
        )
        let epubURL = rootURL.appendingPathComponent("two-chapters.epub")
        try makeSimpleEPUB(at: epubURL)

        let store = FreeNoteStore(rootURL: rootURL)
        let imported = await store.importFiles([pptxURL, epubURL], destination: .library)
        let pptxResourceID = try XCTUnwrap(imported.first?.itemID)
        let epubResourceID = try XCTUnwrap(imported.last?.itemID)

        let pptxPageCount = try await store.attachmentPageCount(resourceID: pptxResourceID)
        let epubPageCount = try await store.attachmentPageCount(resourceID: epubResourceID)
        XCTAssertEqual(pptxPageCount, 2)
        XCTAssertEqual(epubPageCount, 2)

        let pptxNotebook = try store.createNotebook(title: "PPTX", kind: .paged, paperStyle: .blank)
        let pptxPage = try XCTUnwrap(pptxNotebook.pages.first)
        let pptxInserted = try await store.insertAttachmentPages(
            resourceID: pptxResourceID,
            notebookID: pptxNotebook.id,
            afterPageID: pptxPage.id
        )
        XCTAssertEqual(pptxInserted.flatMap { $0.attachments.map(\.pageIndex) }, [0, 1] as [Int?])

        let epubNotebook = try store.createNotebook(title: "EPUB", kind: .paged, paperStyle: .blank)
        let epubPage = try XCTUnwrap(epubNotebook.pages.first)
        let epubInserted = try await store.insertAttachmentPages(
            resourceID: epubResourceID,
            notebookID: epubNotebook.id,
            afterPageID: epubPage.id
        )
        XCTAssertEqual(epubInserted.flatMap { $0.attachments.map(\.pageIndex) }, [0, 1] as [Int?])
    }

    @MainActor
    func testCurrentPageImageAttachmentUsesWholeResourceThenSinglePageIndex() async throws {
        let imageURL = rootURL.appendingPathComponent("image.png")
        try Data([1, 2, 3]).write(to: imageURL)
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "图片", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)

        let imported = await store.importFiles(
            [imageURL],
            notebookID: notebook.id,
            pageID: page.id
        )
        let resourceID = try XCTUnwrap(imported.first?.itemID)
        let withAttachment = try XCTUnwrap(store.notebooks.first)
        XCTAssertNil(withAttachment.pages[0].attachments[0].pageIndex)
        let imagePageCount = try await store.attachmentPageCount(resourceID: resourceID)
        XCTAssertEqual(imagePageCount, 1)

        let inserted = try await store.insertAttachmentPages(
            resourceID: resourceID,
            notebookID: notebook.id,
            afterPageID: page.id
        )
        XCTAssertEqual(inserted.count, 1)
        XCTAssertEqual(inserted[0].attachments[0].pageIndex, Optional(0))
    }

    private func slideXML(text: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
               xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
          <p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>\(text)</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld>
        </p:sld>
        """
    }

    private func makeSimpleEPUB(at url: URL) throws {
        try TestArchiveBuilder.createArchive(
            at: url,
            entries: [
                "META-INF/container.xml": """
                <?xml version="1.0"?>
                <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
                  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
                </container>
                """,
                "OEBPS/content.opf": """
                <?xml version="1.0"?>
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
                <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
                  <body><nav epub:type="toc"><ol>
                    <li><a href="chapter1.xhtml">Chapter One</a></li>
                    <li><a href="chapter2.xhtml">Chapter Two</a></li>
                  </ol></nav></body>
                </html>
                """,
                "OEBPS/chapter1.xhtml": "<html><body><h1>Chapter One</h1><p>First chapter body.</p></body></html>",
                "OEBPS/chapter2.xhtml": "<html><body><h1>Chapter Two</h1><p>Second chapter body.</p></body></html>"
            ]
        )
    }
}
