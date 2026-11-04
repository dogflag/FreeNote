# FreeNote Architecture & Module Contract

## Product baseline

- Target: iPadOS 16.0+, iPad only for v1.
- UI: SwiftUI shell; PencilKit for handwriting; PDFKit for PDF rendering and text selection.
- Persistence: local-first, Application Support.
- Distribution: unsigned IPA built on a macOS CI runner, installed with TrollStore.
- No account, cloud sync, collaboration, IAP, or AI features in v1.

## Module ownership

### Core (backend agent)

- Models and Codable persistence.
- Notebook lifecycle, pages, drawing blobs and assets.
- Bookshelf/library import and file copying.
- Outline tree storage, editing and auto-extraction.
- Settings persistence.
- Unit-testable services with no SwiftUI imports unless strictly required by system frameworks.

### UI (frontend agent)

- App entry and navigation shell.
- Notes list and PencilKit workspace.
- Bookshelf, library and unified reader.
- Bottom-right outline handle and outline drawer.
- Import dialogs, settings sheet and batch management.
- Uses only the public store/service contract below; does not write files directly.

### Main agent

- XcodeGen project, build scripts, CI, assets and integration.
- Interface reconciliation and final acceptance.

### Reviewer agent

- Read-only code review. Reports concrete file/line findings, especially compile errors, unsafe unwraps, invalid ranges, data loss, memory/file-handle leaks, expensive body rebuilds and oversized types.

## Shared public contract

Core must expose the following names so the UI layer can compile against them. Additional APIs are allowed and should be additive.

```swift
enum AppSection: String, CaseIterable, Identifiable { case notes, bookshelf, library
    var id: Self { self }
}

enum NotebookKind: String, Codable, CaseIterable, Identifiable { case paged, infiniteCanvas
    var id: Self { self }
}
enum PaperStyle: String, Codable, CaseIterable, Identifiable { case blank, lined, grid, dotted
    var id: Self { self }
}

enum DocumentKind: String, Codable, CaseIterable, Identifiable { case pdf, epub, office, image, audio, text, other
    var id: Self { self }
}
enum ImportDestination: String, Codable, CaseIterable, Identifiable { case bookshelf, library, currentPage
    var id: Self { self }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable { case light, dark, system
    var id: Self { self }
}
enum ReadingFont: String, Codable, CaseIterable, Identifiable { case system, serif, rounded
    var id: Self { self }
}

struct OutlineNode: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var startPage: Int   // 1-based, inclusive
    var endPage: Int     // 1-based, inclusive
    var children: [OutlineNode]
}

struct NotePage: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var attachments: [AttachmentRef]
    // Drawing data lives only in pages/<id>.drawing; never embed it in store.json.
}

struct AttachmentRef: Identifiable, Codable, Hashable {
    var id: UUID
    var resourceID: UUID
}

struct Notebook: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var kind: NotebookKind
    var paperStyle: PaperStyle
    var pages: [NotePage]
    var outline: [OutlineNode]
    var createdAt: Date
    var updatedAt: Date
}

struct BookItem: Identifiable, Codable, Hashable {
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
}

struct ResourceItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var kind: DocumentKind
    var fileName: String
    var createdAt: Date
    var lastUsedAt: Date?
}

struct AppSettings: Codable, Equatable {
    var appearance: AppAppearance
    var fontSize: Double
    var readingFont: ReadingFont
    var paperTone: String
    var autoSave: Bool
    var privacyMode: Bool
    var pencilOnlyDrawing: Bool
    var showRecentItems: Bool
}

@MainActor
final class FreeNoteStore: ObservableObject {
    @Published private(set) var notebooks: [Notebook]
    @Published private(set) var books: [BookItem]
    @Published private(set) var resources: [ResourceItem]
    @Published var settings: AppSettings

    func createNotebook(title: String, kind: NotebookKind, paperStyle: PaperStyle) throws -> Notebook
    func deleteNotebook(id: UUID) throws
    func updateNotebook(_ notebook: Notebook) throws
    func renameNotebook(id: UUID, title: String) throws
    func setNotebookPaperStyle(id: UUID, style: PaperStyle) throws
    func addPage(to notebookID: UUID) throws
    func deletePages(notebookID: UUID, pageIDs: Set<UUID>) throws
    func drawingData(notebookID: UUID, pageID: UUID) throws -> Data
    func drawingLoadResult(notebookID: UUID, pageID: UUID) throws -> Data?
    func saveDrawing(_ data: Data, pageID: UUID, notebookID: UUID) throws
    func attachments(forNotebookID notebookID: UUID, pageID: UUID) throws -> [ResourceItem]
    func detachResource(resourceID: UUID, notebookID: UUID, pageID: UUID) throws
    func saveSettings() throws

    func importFiles(_ urls: [URL], destination: ImportDestination) async -> [ImportResult]
    func importFiles(_ urls: [URL], notebookID: UUID, pageID: UUID) async -> [ImportResult]
    func annotationData(bookID: UUID, pageIndex: Int) throws -> Data
    func saveAnnotation(_ data: Data, bookID: UUID, pageIndex: Int) throws
    func storedURL(for book: BookItem) -> URL?
    func storedURL(for resource: ResourceItem) -> URL?

    func updateOutline(_ nodes: [OutlineNode], forBookID id: UUID) throws
    func updateOutline(_ nodes: [OutlineNode], forNotebookID id: UUID) throws
    func updateReadingProgress(bookID: UUID, page: Int) throws
    func deleteBooks(ids: Set<UUID>) throws
    func deleteResources(ids: Set<UUID>) throws
    func moveResource(id: UUID, to destination: ImportDestination) throws
}

struct ImportResult: Identifiable {
    let id: UUID
    let title: String
    let kind: DocumentKind
    let destination: ImportDestination
    let success: Bool
    let errorMessage: String?
    let warningMessage: String?
    let itemID: UUID?
    let notebookID: UUID?
    let pageID: UUID?
}
```

## Outline rules

1. Each notebook/book owns an independent outline tree.
2. Depth is unlimited.
3. Every node binds to one inclusive continuous page range (`startPage...endPage`), where `endPage >= startPage`; a single page range is valid.
4. Import priority:
   - embedded PDF outline/bookmarks or EPUB navigation document;
   - conservative heading/chapter heuristics;
   - fallback: one top-level node per page, no children.
5. User operations: add sibling, add child, rename, indent, outdent, move up/down, change page range, delete subtree.
6. Pages use stable UUIDs; visual order is defined only by Notebook.pages array order. NotePage.index must be normalized after any insertion/deletion. Page deletion must validate, clip or remap outline ranges so no node references a missing page.
7. For reflowable EPUB, page numbers are presentation-dependent. The first implementation may store chapter order and recompute outline page ranges after pagination; it must not silently destroy a user-edited outline.
8. Tree traversal must be iterative or depth-bounded defensively to avoid stack overflow on corrupted data.
9. Auto-generated outlines remain editable and persist until the user changes them.

## Unified outline gesture

- A visible handle sits above the bottom safe area at bottom-right (not on the system edge).
- Tap opens; upward drag from the handle opens.
- Only finger input activates the handle, never Apple Pencil drawing.
- The same component and animation is used in notebook and reader screens.
- The outline is shown in a right-side drawer, visually aligned with the annotation drawer.

## Persistence layout

```
Application Support/FreeNote/
  store.json
  Notebooks/<notebook-id>/
    pages/<page-id>.drawing  # sole source of truth for handwriting
    attachments/
  Library/<item-id>/<stored-file>
  Annotations/<book-id>/<page-index>.annotation
  Backups/
```

Metadata referencing missing files must be surfaced as a recoverable error, not crash.

## Build pipeline

- XcodeGen generates the Xcode project from `project.yml`.
- GitHub Actions runs `scripts/build-ipa.sh` on macOS.
- Output: `build/FreeNote-unsigned.ipa`.
- No signing identity is required for TrollStore testing.


