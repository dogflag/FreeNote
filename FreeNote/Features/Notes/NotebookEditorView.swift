import SwiftUI
import UIKit

struct NotebookEditorView: View {
    private static let logicalPageSize = CGSize(width: 820, height: 1160)
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismissView
    @Environment(\.colorScheme) private var colorScheme
    let notebookID: UUID
    let isFullScreen: Bool
    let initialPageID: UUID?

    @State private var selectedPageID: UUID?
    @State private var drawingData = Data()
    @State private var lastDrawingData = Data()
    @State private var tool: DrawingTool = .pen
    @State private var inkColor = UIColor.black
    @State private var hasManuallySelectedInkColor = false
    @State private var lineWidth: CGFloat = 3
    @State private var saveState: DrawingSaveState = .saved
    @State private var showingPalette = false
    @State private var showingWidth = false
    @State private var showingOutline = false
    @State private var showingImport = false
    @State private var showingDeletePage = false
    @State private var showingFullScreenEditor = false
    @State private var toolbarOffset = CGSize.zero
    @State private var toolbarDragOrigin = CGSize.zero
    @State private var showingFullScreenHint = false
    @State private var showingCanvasNavigator = false
    @State private var isInsertingAttachmentPages = false
    @State private var errorMessage: String?
    @State private var didInitialize = false
    @State private var drawingReadOnly = false
    @State private var drawingHasPendingSave = false
    @State private var drawingLoadError: String?
    @State private var saveTask: Task<Void, Never>?
    @State private var selectedAttachmentPreview: AttachmentPreviewRequest?
    @State private var pageAttachmentResources: [ResourceItem] = []
    @StateObject private var canvasController = PencilCanvasController()

    init(
        notebookID: UUID,
        isFullScreen: Bool = false,
        initialPageID: UUID? = nil,
        initialInkColor: UIColor? = nil,
        initialInkWasManuallySelected: Bool = false
    ) {
        self.notebookID = notebookID
        self.isFullScreen = isFullScreen
        self.initialPageID = initialPageID
        _inkColor = State(initialValue: initialInkColor ?? UIColor.black)
        _hasManuallySelectedInkColor = State(initialValue: initialInkWasManuallySelected)
    }

    private var notebook: Notebook? {
        store.notebooks.first { $0.id == notebookID }
    }

    private var currentPage: NotePage? {
        guard let notebook, let selectedPageID else { return nil }
        return notebook.pages.first { $0.id == selectedPageID }
    }

    private var currentPageIndex: Int {
        guard let notebook, let currentPage else { return 1 }
        return (notebook.pages.firstIndex(where: { $0.id == currentPage.id }) ?? 0) + 1
    }

    private var currentAttachmentPageContext: AttachmentPageContext? {
        guard let attachment = currentPage?.attachments.first(where: { $0.pageIndex != nil }),
              let resource = store.resources.first(where: { $0.id == attachment.resourceID }),
              let url = store.storedURL(for: resource) else {
            return nil
        }
        return AttachmentPageContext(attachment: attachment, resource: resource, url: url)
    }

    var body: some View {
        Group {
            if let notebook {
                content(notebook)
            } else {
                FNEmptyState(
                    symbol: "exclamationmark.triangle",
                    title: "无法打开笔记",
                    message: "这本笔记可能已被删除或暂时不可用。"
                )
            }
        }
        .background(FNTheme.appBackground)
        .statusBar(hidden: isFullScreen)
        .persistentSystemOverlays(isFullScreen ? .hidden : .automatic)
        .onAppear {
            applyDefaultInkColorIfNeeded()
            initializePagesIfNeeded()
            showFullScreenHintIfNeeded()
        }
        .onChange(of: colorScheme) { _ in
            applyDefaultInkColorIfNeeded()
        }
        .onChange(of: notebook?.pages.map(\.id) ?? []) { _ in
            ensurePageSelection()
        }
        .onChange(of: selectedPageID) { _ in
            reloadPageAttachments()
        }
        .onChange(of: currentPage?.attachments ?? []) { _ in
            reloadPageAttachments()
        }
        .interactiveDismissDisabled(isFullScreen && drawingHasPendingSave)
        .onDisappear {
            if !flushPendingDrawing() {
                store.reportRecoveryIssue("退出界面时仍有未保存内容，正在同步重试。")
                retryPendingDrawingOnce()
            }
        }
        .fullScreenCover(isPresented: $showingFullScreenEditor, onDismiss: reloadAfterFullScreen) {
            NotebookEditorView(
                notebookID: notebookID,
                isFullScreen: true,
                initialPageID: selectedPageID,
                initialInkColor: inkColor,
                initialInkWasManuallySelected: hasManuallySelectedInkColor
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showingImport) {
            DocumentImportSheet(
                defaultDestination: .currentPage,
                allowsCurrentPage: true,
                notebookID: notebookID,
                pageID: selectedPageID
            )
            .environmentObject(store)
        }
        .sheet(item: $selectedAttachmentPreview) { request in
            AttachmentPreviewView(resource: request.resource, pageIndex: request.pageIndex)
                .environmentObject(store)
        }
        .alert("无法删除页面", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("删除当前页？", isPresented: $showingDeletePage) {
            Button("删除", role: .destructive, action: deleteCurrentPage)
            Button("取消", role: .cancel) { }
        } message: {
            Text("页面上的手写内容会被删除，大纲中超出页数的范围将自动调整。")
        }
    }

    @ViewBuilder
    private func content(_ notebook: Notebook) -> some View {
        if isFullScreen {
            fullScreenContent(notebook)
        } else {
            standardContent(notebook)
        }
    }

    private func standardContent(_ notebook: Notebook) -> some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                editorHeader(notebook)
                Rectangle().fill(FNTheme.divider).frame(height: 1)
                HStack(spacing: 0) {
                    canvasArea(notebook)
                    pageRail(notebook)
                }
            }

            OutlineHandle {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingOutline = true
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 96)

            if showingOutline {
                OutlineDrawerOverlay(
                    isPresented: $showingOutline,
                    documentTitle: notebook.title,
                    pageCount: max(notebook.pages.count, 1),
                    initialNodes: notebook.outline,
                    initialPage: currentPageIndex,
                    onSave: { try store.updateOutline($0, forNotebookID: notebook.id) },
                    onJumpToPage: { selectPageNumber($0) }
                )
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingOutline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if !pageAttachmentResources.isEmpty {
                    PageAttachmentBar(
                        attachments: currentPage?.attachments ?? [],
                        resources: pageAttachmentResources,
                        allowsPageInsert: notebook.kind == .paged,
                        urlFor: { resource in
                            store.storedURL(for: resource)
                        },
                        onOpen: { resource, pageIndex in
                            selectedAttachmentPreview = AttachmentPreviewRequest(
                                resource: resource,
                                pageIndex: pageIndex
                            )
                        },
                        onDetach: detachAttachment,
                        onInsertAfter: insertAttachmentPages
                    )
                }

                drawingToolbar
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .background(FNTheme.appBackground.opacity(0.92))
        }
    }

    private func fullScreenContent(_ notebook: Notebook) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                fullScreenCanvasArea(notebook)
                    .ignoresSafeArea()

                if showingFullScreenHint {
                    VStack {
                        Text("两指双击退出全屏")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FNTheme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(FNTheme.cardRaised.opacity(0.96))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(FNTheme.divider, lineWidth: 1))
                            .shadow(color: Color.black.opacity(0.10), radius: 10, y: 4)
                        Spacer()
                    }
                    .padding(.top, 18)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }

                VStack {
                    Spacer()
                    drawingToolbar
                        .clipShape(Capsule())
                        .offset(toolbarOffset)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 4)
                                .onChanged { value in
                                    let accumulated = CGSize(
                                        width: toolbarDragOrigin.width + value.translation.width,
                                        height: toolbarDragOrigin.height + value.translation.height
                                    )
                                    toolbarOffset = clampedToolbarOffset(
                                        accumulated,
                                        canvasSize: proxy.size
                                    )
                                }
                                .onEnded { _ in
                                    toolbarDragOrigin = toolbarOffset
                                }
                        )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 16)

                OutlineHandle {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingOutline = true
                    }
                }
                .padding(.trailing, 18)
                .padding(.bottom, 142)

                if showingOutline {
                    OutlineDrawerOverlay(
                        isPresented: $showingOutline,
                        documentTitle: notebook.title,
                        pageCount: max(notebook.pages.count, 1),
                        initialNodes: notebook.outline,
                        initialPage: currentPageIndex,
                        onSave: { try store.updateOutline($0, forNotebookID: notebook.id) },
                        onJumpToPage: { selectPageNumber($0) }
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
        }
        .background(
            WindowTwoFingerDoubleTapInstaller {
                dismissFullScreenAfterFlush()
            }
            .frame(width: 1, height: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: showingOutline)
        .animation(.easeInOut(duration: 0.25), value: showingFullScreenHint)
    }

    private func clampedToolbarOffset(_ translation: CGSize, canvasSize: CGSize) -> CGSize {
        let toolbarWidth = min(max(canvasSize.width - 32, 320), 620)
        let maxHorizontal = max((canvasSize.width - toolbarWidth) / 2, 0)
        let maxUpward = max(canvasSize.height - 120, 0)
        return CGSize(
            width: min(max(translation.width, -maxHorizontal), maxHorizontal),
            height: min(max(translation.height, -maxUpward), 0)
        )
    }

    private func dismissFullScreenAfterFlush() {
        guard flushPendingDrawing() else { return }
        dismissView()
    }

    private func showFullScreenHintIfNeeded() {
        guard isFullScreen else { return }
        showingFullScreenHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                showingFullScreenHint = false
            }
        }
    }

    @ViewBuilder
    private func fullScreenCanvasArea(_ notebook: Notebook) -> some View {
        if notebook.kind == .infiniteCanvas, currentAttachmentPageContext == nil {
            ZStack(alignment: .topLeading) {
                if let pageID = selectedPageID {
                    InfinitePencilCanvasView(
                        drawingData: drawingData,
                        tool: tool,
                        color: inkColor,
                        lineWidth: lineWidth,
                        paperStyle: notebook.paperStyle,
                        paperTone: store.settings.paperTone,
                        controller: canvasController,
                        onDrawingChanged: { data in
                            handleDrawingChanged(data, pageID: pageID)
                        }
                    )
                    .id(pageID)
                    .allowsHitTesting(!drawingReadOnly && !isInsertingAttachmentPages)
                }

                if drawingReadOnly, let pageID = selectedPageID {
                    FNRecoveryReadOnlyView(
                        title: "无法读取此页笔迹",
                        message: drawingLoadError ?? "为避免覆盖原始笔迹，当前页面已切换为只读状态。",
                        issues: store.recoveryIssues,
                        onRetry: { loadDrawing(pageID: pageID) }
                    )
                }
            }
            .background(FNTheme.appBackground)
        } else {
            GeometryReader { proxy in
                let logicalSize = Self.logicalPageSize
                let availableWidth = max(proxy.size.width - 16, 280)
                let availableHeight = max(proxy.size.height - 16, 420)
                let scale = min(availableWidth / logicalSize.width, availableHeight / logicalSize.height)
                ScrollView(.vertical, showsIndicators: false) {
                    ZStack {
                        pagedBackground(notebook)
                        pagedPencilCanvas(notebook)
                    }
                    .frame(width: logicalSize.width, height: logicalSize.height)
                    .scaleEffect(scale)
                    .frame(
                        width: logicalSize.width * scale,
                        height: logicalSize.height * scale
                    )
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .background(FNTheme.appBackground)
            }
        }
    }

    private var compactPageControls: some View {
        HStack(spacing: 5) {
            Button {
                selectPageNumber(currentPageIndex - 1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 30)
            }
            .disabled(currentPageIndex <= 1)

            Text("\(currentPageIndex)/\(max(notebook?.pages.count ?? 1, 1))")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(FNTheme.secondaryInk)
                .frame(minWidth: 34)

            Button {
                selectPageNumber(currentPageIndex + 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 30)
            }
            .disabled(currentPageIndex >= (notebook?.pages.count ?? 1))
        }
        .foregroundStyle(FNTheme.secondaryInk)
        .buttonStyle(.plain)
    }

    private func editorHeader(_ notebook: Notebook) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(notebook.title.isEmpty ? "未命名笔记" : notebook.title)
                    .font(FNTheme.serif(21, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(notebook.kind.fnTitle)
                    Text("·")
                    Text(saveState.label)
                        .foregroundStyle(saveState.color)
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
            }

            Spacer()

            FNPageIndicator(current: currentPageIndex, total: notebook.pages.count)

            Menu {
                ForEach(PaperStyle.allCases) { style in
                    Button {
                        updatePaperStyle(style)
                    } label: {
                        Label(style.fnTitle, systemImage: style.fnSymbol)
                    }
                }
            } label: {
                Label("纸张", systemImage: "square.grid.2x2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )
            }

            FNTopActionButton(symbol: "square.and.arrow.down", title: "插入") {
                showingImport = true
            }

            FNTopActionButton(
                symbol: "arrow.up.left.and.arrow.down.right",
                title: "全屏"
            ) {
                guard flushPendingDrawing() else { return }
                showingFullScreenEditor = true
            }

            Menu {
                Button { addPage() } label: { Label("增加新页", systemImage: "plus") }
                Divider()
                Button(role: .destructive) {
                    showingDeletePage = true
                } label: {
                    Label("删除当前页", systemImage: "trash")
                }
                .disabled(notebook.pages.count <= 1)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .frame(width: 36, height: 36)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(FNTheme.card.opacity(0.82))
    }

    @ViewBuilder
    private func canvasArea(_ notebook: Notebook) -> some View {
        if notebook.kind == .infiniteCanvas, currentAttachmentPageContext == nil {
            infiniteCanvasArea(notebook)
        } else {
            pagedCanvasArea(notebook)
        }
    }

    private func pagedCanvasArea(_ notebook: Notebook) -> some View {
        GeometryReader { proxy in
            let logicalSize = Self.logicalPageSize
            let availableWidth = max(proxy.size.width - 110, 280)
            let availableHeight = max(proxy.size.height - 56, 420)
            let scale = min(availableWidth / logicalSize.width, availableHeight / logicalSize.height)

            ScrollView(.vertical, showsIndicators: false) {
                ZStack {
                    pagedBackground(notebook)
                    pagedPencilCanvas(notebook)
                }
                .frame(width: logicalSize.width, height: logicalSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(FNTheme.divider.opacity(0.7), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, y: 7)
                .scaleEffect(scale)
                .frame(
                    width: logicalSize.width * scale,
                    height: logicalSize.height * scale
                )
                .padding(.horizontal, 34)
                .padding(.top, 16)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .background(
                LinearGradient(
                    colors: [FNTheme.appBackground, FNTheme.contentBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private func infiniteCanvasArea(_ notebook: Notebook) -> some View {
        GeometryReader { _ in
            ZStack(alignment: .topTrailing) {
                Group {
                    if let pageID = selectedPageID {
                        InfinitePencilCanvasView(
                            drawingData: drawingData,
                            tool: tool,
                            color: inkColor,
                            lineWidth: lineWidth,
                            paperStyle: notebook.paperStyle,
                            paperTone: store.settings.paperTone,
                            controller: canvasController,
                            onDrawingChanged: { data in
                                handleDrawingChanged(data, pageID: pageID)
                            }
                        )
                        .id(pageID)
                        .allowsHitTesting(!drawingReadOnly && !isInsertingAttachmentPages)
                    } else {
                        Color.clear
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(FNTheme.divider.opacity(0.8), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)

                if drawingReadOnly, let pageID = selectedPageID {
                    FNRecoveryReadOnlyView(
                        title: "无法读取此页笔迹",
                        message: drawingLoadError ?? "为避免覆盖原始笔迹，当前页面已切换为只读状态。",
                        issues: store.recoveryIssues,
                        onRetry: { loadDrawing(pageID: pageID) }
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [FNTheme.appBackground, FNTheme.contentBackground],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var canvasNavigatorPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("画布导航")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FNTheme.secondaryInk)

            HStack(spacing: 8) {
                Button {
                    canvasController.zoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .frame(width: 34, height: 32)
                }
                Text("\(Int((canvasController.zoomScale * 100).rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                    .frame(width: 48)
                Button {
                    canvasController.zoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .frame(width: 34, height: 32)
                }
            }
            .foregroundStyle(FNTheme.secondaryInk)
            .buttonStyle(.plain)

            Button {
                canvasController.recenter()
            } label: {
                Label("画布回中", systemImage: "scope")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FNTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(FNTheme.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(FNTheme.cardRaised)
    }

    @ViewBuilder
    private func pagedBackground(_ notebook: Notebook) -> some View {
        if let context = currentAttachmentPageContext {
            AttachmentPageBackgroundView(
                attachment: context.attachment,
                resource: context.resource,
                url: context.url
            )
            .id("\(context.resource.id)-\(context.attachment.pageIndex ?? -1)")
        } else {
            FNPaperBackgroundView(style: notebook.paperStyle, tone: store.settings.paperTone)
        }
    }

    @ViewBuilder
    private func pagedPencilCanvas(_ notebook: Notebook) -> some View {
        if let pageID = selectedPageID {
            ZStack {
                PencilCanvasView(
                    drawingData: drawingData,
                    tool: tool,
                    color: inkColor,
                    lineWidth: lineWidth,
                    pencilOnly: store.settings.pencilOnlyDrawing,
                    controller: canvasController,
                    onDrawingChanged: { data in
                        handleDrawingChanged(data, pageID: pageID)
                    }
                )
                .allowsHitTesting(!drawingReadOnly && !isInsertingAttachmentPages)

                if drawingReadOnly {
                    FNRecoveryReadOnlyView(
                        title: "无法读取此页笔迹",
                        message: drawingLoadError ?? "为避免覆盖原始笔迹，当前页面已切换为只读状态。",
                        issues: store.recoveryIssues,
                        onRetry: { loadDrawing(pageID: pageID) }
                    )
                }
            }
            .id(pageID)
        } else {
            Color.clear
        }
    }

    private func pageRail(_ notebook: Notebook) -> some View {
        VStack(spacing: 8) {
            FNIconButton(symbol: "plus", size: 34) { addPage() }
                .background(FNTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(FNTheme.divider, lineWidth: 1)
                )

            ScrollView(showsIndicators: false) {
                VStack(spacing: 7) {
                    ForEach(notebook.pages) { page in
                        let pageNumber = (notebook.pages.firstIndex(where: { $0.id == page.id }) ?? 0) + 1
                        Button {
                            switchToPage(page.id)
                        } label: {
                            Text(String(format: "%02d", pageNumber))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(selectedPageID == page.id ? FNTheme.selectionText : FNTheme.secondaryInk)
                                .frame(width: 34, height: 34)
                                .background(selectedPageID == page.id ? FNTheme.selectionFill : FNTheme.card)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(selectedPageID == page.id ? Color.clear : FNTheme.divider, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 10)
        .padding(.bottom, 18)
        .frame(width: 58)
        .background(FNTheme.contentBackground)
        .overlay(alignment: .leading) {
            Rectangle().fill(FNTheme.divider).frame(width: 1)
        }
    }

    private var drawingToolbar: some View {
        HStack(spacing: 8) {
            ForEach(DrawingTool.allCases) { item in
                Button {
                    tool = item
                } label: {
                    VStack(spacing: 1) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 15, weight: .medium))
                        if item == .eraser {
                            Text("橡皮")
                                .font(.system(size: 7, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(tool == item ? FNTheme.selectionText : FNTheme.secondaryInk)
                    .frame(width: item == .eraser ? 52 : 36, height: 36)
                    .background(tool == item ? FNTheme.selectionFill : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        guard item == .eraser, !drawingReadOnly else { return }
                        canvasController.clearWithUndo()
                    }
                )
            }

            divider

            Button {
                canvasController.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            Button {
                canvasController.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)

            divider

            Button {
                showingPalette.toggle()
            } label: {
                Circle()
                    .fill(Color(uiColor: inkColor))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(FNTheme.secondaryInk.opacity(0.9), lineWidth: 1))
                    .frame(width: 34, height: 34)
                    .background(FNTheme.sidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPalette, arrowEdge: .bottom) {
                palettePopover
            }

            Button {
                showingWidth.toggle()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(FNTheme.ink)
                        .frame(width: min(max(lineWidth, 3), 10), height: min(max(lineWidth, 3), 10))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
                .frame(width: 38, height: 34)
                .background(FNTheme.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingWidth, arrowEdge: .bottom) {
                widthPopover
            }

            if notebook?.kind == .infiniteCanvas {
                Button {
                    showingCanvasNavigator.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                        .frame(width: 34, height: 34)
                        .background(FNTheme.sidebar)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("画布缩放与回中")
                .popover(isPresented: $showingCanvasNavigator, arrowEdge: .bottom) {
                    canvasNavigatorPopover
                }
            }

            if !store.settings.autoSave {
                divider
                Button {
                    saveCurrentDrawing()
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(FNTheme.accent)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(FNTheme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.11), radius: 14, y: 5)
    }

    private var divider: some View {
        Rectangle()
            .fill(FNTheme.divider)
            .frame(width: 1, height: 23)
            .padding(.horizontal, 2)
    }

    private var palettePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("笔迹颜色")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FNTheme.secondaryInk)

            HStack(spacing: 10) {
                ForEach(inkPalette.indices, id: \.self) { index in
                    let color = inkPalette[index]
                    Button {
                        inkColor = color
                        hasManuallySelectedInkColor = true
                        showingPalette = false
                    } label: {
                        Circle()
                            .fill(Color(uiColor: color))
                            .frame(width: 25, height: 25)
                            .overlay(
                                Circle().stroke(
                                    color == inkColor
                                        ? FNTheme.accent
                                        : (isMonochrome(color) ? FNTheme.secondaryInk : FNTheme.divider),
                                    lineWidth: color == inkColor ? 2 : (isMonochrome(color) ? 1.5 : 1)
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 0 ? "纯黑" : "颜色选项")
                }
            }

            Divider().overlay(FNTheme.divider)

            ColorPicker("自定义颜色", selection: customInkColorBinding, supportsOpacity: false)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FNTheme.ink)
        }
        .padding(14)
        .background(FNTheme.cardRaised)
    }

    private var customInkColorBinding: Binding<Color> {
        Binding(
            get: { Color(uiColor: inkColor) },
            set: {
                inkColor = UIColor($0)
                hasManuallySelectedInkColor = true
            }
        )
    }

    private var widthPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("笔画粗细")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(FNTheme.secondaryInk)
            Slider(value: $lineWidth, in: 1...18, step: 1)
                .tint(FNTheme.accent)
                .frame(width: 180)
            Text("\(Int(lineWidth)) pt")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
            if tool == .eraser {
                Text("长按 Apple Pencil 约 0.36 秒临时切换为 bitmap 橡皮，松开自动恢复当前工具。")
                    .font(.system(size: 8))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 180, alignment: .leading)
                Text("双击工具栏中的“橡皮”可清空当前画布，支持撤销。")
                    .font(.system(size: 8))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 180, alignment: .leading)
            }
        }
        .padding(16)
    }

    private var inkPalette: [UIColor] {
        [
            UIColor(hex: 0x000000),
            UIColor.white,
            UIColor(hex: 0x26322F),
            UIColor(hex: 0x4F6759),
            UIColor(hex: 0x486A88),
            UIColor(hex: 0x8C5D55),
            UIColor(hex: 0xB38B42),
            UIColor(hex: 0x775E81)
        ]
    }

    private func applyDefaultInkColorIfNeeded() {
        guard !hasManuallySelectedInkColor else { return }
        inkColor = colorScheme == .dark ? UIColor.white : UIColor.black
    }

    private func isMonochrome(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return false
        }
        return (red < 0.08 && green < 0.08 && blue < 0.08)
            || (red > 0.92 && green > 0.92 && blue > 0.92)
    }

    private func initializePagesIfNeeded() {
        guard !didInitialize, let notebook else { return }
        didInitialize = true
        let initialPage = initialPageID.flatMap { id in
            notebook.pages.first { $0.id == id }
        } ?? notebook.pages.first
        if let initialPage {
            selectedPageID = initialPage.id
            loadDrawing(pageID: initialPage.id)
            reloadPageAttachments()
        }
    }

    private func ensurePageSelection() {
        guard let notebook else { return }
        if let selectedPageID, notebook.pages.contains(where: { $0.id == selectedPageID }) {
            return
        }
        saveTask?.cancel()
        saveTask = nil
        guard let firstPage = notebook.pages.first else {
            selectedPageID = nil
            drawingData = Data()
            drawingReadOnly = false
            drawingLoadError = nil
            return
        }
        selectedPageID = firstPage.id
        loadDrawing(pageID: firstPage.id)
    }

    private func switchToPage(_ pageID: UUID) {
        guard pageID != selectedPageID else { return }
        guard flushPendingDrawing() else { return }
        selectedPageID = pageID
        loadDrawing(pageID: pageID)
    }

    private func selectPageNumber(_ page: Int) {
        guard let notebook, !notebook.pages.isEmpty else { return }
        let bounded = min(max(page, 1), notebook.pages.count)
        switchToPage(notebook.pages[bounded - 1].id)
    }

    private func loadDrawing(pageID: UUID) {
        do {
            let data = try store.drawingData(notebookID: notebookID, pageID: pageID)
            drawingData = data
            lastDrawingData = data
            drawingHasPendingSave = false
            canvasController.markDrawingFlushed()
            drawingReadOnly = false
            drawingLoadError = nil
            saveState = .saved
        } catch {
            saveTask?.cancel()
            saveTask = nil
            drawingData = Data()
            lastDrawingData = Data()
            drawingHasPendingSave = false
            drawingReadOnly = true
            drawingLoadError = error.localizedDescription
            saveState = .failed
        }
    }

    private func handleDrawingChanged(_ data: Data, pageID: UUID) {
        guard !drawingReadOnly else { return }
        drawingData = data
        lastDrawingData = data
        drawingHasPendingSave = true
        guard store.settings.autoSave else {
            saveState = .unsaved
            return
        }
        saveState = .saving
        scheduleSave(data: data, pageID: pageID)
    }

    private func scheduleSave(data: Data, pageID: UUID) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            commitDrawing(data, pageID: pageID)
        }
    }

    @discardableResult
    private func commitDrawing(_ data: Data, pageID: UUID) -> Bool {
        guard !drawingReadOnly else { return false }
        do {
            try store.saveDrawing(data, pageID: pageID, notebookID: notebookID)
            drawingHasPendingSave = false
            if pageID == selectedPageID {
                saveState = .saved
            }
            return true
        } catch {
            drawingReadOnly = true
            drawingLoadError = error.localizedDescription
            saveState = .failed
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func flushPendingDrawing() -> Bool {
        saveTask?.cancel()
        saveTask = nil

        if canvasController.hasUnflushedDrawingChanges,
           let latestDrawing = canvasController.currentDrawingData {
            drawingData = latestDrawing
            lastDrawingData = latestDrawing
            drawingHasPendingSave = true
            canvasController.markDrawingFlushed()
        }

        guard drawingHasPendingSave else { return true }
        guard !drawingReadOnly, let selectedPageID else { return false }
        return commitDrawing(lastDrawingData, pageID: selectedPageID)
    }

    private func retryPendingDrawingOnce() {
        guard drawingHasPendingSave, let selectedPageID else { return }
        do {
            try store.saveDrawing(
                lastDrawingData,
                pageID: selectedPageID,
                notebookID: notebookID
            )
            drawingHasPendingSave = false
            drawingReadOnly = false
            drawingLoadError = nil
            saveState = .saved
        } catch {
            drawingReadOnly = true
            drawingLoadError = error.localizedDescription
            saveState = .failed
        }
    }

    @discardableResult
    private func saveCurrentDrawing() -> Bool {
        return flushPendingDrawing()
    }

    private func addPage() {
        guard flushPendingDrawing() else { return }
        do {
            try store.addPage(to: notebookID)
            guard let notebook, let lastPage = notebook.pages.last else { return }
            selectedPageID = lastPage.id
            loadDrawing(pageID: lastPage.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrentPage() {
        guard let notebook, let selectedPageID, notebook.pages.count > 1 else { return }
        saveTask?.cancel()
        saveTask = nil
        drawingHasPendingSave = false
        do {
            try store.deletePages(notebookID: notebookID, pageIDs: [selectedPageID])
            ensurePageSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadPageAttachments() {
        guard let selectedPageID else {
            pageAttachmentResources = []
            return
        }
        do {
            pageAttachmentResources = try store.attachments(
                forNotebookID: notebookID,
                pageID: selectedPageID
            )
        } catch {
            pageAttachmentResources = []
            errorMessage = error.localizedDescription
        }
    }

    private func detachAttachment(_ attachment: AttachmentRef) {
        guard let selectedPageID else { return }
        do {
            try store.detachResource(
                resourceID: attachment.resourceID,
                notebookID: notebookID,
                pageID: selectedPageID
            )
            reloadPageAttachments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func insertAttachmentPages(_ resource: ResourceItem) {
        guard !isInsertingAttachmentPages,
              notebook?.kind == .paged,
              let anchorPageID = selectedPageID,
              flushPendingDrawing() else { return }

        isInsertingAttachmentPages = true
        Task { @MainActor in
            do {
                let insertedPages = try await store.insertAttachmentPages(
                    resourceID: resource.id,
                    notebookID: notebookID,
                    afterPageID: anchorPageID
                )
                guard flushPendingDrawing() else {
                    isInsertingAttachmentPages = false
                    return
                }
                isInsertingAttachmentPages = false
                reloadPageAttachments()
                if let firstInsertedPage = insertedPages.first {
                    selectedPageID = firstInsertedPage.id
                    loadDrawing(pageID: firstInsertedPage.id)
                    reloadPageAttachments()
                }
            } catch {
                isInsertingAttachmentPages = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func reloadAfterFullScreen() {
        guard let notebook else { return }
        if let selectedPageID, notebook.pages.contains(where: { $0.id == selectedPageID }) {
            loadDrawing(pageID: selectedPageID)
        } else {
            selectedPageID = nil
            ensurePageSelection()
        }
        reloadPageAttachments()
    }

    private func updatePaperStyle(_ style: PaperStyle) {
        guard notebook != nil else { return }
        do {
            try store.setNotebookPaperStyle(id: notebookID, style: style)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DrawingSaveState: Equatable {
    case saved
    case saving
    case unsaved
    case failed

    var label: String {
        switch self {
        case .saved: return "已保存"
        case .saving: return "正在保存"
        case .unsaved: return "未保存"
        case .failed: return "保存失败"
        }
    }

    var color: Color {
        switch self {
        case .saved: return FNTheme.accent
        case .saving: return FNTheme.secondaryInk
        case .unsaved: return Color(hex: 0xB38B42)
        case .failed: return FNTheme.danger
        }
    }
}



private struct AttachmentPageContext {
    let attachment: AttachmentRef
    let resource: ResourceItem
    let url: URL
}


private struct AttachmentPreviewRequest: Identifiable {
    let id = UUID()
    let resource: ResourceItem
    let pageIndex: Int?
}
