import Foundation

struct PreparedImport: Sendable {
    let resultID: UUID
    let itemID: UUID
    let title: String
    let kind: DocumentKind
    let destination: ImportDestination
    let fileName: String
    let stagedURL: URL
    let pageCount: Int
    let outline: [OutlineNode]
    let warningMessage: String?
    let notebookID: UUID?
    let pageID: UUID?
}

enum PreparedImportOutcome: Sendable {
    case ready(PreparedImport)
    case failed(ImportResult)
}

enum ImportPreparation {
    static func prepare(
        urls: [URL],
        destination: ImportDestination,
        freeNoteRoot: URL,
        notebookID: UUID?,
        pageID: UUID?
    ) -> [PreparedImportOutcome] {
        let fileManager = FileManager.default
        let stagingRoot = freeNoteRoot.appendingPathComponent("ImportStaging", isDirectory: true)
        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        } catch {
            return urls.map { url in
                failure(
                    for: url,
                    destination: destination,
                    error: error,
                    notebookID: notebookID,
                    pageID: pageID
                )
            }
        }

        return urls.map { sourceURL in
            prepareOne(
                sourceURL: sourceURL,
                destination: destination,
                freeNoteRoot: freeNoteRoot,
                stagingRoot: stagingRoot,
                notebookID: notebookID,
                pageID: pageID
            )
        }
    }

    private static func prepareOne(
        sourceURL: URL,
        destination: ImportDestination,
        freeNoteRoot: URL,
        stagingRoot: URL,
        notebookID: UUID?,
        pageID: UUID?
    ) -> PreparedImportOutcome {
        let kind = DocumentClassifier.kind(for: sourceURL)
        let title = DocumentClassifier.displayTitle(for: sourceURL)
        let token = UUID()
        let fileName = sanitizedFileName(sourceURL.lastPathComponent)
        let itemID = UUID()
        let resultID = UUID()
        let itemStagingDirectory = stagingRoot.appendingPathComponent(token.uuidString, isDirectory: true)
        let stagedURL = itemStagingDirectory.appendingPathComponent(fileName)

        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let resourceValues = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey])
            guard resourceValues.isRegularFile == true, resourceValues.isReadable == true else {
                throw FreeNoteError.importSourceUnreadable(sourceURL.lastPathComponent)
            }
            try FileManager.default.createDirectory(
                at: itemStagingDirectory,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: sourceURL, to: stagedURL)
        } catch {
            try? FileManager.default.removeItem(at: itemStagingDirectory)
            return failure(
                id: resultID,
                title: title,
                kind: kind,
                destination: destination,
                error: error,
                notebookID: notebookID,
                pageID: pageID
            )
        }

        var pageCount = 0
        var outline: [OutlineNode] = []
        var warningMessage: String?
        if destination == .bookshelf {
            let inspected = DocumentOutlineExtractor.inspect(url: stagedURL, kind: kind)
            pageCount = inspected.pageCount
            outline = inspected.outline
            warningMessage = inspected.warning
            guard pageCount > 0 else {
                try? FileManager.default.removeItem(at: itemStagingDirectory)
                let error = FreeNoteError.documentHasNoReadablePages(fileName)
                return .failed(
                    ImportResult(
                        id: resultID,
                        title: title,
                        kind: kind,
                        destination: destination,
                        success: false,
                        errorMessage: (error as LocalizedError).errorDescription,
                        itemID: nil,
                        notebookID: nil,
                        pageID: nil,
                        warningMessage: inspected.warning
                    )
                )
            }
        }

        return .ready(
            PreparedImport(
                resultID: resultID,
                itemID: itemID,
                title: title,
                kind: kind,
                destination: destination,
                fileName: fileName,
                stagedURL: stagedURL,
                pageCount: pageCount,
                outline: outline,
                warningMessage: warningMessage,
                notebookID: destination == .currentPage ? notebookID : nil,
                pageID: destination == .currentPage ? pageID : nil
            )
        )
    }

    private static func failure(
        for url: URL,
        destination: ImportDestination,
        error: Error,
        notebookID: UUID?,
        pageID: UUID?
    ) -> PreparedImportOutcome {
        failure(
            id: UUID(),
            title: DocumentClassifier.displayTitle(for: url),
            kind: DocumentClassifier.kind(for: url),
            destination: destination,
            error: error,
            notebookID: notebookID,
            pageID: pageID
        )
    }

    private static func failure(
        id: UUID,
        title: String,
        kind: DocumentKind,
        destination: ImportDestination,
        error: Error,
        notebookID: UUID?,
        pageID: UUID?
    ) -> PreparedImportOutcome {
        .failed(
            ImportResult(
                id: id,
                title: title,
                kind: kind,
                destination: destination,
                success: false,
                errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                itemID: nil,
                notebookID: notebookID,
                pageID: pageID
            )
        )
    }

    static func sanitizedFileName(_ candidate: String) -> String {
        let lastComponent = (candidate as NSString).lastPathComponent
        let sanitized = lastComponent
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty, sanitized != ".", sanitized != ".." else {
            return "ImportedFile"
        }
        return sanitized
    }
}
