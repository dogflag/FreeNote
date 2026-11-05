import Foundation

enum DocumentClassifier {
    private static let officeExtensions: Set<String> = [
        "doc", "docx", "docm",
        "ppt", "pptx", "pptm",
        "xls", "xlsx", "xlsm", "xlsb",
        "odt", "odp", "ods",
        "pages", "numbers", "key"
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "webp",
        "gif", "tif", "tiff", "bmp"
    ]

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "aiff", "aif",
        "flac", "ogg", "opus"
    ]

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "rtf", "csv", "json", "xml", "html", "htm"
    ]

    static func kind(for url: URL) -> DocumentKind {
        let fileExtension = url.pathExtension.lowercased()
        if fileExtension == "pdf" {
            return .pdf
        }
        if fileExtension == "epub" {
            return .epub
        }
        if officeExtensions.contains(fileExtension) {
            return .office
        }
        if imageExtensions.contains(fileExtension) {
            return .image
        }
        if audioExtensions.contains(fileExtension) {
            return .audio
        }
        if textExtensions.contains(fileExtension) {
            return .text
        }
        return .other
    }

    static func suggestedDestination(for url: URL) -> ImportDestination {
        switch url.pathExtension.lowercased() {
        case "pdf", "epub", "ppt", "pptx", "pptm":
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
        ["pdf", "epub", "ppt", "pptx", "pptm"].contains(url.pathExtension.lowercased())
    }
}
