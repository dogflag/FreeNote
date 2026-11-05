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

    @MainActor
    func testMultiDestinationImportsSameURLsIndependentlyIntoLibraryAndBookshelf() async throws {
        let first = try makeFile(name: "multi-first.txt", contents: Data("first".utf8))
        let second = try makeFile(name: "multi-second.txt", contents: Data("second".utf8))
        let store = FreeNoteStore(rootURL: rootURL)

        let results = await store.importFiles(
            [first, second],
            destinations: [.library, .bookshelf]
        )

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(
            results.map(\.destination),
            [.bookshelf, .bookshelf, .library, .library]
        )
        XCTAssertEqual(
            results.map(\.title),
            ["multi-first", "multi-second", "multi-first", "multi-second"]
        )
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertEqual(store.books.map(\.title), ["multi-first", "multi-second"])
        XCTAssertEqual(store.resources.map(\.title), ["multi-first", "multi-second"])

        let itemIDs = results.compactMap(\.itemID)
        XCTAssertEqual(itemIDs.count, 4)
        XCTAssertEqual(Set(itemIDs).count, 4)
    }

    @MainActor
    func testMultiDestinationWithCurrentPageBindsOnlyCurrentPageResults() async throws {
        let first = try makeFile(name: "all-first.png", contents: Data([11]))
        let second = try makeFile(name: "all-second.png", contents: Data([22]))
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "三目的地", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)

        let results = await store.importFiles(
            [first, second],
            destinations: [.library, .bookshelf, .currentPage],
            notebookID: notebook.id,
            pageID: page.id
        )

        XCTAssertEqual(results.count, 6)
        XCTAssertEqual(
            results.map(\.destination),
            [
                .bookshelf, .bookshelf,
                .library, .library,
                .currentPage, .currentPage
            ]
        )
        XCTAssertTrue(results.allSatisfy { $0.success })
        XCTAssertEqual(store.books.count, 2)
        XCTAssertEqual(store.resources.count, 4)

        let currentPageResults = results.filter { $0.destination == .currentPage }
        let currentPageIDs = currentPageResults.compactMap(\.itemID)
        XCTAssertEqual(currentPageIDs.count, 2)
        let attachments = try store.attachments(forNotebookID: notebook.id, pageID: page.id)
        XCTAssertEqual(attachments.map(\.id), currentPageIDs)
        XCTAssertTrue(
            currentPageResults.allSatisfy {
                $0.notebookID == notebook.id && $0.pageID == page.id
            }
        )

        let allItemIDs = results.compactMap(\.itemID)
        XCTAssertEqual(allItemIDs.count, 6)
        XCTAssertEqual(Set(allItemIDs).count, 6)
    }

    @MainActor
    func testMissingCurrentPageContextFailsOnlyCurrentPageDestination() async throws {
        let first = try makeFile(name: "context-first.txt", contents: Data("first".utf8))
        let second = try makeFile(name: "context-second.txt", contents: Data("second".utf8))
        let store = FreeNoteStore(rootURL: rootURL)

        let results = await store.importFiles(
            [first, second],
            destinations: [.library, .currentPage]
        )

        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(
            results.map(\.destination),
            [.library, .library, .currentPage, .currentPage]
        )
        XCTAssertEqual(results.map(\.success), [true, true, false, false])
        XCTAssertEqual(store.resources.count, 2)
        XCTAssertTrue(store.books.isEmpty)

        let currentPageResults = results.filter { $0.destination == .currentPage }
        XCTAssertTrue(currentPageResults.allSatisfy { $0.itemID == nil })
        XCTAssertTrue(currentPageResults.allSatisfy { $0.errorMessage != nil })
    }

    @MainActor
    func testPartialFileFailureIsScopedToEachDestination() async throws {
        let first = try makeFile(name: "scope-first.txt", contents: Data("first".utf8))
        let invalidPDF = try makeFile(name: "scope-broken.pdf", contents: Data("bad".utf8))
        let second = try makeFile(name: "scope-second.txt", contents: Data("second".utf8))
        let store = FreeNoteStore(rootURL: rootURL)

        let results = await store.importFiles(
            [first, invalidPDF, second],
            destinations: [.library, .bookshelf]
        )

        XCTAssertEqual(results.count, 6)
        XCTAssertEqual(
            results.map(\.destination),
            [
                .bookshelf, .bookshelf, .bookshelf,
                .library, .library, .library
            ]
        )
        XCTAssertEqual(
            results.map(\.success),
            [true, false, true, true, true, true]
        )
        XCTAssertEqual(store.books.map(\.title), ["scope-first", "scope-second"])
        XCTAssertEqual(
            store.resources.map(\.title),
            ["scope-first", "scope-broken", "scope-second"]
        )
        XCTAssertNil(results[1].itemID)
        XCTAssertNotNil(results[1].errorMessage)
    }

    @MainActor
    func testFinalMetadataWriteFailureRollsBackCopiedFile() async throws {
        let source = try makeFile(name: "rollback.txt", contents: Data("rollback".utf8))
        let store = FreeNoteStore(rootURL: rootURL)
        let storeURL = rootURL.appendingPathComponent("store.json")
        try FileManager.default.removeItem(at: storeURL)
        try FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: false)

        let results = await store.importFiles([source], destinations: [.library])

        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].success)
        XCTAssertTrue(store.resources.isEmpty)
        let libraryEntries = try FileManager.default.contentsOfDirectory(
            at: rootURL.appendingPathComponent("Library", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(libraryEntries.isEmpty)
    }

    private func makeFile(name: String, contents: Data) throws -> URL {
        let url = rootURL.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }
}
