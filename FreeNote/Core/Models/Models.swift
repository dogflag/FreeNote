import Foundation

struct OutlineNode: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var startPage: Int
    var endPage: Int
    var children: [OutlineNode]

    init(
        id: UUID = UUID(),
        title: String,
        startPage: Int,
        endPage: Int,
        children: [OutlineNode] = []
    ) {
        self.id = id
        self.title = title
        self.startPage = startPage
        self.endPage = endPage
        self.children = children
    }
}

struct NotePage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var index: Int
    var attachments: [AttachmentRef]

    init(
        id: UUID = UUID(),
        index: Int,
        attachments: [AttachmentRef] = []
    ) {
        self.id = id
        self.index = index
        self.attachments = attachments
    }
}

struct AttachmentRef: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var resourceID: UUID
    /// 0-based source page/slide/chapter index. Nil means the whole resource.
    var pageIndex: Int?

    init(id: UUID = UUID(), resourceID: UUID, pageIndex: Int? = nil) {
        self.id = id
        self.resourceID = resourceID
        self.pageIndex = pageIndex
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case resourceID
        case pageIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        resourceID = try container.decode(UUID.self, forKey: .resourceID)
        pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(resourceID, forKey: .resourceID)
        try container.encodeIfPresent(pageIndex, forKey: .pageIndex)
    }
}

struct Notebook: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: NotebookKind
    var paperStyle: PaperStyle
    var pages: [NotePage]
    var outline: [OutlineNode]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: NotebookKind,
        paperStyle: PaperStyle,
        pages: [NotePage] = [],
        outline: [OutlineNode] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.paperStyle = paperStyle
        self.pages = pages
        self.outline = outline
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct BookItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: DocumentKind
    var fileName: String
    var pageCount: Int
    var currentPage: Int
    var outline: [OutlineNode]
    var createdAt: Date
    var lastOpenedAt: Date?
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kind: DocumentKind,
        fileName: String,
        pageCount: Int,
        currentPage: Int = 1,
        outline: [OutlineNode] = [],
        createdAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.fileName = fileName
        self.pageCount = pageCount
        self.currentPage = currentPage
        self.outline = outline
        self.createdAt = createdAt
        self.lastOpenedAt = lastOpenedAt
        self.isCompleted = isCompleted
    }
}

struct ResourceItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: DocumentKind
    var fileName: String
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        kind: DocumentKind,
        fileName: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.fileName = fileName
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

struct RecoveryIssue: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let message: String
    let occurredAt: Date

    init(id: UUID = UUID(), message: String, occurredAt: Date = Date()) {
        self.id = id
        self.message = message
        self.occurredAt = occurredAt
    }
}
