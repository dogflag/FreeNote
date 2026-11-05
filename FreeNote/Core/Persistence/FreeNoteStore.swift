import Combine
import Foundation

@MainActor
final class FreeNoteStore: ObservableObject {
    static let shared = FreeNoteStore()

    @Published private(set) var notebooks: [Notebook]
    @Published private(set) var books: [BookItem]
    @Published private(set) var resources: [ResourceItem]
    @Published var settings: AppSettings
    @Published private(set) var recoveryIssues: [RecoveryIssue]

    let rootURL: URL

    private let fileManager: FileManager

    private var storeURL: URL {
        rootURL.appendingPathComponent("store.json")
    }

    private var notebooksDirectory: URL {
        rootURL.appendingPathComponent("Notebooks", isDirectory: true)
    }

    private var libraryDirectory: URL {
        rootURL.appendingPathComponent("Library", isDirectory: true)
    }

    private var annotationsDirectory: URL {
        rootURL.appendingPathComponent("Annotations", isDirectory: true)
    }

    private var backupsDirectory: URL {
        rootURL.appendingPathComponent("Backups", isDirectory: true)
    }

    private var stagingDirectory: URL {
        rootURL.appendingPathComponent("ImportStaging", isDirectory: true)
    }

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.notebooks = []
        self.books = []
        self.resources = []
        self.settings = .defaultValue
        self.recoveryIssues = []

        var startupIssue: String?
        if let rootURL {
            self.rootURL = rootURL.standardizedFileURL
        } else {
            do {
                let applicationSupport = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
                self.rootURL = applicationSupport
                    .appendingPathComponent("FreeNote", isDirectory: true)
            } catch {
                self.rootURL = fileManager.temporaryDirectory
                    .appendingPathComponent("FreeNote", isDirectory: true)
                startupIssue = "无法访问 Application Support，已使用临时目录：\(error.localizedDescription)"
            }
        }

        do {
            try prepareDirectories()
            try loadState()
            if !fileManager.fileExists(atPath: storeURL.path) {
                try writeState(
                    notebooks: notebooks,
                    books: books,
                    resources: resources,
                    settings: settings
                )
            }
        } catch {
            recordRecoveryIssue("初始化本地存储失败：\(friendlyMessage(for: error))")
        }
        if let startupIssue {
            recordRecoveryIssue(startupIssue)
        }
    }

    func clearRecoveryIssues() {
        recoveryIssues.removeAll()
    }

    func reportRecoveryIssue(_ message: String) {
        recordRecoveryIssue(message)
    }

    // MARK: - Notebook lifecycle

    func createNotebook(
        title: String,
        kind: NotebookKind,
        paperStyle: PaperStyle
    ) throws -> Notebook {
        let now = Date()
        let page = NotePage(index: 1)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notebook = Notebook(
            title: trimmedTitle.isEmpty ? "未命名笔记" : trimmedTitle,
            kind: kind,
            paperStyle: paperStyle,
            pages: [page],
            createdAt: now,
            updatedAt: now
        )

        do {
            try ensureNotebookDirectories(for: notebook.id)
            try writeDrawing(Data(), notebookID: notebook.id, pageID: page.id)
            var updatedNotebooks = notebooks
            updatedNotebooks.append(notebook)
            try commit(
                notebooks: updatedNotebooks,
                books: books,
                resources: resources,
                settings: settings
            )
            return notebook
        } catch {
            try? fileManager.removeItem(at: notebookDirectory(for: notebook.id))
            throw error
        }
    }

    func deleteNotebook(id: UUID) throws {
        guard notebooks.contains(where: { $0.id == id }) else {
            throw FreeNoteError.notebookNotFound(id)
        }
        let remaining = notebooks.filter { $0.id != id }
        try commit(notebooks: remaining, books: books, resources: resources, settings: settings)
        removeItemBestEffort(at: notebookDirectory(for: id), context: "删除笔记目录")
    }

    func updateNotebook(_ notebook: Notebook) throws {
        guard let existingIndex = notebooks.firstIndex(where: { $0.id == notebook.id }) else {
            throw FreeNoteError.notebookNotFound(notebook.id)
        }
        var normalized = notebook
        try normalizeAndValidateNotebook(&normalized)
        normalized.updatedAt = Date()

        do {
            try ensureNotebookDirectories(for: normalized.id)
            let existingPageIDs = Set(notebooks[existingIndex].pages.map(\.id))
            for page in normalized.pages where !existingPageIDs.contains(page.id) {
                let url = drawingURL(notebookID: normalized.id, pageID: page.id)
                if !fileManager.fileExists(atPath: url.path) {
                    try writeDrawing(Data(), notebookID: normalized.id, pageID: page.id)
                }
            }
            var updatedNotebooks = notebooks
            updatedNotebooks[existingIndex] = normalized
            try commit(
                notebooks: updatedNotebooks,
                books: books,
                resources: resources,
                settings: settings
            )
            removeOrphanDrawings(
                notebookID: normalized.id,
                validPageIDs: Set(normalized.pages.map(\.id))
            )
        } catch {
            throw error
        }
    }

    func renameNotebook(id: UUID, title: String) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else {
            throw FreeNoteError.notebookNotFound(id)
        }
        var notebook = notebooks[index]
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        notebook.title = trimmed.isEmpty ? "未命名笔记" : trimmed
        notebook.updatedAt = Date()
        var updatedNotebooks = notebooks
        updatedNotebooks[index] = notebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )
    }

    func setNotebookPaperStyle(id: UUID, style: PaperStyle) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else {
            throw FreeNoteError.notebookNotFound(id)
        }
        var notebook = notebooks[index]
        notebook.paperStyle = style
        notebook.updatedAt = Date()
        var updatedNotebooks = notebooks
        updatedNotebooks[index] = notebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )
    }

    func updateBook(_ book: BookItem) throws {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else {
            throw FreeNoteError.bookNotFound(book.id)
        }
        guard book.pageCount >= 1 else {
            throw FreeNoteError.documentHasNoReadablePages(book.fileName)
        }
        var normalized = book
        normalized.fileName = books[index].fileName
        normalized.currentPage = min(max(normalized.currentPage, 1), normalized.pageCount)
        try OutlineEditor.validate(normalized.outline, pageCount: normalized.pageCount)
        var updatedBooks = books
        updatedBooks[index] = normalized
        try commit(notebooks: notebooks, books: updatedBooks, resources: resources, settings: settings)
    }

    func updateResource(_ resource: ResourceItem) throws {
        guard let index = resources.firstIndex(where: { $0.id == resource.id }) else {
            throw FreeNoteError.resourceNotFound(resource.id)
        }
        var normalized = resource
        normalized.fileName = resources[index].fileName
        var updatedResources = resources
        updatedResources[index] = normalized
        try commit(notebooks: notebooks, books: books, resources: updatedResources, settings: settings)
    }

    func addPage(to notebookID: UUID) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        var notebook = notebooks[index]
        let page = NotePage(index: notebook.pages.count + 1)
        do {
            try writeDrawing(Data(), notebookID: notebookID, pageID: page.id)
            notebook.pages.append(page)
            notebook.updatedAt = Date()
            var updatedNotebooks = notebooks
            updatedNotebooks[index] = notebook
            try commit(
                notebooks: updatedNotebooks,
                books: books,
                resources: resources,
                settings: settings
            )
        } catch {
            try? fileManager.removeItem(at: drawingURL(notebookID: notebookID, pageID: page.id))
            throw error
        }
    }

    func deletePages(notebookID: UUID, pageIDs: Set<UUID>) throws {
        guard !pageIDs.isEmpty else {
            return
        }
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        let notebook = notebooks[notebookIndex]
        let oldPageIDs = notebook.pages.map(\.id)
        let deletedPageIDs = Set(oldPageIDs.filter { pageIDs.contains($0) })
        guard !deletedPageIDs.isEmpty else {
            return
        }
        let remainingPages = notebook.pages.filter { !deletedPageIDs.contains($0.id) }
        guard !remainingPages.isEmpty else {
            throw FreeNoteError.cannotDeleteLastPage(notebookID)
        }

        try OutlineEditor.validate(notebook.outline, pageCount: oldPageIDs.count)
        let remainingPageIDs = remainingPages.map(\.id)
        let remappedOutline = try OutlineEditor.remapPageRanges(
            notebook.outline,
            oldPageIDs: oldPageIDs,
            newPageIDs: remainingPageIDs
        )
        var normalizedPages = remainingPages.enumerated().map { offset, page in
            var copy = page
            copy.index = offset + 1
            return copy
        }
        var updatedNotebook = notebook
        updatedNotebook.pages = normalizedPages
        updatedNotebook.outline = remappedOutline
        updatedNotebook.updatedAt = Date()
        try normalizeAndValidateNotebook(&updatedNotebook)
        normalizedPages = updatedNotebook.pages

        var updatedNotebooks = notebooks
        updatedNotebooks[notebookIndex] = updatedNotebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )

        for pageID in deletedPageIDs {
            removeItemBestEffort(
                at: drawingURL(notebookID: notebookID, pageID: pageID),
                context: "删除页面笔迹"
            )
        }
    }

    func drawingLoadResult(notebookID: UUID, pageID: UUID) throws -> Data? {
        guard let notebook = notebooks.first(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        guard notebook.pages.contains(where: { $0.id == pageID }) else {
            throw FreeNoteError.pageNotFound(pageID)
        }
        let url = drawingURL(notebookID: notebookID, pageID: pageID)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            recordRecoveryIssue("无法读取页面 \(pageID.uuidString) 的手写文件：\(error.localizedDescription)")
            throw FreeNoteError.fileOperationFailed(error.localizedDescription)
        }
    }

    func drawingData(notebookID: UUID, pageID: UUID) throws -> Data {
        guard let data = try drawingLoadResult(notebookID: notebookID, pageID: pageID) else {
            recordRecoveryIssue("页面 \(pageID.uuidString) 的手写文件缺失，已阻止空白覆盖。")
            throw FreeNoteError.drawingFileMissing(pageID)
        }
        return data
    }

    func saveDrawing(_ data: Data, pageID: UUID, notebookID: UUID) throws {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            reportRecoveryIssue(
                "保存手写失败：笔记不存在。notebookID=\(notebookID.uuidString), pageID=\(pageID.uuidString)"
            )
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        guard notebooks[notebookIndex].pages.contains(where: { $0.id == pageID }) else {
            reportRecoveryIssue(
                "保存手写失败：页面不存在。notebookID=\(notebookID.uuidString), pageID=\(pageID.uuidString)"
            )
            throw FreeNoteError.pageNotFound(pageID)
        }
        do {
            try writeDrawing(data, notebookID: notebookID, pageID: pageID)
            var notebook = notebooks[notebookIndex]
            notebook.updatedAt = Date()
            var updatedNotebooks = notebooks
            updatedNotebooks[notebookIndex] = notebook
            try commit(
                notebooks: updatedNotebooks,
                books: books,
                resources: resources,
                settings: settings
            )
        } catch {
            reportRecoveryIssue(
                "保存手写失败：notebookID=\(notebookID.uuidString), pageID=\(pageID.uuidString), error=\(friendlyMessage(for: error))"
            )
            throw error
        }
    }

    func attachResource(_ resourceID: UUID, toNotebookID notebookID: UUID, pageID: UUID) throws {
        guard resources.contains(where: { $0.id == resourceID }) else {
            throw FreeNoteError.resourceNotFound(resourceID)
        }
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else {
            throw FreeNoteError.pageNotFound(pageID)
        }
        var notebook = notebooks[notebookIndex]
        guard !notebook.pages[pageIndex].attachments.contains(where: { $0.resourceID == resourceID }) else {
            return
        }
        notebook.pages[pageIndex].attachments.append(AttachmentRef(resourceID: resourceID))
        notebook.updatedAt = Date()
        var updatedNotebooks = notebooks
        updatedNotebooks[notebookIndex] = notebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )
    }

    func attachments(forNotebookID notebookID: UUID, pageID: UUID) throws -> [ResourceItem] {
        guard let notebook = notebooks.first(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        guard let page = notebook.pages.first(where: { $0.id == pageID }) else {
            throw FreeNoteError.pageNotFound(pageID)
        }
        var resourcesByID: [UUID: ResourceItem] = [:]
        for resource in resources {
            resourcesByID[resource.id] = resource
        }
        var result: [ResourceItem] = []
        for attachment in page.attachments {
            if let resource = resourcesByID[attachment.resourceID] {
                result.append(resource)
            } else {
                recordRecoveryIssue("页面 \(pageID.uuidString) 含有失效的资源引用。")
            }
        }
        return result
    }

    func detachResource(resourceID: UUID, notebookID: UUID, pageID: UUID) throws {
        guard let notebookIndex = notebooks.firstIndex(where: { $0.id == notebookID }) else {
            throw FreeNoteError.notebookNotFound(notebookID)
        }
        guard let pageIndex = notebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else {
            throw FreeNoteError.pageNotFound(pageID)
        }
        var notebook = notebooks[notebookIndex]
        let originalCount = notebook.pages[pageIndex].attachments.count
        notebook.pages[pageIndex].attachments.removeAll { $0.resourceID == resourceID }
        guard notebook.pages[pageIndex].attachments.count != originalCount else {
            return
        }
        notebook.updatedAt = Date()
        var updatedNotebooks = notebooks
        updatedNotebooks[notebookIndex] = notebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )
    }

    // MARK: - Settings

    func saveSettings() throws {
        let previous = settings
        var normalized = settings
        normalized.fontSize = min(max(normalized.fontSize, 8), 96)
        do {
            try commit(
                notebooks: notebooks,
                books: books,
                resources: resources,
                settings: normalized
            )
        } catch {
            settings = previous
            throw error
        }
    }

    // MARK: - Outline and reading progress

    func updateOutline(_ nodes: [OutlineNode], forBookID id: UUID) throws {
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw FreeNoteError.bookNotFound(id)
        }
        try OutlineEditor.validate(nodes, pageCount: books[index].pageCount)
        var book = books[index]
        book.outline = nodes
        var updatedBooks = books
        updatedBooks[index] = book
        try commit(notebooks: notebooks, books: updatedBooks, resources: resources, settings: settings)
    }

    func updateOutline(_ nodes: [OutlineNode], forNotebookID id: UUID) throws {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else {
            throw FreeNoteError.notebookNotFound(id)
        }
        try OutlineEditor.validate(nodes, pageCount: notebooks[index].pages.count)
        var notebook = notebooks[index]
        notebook.outline = nodes
        notebook.updatedAt = Date()
        var updatedNotebooks = notebooks
        updatedNotebooks[index] = notebook
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: resources,
            settings: settings
        )
    }

    func updateReadingProgress(bookID: UUID, page: Int) throws {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else {
            throw FreeNoteError.bookNotFound(bookID)
        }
        var book = books[index]
        let clampedPage = book.pageCount > 0
            ? min(max(page, 1), book.pageCount)
            : 0
        book.currentPage = clampedPage
        book.lastOpenedAt = Date()
        book.isCompleted = book.pageCount > 0 && clampedPage >= book.pageCount
        var updatedBooks = books
        updatedBooks[index] = book
        try commit(notebooks: notebooks, books: updatedBooks, resources: resources, settings: settings)
    }

    // MARK: - Annotations

    func annotationData(bookID: UUID, pageIndex: Int) throws -> Data {
        guard let book = books.first(where: { $0.id == bookID }) else {
            throw FreeNoteError.bookNotFound(bookID)
        }
        try validatePageIndex(pageIndex, pageCount: book.pageCount)
        let url = annotationURL(bookID: bookID, pageIndex: pageIndex)
        guard fileManager.fileExists(atPath: url.path) else {
            return Data()
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            recordRecoveryIssue("无法读取书籍批注 \(bookID.uuidString)/\(pageIndex)：\(error.localizedDescription)")
            throw FreeNoteError.fileOperationFailed(error.localizedDescription)
        }
    }

    func saveAnnotation(_ data: Data, bookID: UUID, pageIndex: Int) throws {
        guard let book = books.first(where: { $0.id == bookID }) else {
            reportRecoveryIssue(
                "保存批注失败：书籍不存在。bookID=\(bookID.uuidString), pageIndex=\(pageIndex)"
            )
            throw FreeNoteError.bookNotFound(bookID)
        }
        do {
            try validatePageIndex(pageIndex, pageCount: book.pageCount)
        } catch {
            reportRecoveryIssue(
                "保存批注失败：页码无效。bookID=\(bookID.uuidString), pageIndex=\(pageIndex), error=\(friendlyMessage(for: error))"
            )
            throw error
        }
        let directory = annotationsDirectory.appendingPathComponent(bookID.uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = annotationURL(bookID: bookID, pageIndex: pageIndex)
            try data.write(to: url, options: [.atomic])
        } catch {
            reportRecoveryIssue(
                "保存批注失败：bookID=\(bookID.uuidString), pageIndex=\(pageIndex), error=\(error.localizedDescription)"
            )
            throw FreeNoteError.fileOperationFailed(error.localizedDescription)
        }
    }

    // MARK: - Stored files

    func storedURL(for book: BookItem) -> URL? {
        guard books.contains(where: { $0.id == book.id }) else {
            recordRecoveryIssue("书籍 \(book.id.uuidString) 的元数据已不存在。")
            return nil
        }
        let safeName = ImportPreparation.sanitizedFileName(book.fileName)
        let url = libraryDirectory
            .appendingPathComponent(book.id.uuidString, isDirectory: true)
            .appendingPathComponent(safeName)
        guard fileManager.fileExists(atPath: url.path) else {
            recordRecoveryIssue("书籍 \(book.id.uuidString) 的文件缺失：\(safeName)")
            return nil
        }
        return url
    }

    func storedURL(for resource: ResourceItem) -> URL? {
        guard resources.contains(where: { $0.id == resource.id }) else {
            recordRecoveryIssue("资源 \(resource.id.uuidString) 的元数据已不存在。")
            return nil
        }
        let safeName = ImportPreparation.sanitizedFileName(resource.fileName)
        let url = libraryDirectory
            .appendingPathComponent(resource.id.uuidString, isDirectory: true)
            .appendingPathComponent(safeName)
        guard fileManager.fileExists(atPath: url.path) else {
            recordRecoveryIssue("资源 \(resource.id.uuidString) 的文件缺失：\(safeName)")
            return nil
        }
        return url
    }

    // MARK: - Import

    func importFiles(_ urls: [URL], destination: ImportDestination) async -> [ImportResult] {
        if destination == .currentPage {
            return urls.map {
                ImportResult(
                    title: DocumentClassifier.displayTitle(for: $0),
                    kind: DocumentClassifier.kind(for: $0),
                    destination: .currentPage,
                    success: false,
                    errorMessage: "导入到当前页时必须提供笔记与页面标识。"
                )
            }
        }

        let root = rootURL
        let outcomes = await Task.detached(priority: .userInitiated) {
            ImportPreparation.prepare(
                urls: urls,
                destination: destination,
                freeNoteRoot: root,
                notebookID: nil,
                pageID: nil
            )
        }.value
        return commitPreparedImports(outcomes)
    }

    func importFiles(
        _ urls: [URL],
        notebookID: UUID,
        pageID: UUID
    ) async -> [ImportResult] {
        guard notebooks.contains(where: { $0.id == notebookID }) else {
            return urls.map {
                ImportResult(
                    title: DocumentClassifier.displayTitle(for: $0),
                    kind: DocumentClassifier.kind(for: $0),
                    destination: .currentPage,
                    success: false,
                    errorMessage: "目标笔记不存在。",
                    notebookID: notebookID,
                    pageID: pageID
                )
            }
        }
        guard notebooks
            .first(where: { $0.id == notebookID })?
            .pages.contains(where: { $0.id == pageID }) == true else {
            return urls.map {
                ImportResult(
                    title: DocumentClassifier.displayTitle(for: $0),
                    kind: DocumentClassifier.kind(for: $0),
                    destination: .currentPage,
                    success: false,
                    errorMessage: "目标页面不存在。",
                    notebookID: notebookID,
                    pageID: pageID
                )
            }
        }

        let root = rootURL
        let outcomes = await Task.detached(priority: .userInitiated) {
            ImportPreparation.prepare(
                urls: urls,
                destination: .currentPage,
                freeNoteRoot: root,
                notebookID: notebookID,
                pageID: pageID
            )
        }.value
        return commitPreparedImports(outcomes)
    }

    func importFiles(
        _ urls: [URL],
        destinations: Set<ImportDestination>,
        notebookID: UUID? = nil,
        pageID: UUID? = nil
    ) async -> [ImportResult] {
        guard !urls.isEmpty, !destinations.isEmpty else {
            return []
        }

        var results: [ImportResult] = []
        for destination in ImportDestination.allCases where destinations.contains(destination) {
            switch destination {
            case .bookshelf, .library:
                let destinationResults = await importFiles(urls, destination: destination)
                results.append(contentsOf: destinationResults)

            case .currentPage:
                guard let notebookID, let pageID else {
                    let contextMessage = "导入到当前页时必须提供有效的笔记与页面标识。"
                    results.append(contentsOf: urls.map { url in
                        ImportResult(
                            title: DocumentClassifier.displayTitle(for: url),
                            kind: DocumentClassifier.kind(for: url),
                            destination: .currentPage,
                            success: false,
                            errorMessage: contextMessage,
                            itemID: nil,
                            notebookID: notebookID,
                            pageID: pageID
                        )
                    })
                    continue
                }
                let destinationResults = await importFiles(
                    urls,
                    notebookID: notebookID,
                    pageID: pageID
                )
                results.append(contentsOf: destinationResults)
            }
        }
        return results
    }

    // MARK: - Deletion and moving

    func deleteBooks(ids: Set<UUID>) throws {
        guard !ids.isEmpty else {
            return
        }
        let remaining = books.filter { !ids.contains($0.id) }
        try commit(notebooks: notebooks, books: remaining, resources: resources, settings: settings)
        for id in ids {
            removeItemBestEffort(
                at: libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true),
                context: "删除书籍文件"
            )
            removeItemBestEffort(
                at: annotationsDirectory.appendingPathComponent(id.uuidString, isDirectory: true),
                context: "删除书籍批注"
            )
        }
    }

    func deleteResources(ids: Set<UUID>) throws {
        guard !ids.isEmpty else {
            return
        }
        let remaining = resources.filter { !ids.contains($0.id) }
        var updatedNotebooks = notebooks
        _ = removeAttachmentReferences(ids, from: &updatedNotebooks)
        try commit(
            notebooks: updatedNotebooks,
            books: books,
            resources: remaining,
            settings: settings
        )
        for id in ids {
            removeItemBestEffort(
                at: libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true),
                context: "删除资源文件"
            )
        }
    }

    func moveResource(id: UUID, to destination: ImportDestination) throws {
        guard let resourceIndex = resources.firstIndex(where: { $0.id == id }) else {
            throw FreeNoteError.resourceNotFound(id)
        }
        let resource = resources[resourceIndex]
        switch destination {
        case .library:
            return
        case .currentPage:
            throw FreeNoteError.invalidState("请使用 attachResource(_:toNotebookID:pageID:) 将资源附加到指定页面。")
        case .bookshelf:
            let safeName = ImportPreparation.sanitizedFileName(resource.fileName)
            let sourceURL = libraryDirectory
                .appendingPathComponent(resource.id.uuidString, isDirectory: true)
                .appendingPathComponent(safeName)
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                throw FreeNoteError.fileOperationFailed("资源文件不存在。")
            }

            let inspected = DocumentOutlineExtractor.inspect(url: sourceURL, kind: resource.kind)
            guard inspected.pageCount >= 1 else {
                throw FreeNoteError.documentHasNoReadablePages(safeName)
            }
            let outline: [OutlineNode]
            if !inspected.outline.isEmpty,
               (try? OutlineEditor.validate(inspected.outline, pageCount: inspected.pageCount)) != nil {
                outline = inspected.outline
            } else {
                outline = DocumentOutlineExtractor.fallbackOutline(pageCount: inspected.pageCount)
            }
            if let warning = inspected.warning, !warning.isEmpty {
                recordRecoveryIssue(warning)
            }

            let bookID = UUID()
            let destinationDirectory = libraryDirectory.appendingPathComponent(bookID.uuidString, isDirectory: true)
            let destinationURL = destinationDirectory.appendingPathComponent(safeName)
            do {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try? fileManager.removeItem(at: destinationDirectory)
                throw FreeNoteError.fileOperationFailed(error.localizedDescription)
            }

            let book = BookItem(
                id: bookID,
                title: resource.title,
                kind: resource.kind,
                fileName: safeName,
                pageCount: inspected.pageCount,
                currentPage: 1,
                outline: outline
            )
            var updatedBooks = books
            updatedBooks.append(book)
            var updatedResources = resources
            updatedResources.remove(at: resourceIndex)
            var updatedNotebooks = notebooks
            _ = removeAttachmentReferences(Set([id]), from: &updatedNotebooks)
            do {
                try commit(
                    notebooks: updatedNotebooks,
                    books: updatedBooks,
                    resources: updatedResources,
                    settings: settings
                )
            } catch {
                do {
                    try fileManager.moveItem(at: destinationURL, to: sourceURL)
                    try? fileManager.removeItem(at: destinationDirectory)
                } catch {
                    recordRecoveryIssue("资源移动回滚失败：\(error.localizedDescription)")
                }
                throw error
            }
            removeItemBestEffort(
                at: libraryDirectory.appendingPathComponent(id.uuidString, isDirectory: true),
                context: "移动资源目录"
            )
        }
    }
    // MARK: - Persistence

    private struct PersistedState: Codable {
        var schemaVersion: Int
        var notebooks: [Notebook]
        var books: [BookItem]
        var resources: [ResourceItem]
        var settings: AppSettings
    }

    private func prepareDirectories() throws {
        for directory in [
            rootURL,
            notebooksDirectory,
            libraryDirectory,
            annotationsDirectory,
            backupsDirectory,
            stagingDirectory
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadState() throws {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return
        }
        do {
            let data = try Data(contentsOf: storeURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            let state = try decoder.decode(PersistedState.self, from: data)
            notebooks = state.notebooks
            books = state.books
            resources = state.resources
            settings = state.settings
            normalizeLoadedPageIndexes()
            validateLoadedMetadata()
        } catch {
            preserveUnreadableStore()
            recordRecoveryIssue("store.json 无法读取：\(error.localizedDescription)")
            notebooks = []
            books = []
            resources = []
            settings = .defaultValue
        }
    }

    private func writeState(
        notebooks: [Notebook],
        books: [BookItem],
        resources: [ResourceItem],
        settings: AppSettings
    ) throws {
        let state = PersistedState(
            schemaVersion: 1,
            notebooks: notebooks,
            books: books,
            resources: resources,
            settings: settings
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        do {
            let data = try encoder.encode(state)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            throw FreeNoteError.persistenceFailed(error.localizedDescription)
        }
    }

    private func commit(
        notebooks: [Notebook],
        books: [BookItem],
        resources: [ResourceItem],
        settings: AppSettings
    ) throws {
        try writeState(
            notebooks: notebooks,
            books: books,
            resources: resources,
            settings: settings
        )
        self.notebooks = notebooks
        self.books = books
        self.resources = resources
        self.settings = settings
    }

    // MARK: - Import commit

    private func commitPreparedImports(_ outcomes: [PreparedImportOutcome]) -> [ImportResult] {
        var updatedNotebooks = notebooks
        var updatedBooks = books
        var updatedResources = resources
        var results: [ImportResult] = []
        var movedDirectories: [URL] = []
        var succeeded = false

        for outcome in outcomes {
            switch outcome {
            case let .failed(result):
                results.append(result)

            case let .ready(prepared):
                do {
                    let itemDirectory = libraryDirectory
                        .appendingPathComponent(prepared.itemID.uuidString, isDirectory: true)
                    let destinationURL = itemDirectory
                        .appendingPathComponent(prepared.fileName)
                    try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
                    try fileManager.moveItem(at: prepared.stagedURL, to: destinationURL)

                    switch prepared.destination {
                    case .bookshelf:
                        guard prepared.pageCount >= 1 else {
                            throw FreeNoteError.documentHasNoReadablePages(prepared.fileName)
                        }
                        let pageCount = prepared.pageCount
                        let currentPage = 1
                        let safeOutline: [OutlineNode]
                        if pageCount > 0,
                           !prepared.outline.isEmpty,
                           (try? OutlineEditor.validate(prepared.outline, pageCount: pageCount)) != nil {
                            safeOutline = prepared.outline
                        } else {
                            safeOutline = DocumentOutlineExtractor.fallbackOutline(pageCount: pageCount)
                        }
                        let book = BookItem(
                            id: prepared.itemID,
                            title: prepared.title,
                            kind: prepared.kind,
                            fileName: prepared.fileName,
                            pageCount: pageCount,
                            currentPage: currentPage,
                            outline: safeOutline
                        )
                        updatedBooks.append(book)
                        results.append(
                            ImportResult(
                                id: prepared.resultID,
                                title: prepared.title,
                                kind: prepared.kind,
                                destination: .bookshelf,
                                success: true,
                                itemID: prepared.itemID,
                                warningMessage: prepared.warningMessage
                            )
                        )

                    case .library:
                        let resource = ResourceItem(
                            id: prepared.itemID,
                            title: prepared.title,
                            kind: prepared.kind,
                            fileName: prepared.fileName
                        )
                        updatedResources.append(resource)
                        results.append(
                            ImportResult(
                                id: prepared.resultID,
                                title: prepared.title,
                                kind: prepared.kind,
                                destination: .library,
                                success: true,
                                itemID: prepared.itemID,
                                warningMessage: prepared.warningMessage
                            )
                        )

                    case .currentPage:
                        guard let notebookID = prepared.notebookID,
                              let pageID = prepared.pageID,
                              let notebookIndex = updatedNotebooks.firstIndex(where: { $0.id == notebookID }),
                              let pageIndex = updatedNotebooks[notebookIndex].pages.firstIndex(where: { $0.id == pageID }) else {
                            throw FreeNoteError.invalidState("导入完成前目标笔记页已不存在。")
                        }
                        let resource = ResourceItem(
                            id: prepared.itemID,
                            title: prepared.title,
                            kind: prepared.kind,
                            fileName: prepared.fileName
                        )
                        updatedResources.append(resource)
                        updatedNotebooks[notebookIndex].pages[pageIndex].attachments.append(
                            AttachmentRef(resourceID: resource.id)
                        )
                        updatedNotebooks[notebookIndex].updatedAt = Date()
                        results.append(
                            ImportResult(
                                id: prepared.resultID,
                                title: prepared.title,
                                kind: prepared.kind,
                                destination: .currentPage,
                                success: true,
                                itemID: prepared.itemID,
                                notebookID: notebookID,
                                pageID: pageID,
                                warningMessage: prepared.warningMessage
                            )
                        )
                    }

                    movedDirectories.append(itemDirectory)
                    succeeded = true
                    removeItemBestEffort(
                        at: prepared.stagedURL.deletingLastPathComponent(),
                        context: "清理导入暂存目录"
                    )
                } catch {
                    try? fileManager.removeItem(
                        at: libraryDirectory.appendingPathComponent(prepared.itemID.uuidString, isDirectory: true)
                    )
                    try? fileManager.removeItem(at: prepared.stagedURL.deletingLastPathComponent())
                    results.append(
                        ImportResult(
                            id: prepared.resultID,
                            title: prepared.title,
                            kind: prepared.kind,
                            destination: prepared.destination,
                            success: false,
                            errorMessage: friendlyMessage(for: error),
                            notebookID: prepared.notebookID,
                            pageID: prepared.pageID,
                            warningMessage: prepared.warningMessage
                        )
                    )
                }
            }
        }

        guard succeeded else {
            return results
        }

        do {
            try commit(
                notebooks: updatedNotebooks,
                books: updatedBooks,
                resources: updatedResources,
                settings: settings
            )
            return results
        } catch {
            for directory in movedDirectories {
                try? fileManager.removeItem(at: directory)
            }
            return results.map { result in
                guard result.success else {
                    return result
                }
                return ImportResult(
                    id: result.id,
                    title: result.title,
                    kind: result.kind,
                    destination: result.destination,
                    success: false,
                    errorMessage: friendlyMessage(for: error),
                    itemID: nil,
                    notebookID: result.notebookID,
                    pageID: result.pageID,
                    warningMessage: result.warningMessage
                )
            }
        }
    }

    // MARK: - Helpers

    private func normalizeLoadedPageIndexes() {
        for notebookIndex in notebooks.indices {
            for pageIndex in notebooks[notebookIndex].pages.indices {
                notebooks[notebookIndex].pages[pageIndex].index = pageIndex + 1
            }
        }
    }

    private func validateLoadedMetadata() {
        for notebook in notebooks {
            var seen = Set<UUID>()
            for page in notebook.pages where !seen.insert(page.id).inserted {
                recordRecoveryIssue("笔记 \(notebook.id.uuidString) 含有重复页面标识。")
            }
            do {
                try OutlineEditor.validate(notebook.outline, pageCount: notebook.pages.count)
            } catch {
                recordRecoveryIssue(
                    "笔记 \(notebook.id.uuidString) 的大纲数据需要修复：\(friendlyMessage(for: error))"
                )
            }
        }
        for book in books {
            do {
                try OutlineEditor.validate(book.outline, pageCount: max(book.pageCount, 0))
            } catch {
                recordRecoveryIssue(
                    "书籍 \(book.id.uuidString) 的大纲数据需要修复：\(friendlyMessage(for: error))"
                )
            }
        }
    }

    private func normalizeAndValidateNotebook(_ notebook: inout Notebook) throws {
        guard !notebook.pages.isEmpty else {
            throw FreeNoteError.cannotDeleteLastPage(notebook.id)
        }
        var seen = Set<UUID>()
        for (index, page) in notebook.pages.enumerated() {
            guard seen.insert(page.id).inserted else {
                throw FreeNoteError.duplicatePageID(page.id)
            }
            notebook.pages[index].index = index + 1
        }
        try OutlineEditor.validate(notebook.outline, pageCount: notebook.pages.count)
    }

    private func validatePageIndex(_ pageIndex: Int, pageCount: Int) throws {
        guard pageCount > 0, pageIndex >= 1, pageIndex <= pageCount else {
            throw FreeNoteError.invalidState("页码 \(pageIndex) 超出范围 1–\(pageCount)。")
        }
    }

    private func ensureNotebookDirectories(for notebookID: UUID) throws {
        let directory = notebookDirectory(for: notebookID)
        do {
            try fileManager.createDirectory(
                at: directory.appendingPathComponent("pages", isDirectory: true),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: directory.appendingPathComponent("attachments", isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            throw FreeNoteError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func writeDrawing(_ data: Data, notebookID: UUID, pageID: UUID) throws {
        do {
            try ensureNotebookDirectories(for: notebookID)
            try data.write(
                to: drawingURL(notebookID: notebookID, pageID: pageID),
                options: [.atomic]
            )
        } catch let error as FreeNoteError {
            throw error
        } catch {
            throw FreeNoteError.fileOperationFailed(error.localizedDescription)
        }
    }

    private func notebookDirectory(for id: UUID) -> URL {
        notebooksDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func drawingURL(notebookID: UUID, pageID: UUID) -> URL {
        notebookDirectory(for: notebookID)
            .appendingPathComponent("pages", isDirectory: true)
            .appendingPathComponent("\(pageID.uuidString).drawing")
    }

    private func annotationURL(bookID: UUID, pageIndex: Int) -> URL {
        annotationsDirectory
            .appendingPathComponent(bookID.uuidString, isDirectory: true)
            .appendingPathComponent("\(pageIndex).annotation")
    }

    @discardableResult
    private func removeAttachmentReferences(
        _ resourceIDs: Set<UUID>,
        from notebooks: inout [Notebook]
    ) -> Bool {
        guard !resourceIDs.isEmpty else {
            return false
        }
        var changed = false
        for notebookIndex in notebooks.indices {
            var notebookChanged = false
            for pageIndex in notebooks[notebookIndex].pages.indices {
                let originalCount = notebooks[notebookIndex].pages[pageIndex].attachments.count
                notebooks[notebookIndex].pages[pageIndex].attachments.removeAll {
                    resourceIDs.contains($0.resourceID)
                }
                if notebooks[notebookIndex].pages[pageIndex].attachments.count != originalCount {
                    notebookChanged = true
                }
            }
            if notebookChanged {
                notebooks[notebookIndex].updatedAt = Date()
                changed = true
            }
        }
        return changed
    }

    private func removeOrphanDrawings(notebookID: UUID, validPageIDs: Set<UUID>) {
        let pagesDirectory = notebookDirectory(for: notebookID)
            .appendingPathComponent("pages", isDirectory: true)
        guard let fileNames = try? fileManager.contentsOfDirectory(atPath: pagesDirectory.path) else {
            return
        }
        for fileName in fileNames where fileName.hasSuffix(".drawing") {
            let pageID = String(fileName.dropLast(".drawing".count))
            guard UUID(uuidString: pageID) != nil,
                  !validPageIDs.contains(where: { $0.uuidString == pageID }) else {
                continue
            }
            removeItemBestEffort(
                at: pagesDirectory.appendingPathComponent(fileName),
                context: "清理孤立手写文件"
            )
        }
    }

    private func removeItemBestEffort(at url: URL, context: String) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.removeItem(at: url)
        } catch {
            recordRecoveryIssue("\(context)失败：\(error.localizedDescription)")
        }
    }

    private func preserveUnreadableStore() {
        guard fileManager.fileExists(atPath: storeURL.path) else {
            return
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let destination = backupsDirectory
            .appendingPathComponent("corrupt-store-\(timestamp).json")
        do {
            try fileManager.copyItem(at: storeURL, to: destination)
        } catch {
            recordRecoveryIssue("损坏的 store.json 无法备份：\(error.localizedDescription)")
        }
    }

    private func recordRecoveryIssue(_ message: String) {
        guard !recoveryIssues.contains(where: { $0.message == message }) else {
            return
        }
        recoveryIssues.append(RecoveryIssue(message: message))
        if recoveryIssues.count > 100 {
            recoveryIssues.removeFirst(recoveryIssues.count - 100)
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
