import SwiftUI

struct OutlineDrawerOverlay: View {
    @Binding var isPresented: Bool
    let documentTitle: String
    let pageCount: Int
    let initialNodes: [OutlineNode]
    let initialPage: Int
    let onSave: ([OutlineNode]) throws -> Void
    let onJumpToPage: ((Int) -> Void)?

    @State private var draft: [OutlineNode] = []
    @State private var selectedID: UUID?
    @State private var expandedIDs = Set<UUID>()
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    @State private var didLoad = false

    private var rows: [OutlineFlatRow] {
        OutlineTreeOperations.flatten(nodes: draft, expanded: expandedIDs)
    }

    private var selectedNode: OutlineNode? {
        guard let selectedID else { return nil }
        return OutlineTreeOperations.node(id: selectedID, in: draft)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    drawer(width: min(430, max(340, proxy.size.width * 0.46)))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .onAppear(perform: loadIfNeeded)
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("删除这个大纲节点？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { deleteSelected() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("其所有子节点也会被删除。")
        }
    }

    private func drawer(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(FNTheme.divider).frame(height: 1)

            if draft.isEmpty {
                FNEmptyState(
                    symbol: "list.bullet.indent",
                    title: "还没有大纲",
                    message: "为当前文档建立独立目录。节点可绑定一页，也可绑定连续页码范围。",
                    actionTitle: "新建根节点",
                    action: addRoot
                )
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(rows) { row in
                            outlineRow(row.node, depth: row.depth)
                        }
                    }
                    .padding(14)
                }
                inspector
            }

            Rectangle().fill(FNTheme.divider).frame(height: 1)
            actionBar
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(FNTheme.contentBackground)
        .shadow(color: Color.black.opacity(0.18), radius: 24, x: -8, y: 0)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("大纲")
                    .font(FNTheme.serif(24, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                Text(documentTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(draft.count) 个根节点")
                .font(.system(size: 10))
                .foregroundStyle(FNTheme.tertiaryInk)
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .tint(FNTheme.accent)
                .controlSize(.small)
            FNIconButton(symbol: "xmark") { close() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(FNTheme.card)
    }

    private func outlineRow(_ node: OutlineNode, depth: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                toggleExpanded(node.id)
            } label: {
                Image(systemName: expandedIDs.contains(node.id) ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .frame(width: 18, height: 28)
            }
            .buttonStyle(.plain)
            .opacity(node.children.isEmpty ? 0 : 1)
            .disabled(node.children.isEmpty)

            VStack(alignment: .leading, spacing: 3) {
                Text(node.title.isEmpty ? "未命名节点" : node.title)
                    .font(.system(size: 13, weight: selectedID == node.id ? .semibold : .regular))
                    .foregroundStyle(FNTheme.ink)
                    .lineLimit(2)
                Text(pageRangeText(node))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            Spacer(minLength: 4)
            if node.children.count > 0 {
                Text("\(node.children.count)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(FNTheme.sidebar)
                    .clipShape(Capsule())
            }
        }
        .padding(.leading, CGFloat(min(depth, 12)) * 13)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(selectedID == node.id ? FNTheme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedID = node.id
            }
        }
        .contextMenu {
            Button("添加子节点") {
                selectedID = node.id
                addChild()
            }
            Button("添加同级节点") {
                selectedID = node.id
                addSibling()
            }
            Button("缩进") {
                selectedID = node.id
                indentSelected()
            }
            Button("减少缩进") {
                selectedID = node.id
                outdentSelected()
            }
            Divider()
            Button("删除", role: .destructive) {
                selectedID = node.id
                confirmDelete = true
            }
        }
    }

    private var inspector: some View {
        VStack(spacing: 11) {
            Rectangle().fill(FNTheme.divider).frame(height: 1)

            if selectedNode != nil {
                HStack {
                    Text("节点详情")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(FNTheme.secondaryInk)
                    Spacer()
                    if let onJumpToPage, let selectedNode {
                        Button("跳转到第 \(selectedNode.startPage) 页") {
                            onJumpToPage(selectedNode.startPage)
                            close()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(FNTheme.accent)
                    }
                }

                TextField("节点标题", text: selectedTitleBinding)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )

                HStack(spacing: 14) {
                    pageStepper(title: "起始页", value: selectedStartPageBinding)
                    pageStepper(title: "结束页", value: selectedEndPageBinding)
                }
            } else {
                Text("选择一个节点后可编辑标题和页码范围。")
                    .font(.system(size: 10))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 11)
        .padding(.bottom, 12)
        .background(FNTheme.card)
    }

    private func pageStepper(title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
            Stepper(value: value, in: 1...max(pageCount, 1)) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FNTheme.ink)
            }
            .labelsHidden()
            .overlay(alignment: .leading) {
                Text("\(value.wrappedValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FNTheme.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                actionButton("plus", title: "根节点", action: addRoot)
                actionButton("plus.rectangle.on.rectangle", title: "同级", action: addSibling)
                actionButton("arrow.turn.down.right", title: "子节点", action: addChild)
                actionButton("arrow.up", title: "上移") { moveSelected(offset: -1) }
                actionButton("arrow.down", title: "下移") { moveSelected(offset: 1) }
                actionButton("increase.indent", title: "缩进", action: indentSelected)
                actionButton("decrease.indent", title: "反缩进", action: outdentSelected)
                actionButton("trash", title: "删除", tint: FNTheme.danger) { confirmDelete = true }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .background(FNTheme.card)
    }

    private func actionButton(_ symbol: String, title: String, tint: Color = FNTheme.secondaryInk, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundStyle(tint)
            .frame(width: 56, height: 43)
            .background(FNTheme.sidebar.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var selectedTitleBinding: Binding<String> {
        Binding(
            get: { selectedNode?.title ?? "" },
            set: { value in
                guard let selectedID else { return }
                updateSelected { $0.title = value }
            }
        )
    }

    private var selectedStartPageBinding: Binding<Int> {
        Binding(
            get: { selectedNode?.startPage ?? 1 },
            set: { value in
                updateSelected { node in
                    node.startPage = OutlineTreeOperations.boundedPage(value, pageCount: pageCount)
                    node.endPage = max(node.endPage, node.startPage)
                }
            }
        )
    }

    private var selectedEndPageBinding: Binding<Int> {
        Binding(
            get: { selectedNode?.endPage ?? 1 },
            set: { value in
                updateSelected { node in
                    node.endPage = OutlineTreeOperations.boundedPage(value, pageCount: pageCount)
                    node.startPage = min(node.startPage, node.endPage)
                }
            }
        )
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        draft = initialNodes
        expandedIDs = OutlineTreeOperations.allIDs(in: initialNodes)
        selectedID = OutlineTreeOperations.flatten(nodes: initialNodes, expanded: expandedIDs).first?.node.id
    }

    private func toggleExpanded(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    private func addRoot() {
        OutlineTreeOperations.addRoot(to: &draft, page: initialPage, pageCount: pageCount)
        if let newID = draft.last?.id {
            selectedID = newID
            expandedIDs.insert(newID)
        }
    }

    private func addSibling() {
        if let newID = OutlineTreeOperations.addSibling(after: selectedID, in: &draft, page: initialPage, pageCount: pageCount) {
            selectedID = newID
            expandedIDs.insert(newID)
        }
    }

    private func addChild() {
        guard let selectedID else {
            addRoot()
            return
        }
        if let newID = OutlineTreeOperations.addChild(to: selectedID, in: &draft, page: initialPage, pageCount: pageCount) {
            selectedID = newID
            expandedIDs.insert(newID)
        }
    }

    private func moveSelected(offset: Int) {
        guard let selectedID else { return }
        if !OutlineTreeOperations.moveSibling(id: selectedID, offset: offset, in: &draft) {
            errorMessage = offset < 0 ? "已经位于同级节点的最上方。" : "已经位于同级节点的最下方。"
        }
    }

    private func indentSelected() {
        guard let selectedID else { return }
        if !OutlineTreeOperations.indent(id: selectedID, in: &draft) {
            errorMessage = "该节点没有可以成为父节点的上一个同级节点。"
        }
    }

    private func outdentSelected() {
        guard let selectedID else { return }
        if !OutlineTreeOperations.outdent(id: selectedID, in: &draft) {
            errorMessage = "根节点不能继续减少缩进。"
        }
    }

    private func deleteSelected() {
        guard let selectedID else { return }
        let removed = OutlineTreeOperations.remove(id: selectedID, in: &draft)
        if removed {
            expandedIDs.remove(selectedID)
            self.selectedID = nil
        }
    }

    private func updateSelected(_ transform: (inout OutlineNode) -> Void) {
        guard let selectedID else { return }
        _ = OutlineTreeOperations.updateNode(id: selectedID, in: &draft, transform: transform)
    }

    private func pageRangeText(_ node: OutlineNode) -> String {
        node.startPage == node.endPage ? "第 \(node.startPage) 页" : "第 \(node.startPage)–\(node.endPage) 页"
    }

    private func save() {
        do {
            try onSave(draft)
            close()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func close() {
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}
