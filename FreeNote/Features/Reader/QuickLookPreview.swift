import SwiftUI
import QuickLook

struct QuickLookPreviewController: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

struct QuickLookResourceSheet: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    let resource: ResourceItem

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FNDocumentBadge(kind: resource.kind)
                Text(resource.title)
                    .font(FNTheme.serif(20, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                    .lineLimit(1)
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(FNTheme.selectionFill)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(FNTheme.card)

            Rectangle().fill(FNTheme.divider).frame(height: 1)

            if let url = store.storedURL(for: resource) {
                QuickLookPreviewController(url: url)
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
}
