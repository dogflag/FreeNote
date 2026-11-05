import SwiftUI

struct NotesWorkspaceView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @State private var selectedNotebookID: UUID?
    @State private var searchText = ""
    @State private var filter: NoteFilter = .all
    @State private var editingSelection = false
    @State private var selectedIDs = Set<UUID>()
    @State private var showingNewNote = false
    @State private var renameTarget: Notebook?
    @State private var showingDeleteConfirmation = false
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var errorMessage: String?

    private var filteredNotebooks: [Notebook] {
        let sorted = store.notebooks.sorted { $0.updatedAt > $1.updatedAt }
        let byFilter: [Notebook]
        switch filter {
        case .all:
            byFilter = sorted
        case .recent:
            let threshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
            byFilter = sorted.filter { $0.updatedAt >= threshold }
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return byFilter
        }
        return byFilter.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedNotebook: Notebook? {
        guard let selectedNotebookID else { return nil }
        return store.notebooks.first { $0.id == selectedNotebookID }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(FNTheme.divider).frame(width: 1)
            editorArea
        }
        .background(FNTheme.contentBackground)
        .onAppear(perform: ensureSelection)
        .onChange(of: store.notebooks.map(\.id)) { _ in
            ensureSelection()
        }
        .sheet(isPresented: $showingNewNote) {
            NewNotebookSheet()
                .environmentObject(store)
        }
        .sheet(item: $renameTarget) { notebook in
            RenameNotebookSheet(notebook: notebook)
                .environmentObject(store)
        }
        .alert("删除笔记？", isPresented: $showingDeleteConfirmation) {
            Button("删除", role: .destructive, action: deletePendingNotebooks)
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("笔记及其手写页面、附件将一并删除，且无法撤销。")
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

    private var sidebar: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("笔记")
                    .font(FNTheme.serif(30, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Spacer()
                if editingSelection {
                    Button("完成") {
                        editingSelection = false
                        selectedIDs.removeAll()
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FNTheme.accent)
                    .buttonStyle(.plain)
                } else {
                    Button {
                        showingNewNote = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(FNTheme.selectionText)
                            .frame(width: 38, height: 38)
                            .background(FNTheme.selectionFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("新建笔记")
                }
            }

            FNSearchField(text: $searchText, placeholder: "搜索笔记")

            HStack(spacing: 7) {
                FNFilterChip(title: "全部", isSelected: filter == .all) { filter = .all }
                FNFilterChip(title: "最近", isSelected: filter == .recent) { filter = .recent }
                Spacer()
                if !editingSelection {
                    Button("选择") {
                        editingSelection = true
                        selectedIDs.removeAll()
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .buttonStyle(.plain)
                }
            }

            if editingSelection {
                HStack(spacing: 8) {
                    Text("已选 \(selectedIDs.count) 项")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                    Spacer()
                    Button("全选") {
                        selectedIDs = Set(filteredNotebooks.map(\.id))
                    }
                    .buttonStyle(.plain)
                    Button("删除") {
                        requestDelete(selectedIDs)
                    }
                    .foregroundStyle(FNTheme.danger)
                    .buttonStyle(.plain)
                    .disabled(selectedIDs.isEmpty)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 2)
            }

            if filteredNotebooks.isEmpty {
                if searchText.isEmpty {
                    FNEmptyState(
                        symbol: "note.text",
                        title: "开始第一本笔记",
                        message: "选择分页本或无限画布，随时写下想法。",
                        actionTitle: "新建笔记",
                        action: { showingNewNote = true }
                    )
                } else {
                    FNEmptyState(
                        symbol: "note.text",
                        title: "没有匹配的笔记",
                        message: "尝试更换关键词或筛选条件。"
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(filteredNotebooks) { notebook in
                            NotebookListRow(
                                notebook: notebook,
                                isSelected: selectedNotebookID == notebook.id,
                                isEditing: editingSelection,
                                isChecked: selectedIDs.contains(notebook.id),
                                privacyMode: store.settings.privacyMode
                            ) {
                                if editingSelection {
                                    toggleSelection(notebook.id)
                                } else {
                                    selectedNotebookID = notebook.id
                                }
                            }
                            .contextMenu {
                                Button("重命名") { renameTarget = notebook }
                                Button("删除", role: .destructive) {
                                    requestDelete([notebook.id])
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(width: 340)
        .background(FNTheme.contentBackground)
    }

    @ViewBuilder
    private var editorArea: some View {
        if let selectedNotebook {
            NotebookEditorView(notebookID: selectedNotebook.id)
                .id(selectedNotebook.id)
        } else {
            FNEmptyState(
                symbol: "pencil.and.outline",
                title: "选择一本笔记",
                message: "从左侧打开笔记，或新建一个分页本 / 无限画布。",
                actionTitle: "新建笔记",
                action: { showingNewNote = true }
            )
            .background(FNTheme.appBackground)
        }
    }

    private func ensureSelection() {
        guard !store.notebooks.isEmpty else {
            selectedNotebookID = nil
            selectedIDs.removeAll()
            return
        }
        if let selectedNotebookID, store.notebooks.contains(where: { $0.id == selectedNotebookID }) {
            return
        }
        selectedNotebookID = store.notebooks.sorted { $0.updatedAt > $1.updatedAt }.first?.id
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDeleteIDs = ids
        showingDeleteConfirmation = true
    }

    private func deletePendingNotebooks() {
        let ids = pendingDeleteIDs
        pendingDeleteIDs.removeAll()
        var firstError: Error?
        for id in ids {
            do {
                try store.deleteNotebook(id: id)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        
        selectedIDs.subtract(ids)
        editingSelection = false
        ensureSelection()
        if let firstError {
            errorMessage = firstError.localizedDescription
        }
    }
}

private enum NoteFilter: String, CaseIterable {
    case all
    case recent
}

private struct NotebookListRow: View {
    let notebook: Notebook
    let isSelected: Bool
    let isEditing: Bool
    let isChecked: Bool
    let privacyMode: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 11) {
                if isEditing {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isChecked ? FNTheme.accent : FNTheme.tertiaryInk)
                        .padding(.top, 1)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(FNTheme.coverColor(for: notebook.id))
                        .frame(width: 4)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Image(systemName: notebook.kind.fnSymbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FNTheme.accent)
                        Text(notebook.title.isEmpty ? "未命名笔记" : notebook.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FNTheme.ink)
                            .lineLimit(1)
                    }

                    Text(privacyMode ? "内容已隐藏" : "\(notebook.paperStyle.fnTitle) · \(notebook.kind.fnTitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(FNTheme.tertiaryInk)
                        .lineLimit(1)

                    HStack {
                        Text(notebook.updatedAt, format: .dateTime.month().day().hour().minute())
                            .font(.system(size: 9))
                            .foregroundStyle(FNTheme.tertiaryInk)
                        Spacer()
                        Text("\(notebook.pages.count) 页")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(FNTheme.tertiaryInk)
                    }
                }
            }
            .padding(13)
            .background(isSelected ? FNTheme.cardRaised : FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? FNTheme.accent.opacity(0.35) : FNTheme.divider, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.025), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct NewNotebookSheet: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = "未命名笔记"
    @State private var kind: NotebookKind = .paged
    @State private var paperStyle: PaperStyle = .dotted
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            FNModalHeader(
                title: "新建笔记",
                subtitle: "选择一种适合当前场景的页面。",
                onClose: { dismiss() }
            )

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("笔记名称")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.secondaryInk)
                    TextField("未命名笔记", text: $title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 13)
                        .frame(height: 40)
                        .background(FNTheme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(FNTheme.divider, lineWidth: 1)
                        )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("笔记类型")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.secondaryInk)
                    HStack(spacing: 10) {
                        ForEach(NotebookKind.allCases) { item in
                            notebookKindCard(item)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("纸张模板")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.secondaryInk)
                    HStack(spacing: 8) {
                        ForEach(PaperStyle.allCases) { style in
                            Button {
                                paperStyle = style
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: style.fnSymbol)
                                        .font(.system(size: 16, weight: .regular))
                                    Text(style.fnTitle)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundStyle(paperStyle == style ? FNTheme.accent : FNTheme.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 62)
                                .background(paperStyle == style ? FNTheme.accentSoft : FNTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .stroke(paperStyle == style ? FNTheme.accent.opacity(0.35) : FNTheme.divider, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.bordered)
                    Button("创建笔记", action: createNotebook)
                        .buttonStyle(.borderedProminent)
                        .tint(FNTheme.selectionFill)
                }
            }
            .padding(26)
        }
        .frame(minWidth: 620, minHeight: 620)
        .background(FNTheme.contentBackground)
        .alert("无法创建笔记", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func notebookKindCard(_ item: NotebookKind) -> some View {
        Button {
            kind = item
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: item.fnSymbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(kind == item ? FNTheme.accent : FNTheme.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(kind == item ? FNTheme.accentSoft : FNTheme.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.fnTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text(item.fnSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(kind == item ? FNTheme.accentSoft.opacity(0.65) : FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(kind == item ? FNTheme.accent.opacity(0.4) : FNTheme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func createNotebook() {
        do {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try store.createNotebook(
                title: trimmed.isEmpty ? "未命名笔记" : trimmed,
                kind: kind,
                paperStyle: paperStyle
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RenameNotebookSheet: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    let notebook: Notebook
    @State private var title: String
    @State private var errorMessage: String?

    init(notebook: Notebook) {
        self.notebook = notebook
        _title = State(initialValue: notebook.title)
    }

    var body: some View {
        VStack(spacing: 0) {
            FNModalHeader(
                title: "重命名笔记",
                subtitle: "只修改名称，不会影响页面、附件与大纲。",
                onClose: { dismiss() }
            )

            VStack(alignment: .leading, spacing: 18) {
                TextField("笔记名称", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button("取消") { dismiss() }
                        .buttonStyle(.bordered)
                    Button("保存", action: rename)
                        .buttonStyle(.borderedProminent)
                        .tint(FNTheme.selectionFill)
                }
            }
            .padding(24)
        }
        .frame(width: 480, minHeight: 300)
        .background(FNTheme.contentBackground)
        .alert("无法重命名", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func rename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "未命名笔记" : trimmed
        do {
            try store.renameNotebook(id: notebook.id, title: finalTitle)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


