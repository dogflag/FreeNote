import SwiftUI
import PDFKit
import WebKit
import AVFoundation
import UIKit

struct AttachmentPreviewView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    let resource: ResourceItem
    var pageIndex: Int? = nil

    @State private var previewHTML: String?
    @State private var textContent = ""
    @State private var errorMessage: String?
    @State private var pdfPage = 1
    @State private var pdfPageCount = 1
    @State private var showingShareSheet = false
    @State private var isLoading = true
    @StateObject private var audioPlayer = AudioAttachmentPlayer()

    private var url: URL? {
        store.storedURL(for: resource)
    }

    private var previewSubtitle: String {
        guard let pageIndex else {
            return "\(resource.title) · \(resource.kind.fnTitle)"
        }
        return "\(resource.title) · 第 \(pageIndex + 1) 页"
    }

    var body: some View {
        VStack(spacing: 0) {
            FNModalHeader(
                title: "附件预览",
                subtitle: previewSubtitle,
                onClose: { dismiss() }
            )

            Group {
                if isLoading {
                    ProgressView("正在准备预览…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    unsupportedView(message: errorMessage)
                } else {
                    previewContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FNTheme.contentBackground)
        }
        .background(FNTheme.contentBackground)
        .task {
            await loadPreview()
        }
        .onDisappear {
            audioPlayer.stop()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url {
                ActivityView(activityItems: [url])
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch resource.kind {
        case .pdf:
            if let url {
                pdfContent(url: url)
            } else {
                unsupportedView(message: "PDF 文件不存在。")
            }
        case .image:
            if let url, let image = UIImage(contentsOfFile: url.path) {
                ZoomableImageView(image: image)
                    .padding(12)
            } else {
                unsupportedView(message: "无法读取图片文件。")
            }
        case .audio:
            if let url {
                audioContent(url: url)
            } else {
                unsupportedView(message: "音频文件不存在。")
            }
        case .office, .epub:
            if let previewHTML {
                HTMLPreviewView(
                    html: previewHTML,
                    baseURL: url?.deletingLastPathComponent()
                )
            } else {
                unsupportedView(message: "该文档暂不支持应用内 HTML 预览。")
            }
        case .text:
            if let previewHTML {
                HTMLPreviewView(
                    html: previewHTML,
                    baseURL: url?.deletingLastPathComponent()
                )
            } else if !textContent.isEmpty {
                PlainTextPreview(text: textContent)
            } else {
                unsupportedView(message: "无法读取文本内容。")
            }
        case .other:
            unsupportedView(message: "该格式暂不支持应用内预览。")
        }
    }

    private func pdfContent(url: URL) -> some View {
        VStack(spacing: 0) {
            PDFKitReaderView(url: url, currentPage: $pdfPage)
            HStack(spacing: 16) {
                Button {
                    pdfPage = max(pdfPage - 1, 1)
                } label: {
                    Label("上一页", systemImage: "chevron.left")
                }
                .disabled(pdfPage <= 1)

                Text("第 \(pdfPage) / \(max(pdfPageCount, 1)) 页")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)

                Button {
                    pdfPage = min(pdfPage + 1, max(pdfPageCount, 1))
                } label: {
                    Label("下一页", systemImage: "chevron.right")
                }
                .disabled(pdfPage >= pdfPageCount)
            }
            .buttonStyle(.plain)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(FNTheme.card)
        }
    }

    private func audioContent(url: URL) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 70, weight: .light))
                .foregroundStyle(FNTheme.accent)
            Text(resource.title)
                .font(FNTheme.serif(22, weight: .semibold))
                .foregroundStyle(FNTheme.ink)
            Slider(
                value: Binding(
                    get: { audioPlayer.currentTime },
                    set: { audioPlayer.seek(to: $0) }
                ),
                in: 0...max(audioPlayer.duration, 0.1)
            )
            .tint(FNTheme.accent)
            .frame(maxWidth: 420)
            HStack {
                Text(audioPlayer.currentTimeLabel)
                Spacer()
                Text(audioPlayer.durationLabel)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FNTheme.tertiaryInk)
            .frame(maxWidth: 420)
            Button {
                audioPlayer.toggle()
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(FNTheme.selectionFill)
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .task(id: url) {
            audioPlayer.load(url: url)
        }
    }

    @ViewBuilder
    private func unsupportedView(message: String) -> some View {
        if url != nil {
            FNEmptyState(
                symbol: "doc.questionmark",
                title: "暂不支持应用内预览",
                message: message,
                actionTitle: "使用其他应用打开",
                action: { showingShareSheet = true }
            )
        } else {
            FNEmptyState(
                symbol: "doc.questionmark",
                title: "暂不支持应用内预览",
                message: message
            )
        }
    }

    private func loadPreview() async {
        guard errorMessage == nil else { return }
        guard let url else {
            isLoading = false
            errorMessage = "本地资源文件不存在。"
            return
        }

        switch resource.kind {
        case .pdf:
            pdfPageCount = max(PDFDocument(url: url)?.pageCount ?? 0, 1)
            pdfPage = min(max((pageIndex ?? 0) + 1, 1), pdfPageCount)
            isLoading = false
        case .image, .audio:
            isLoading = false
        case .office, .epub:
            do {
                let html = try await store.resourcePreviewHTML(
                    resourceID: resource.id,
                    pageIndex: pageIndex
                )
                await MainActor.run {
                    previewHTML = html
                    if html == nil {
                        errorMessage = "当前 Office/EPUB 内容没有可用的应用内 HTML 预览。"
                    }
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        case .text:
            let ext = url.pathExtension.lowercased()
            if ext == "html" || ext == "htm" {
                do {
                    previewHTML = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                do {
                    textContent = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        case .other:
            isLoading = false
            errorMessage = "该格式暂不支持应用内预览。"
        }
    }
}

private final class AudioAttachmentPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var currentTimeLabel: String { format(currentTime) }
    var durationLabel: String { format(duration) }

    func load(url: URL) {
        stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            currentTime = 0
        } catch {
            duration = 0
            currentTime = 0
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.timer?.invalidate()
                }
            }
        }
    }

    func seek(to value: Double) {
        guard let player else { return }
        player.currentTime = min(max(value, 0), player.duration)
        currentTime = player.currentTime
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
    }

    private func format(_ value: Double) -> String {
        let total = max(Int(value.rounded()), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator(image: image)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.imageView?.image = image
        if let imageView = context.coordinator.imageView {
            imageView.frame = scrollView.bounds
        }
        scrollView.contentSize = scrollView.bounds.size
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        let image: UIImage
        weak var imageView: UIImageView?

        init(image: UIImage) {
            self.image = image
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }
    }
}

private struct HTMLPreviewView: UIViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.loadHTMLString(html, baseURL: baseURL)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML = ""

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let allowedSchemes = ["about", "data", "file"]
            if let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }
    }
}

private struct PlainTextPreview: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 20, left: 18, bottom: 20, right: 18)
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
