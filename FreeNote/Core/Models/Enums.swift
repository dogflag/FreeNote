import Foundation

enum AppSection: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case notes
    case bookshelf
    case library

    var id: Self { self }
}

enum NotebookKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case paged
    case infiniteCanvas

    var id: Self { self }
}

enum PaperStyle: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case blank
    case lined
    case grid
    case dotted

    var id: Self { self }
}

enum DocumentKind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case pdf
    case epub
    case office
    case image
    case audio
    case text
    case other

    var id: Self { self }
}

enum ImportDestination: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case bookshelf
    case library
    case currentPage

    var id: Self { self }
}

enum AppAppearance: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case light
    case dark
    case system

    var id: Self { self }
}

enum ReadingFont: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case system
    case serif
    case rounded

    var id: Self { self }
}
