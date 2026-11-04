import UIKit
import XCTest
@testable import FreeNote

final class FreeNoteStoreTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeNoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
    }

    @MainActor
    func testNotebookPageLifecycleAndDrawingPersistence() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(
            title: "测试笔记",
            kind: .paged,
            paperStyle: .dotted
        )
        let firstPage = try XCTUnwrap(notebook.pages.first)
        XCTAssertEqual(firstPage.index, 1)

        try store.saveDrawing(Data([0, 1, 2, 3, 4]), pageID: firstPage.id, notebookID: notebook.id)
        XCTAssertEqual(
            try store.drawingData(notebookID: notebook.id, pageID: firstPage.id),
            Data([0, 1, 2, 3, 4])
        )

        try store.addPage(to: notebook.id)
        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertEqual(updated.pages.map(\.index), [1, 2])

        try store.deletePages(notebookID: notebook.id, pageIDs: [updated.pages[0].id])
        let afterDeletion = try XCTUnwrap(store.notebooks.first)
        XCTAssertEqual(afterDeletion.pages.count, 1)
        XCTAssertEqual(afterDeletion.pages[0].index, 1)
    }

    @MainActor
    func testDeletingPageRemapsOutlineToExistingPagesOnly() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "大纲", kind: .paged, paperStyle: .blank)
        try store.addPage(to: notebook.id)
        try store.addPage(to: notebook.id)
        let original = try XCTUnwrap(store.notebooks.first)
        let chapter = OutlineNode(
            title: "全部",
            startPage: 1,
            endPage: 3,
            children: [
                OutlineNode(title: "第一部分", startPage: 1, endPage: 2),
                OutlineNode(title: "第二部分", startPage: 3, endPage: 3)
            ]
        )
        try store.updateOutline([chapter], forNotebookID: notebook.id)

        try store.deletePages(notebookID: notebook.id, pageIDs: [original.pages[1].id])
        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertEqual(updated.pages.map(\.index), [1, 2])
        XCTAssertNoThrow(try OutlineEditor.validate(updated.outline, pageCount: 2))
        XCTAssertEqual(updated.outline[0].startPage, 1)
        XCTAssertEqual(updated.outline[0].endPage, 2)
        XCTAssertEqual(updated.outline[0].children[1].startPage, 2)
        XCTAssertEqual(updated.outline[0].children[1].endPage, 2)
    }

    @MainActor
    func testRejectsEmptyNotebookSnapshotAndSupportsFieldUpdates() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "旧标题", kind: .paged, paperStyle: .blank)

        var emptySnapshot = notebook
        emptySnapshot.pages = []
        XCTAssertThrowsError(try store.updateNotebook(emptySnapshot))

        try store.renameNotebook(id: notebook.id, title: "新标题")
        try store.setNotebookPaperStyle(id: notebook.id, style: .grid)
        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertEqual(updated.title, "新标题")
        XCTAssertEqual(updated.paperStyle, .grid)
        XCTAssertEqual(updated.pages.count, 1)
    }

    @MainActor
    func testDrawingLoadResultDistinguishesMissingAndEmptyCanvas() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "文件", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)
        try store.saveDrawing(Data(), pageID: page.id, notebookID: notebook.id)
        let emptyCanvas = try store.drawingLoadResult(notebookID: notebook.id, pageID: page.id)
        XCTAssertEqual(emptyCanvas, Data())

        let drawingURL = rootURL
            .appendingPathComponent("Notebooks", isDirectory: true)
            .appendingPathComponent(notebook.id.uuidString, isDirectory: true)
            .appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent("\(page.id.uuidString).drawing")
        try FileManager.default.removeItem(at: drawingURL)

        let missingCanvas = try store.drawingLoadResult(notebookID: notebook.id, pageID: page.id)
        XCTAssertNil(missingCanvas)
        XCTAssertThrowsError(try store.drawingData(notebookID: notebook.id, pageID: page.id))
    }

    @MainActor
    func testDrawingIsStoredOutsideMetadataAndReloads() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "文件", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)
        let drawing = Data(repeating: 0x7A, count: 4_096)
        try store.saveDrawing(drawing, pageID: page.id, notebookID: notebook.id)

        let metadataURL = rootURL.appendingPathComponent("store.json")
        let metadata = try Data(contentsOf: metadataURL)
        let metadataText = String(decoding: metadata, as: UTF8.self)
        XCTAssertFalse(metadataText.contains(drawing.base64EncodedString()))

        let reloaded = FreeNoteStore(rootURL: rootURL)
        XCTAssertEqual(
            try reloaded.drawingData(notebookID: notebook.id, pageID: page.id),
            drawing
        )
    }

    @MainActor
    func testSettingsPersist() throws {
        let store = FreeNoteStore(rootURL: rootURL)
        store.settings.fontSize = 28
        store.settings.readingFont = .serif
        try store.saveSettings()

        let reloaded = FreeNoteStore(rootURL: rootURL)
        XCTAssertEqual(reloaded.settings.fontSize, 28)
        XCTAssertEqual(reloaded.settings.readingFont, .serif)
    }

    @MainActor
    func testLibraryImportCopiesFileAndSupportsMoveAndAnnotation() async throws {
        let sourceURL = rootURL.appendingPathComponent("source.txt")
        try Data("hello".utf8).write(to: sourceURL)
        let store = FreeNoteStore(rootURL: rootURL)

        let results = await store.importFiles([sourceURL], destination: .library)
        let result = try XCTUnwrap(results.first)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.destination, .library)
        let resourceID = try XCTUnwrap(result.itemID)
        let resource = try XCTUnwrap(store.resources.first { $0.id == resourceID })
        let storedURL = try XCTUnwrap(store.storedURL(for: resource))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))

        try store.moveResource(id: resourceID, to: .bookshelf)
        let book = try XCTUnwrap(store.books.first)
        XCTAssertEqual(book.pageCount, 1)
        let annotation = Data([9, 8, 7])
        try store.saveAnnotation(annotation, bookID: book.id, pageIndex: 1)
        XCTAssertEqual(try store.annotationData(bookID: book.id, pageIndex: 1), annotation)
    }

    @MainActor
    func testCurrentPageImportAndAttachmentLifecycle() async throws {
        let sourceURL = rootURL.appendingPathComponent("photo.png")
        try Data([1, 2, 3]).write(to: sourceURL)
        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "附件", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)

        let results = await store.importFiles(
            [sourceURL],
            notebookID: notebook.id,
            pageID: page.id
        )
        let result = try XCTUnwrap(results.first)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.destination, .currentPage)
        XCTAssertEqual(result.notebookID, notebook.id)
        XCTAssertEqual(result.pageID, page.id)
        let resourceID = try XCTUnwrap(result.itemID)

        XCTAssertEqual(
            try store.attachments(forNotebookID: notebook.id, pageID: page.id).map(\.id),
            [resourceID]
        )
        try store.detachResource(resourceID: resourceID, notebookID: notebook.id, pageID: page.id)
        XCTAssertTrue(
            try store.attachments(forNotebookID: notebook.id, pageID: page.id).isEmpty
        )

        try store.attachResource(resourceID, toNotebookID: notebook.id, pageID: page.id)
        try store.deleteResources(ids: [resourceID])
        XCTAssertTrue(store.resources.isEmpty)
        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertTrue(updated.pages[0].attachments.isEmpty)
    }

    @MainActor
    func testMoveResourceUsesRealDocumentPageCountAndDetachesReferences() async throws {
        let pdfURL = rootURL.appendingPathComponent("two-pages.pdf")
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: 320, height: 480),
            format: format
        )
        let pdfData = renderer.pdfData { context in
            context.beginPage()
            context.beginPage()
        }
        try pdfData.write(to: pdfURL)

        let store = FreeNoteStore(rootURL: rootURL)
        let notebook = try store.createNotebook(title: "引用", kind: .paged, paperStyle: .blank)
        let page = try XCTUnwrap(notebook.pages.first)
        let libraryResults = await store.importFiles([pdfURL], destination: .library)
        let resourceID = try XCTUnwrap(libraryResults.first?.itemID)
        try store.attachResource(resourceID, toNotebookID: notebook.id, pageID: page.id)

        let beforeMoveResources = store.resources
        let beforeMoveBooks = store.books
        try store.moveResource(id: resourceID, to: .bookshelf)
        let book = try XCTUnwrap(store.books.first)
        XCTAssertEqual(book.pageCount, 2)
        XCTAssertEqual(book.outline.count, 2)
        XCTAssertTrue(store.resources.isEmpty)
        XCTAssertFalse(store.books == beforeMoveBooks)

        let updated = try XCTUnwrap(store.notebooks.first)
        XCTAssertTrue(updated.pages[0].attachments.isEmpty)
        XCTAssertFalse(beforeMoveResources.isEmpty)
    }

    @MainActor
    func testZeroPageBookImportIsRejected() async throws {
        let invalidPDF = rootURL.appendingPathComponent("invalid.pdf")
        try Data("not a pdf".utf8).write(to: invalidPDF)
        let store = FreeNoteStore(rootURL: rootURL)

        let results = await store.importFiles([invalidPDF], destination: .bookshelf)
        let result = try XCTUnwrap(results.first)
        XCTAssertFalse(result.success)
        XCTAssertNil(result.itemID)
        XCTAssertNotNil(result.errorMessage)
        XCTAssertNotNil(result.warningMessage)
        XCTAssertTrue(store.books.isEmpty)
    }
}
