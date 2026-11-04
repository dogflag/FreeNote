import Foundation

enum DocumentClassifier {
    static func kind(for url: URL) -> DocumentKind {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "epub":
            return .epub
        case "doc", "docx", "ppt", "pptx", "xls", "xlsx",
             "odt", "odp", "ods", "pages", "numbers", "key":
            return .office
        case "png", "jpg", "jpeg", "heic", "heif", "webp", "gif", "tif", "tiff", "bmp":
            return .image
        case "mp3", "m4a", "wav", "aac", "aiff", "aif", "flac", "ogg", "opus":
            return .audio
        case "txt", "md", "markdown", "rtf", "csv", "json", "xml", "html", "htm":
            return .text
        default:
            return .other
        }
    }

    static func suggestedDestination(for url: URL) -> ImportDestination {
        switch url.pathExtension.lowercased() {
        case "pdf", "epub", "ppt", "pptx":
            return .bookshelf
        default:
            return .library
        }
    }

    static func displayTitle(for url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名文件" : name
    }

    static func isBookLike(_ url: URL) -> Bool {
        ["pdf", "epub", "ppt", "pptx"].contains(url.pathExtension.lowercased())
    }
}
