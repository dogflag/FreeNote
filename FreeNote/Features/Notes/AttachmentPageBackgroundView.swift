import SwiftUI
import PDFKit
import WebKit
import UIKit

struct AttachmentPageBackgroundView: View {
    @EnvironmentObject private var store: FreeNoteStore
    let attachment: AttachmentRef
    let resource: ResourceItem
    let url: URL

    @State private var pageImage: UIImage?
    @State private var previewHTML: String?
    @State private var loadError: String?

    var body: some View {
        ZStack {
            FNTheme.paperColor(tone: store.settings.paperTone)

            if let loadError {
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(loadError)
                        .font(.system(size: 10))
                }
                .foregroundStyle(FNTheme.secondaryInk)
                .padding(18)
            } else if let pageImage {
                Image(uiImage: pageImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let previewHTML {
                NonInteractiveHTMLView(
                    html: previewHTML,
                    baseURL: url.deletingLastPathComponent()
                )
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .clipped()
        .task {
            await load()
        }
    }

    private func load() async {
        guard let sourceIndex = attachment.pageIndex else { return }
        switch resource.kind {
        case .pdf:
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: sourceIndex) else {
                loadError = "无法读取 PDF 页面。"
                return
            }
            let bounds = page.bounds(for: .mediaBox)
            let maxDimension: CGFloat = 2000
            guard bounds.width > 0, bounds.height > 0 else {
                loadError = "PDF 页面尺寸无效。"
                return
            }
            let scale = min(maxDimension / bounds.width, maxDimension / bounds.height)
            let target = CGSize(
                width: max(bounds.width * scale, 1),
                height: max(bounds.height * scale, 1)
            )
            pageImage = page.thumbnail(of: target, for: .mediaBox)
        case .image:
            pageImage = UIImage(contentsOfFile: url.path)
            if pageImage == nil {
                loadError = "无法读取图片附件。"
            }
        case .office, .epub, .text:
            do {
                let html = try await store.resourcePreviewHTML(
                    resourceID: resource.id,
                    pageIndex: sourceIndex
                )
                await MainActor.run {
                    previewHTML = html
                    if html == nil {
                        loadError = "该附件暂不支持应用内页面预览。"
                    }
                }
            } catch {
                await MainActor.run {
                    loadError = error.localizedDescription
                }
            }
        case .audio, .other:
            loadError = "该附件不能作为页面背景显示。"
        }
    }
}

private struct NonInteractiveHTMLView: UIViewRepresentable {
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
        webView.isUserInteractionEnabled = false
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
