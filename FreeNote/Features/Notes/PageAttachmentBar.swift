import SwiftUI
import UIKit

struct PageAttachmentBar: View {
    let attachments: [AttachmentRef]
    let resources: [ResourceItem]
    let allowsPageInsert: Bool
    let urlFor: (ResourceItem) -> URL?
    let onOpen: (ResourceItem, Int?) -> Void
    let onDetach: (AttachmentRef) -> Void
    let onInsertAfter: (ResourceItem) -> Void

    private var items: [AttachmentDisplayItem] {
        let resourceMap = Dictionary(uniqueKeysWithValues: resources.map { ($0.id, $0) })
        return attachments.map { attachment in
            AttachmentDisplayItem(
                attachment: attachment,
                resource: resourceMap[attachment.resourceID]
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 10, weight: .semibold))
                Text("页面附件")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(items.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
                Spacer()
            }
            .foregroundStyle(FNTheme.secondaryInk)
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        AttachmentResourceCard(
                            item: item,
                            url: item.resource.flatMap { urlFor($0) },
                            canInsertPages: allowsPageInsert && item.canInsertPages,
                            onOpen: {
                                if let resource = item.resource { onOpen(resource, item.attachment.pageIndex) }
                            },
                            onDetach: { onDetach(item.attachment) },
                            onInsertAfter: {
                                if let resource = item.resource { onInsertAfter(resource) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .background(FNTheme.cardRaised.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }
}

private struct AttachmentDisplayItem: Identifiable {
    let attachment: AttachmentRef
    let resource: ResourceItem?

    var id: UUID { attachment.id }

    var canInsertPages: Bool {
        guard attachment.pageIndex == nil, let resource else { return false }
        return ["pdf", "pptx", "epub"].contains(resource.fileName.pathExtension.lowercased())
    }
}

private struct AttachmentResourceCard: View {
    let item: AttachmentDisplayItem
    let url: URL?
    let canInsertPages: Bool
    let onOpen: () -> Void
    let onDetach: () -> Void
    let onInsertAfter: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.resource?.title ?? "资源缺失")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FNTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let resource = item.resource {
                            Text(detailText(for: resource))
                                .font(.system(size: 8))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.resource == nil)

            if canInsertPages {
                Menu {
                    Button("拆页插入到当前页之后", action: onInsertAfter)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(FNTheme.secondaryInk)
                }
                .buttonStyle(.plain)
            }

            Button(action: onDetach) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除附件")
        }
        .padding(.horizontal, 8)
        .frame(width: canInsertPages ? 188 : 156, height: 54)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }

    private func detailText(for resource: ResourceItem) -> String {
        if let pageIndex = item.attachment.pageIndex {
            return "\(resource.kind.fnTitle) · 第 \(pageIndex + 1) 页"
        }
        return resource.kind.fnTitle
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let resource = item.resource, resource.kind == .image, let url {
            AttachmentImageThumbnail(url: url)
        } else if let resource = item.resource {
            Image(systemName: resource.kind.fnSymbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 38)
                .background(resource.kind.fnTint)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
                .frame(width: 34, height: 38)
                .background(FNTheme.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct AttachmentImageThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FNTheme.selectionText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(FNTheme.selectionFill)
            }
        }
        .frame(width: 34, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onAppear {
            if image == nil {
                image = UIImage(contentsOfFile: url.path)
            }
        }
    }
}
