import Foundation

struct PreparedPageInsertion: Sendable {
    let pageIDs: [UUID]
    let stagedDrawingURLs: [URL]
    let stagingDirectory: URL
}

enum PageInsertionPreparation {
    static func prepare(
        resourceURL: URL,
        kind: DocumentKind,
        stagingRoot: URL
    ) throws -> PreparedPageInsertion {
        let pageCount = try OfficePreviewRenderer.pageCount(for: resourceURL, kind: kind)
        guard pageCount >= 1 else {
            throw FreeNoteError.documentHasNoReadablePages(resourceURL.lastPathComponent)
        }

        let stagingDirectory = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileManager = FileManager.default
        let pageIDs = (0..<pageCount).map { _ in UUID() }
        do {
            try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            var stagedURLs: [URL] = []
            stagedURLs.reserveCapacity(pageIDs.count)
            for pageID in pageIDs {
                let url = stagingDirectory.appendingPathComponent("\(pageID.uuidString).drawing")
                try Data().write(to: url, options: [.atomic])
                stagedURLs.append(url)
            }
            return PreparedPageInsertion(
                pageIDs: pageIDs,
                stagedDrawingURLs: stagedURLs,
                stagingDirectory: stagingDirectory
            )
        } catch {
            try? fileManager.removeItem(at: stagingDirectory)
            throw error
        }
    }
}
