import XCTest
@testable import FreeNote

final class BatchImportTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeNoteBatchTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
    }

    @MainActor
    func testLibraryBatchKeepsOneResultPerURLAndDoesNotRollbackSuccesses() async throws {
        let first = try makeFile(name: "first.txt", contents: Data("first".utf8))
        let third = try makeFile(name: "third.txt", contents: Data("third".utf8))
        let fourth = try makeFile(name: "fourth.txt", contents: Data("fourth".utf8))
        let missing = rootURL.appendingPathComponent("missing.txt")

        let store = FreeNoteStore(rootURL: rootURL)
        let results = await store.importFiles(
            [first, missing, third, fourth],
            destination: .library
        )

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.map(\.title), ["first", "missing", "third", "fourth"])
        XCTAssertEqual(results.map(\.success), [true, false, true, true])
        XCTAssertNil(results[1].itemID)
        XCTAssertNotNil(results[1].errorMessage)

        XCTAssertEqual(store.resources.map(\.title), ["first", "third", "fourth"])
        let successfulIDs = results.compactMap { $0.success ? $0.itemID : nil }
        XCTAssertEqual(successfulIDs.count, 3)
        XCTAssertEqual(Set(successfulIDs).count, 3)
        for resource in store.resources {
            XCTAssertNotNil(store.storedURL(for: resource))
        }

        let libraryEntries = try FileManager.default.contentsOfDirectory(
            at: rootURL.appendingPathComponent("Library", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(libraryEntries.count, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: third.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fourth.path))
    }

    @MainActor
    func testBookshelfBatchKeepsSuccessfulFilesWhenOneDocumentFails() async throws {
        let firstBook = try makeFile(name: "book-a.txt", contents: Data("A".utf8))
        let invalidPDF = try makeFile(name: "broken.pdf", contents: Data("not a pdf".utf8))
        let secondBook = try makeFile(name: "book-b.txt", contents: Data("B".utf8))

        let store = FreeNoteStore(rootURL: rootURL)
        let results = await store.importFiles(
            [firstBook, invalidPDF, secondBook],
            destination: .bookshelf
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map(\.success), [true, false, true])
        XCTAssertEqual(store.books.map(\.title), ["book-a", "book-b"])
        XCTAssertTrue(store.books.allSatisfy { $0.pageCount >= 1 && !$0.outline.isEmpty })
        XCTAssertNotNil(results[1].warningMessage)
        XCTAssertNil(results[1].itemID)
    }

    @MainActor
    func testCurrentPageBatchAttachesSuccessfulFilesToSamePageInInputOrder() async throws {
        let first = try makeFile(name: "first.png", contents: Data([1]))
        let second = try makeFile(name: "second.jpg", contents: Data([2]))
        let third = try makeFile(name: "third.heic", contents: Data([3]))
        let missing = rootURL.appendingPathComponent("missing.png")

        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "多附件", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)
        let inputOrder = [third, missing, first, second]
        let results = await store.importFiles(
            inputOrder,
            notebookID: notebook.id,
            pageID: page.id
        )

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(results.map(\.title), ["third", "missing", "first", "second"])
        XCTAssertEqual(results.map(\.success), [true, false, true, true])
        let resultIDs = results.compactMap(\.itemID)
        XCTAssertEqual(resultIDs.count, 3)
        XCTAssertEqual(store.resources.map(\.id), resultIDs)

        let attachments = try store.attachments(forNotebookID: notebook.id, pageID: page.id)
        XCTAssertEqual(attachments.map(\.id), resultIDs)
        XCTAssertEqual(attachments.map(\.title), ["third", "first", "second"])
        XCTAssertTrue(
            results.filter { $0.success }.allSatisfy {
                $0.destination == .currentPage
                    && $0.notebookID == notebook.id
                    && $0.pageID == page.id
            }
        )
    }

    @MainActor
    func testOfficeDocumentsImportAsResourcesInsteadOfFallingBackToOther() async throws {
        let files = [
            try makeFile(name: "sheet.xlsx", contents: Data([1])),
            try makeFile(name: "legacy.xls", contents: Data([2])),
            try makeFile(name: "report.docx", contents: Data([3])),
            try makeFile(name: "slides.pptx", contents: Data([4])),
            try makeFile(name: "table.csv", contents: Data("a,b".utf8))
        ]
        let store = FreeNoteStore(rootURL: rootURL)
        let results = await store.importFiles(files, destination: .library)

        XCTAssertEqual(results.count, files.count)
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertEqual(
            results.map(\.kind),
            [.office, .office, .office, .office, .text]
        )
        XCTAssertFalse(store.resources.contains { $0.kind == .other })
        XCTAssertEqual(store.resources.map(\.kind), [.office, .office, .office, .office, .text])
    }

    private func makeFile(name: String, contents: Data) throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}
