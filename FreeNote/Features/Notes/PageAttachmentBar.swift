import SwiftUI
import UIKit

struct PageAttachmentBar: View {
    let resources: [ResourceItem]
    let urlFor: (ResourceItem) -> URL?
    let onOpen: (ResourceItem) -> Void
    let onDetach: (ResourceItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.system(size: 10, weight: .semibold))
                Text("页面附件")
                    .font(.system(size: 10, weight: .semibold))
                Text("\(resources.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
                Spacer()
            }
            .foregroundStyle(FNTheme.secondaryInk)
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(resources) { resource in
                        AttachmentResourceCard(
                            resource: resource,
                            url: urlFor(resource),
                            onOpen: { onOpen(resource) },
                            onDetach: { onDetach(resource) }
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

private struct AttachmentResourceCard: View {
    let resource: ResourceItem?
    let url: URL?
    let onOpen: () -> Void
    let onDetach: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onOpen) {
                HStack(spacing: 8) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(resource?.title ?? "资源缺失")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(FNTheme.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let resource {
                            Text(resource.kind.fnTitle)
                                .font(.system(size: 8))
                                .foregroundStyle(FNTheme.tertiaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(resource == nil)

            Button(action: onDetach) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("移除附件")
        }
        .padding(.horizontal, 8)
        .frame(width: 156, height: 54)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let resource, resource.kind == .image, let url {
            AttachmentImageThumbnail(url: url)
        } else if let resource {
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
