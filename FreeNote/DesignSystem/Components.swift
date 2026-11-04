import SwiftUI
import UIKit

struct FNCardModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(FNTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(FNTheme.divider, lineWidth: 1)
            )
    }
}

extension View {
    func fnCard(padding: CGFloat = 18, radius: CGFloat = 18) -> some View {
        modifier(FNCardModifier(padding: padding, radius: radius))
    }
}

struct FNIconButton: View {
    let symbol: String
    var title: String? = nil
    var selected = false
    var tint: Color = FNTheme.ink
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                if let title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .foregroundStyle(selected ? FNTheme.accent : tint)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, title == nil ? 0 : 10)
            .background(selected ? FNTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

struct FNTopActionButton: View {
    let symbol: String
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : FNTheme.ink)
                .padding(.horizontal, 15)
                .frame(height: 38)
                .background(prominent ? FNTheme.accent : FNTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(prominent ? Color.clear : FNTheme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct FNFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : FNTheme.secondaryInk)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(isSelected ? FNTheme.ink : FNTheme.sidebar.opacity(0.72))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FNSearchField: View {
    @Binding var text: String
    var placeholder = "搜索"

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(FNTheme.tertiaryInk)
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .textFieldStyle(.plain)
                .foregroundStyle(FNTheme.ink)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 38)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }
}

struct FNSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(FNTheme.serif(20, weight: .semibold))
                    .foregroundStyle(FNTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
            }
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
        }
    }
}

struct FNEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(FNTheme.accent)
                .frame(width: 68, height: 68)
                .background(FNTheme.accentSoft)
                .clipShape(Circle())
            Text(title)
                .font(FNTheme.serif(20, weight: .semibold))
                .foregroundStyle(FNTheme.ink)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(FNTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 310)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(FNTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FNDocumentBadge: View {
    let kind: DocumentKind
    var compact = false

    var body: some View {
        Text(kind.fnTitle.uppercased())
            .font(.system(size: compact ? 8 : 9, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, compact ? 5 : 7)
            .frame(height: compact ? 18 : 22)
            .background(kind.fnTint)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct FNPaperBackgroundView: View {
    let style: PaperStyle
    let tone: String

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                switch style {
                case .blank:
                    break
                case .lined:
                    let gap: CGFloat = 28
                    var path = Path()
                    var y = gap
                    while y < size.height {
                        path.move(to: CGPoint(x: 28, y: y))
                        path.addLine(to: CGPoint(x: size.width - 28, y: y))
                        y += gap
                    }
                    context.stroke(path, with: .color(FNTheme.divider.opacity(0.58)), lineWidth: 0.7)
                case .grid:
                    let gap: CGFloat = 26
                    var path = Path()
                    var x = gap
                    while x < size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        x += gap
                    }
                    var y = gap
                    while y < size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        y += gap
                    }
                    context.stroke(path, with: .color(FNTheme.divider.opacity(0.46)), lineWidth: 0.65)
                case .dotted:
                    let gap: CGFloat = 24
                    var path = Path()
                    var y = gap
                    while y < size.height {
                        var x = gap
                        while x < size.width {
                            path.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                            x += gap
                        }
                        y += gap
                    }
                    context.fill(path, with: .color(FNTheme.tertiaryInk.opacity(0.38)))
                }
            }
            .background(FNTheme.paperColor(tone: tone))
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// A transparent UIKit gesture target that deliberately ignores Apple Pencil touches.
struct FingerGestureCaptureView: UIViewRepresentable {
    let onTap: () -> Void
    let onSwipeUp: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onSwipeUp: onSwipeUp)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isOpaque = false

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        context.coordinator.tapRecognizer = tap
        context.coordinator.panRecognizer = pan
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onSwipeUp = onSwipeUp
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onSwipeUp: () -> Void
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var panRecognizer: UIPanGestureRecognizer?
        private var didTriggerSwipe = false

        init(onTap: @escaping () -> Void, onSwipeUp: @escaping () -> Void) {
            self.onTap = onTap
            self.onSwipeUp = onSwipeUp
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            touch.type == .direct
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            false
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                didTriggerSwipe = false
            case .changed, .ended:
                guard !didTriggerSwipe else { return }
                let translation = recognizer.translation(in: recognizer.view)
                let isUpward = translation.y < -18 && abs(translation.y) > abs(translation.x)
                if isUpward {
                    didTriggerSwipe = true
                    onSwipeUp()
                }
            case .cancelled, .failed:
                didTriggerSwipe = false
            default:
                break
            }
        }
    }
}

struct OutlineHandle: View {
    let onOpen: () -> Void
    @State private var isPressed = false

    var body: some View {
        ZStack {
            FingerGestureCaptureView(
                onTap: onOpen,
                onSwipeUp: onOpen
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 3) {
                Capsule()
                    .fill(FNTheme.tertiaryInk.opacity(0.72))
                    .frame(width: 18, height: 2)
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FNTheme.accent)
                Text("大纲")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(FNTheme.secondaryInk)
            }
            .allowsHitTesting(false)
        }
        .frame(width: 48, height: 58)
        .background(FNTheme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
        .scaleEffect(isPressed ? 0.95 : 1)
        .animation(.easeOut(duration: 0.12), value: isPressed)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("打开大纲")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }
}

struct FNRecoveryReadOnlyView: View {
    let title: String
    let message: String
    let issues: [RecoveryIssue]
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(FNTheme.danger)
            Text(title)
                .font(FNTheme.serif(18, weight: .semibold))
                .foregroundStyle(FNTheme.ink)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(FNTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(issues.suffix(4))) { issue in
                        Text(issue.message)
                            .font(.system(size: 9))
                            .foregroundStyle(FNTheme.tertiaryInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(9)
                .background(FNTheme.sidebar.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            Button("重新读取", action: onRetry)
                .buttonStyle(.borderedProminent)
                .tint(FNTheme.accent)
                .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: 330)
        .background(FNTheme.cardRaised)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FNTheme.danger.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 7)
    }
}

struct FNInlineNotice: View {
    let symbol: String
    let text: String
    var tint: Color = FNTheme.accent

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(10)
        .background(tint.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct FNPageIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        Text(total > 0 ? "第 \(min(max(current, 1), total)) 页 / 共 \(total) 页" : "暂无页面")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(FNTheme.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(FNTheme.card.opacity(0.92))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(FNTheme.divider, lineWidth: 1))
    }
}


