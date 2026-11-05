import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: FreeNoteStore
    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var hasLoaded = false

    private let paperTones: [PaperToneOption] = [
        PaperToneOption(id: "warmWhite", title: "米白", color: Color(hex: 0xFDFBF5)),
        PaperToneOption(id: "pureWhite", title: "纯白", color: Color(hex: 0xFFFFFF)),
        PaperToneOption(id: "gray", title: "浅灰", color: Color(hex: 0xF1F0EB))
    ]

    var body: some View {
        VStack(spacing: 0) {
            FNModalHeader(
                title: "设置",
                subtitle: "调整书写、阅读与本地存储行为。",
                onClose: { dismiss() }
            )
            ScrollView {
                VStack(spacing: 13) {
                    appearanceSection
                    typographySection
                    paperSection
                    writingSection
                    privacySection
                    aboutSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 620, minHeight: 720)
        .background(FNTheme.contentBackground)
        .onAppear { hasLoaded = true }
        .onChange(of: store.settings) { _ in
            guard hasLoaded else { return }
            save()
        }
        .alert("设置保存失败", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var appearanceSection: some View {
        settingsCard(title: "外观", symbol: "circle.lefthalf.filled") {
            HStack(spacing: 6) {
                ForEach(AppAppearance.allCases) { appearance in
                    choiceButton(
                        title: appearance.fnTitle,
                        selected: store.settings.appearance == appearance
                    ) {
                        store.settings.appearance = appearance
                    }
                }
            }
        }
    }

    private var typographySection: some View {
        settingsCard(title: "字体与排版", symbol: "textformat") {
            VStack(spacing: 14) {
                HStack {
                    Text("字号")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                    Slider(value: $store.settings.fontSize, in: 12...26, step: 1)
                        .tint(FNTheme.accent)
                    Text("\(Int(store.settings.fontSize)) pt")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(FNTheme.tertiaryInk)
                        .frame(width: 42, alignment: .trailing)
                }

                HStack {
                    Text("阅读字体")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FNTheme.secondaryInk)
                    Spacer()
                    ForEach(ReadingFont.allCases) { font in
                        choiceButton(title: font.fnTitle, selected: store.settings.readingFont == font) {
                            store.settings.readingFont = font
                        }
                    }
                }
            }
        }
    }

    private var paperSection: some View {
        settingsCard(title: "纸张颜色", symbol: "doc") {
            HStack(spacing: 18) {
                ForEach(paperTones) { tone in
                    Button {
                        store.settings.paperTone = tone.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tone.color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle().stroke(
                                        store.settings.paperTone == tone.id ? FNTheme.accent : FNTheme.divider,
                                        lineWidth: store.settings.paperTone == tone.id ? 2 : 1
                                    )
                                )
                            Text(tone.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(FNTheme.secondaryInk)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    private var writingSection: some View {
        settingsCard(title: "手写笔", symbol: "pencil.tip") {
            VStack(spacing: 12) {
                settingToggle(
                    title: "自动保存",
                    subtitle: "书写后自动写入手写数据",
                    isOn: $store.settings.autoSave
                )
                settingToggle(
                    title: "仅 Apple Pencil 书写",
                    subtitle: "关闭后允许手指在画布上书写",
                    isOn: $store.settings.pencilOnlyDrawing
                )
                FNInlineNotice(
                    symbol: "hand.draw",
                    text: "右下角大纲把手始终只响应手指；从把手附近上划或轻点即可打开。"
                )
            }
        }
    }

    private var privacySection: some View {
        settingsCard(title: "隐私与最近项目", symbol: "lock") {
            VStack(spacing: 12) {
                settingToggle(
                    title: "隐私模式",
                    subtitle: "隐藏笔记列表中的内容摘要",
                    isOn: $store.settings.privacyMode
                )
                settingToggle(
                    title: "显示最近项目",
                    subtitle: "在首页保留最近打开和编辑入口",
                    isOn: $store.settings.showRecentItems
                )
            }
        }
    }

    private var aboutSection: some View {
        settingsCard(title: "关于 FreeNote", symbol: "info.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FreeNote 0.2.0")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FNTheme.ink)
                    Text("本地优先的手写笔记与阅读工具")
                        .font(.system(size: 10))
                        .foregroundStyle(FNTheme.tertiaryInk)
                }
                Spacer()
                Text("iPadOS 16+")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(FNTheme.tertiaryInk)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(FNTheme.sidebar)
                    .clipShape(Capsule())
            }
        }
    }

    private func settingsCard<Content: View>(title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(FNTheme.ink)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FNTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(FNTheme.divider, lineWidth: 1)
        )
    }

    private func choiceButton(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(selected ? FNTheme.selectionText : FNTheme.secondaryInk)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(selected ? FNTheme.selectionFill : FNTheme.sidebar)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func settingToggle(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(FNTheme.ink)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(FNTheme.tertiaryInk)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(FNTheme.accent)
        }
    }

    private func save() {
        do {
            try store.saveSettings()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct PaperToneOption: Identifiable {
    let id: String
    let title: String
    let color: Color
}

extension ReadingFont {
    var fnTitle: String {
        switch self {
        case .system: return "系统"
        case .serif: return "衬线"
        case .rounded: return "圆体"
        }
    }
}

