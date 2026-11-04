import Foundation

struct AppSettings: Codable, Equatable, Sendable {
    var appearance: AppAppearance
    var fontSize: Double
    var readingFont: ReadingFont
    var paperTone: String
    var autoSave: Bool
    var privacyMode: Bool
    var pencilOnlyDrawing: Bool
    var showRecentItems: Bool

    static let defaultValue = AppSettings()

    init(
        appearance: AppAppearance = .system,
        fontSize: Double = 17,
        readingFont: ReadingFont = .system,
        paperTone: String = "warmWhite",
        autoSave: Bool = true,
        privacyMode: Bool = false,
        pencilOnlyDrawing: Bool = true,
        showRecentItems: Bool = true
    ) {
        self.appearance = appearance
        self.fontSize = fontSize
        self.readingFont = readingFont
        self.paperTone = paperTone
        self.autoSave = autoSave
        self.privacyMode = privacyMode
        self.pencilOnlyDrawing = pencilOnlyDrawing
        self.showRecentItems = showRecentItems
    }

    private enum CodingKeys: String, CodingKey {
        case appearance
        case fontSize
        case readingFont
        case paperTone
        case autoSave
        case privacyMode
        case pencilOnlyDrawing
        case showRecentItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try container.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? .system
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 17
        readingFont = try container.decodeIfPresent(ReadingFont.self, forKey: .readingFont) ?? .system
        paperTone = try container.decodeIfPresent(String.self, forKey: .paperTone) ?? "warmWhite"
        autoSave = try container.decodeIfPresent(Bool.self, forKey: .autoSave) ?? true
        privacyMode = try container.decodeIfPresent(Bool.self, forKey: .privacyMode) ?? false
        pencilOnlyDrawing = try container.decodeIfPresent(Bool.self, forKey: .pencilOnlyDrawing) ?? true
        showRecentItems = try container.decodeIfPresent(Bool.self, forKey: .showRecentItems) ?? true
    }
}
