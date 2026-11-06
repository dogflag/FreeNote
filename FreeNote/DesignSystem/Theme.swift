import SwiftUI
import UIKit

enum FNTheme {
    static let accent = adaptive(light: 0x4F6759, dark: 0x8FA99A)
    static let accentSoft = adaptive(light: 0xDCE6DF, dark: 0x304039)
    static let selectionFill = adaptive(light: 0x3F574B, dark: 0x4F6759)
    static let selectionText = Color.white
    static let ink = adaptive(light: 0x26322F, dark: 0xE8E5DD)
    static let secondaryInk = adaptive(light: 0x6E7772, dark: 0xAEB7B1)
    static let tertiaryInk = adaptive(light: 0x929991, dark: 0x838C86)
    static let appBackground = adaptive(light: 0xF5F1E8, dark: 0x171B18)
    static let sidebar = adaptive(light: 0xEFEAE0, dark: 0x1E2420)
    static let contentBackground = adaptive(light: 0xF7F4EC, dark: 0x1A1F1C)
    static let card = adaptive(light: 0xFCFAF5, dark: 0x242B27)
    static let cardRaised = adaptive(light: 0xFFFEFB, dark: 0x2A322D)
    static let divider = adaptive(light: 0xE3DED3, dark: 0x353D38)
    static let paperLine = adaptive(light: 0xD9D4C9, dark: 0x414A44)
    static let shade = Color.black.opacity(0.18)
    static let danger = adaptive(light: 0xA8564F, dark: 0xE19A93)

    static let coverPalette: [Color] = [
        Color(hex: 0x4F6759),
        Color(hex: 0xA88469),
        Color(hex: 0x697080),
        Color(hex: 0xB29B78),
        Color(hex: 0x825D5A),
        Color(hex: 0x667D73)
    ]

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func coverColor(for id: UUID) -> Color {
        let checksum = id.uuidString.utf8.reduce(0) { ($0 &* 31) &+ UInt32($1) }
        return coverPalette[Int(checksum % UInt32(coverPalette.count))]
    }

    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func readingFont(_ font: ReadingFont, size: CGFloat) -> Font {
        switch font {
        case .system:
            return .system(size: size, design: .default)
        case .serif:
            return .system(size: size, design: .serif)
        case .rounded:
            return .system(size: size, design: .rounded)
        }
    }

    static func paperColor(tone: String) -> Color {
        switch tone {
        case "pureWhite":
            return adaptive(light: 0xFFFEFB, dark: 0x1E2320)
        case "gray":
            return adaptive(light: 0xF1F0EB, dark: 0x252824)
        default:
            return adaptive(light: 0xFDFBF5, dark: 0x252824)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension AppAppearance {
    var fnTitle: String {
        switch self {
        case .light: return "亮色"
        case .dark: return "暗色"
        case .system: return "跟随系统"
        }
    }

    var fnColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

extension AppSection {
    var fnTitle: String {
        switch self {
        case .notes: return "笔记"
        case .bookshelf: return "书架"
        case .library: return "资源库"
        }
    }

    var fnSymbol: String {
        switch self {
        case .notes: return "doc.text"
        case .bookshelf: return "books.vertical"
        case .library: return "folder"
        }
    }
}

extension NotebookKind {
    var fnTitle: String {
        switch self {
        case .paged: return "分页笔记本"
        case .infiniteCanvas: return "无限画布"
        }
    }

    var fnSubtitle: String {
        switch self {
        case .paged: return "适合阅读与整理"
        case .infiniteCanvas: return "适合自由书写"
        }
    }

    var fnSymbol: String {
        switch self {
        case .paged: return "doc"
        case .infiniteCanvas: return "rectangle.dashed"
        }
    }
}

extension PaperStyle {
    var fnTitle: String {
        switch self {
        case .blank: return "空白"
        case .lined: return "横线"
        case .grid: return "方格"
        case .dotted: return "点阵"
        }
    }

    var fnSymbol: String {
        switch self {
        case .blank: return "rectangle"
        case .lined: return "line.3.horizontal"
        case .grid: return "grid"
        case .dotted: return "circle.grid.3x3"
        }
    }
}

extension DocumentKind {
    var fnTitle: String {
        switch self {
        case .pdf: return "PDF"
        case .epub: return "EPUB"
        case .office: return "Office"
        case .image: return "图片"
        case .audio: return "音频"
        case .text: return "文本"
        case .other: return "文件"
        }
    }

    var fnSymbol: String {
        switch self {
        case .pdf: return "doc.richtext"
        case .epub: return "book.closed"
        case .office: return "doc.on.doc"
        case .image: return "photo"
        case .audio: return "waveform"
        case .text: return "doc.plaintext"
        case .other: return "doc"
        }
    }

    var fnTint: Color {
        switch self {
        case .pdf: return Color(hex: 0xB65C54)
        case .epub: return Color(hex: 0x7C6A52)
        case .office: return Color(hex: 0xB08059)
        case .image: return Color(hex: 0x5E8274)
        case .audio: return Color(hex: 0x7A6D91)
        case .text: return Color(hex: 0x697C88)
        case .other: return Color(hex: 0x7E8781)
        }
    }
}

