import SwiftUI
import PDFKit
import PencilKit
import UIKit

struct ReaderView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    let bookID: UUID

    @State private var currentPage = 1
    @State private var annotationData = Data()
    @State private var lastAnnotationData = Data()
    @State private var lastLoadedPage = 1
    @State private var interactionMode: ReaderInteractionMode = .text
    @State private var marginScale: Double = 0.2
    @State private var showingLayout = false
    @State private var showingOutline = false
    @State private var saveState: ReaderSaveState = .saved
    @State private var noticeMessage: String?
    @State private var errorMessage: String?
    @State private var didInitialize = false
    @State private var annotationReadOnly = false
    @State private var annotationHasPendingSave = false
    @State private var annotationLoadError: String?
    @State private var annotationSaveTask: Task<Void, Never>?
    @StateObject private var canvasController = PencilCanvasController()

    private var book: BookItem? {
        store.books.first { $0.id == bookID }
    }

    var body: some View {
        Group {
            if let book {
                readerContent(book)
            } else {
                ZStack {
                    FNTheme.appBackground.ignoresSafeArea()
                    VStack(spacing: 16) {
                        FNEmptyState(
                            symbol: "book.closed",
                            title: "无法打开文档",
                            message: "文档可能已被移除或本地文件暂时不可用。"
                        )
                        Button("返回书架") { dismiss() }
                            .buttonStyle(.borderedProminent)
                            .tint(FNTheme.accent)
                    }
                    .padding(30)
                }
            }
        }
        .interactiveDismissDisabled(annotationHasPendingSave)
        .onAppear(perform: initializeIfNeeded)
        .onChange(of: currentPage) { newPage in
            handlePageChanged(newPage)
        }
        .onDisappear {
            if !flushPendingAnnotation() {
                store.reportRecoveryIssue("退出界面时仍有未保存内容，正在同步重试。")
                retryPendingAnnotationOnce()
            }
        }
        .sheet(isPresented: $showingLayout) {
            ReaderLayoutSheet(
                marginScale: $marginScale,
                onInsertBlankPage: {
                    showingLayout = false
                    noticeMessage = "插页控件已就绪。当前 Core 契约尚未暴露 PDF 页面结构编辑接口，因此本次仅预览留白调整，不会修改原 PDF。"
                }
            )
            .presentationDetents([.height(290)])
        }
        .alert("提示", isPresented: Binding(
            get: { noticeMessage != nil },
            set: { if !$0 { noticeMessage = nil } }
        )) {
            Button("好", role: .cancel) { noticeMessage = nil }
        } message: {
            Text(noticeMessage ?? "")
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

    @ViewBuilder
    private func readerContent(_ book: BookItem) -> some View {
        if book.pageCount <= 0 {
            zeroPageReaderContent(book)
        } else {
            ZStack(alignment: .bottomTrailing) {
                VStack(spacing: 0) {
                    readerHeader(book)
                    Rectangle().fill(FNTheme.divider).frame(height: 1)
                    readerSurface(book)
                }

                OutlineHandle {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingOutline = true
                    }
                }
                .padding(.trailing, 20)
                .padding(.bottom, 94)

                if showingOutline {
                    OutlineDrawerOverlay(
                        isPresented: $showingOutline,
                        documentTitle: book.title,
                        pageCount: book.pageCount,
                        initialNodes: book.outline,
                        initialPage: currentPage,
                        onSave: { try store.updateOutline($0, forBookID: book.id) },
                        onJumpToPage: outlineJumpAction(for: book)
                    )
                    .transition(.opacity)
                    .zIndex(20)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showingOutline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                readerBottomBar(book)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 7)
                    .background(FNTheme.appBackground.opacity(0.92))
            }
            .preferredColorScheme(store.settings.appearance.fnColorScheme)
        }
    }

    private func zeroPageReaderContent(_ book: BookItem) -> some View {
        VStack(spacing: 0) {
            readerHeader(book)
            Rectangle().fill(FNTheme.divider).frame(height: 1)
            FNEmptyState(
                symbol: "doc.questionmark",
                title: "暂不支持预览",
                message: "未识别到可分页内容。当前版本不会为该文档启用批注或大纲编辑。"
            )
            .background(FNTheme.contentBackground)
        }
        .preferredColorScheme(store.settings.appearance.fnColorScheme)
    }

    private func outlineJumpAction(for book: BookItem) -> ((Int) -> Void)? {
        guard book.kind == .pdf, book.pageCount > 0 else { return nil }
        return { page in goToPage(page) }
    }

    private func readerHeader(_ book: BookItem) -> some View {
        HStack(spacing: 13) {
            Button {
                guard flushPendingAnnotation() else { return }
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .frame(width: 36, height: 36)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(FNTheme.serif(20, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(book.kind.fnTitle)
                    Text("·")
                    if book.pageCount <= 0 {
                        Text("暂不支持预览")
                    } else if book.kind == .pdf {
                        Text("第 \(currentPage) / \(book.pageCount) 页")
                        Text("·")
                        Text(saveState.label)
                            .foregroundStyle(saveState.color)
                    } else {
                        Text("系统预览")
                    }
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
            }

            Spacer()

            if book.kind == .pdf, book.pageCount > 0 {
                HStack(spacing: 3) {
                    interactionButton(title: "选择", symbol: "text.cursor", value: .text)
                    interactionButton(title: "批注", symbol: "pencil.tip", value: .annotation)
                }
                .padding(3)
                .background(FNTheme.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                FNPageIndicator(current: currentPage, total: book.pageCount)
            }

            if book.pageCount > 0 {
                Button {
                    showingLayout = true
                } label: {
                    Label("留白预览", systemImage: "rectangle.inset.filled")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(FNTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(FNTheme.divider, lineWidth: 1)
                    )
            }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(FNTheme.card.opacity(0.82))
    }

    private func interactionButton(title: String, symbol: String, value: ReaderInteractionMode) -> some View {
        Button {
            interactionMode = value
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(interactionMode == value ? FNTheme.accent : FNTheme.secondaryInk)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(interactionMode == value ? FNTheme.card : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func readerSurface(_ book: BookItem) -> some View {
        if book.kind == .pdf {
            pdfSurface(book)
        } else {
            quickLookSurface(book)
        }
    }

    private func pdfSurface(_ book: BookItem) -> some View {
        Group {
            if let url = store.storedURL(for: book) {
                GeometryReader { proxy in
                    let logicalSize = CGSize(width: 760, height: 1075)
                    let inset = CGFloat(marginScale) * 28
                    let availableWidth = max(proxy.size.width - inset * 2, 200)
                    let availableHeight = max(proxy.size.height - inset * 2, 200)
                    let pageScale = min(availableWidth / logicalSize.width, availableHeight / logicalSize.height)

                    ZStack {
                        ZStack {
                            PDFKitReaderView(url: url, currentPage: $currentPage)
                                .frame(width: logicalSize.width, height: logicalSize.height)
                                .background(FNTheme.paperColor(tone: "pureWhite"))
                                .allowsHitTesting(interactionMode == .text)

                            if interactionMode == .annotation, !annotationReadOnly {
                                PencilCanvasView(
                                    drawingData: annotationData,
                                    tool: .pen,
                                    color: UIColor(hex: 0x26322F),
                                    lineWidth: 3,
                                    pencilOnly: store.settings.pencilOnlyDrawing,
                                    controller: canvasController,
                                    onDrawingChanged: { data in
                                        handleAnnotationChanged(data, page: currentPage)
                                    }
                                )
                                .id("annotation-\(book.id)-\(currentPage)")
                                .frame(width: logicalSize.width, height: logicalSize.height)
                                .background(Color.clear)
                            }
                        }
                        .frame(width: logicalSize.width, height: logicalSize.height)
                        .scaleEffect(pageScale)
                        .frame(
                            width: logicalSize.width * pageScale,
                            height: logicalSize.height * pageScale
                        )

                        if interactionMode == .annotation, annotationReadOnly {
                            FNRecoveryReadOnlyView(
                                title: "无法读取此页批注",
                                message: annotationLoadError ?? "为避免覆盖原始批注，当前页面已切换为只读状态。",
                                issues: store.recoveryIssues,
                                onRetry: { loadAnnotation(page: currentPage) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                FNEmptyState(
                    symbol: "doc.questionmark",
                    title: "找不到 PDF",
                    message: "本地文件可能已移动或暂时不可读。"
                )
            }
        }
        .background(FNTheme.appBackground)
    }

    private func quickLookSurface(_ book: BookItem) -> some View {
        Group {
            if let url = store.storedURL(for: book) {
                ZStack(alignment: .top) {
                    QuickLookPreviewController(url: url)
                    FNInlineNotice(
                        symbol: "info.circle",
                        text: "EPUB、Office 等格式首版通过系统 QuickLook 预览；完整排版批注将在后续格式适配中提供。"
                    )
                    .padding(14)
                }
            } else {
                FNEmptyState(
                    symbol: "doc.questionmark",
                    title: "找不到文件",
                    message: "本地文件可能已移动或暂时不可读。"
                )
            }
        }
        .background(FNTheme.contentBackground)
    }

    private func readerBottomBar(_ book: BookItem) -> some View {
        HStack {
            if book.kind == .pdf {
                Button {
                    goToPage(currentPage - 1)
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage > 1 ? FNTheme.secondaryInk : FNTheme.tertiaryInk)
                .disabled(currentPage <= 1)
            }

            Spacer()

            Text(book.kind == .pdf ? "上下页可通过页脚或大纲跳转" : "系统预览中")
                .font(.system(size: 9))
                .foregroundStyle(FNTheme.tertiaryInk)

            Spacer()

            if book.kind == .pdf {
                Button {
                    goToPage(currentPage + 1)
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage < book.pageCount ? FNTheme.secondaryInk : FNTheme.tertiaryInk)
                .disabled(currentPage >= book.pageCount)
            }
        }
        .frame(height: 32)
    }

    private func initializeIfNeeded() {
        guard !didInitialize, let book else { return }
        didInitialize = true
        guard book.pageCount > 0 else { return }
        let bounded = min(max(book.currentPage, 1), book.pageCount)
        currentPage = bounded
        lastLoadedPage = bounded
        if book.kind == .pdf {
            loadAnnotation(page: bounded)
            interactionMode = .text
            do {
                try store.updateReadingProgress(bookID: book.id, page: bounded)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            annotationData = Data()
            lastAnnotationData = Data()
        }
    }

    private func handlePageChanged(_ newPage: Int) {
        guard didInitialize, let book, book.kind == .pdf, book.pageCount > 0 else { return }
        let bounded = min(max(newPage, 1), book.pageCount)
        if bounded != newPage {
            currentPage = bounded
            return
        }

        if lastLoadedPage != bounded {
            guard flushPendingAnnotation() else {
                currentPage = lastLoadedPage
                return
            }
            lastLoadedPage = bounded
            loadAnnotation(page: bounded)
        }

        do {
            try store.updateReadingProgress(bookID: book.id, page: bounded)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func goToPage(_ page: Int) {
        guard let book, book.pageCount > 0 else { return }
        let bounded = min(max(page, 1), book.pageCount)
        if currentPage == bounded { return }
        currentPage = bounded
    }

    private func loadAnnotation(page: Int) {
        annotationSaveTask?.cancel()
        annotationSaveTask = nil
        do {
            let data = try store.annotationData(bookID: bookID, pageIndex: page)
            annotationData = data
            lastAnnotationData = data
            annotationHasPendingSave = false
            annotationReadOnly = false
            annotationLoadError = nil
            saveState = .saved
        } catch {
            annotationData = Data()
            lastAnnotationData = Data()
            annotationHasPendingSave = false
            annotationReadOnly = true
            annotationLoadError = error.localizedDescription
            interactionMode = .annotation
            saveState = .failed
        }
    }

    private func handleAnnotationChanged(_ data: Data, page: Int) {
        guard !annotationReadOnly else { return }
        annotationData = data
        lastAnnotationData = data
        annotationHasPendingSave = true
        guard store.settings.autoSave else {
            saveState = .unsaved
            return
        }
        saveState = .saving
        scheduleAnnotationSave(data: data, page: page)
    }

    private func scheduleAnnotationSave(data: Data, page: Int) {
        annotationSaveTask?.cancel()
        annotationSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled else { return }
            commitAnnotation(data: data, page: page)
        }
    }

    @discardableResult
    private func commitAnnotation(data: Data, page: Int) -> Bool {
        guard !annotationReadOnly else { return false }
        do {
            try store.saveAnnotation(data, bookID: bookID, pageIndex: page)
            annotationHasPendingSave = false
            if page == currentPage {
                saveState = .saved
            }
            return true
        } catch {
            annotationReadOnly = true
            annotationLoadError = error.localizedDescription
            interactionMode = .annotation
            saveState = .failed
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func flushPendingAnnotation() -> Bool {
        annotationSaveTask?.cancel()
        annotationSaveTask = nil
        guard annotationHasPendingSave else { return true }
        guard let book, didInitialize, book.kind == .pdf, book.pageCount > 0, !annotationReadOnly else {
            return false
        }
        return commitAnnotation(data: lastAnnotationData, page: lastLoadedPage)
    }

    private func retryPendingAnnotationOnce() {
        guard let book, annotationHasPendingSave, book.kind == .pdf, book.pageCount > 0 else {
            return
        }
        do {
            try store.saveAnnotation(
                lastAnnotationData,
                bookID: bookID,
                pageIndex: lastLoadedPage
            )
            annotationHasPendingSave = false
            annotationReadOnly = false
            annotationLoadError = nil
            saveState = .saved
        } catch {
            annotationReadOnly = true
            annotationLoadError = error.localizedDescription
            interactionMode = .annotation
            saveState = .failed
        }
    }
}

private enum ReaderInteractionMode {
    case text
    case annotation
}

private enum ReaderSaveState {
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

private struct ReaderLayoutSheet: View {
    @Binding var marginScale: Double
    let onInsertBlankPage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("页面留白（预览）")
                .font(FNTheme.serif(24, weight: .semibold))
                .foregroundStyle(FNTheme.ink)
            Text("仅调整阅读时的视觉留白，尚未写入原 PDF，也不会更改页面尺寸。")
                .font(.system(size: 11))
                .foregroundStyle(FNTheme.secondaryInk)

            HStack(spacing: 12) {
                Text("窄")
                Slider(value: $marginScale, in: 0...1)
                    .tint(FNTheme.accent)
                Text("宽")
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FNTheme.tertiaryInk)

            FNInlineNotice(
                symbol: "info.circle",
                text: "插入空白页需要 Core 提供 PDF 页面结构编辑接口；本版先保留入口与提示。"
            )

            HStack {
                Button("插入空白页", action: onInsertBlankPage)
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(Int(marginScale * 100))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
        }
        .padding(24)
        .background(FNTheme.contentBackground)
    }
}

private final class LockedPDFView: PDFView {
    override func layoutSubviews() {
        super.layoutSubviews()
        lockInternalScrolling(in: self)
    }

    private func lockInternalScrolling(in view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            if recognizer is UIPinchGestureRecognizer {
                recognizer.isEnabled = false
            }
            if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired >= 2 {
                tap.isEnabled = false
            }
        }
        for subview in view.subviews {
            if let scrollView = subview as? UIScrollView {
                scrollView.isScrollEnabled = false
                scrollView.pinchGestureRecognizer?.isEnabled = false
            }
            lockInternalScrolling(in: subview)
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPinchGestureRecognizer {
            return false
        }
        if let tap = gestureRecognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired >= 2 {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

struct PDFKitReaderView: UIViewRepresentable {
    let url: URL
    @Binding var currentPage: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PDFView {
        let pdfView = LockedPDFView()
        pdfView.backgroundColor = UIColor.clear
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        pdfView.autoScales = true
        pdfView.displaysPageBreaks = false
        pdfView.document = PDFDocument(url: url)
        pdfView.delegate = context.coordinator

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        if let document = pdfView.document {
            let index = min(max(currentPage - 1, 0), max(document.pageCount - 1, 0))
            if let page = document.page(at: index) {
                pdfView.go(to: page)
            }
        }
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        context.coordinator.parent = self
        guard let document = pdfView.document, document.pageCount > 0 else { return }
        let targetIndex = min(max(currentPage - 1, 0), document.pageCount - 1)
        guard let page = document.page(at: targetIndex) else { return }
        if pdfView.currentPage != page {
            pdfView.go(to: page)
        }
    }

    static func dismantleUIView(_ pdfView: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        pdfView.document = nil
    }

    final class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFKitReaderView

        init(_ parent: PDFKitReaderView) {
            self.parent = parent
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let pdfView = notification.object as? PDFView,
                  let page = pdfView.currentPage,
                  let document = pdfView.document else { return }
            let index = document.index(for: page)
            guard index >= 0 else { return }
            let pageNumber = index + 1
            if parent.currentPage != pageNumber {
                DispatchQueue.main.async {
                    self.parent.currentPage = pageNumber
                }
            }
        }
    }
}
