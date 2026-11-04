import Foundation

struct ImportResult: Identifiable, Sendable {
    let id: UUID
    let title: String
    let kind: DocumentKind
    let destination: ImportDestination
    let success: Bool
    let errorMessage: String?
    let itemID: UUID?
    let notebookID: UUID?
    let pageID: UUID?
    let warningMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        kind: DocumentKind,
        destination: ImportDestination,
        success: Bool,
        errorMessage: String? = nil,
        itemID: UUID? = nil,
        notebookID: UUID? = nil,
        pageID: UUID? = nil,
        warningMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.destination = destination
        self.success = success
        self.errorMessage = errorMessage
        self.itemID = itemID
        self.notebookID = notebookID
        self.pageID = pageID
        self.warningMessage = warningMessage
    }
}
