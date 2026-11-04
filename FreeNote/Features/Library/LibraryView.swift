import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @State private var filter: LibraryFilter = .all
    @State private var searchText = ""
    @State private var displayMode: LibraryDisplayMode = .grid
    @State private var showingImport = false
    @State private var selectedResource: ResourceItem?
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    private var filteredResources: [ResourceItem] {
        let sorted = store.resources.sorted { $0.createdAt > $1.createdAt }
        let byFilter: [ResourceItem]
        switch filter {
        case .all:
            byFilter = sorted
        case .recent:
            let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            byFilter = sorted.filter { $0.createdAt >= threshold }
        case .documents:
            byFilter = sorted.filter { [.pdf, .epub, .office, .text].contains($0.kind) }
        case .images:
            byFilter = sorted.filter { $0.kind == .image }
        case .audio:
            byFilter = sorted.filter { $0.kind == .audio }
        case .other:
            byFilter = sorted.filter { $0.kind == .other }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return byFilter
        }
        return byFilter.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statsGrid
                filterRow

                if filteredResources.isEmpty {
                    if searchText.isEmpty {
                        FNEmptyState(
                            symbol: "folder",
                            title: "资源库还是空的",
                            message: "图片、文档、音频和零散素材都可以收纳在这里。",
                            actionTitle: "导入文件",
                            action: { showingImport = true }
                        )
                        .frame(height: 340)
                    } else {
                        FNEmptyState(
                            symbol: "folder",
                            title: "没有匹配的资源",
                            message: "尝试更换关键词或筛选条件。"
                        )
                        .frame(height: 340)
                    }
                } else if displayMode == .grid {
                    resourceGrid
                } else {
                    resourceList
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .background(FNTheme.contentBackground)
        .sheet(isPresented: $showingImport) {
            DocumentImportSheet(defaultDestination: .library, allowsCurrentPage: false)
                .environmentObject(store)
        }
        .sheet(item: $selectedResource) { resource in
            QuickLookResourceSheet(resource: resource)
                .environmentObject(store)
        }
        .alert("移除资源？", isPresented: $showingDeleteConfirmation) {
            Button("移除", role: .destructive, action: deletePending)
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("将删除 FreeNote 内的本地副本，不影响原始文件。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("资源库")
                    .font(FNTheme.serif(34, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Text("图片、文档、音频和零散素材，都在这里随手可取。")
                    .font(.system(size: 11))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            Spacer()
            HStack(spacing: 9) {
                FNSearchField(text: $searchText, placeholder: "搜索资源")
                    .frame(width: 190)
                FNTopActionButton(symbol: "square.and.arrow.down", title: "导入文件", prominent: true) {
                    showingImport = true
                }
            }
        }
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard(count: store.resources.count, title: "全部文件", symbol: "square.stack")
            statCard(count: store.resources.filter { [.pdf, .epub, .office, .text].contains($0.kind) }.count, title: "文档", symbol: "doc.text")
            statCard(count: store.resources.filter { $0.kind == .image }.count, title: "图片", symbol: "photo")
            statCard(count: store.resources.filter { $0.kind == .audio }.count, title: "音频", symbol: "waveform")
        }
    }

    private func statCard(count: Int, title: String, symbol: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(count)")
                    .font(FNTheme.serif(26, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(FNTheme.accent.opacity(0.7))
        }
        .padding(15)
        .frame(maxWidth: .infinity)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }

    private var filterRow: some View {
        HStack(spacing: 7) {
            FNFilterChip(title: "全部", isSelected: filter == .all) { filter = .all }
            FNFilterChip(title: "最近", isSelected: filter == .recent) { filter = .recent }
            FNFilterChip(title: "文档", isSelected: filter == .documents) { filter = .documents }
            FNFilterChip(title: "图片", isSelected: filter == .images) { filter = .images }
            FNFilterChip(title: "音频", isSelected: filter == .audio) { filter = .audio }
            FNFilterChip(title: "其他", isSelected: filter == .other) { filter = .other }
            Spacer()
            Menu {
                Button("网格视图") { displayMode = .grid }
                Button("列表视图") { displayMode = .list }
            } label: {
                Label(displayMode == .grid ? "网格视图" : "列表视图", systemImage: displayMode == .grid ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
            }
        }
    }

    private var resourceGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 14, alignment: .top)],
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(filteredResources) { resource in
                Button {
                    selectedResource = resource
                } label: {
                    ResourceCard(resource: resource)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("打开预览") { selectedResource = resource }
                    Button("移动到书架") { moveToBookshelf(resource) }
                    Button("删除", role: .destructive) { requestDelete(resource.id) }
                }
            }
        }
    }

    private var resourceList: some View {
        LazyVStack(spacing: 7) {
            ForEach(filteredResources) { resource in
                Button {
                    selectedResource = resource
                } label: {
                    HStack(spacing: 12) {
                        FileTypeTile(kind: resource.kind)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(resource.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FNTheme.ink)
                            Text("\(resource.kind.fnTitle) · \(resource.createdAt, format: .dateTime.month().day().hour().minute())")
                                .font(.system(size: 10))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FNTheme.tertiaryInk)
                    }
                    .padding(11)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("移动到书架") { moveToBookshelf(resource) }
                    Button("删除", role: .destructive) { requestDelete(resource.id) }
                }
            }
        }
    }

    private func moveToBookshelf(_ resource: ResourceItem) {
        do {
            try store.moveResource(id: resource.id, to: .bookshelf)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requestDelete(_ id: UUID) {
        pendingDeleteIDs = [id]
        showingDeleteConfirmation = true
    }

    private func deletePending() {
        let ids = pendingDeleteIDs
        pendingDeleteIDs.removeAll()
        do {
            try store.deleteResources(ids: ids)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum LibraryFilter {
    case all
    case recent
    case documents
    case images
    case audio
    case other
}

private enum LibraryDisplayMode {
    case grid
    case list
}

private struct ResourceCard: View {
    let resource: ResourceItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                FileTypeTile(kind: resource.kind)
                Spacer()
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(resource.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                    .lineLimit(2)
                Text("\(resource.kind.fnTitle) · \(resource.createdAt, format: .dateTime.month().day())")
                    .font(.system(size: 9))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }
}

private struct FileTypeTile: View {
    let kind: DocumentKind

    var body: some View {
        Image(systemName: kind.fnSymbol)
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.white)
            .frame(width: 46, height: 52)
            .background(kind.fnTint)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Text(kind.fnTitle.uppercased())
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.top, 4)
                    .padding(.trailing, 4)
            }
    }
}
