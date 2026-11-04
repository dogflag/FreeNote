import SwiftUI

struct BookshelfView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @State private var searchText = ""
    @State private var filter: BookFilter = .all
    @State private var displayMode: DisplayMode = .grid
    @State private var showingImport = false
    @State private var selectedBook: BookItem?
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    private var filteredBooks: [BookItem] {
        let sorted = store.books.sorted {
            ($0.lastOpenedAt ?? $0.createdAt) > ($1.lastOpenedAt ?? $1.createdAt)
        }
        let filtered: [BookItem]
        switch filter {
        case .all:
            filtered = sorted
        case .reading:
            filtered = sorted.filter { !$0.isCompleted }
        case .completed:
            filtered = sorted.filter(\.isCompleted)
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return filtered
        }
        return filtered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var continueBook: BookItem? {
        store.books
            .filter { !$0.isCompleted }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let continueBook {
                    continueReadingCard(continueBook)
                }
                filterRow
                if filteredBooks.isEmpty {
                    if searchText.isEmpty {
                        FNEmptyState(
                            symbol: "books.vertical",
                            title: "书架还是空的",
                            message: "导入 PDF、EPUB 或课件，阅读进度和手写批注会保存在本地。",
                            actionTitle: "导入书籍",
                            action: { showingImport = true }
                        )
                        .frame(height: 360)
                    } else {
                        FNEmptyState(
                            symbol: "books.vertical",
                            title: "没有匹配的书籍",
                            message: "尝试更换关键词或筛选条件。"
                        )
                        .frame(height: 360)
                    }
                } else if displayMode == .grid {
                    bookGrid
                } else {
                    bookList
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 22)
            .padding(.bottom, 34)
        }
        .background(FNTheme.contentBackground)
        .sheet(isPresented: $showingImport) {
            DocumentImportSheet(defaultDestination: .bookshelf, allowsCurrentPage: false)
                .environmentObject(store)
        }
        .fullScreenCover(item: $selectedBook) { book in
            ReaderView(bookID: book.id)
                .environmentObject(store)
        }
        .alert("移除书籍？", isPresented: $showingDeleteConfirmation) {
            Button("移除", role: .destructive, action: deletePending)
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("将同时删除本地副本、阅读进度与批注，无法撤销。")
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
                Text("书架")
                    .font(FNTheme.serif(34, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Text("你的阅读都停在这里，下一次从上次的位置继续。")
                    .font(.system(size: 11))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            Spacer()
            HStack(spacing: 9) {
                FNSearchField(text: $searchText, placeholder: "搜索书架")
                    .frame(width: 190)
                FNTopActionButton(symbol: "square.and.arrow.down", title: "导入书籍", prominent: true) {
                    showingImport = true
                }
            }
        }
    }

    private func continueReadingCard(_ book: BookItem) -> some View {
        Button {
            selectedBook = book
        } label: {
            HStack(spacing: 20) {
                BookCoverView(book: book, size: CGSize(width: 92, height: 128), compact: true)

                VStack(alignment: .leading, spacing: 9) {
                    Text("CONTINUE READING")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(FNTheme.tertiaryInk)
                    Text(book.title)
                        .font(FNTheme.serif(28, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text(book.kind == .pdf ? "PDF · \(book.pageCount) 页" : book.kind.fnTitle)
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.tertiaryInk)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(FNTheme.divider)
                            Capsule()
                                .fill(FNTheme.accent)
                                .frame(width: proxy.size.width * readProgress(book))
                        }
                    }
                    .frame(height: 5)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("第 \(book.currentPage) / \(max(book.pageCount, 1)) 页")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                    Text("继续阅读")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.accent)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FNTheme.accent)
                }
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: [FNTheme.card, FNTheme.accentSoft.opacity(0.35)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(FNTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var filterRow: some View {
        HStack(spacing: 8) {
            FNFilterChip(title: "全部 \(store.books.count)", isSelected: filter == .all) { filter = .all }
            FNFilterChip(title: "在读 \(store.books.filter { !$0.isCompleted }.count)", isSelected: filter == .reading) { filter = .reading }
            FNFilterChip(title: "已完成 \(store.books.filter(\.isCompleted).count)", isSelected: filter == .completed) { filter = .completed }
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
        .padding(.top, 2)
    }

    private var bookGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 142, maximum: 184), spacing: 20, alignment: .top)],
            alignment: .leading,
            spacing: 22
        ) {
            ForEach(filteredBooks) { book in
                Button {
                    selectedBook = book
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        BookCoverView(book: book, size: CGSize(width: 142, height: 194), compact: false)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FNTheme.ink)
                                .lineLimit(2)
                            HStack {
                                Text(book.isCompleted ? "已完成" : (book.currentPage > 1 ? "在读 · \(Int(readProgress(book) * 100))%" : "未开始"))
                                Spacer()
                                Text(book.kind.fnTitle)
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(FNTheme.tertiaryInk)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("打开") { selectedBook = book }
                    Button("从书架移除", role: .destructive) { requestDelete(book.id) }
                }
            }
        }
    }

    private var bookList: some View {
        LazyVStack(spacing: 8) {
            ForEach(filteredBooks) { book in
                Button {
                    selectedBook = book
                } label: {
                    HStack(spacing: 13) {
                        BookCoverView(book: book, size: CGSize(width: 45, height: 62), compact: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(FNTheme.ink)
                            Text("\(book.kind.fnTitle) · \(book.pageCount) 页 · 第 \(book.currentPage) 页")
                                .font(.system(size: 10))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }
                        Spacer()
                        Text(book.isCompleted ? "已完成" : "\(Int(readProgress(book) * 100))%")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(book.isCompleted ? FNTheme.accent : FNTheme.secondaryInk)
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
                    Button("从书架移除", role: .destructive) { requestDelete(book.id) }
                }
            }
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
            try store.deleteBooks(ids: ids)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func readProgress(_ book: BookItem) -> CGFloat {
        guard book.pageCount > 0 else { return 0 }
        return min(max(CGFloat(book.currentPage) / CGFloat(book.pageCount), 0), 1)
    }
}

private enum BookFilter {
    case all
    case reading
    case completed
}

private enum DisplayMode {
    case grid
    case list
}

struct BookCoverView: View {
    let book: BookItem
    let size: CGSize
    let compact: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [FNTheme.coverColor(for: book.id), FNTheme.coverColor(for: book.id).opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                .frame(width: size.width * 0.78, height: size.width * 0.78)
                .offset(x: size.width * 0.52, y: size.height * 0.08)

            VStack(alignment: .leading, spacing: compact ? 5 : 8) {
                Rectangle()
                    .fill(Color.white.opacity(0.48))
                    .frame(width: compact ? 22 : 28, height: 1)
                Text(book.title)
                    .font(FNTheme.serif(compact ? 12 : 17, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(3)
                Spacer()
                Text(book.kind.fnTitle.uppercased())
                    .font(.system(size: compact ? 7 : 8, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(compact ? 10 : 14)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 11, style: .continuous))
        .shadow(color: Color.black.opacity(0.13), radius: 8, y: 4)
    }
}
