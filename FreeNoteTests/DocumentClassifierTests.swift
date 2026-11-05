import XCTest
@testable import FreeNote

final class DocumentClassifierTests: XCTestCase {
    func testOfficeSpreadsheetAndPresentationExtensions() {
        let officeExtensions = [
            "xls", "xlsx", "doc", "docx", "ppt", "pptx"
        ]
        for fileExtension in officeExtensions {
            let url = URL(fileURLWithPath: "/tmp/sample.\(fileExtension)")
            XCTAssertEqual(
                DocumentClassifier.kind(for: url),
                .office,
                "应识别为 Office：\(fileExtension)"
            )
        }
    }

    func testCSVIsTextAndRemainsImportable() {
        let csv = URL(fileURLWithPath: "/tmp/table.csv")
        XCTAssertEqual(DocumentClassifier.kind(for: csv), .text)
        XCTAssertEqual(DocumentClassifier.suggestedDestination(for: csv), .library)
        XCTAssertFalse(DocumentClassifier.isBookLike(csv))
    }

    func testDocumentPdfEpubImageAudioAndTextClassification() {
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.pdf")), .pdf)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.epub")), .epub)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.jpg")), .image)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.heic")), .image)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.m4a")), .audio)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.txt")), .text)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.md")), .text)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/a.bin")), .other)
    }

    func testCaseInsensitiveExtensionsAndSuggestedDestinations() {
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/A.XLSX")), .office)
        XCTAssertEqual(DocumentClassifier.kind(for: URL(fileURLWithPath: "/tmp/A.PDF")), .pdf)
        XCTAssertEqual(
            DocumentClassifier.suggestedDestination(for: URL(fileURLWithPath: "/tmp/a.pptx")),
            .bookshelf
        )
        XCTAssertEqual(
            DocumentClassifier.suggestedDestination(for: URL(fileURLWithPath: "/tmp/a.docx")),
            .library
        )
        XCTAssertEqual(
            DocumentClassifier.suggestedDestination(for: URL(fileURLWithPath: "/tmp/a.xlsx")),
            .library
        )
        XCTAssertTrue(DocumentClassifier.isBookLike(URL(fileURLWithPath: "/tmp/a.epub")))
        XCTAssertFalse(DocumentClassifier.isBookLike(URL(fileURLWithPath: "/tmp/a.xlsx")))
    }
}
