import CoreGraphics
import Foundation

/// A reusable text style captured from a text clip (F-12R). Presets store
/// style only — text, position, animation, and sticker identity stay with
/// the clip they are applied to.
public struct UserTextStylePreset: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var fontFamily: String
    public var fontSize: Double
    public var fontColor: String
    public var alignment: TextAlignment
    public var backgroundColor: String?
    public var strokeColor: String?
    public var strokeWidth: Double?
    public var shadowColor: String?
    public var shadowOffset: CGPoint?
    public var shadowBlur: Double?
    public var isBold: Bool
    public var isItalic: Bool

    /// Captures the style of existing text content.
    public init(id: UUID = UUID(), name: String, capturing content: TextClipContent) {
        self.id = id
        self.name = name
        self.fontFamily = content.fontFamily
        self.fontSize = content.fontSize
        self.fontColor = content.fontColor
        self.alignment = content.alignment
        self.backgroundColor = content.backgroundColor
        self.strokeColor = content.strokeColor
        self.strokeWidth = content.strokeWidth
        self.shadowColor = content.shadowColor
        self.shadowOffset = content.shadowOffset
        self.shadowBlur = content.shadowBlur
        self.isBold = content.isBold
        self.isItalic = content.isItalic
    }

    /// Returns the content with this preset's style fields applied.
    public func applying(to content: TextClipContent) -> TextClipContent {
        var updated = content
        updated.fontFamily = fontFamily
        updated.fontSize = fontSize
        updated.fontColor = fontColor
        updated.alignment = alignment
        updated.backgroundColor = backgroundColor
        updated.strokeColor = strokeColor
        updated.strokeWidth = strokeWidth
        updated.shadowColor = shadowColor
        updated.shadowOffset = shadowOffset
        updated.shadowBlur = shadowBlur
        updated.isBold = isBold
        updated.isItalic = isItalic
        return updated
    }
}

/// File-backed persistence for user text style presets.
public enum UserTextStylePresetStore {
    /// Default store location under Application Support.
    public static func defaultStoreURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("MovieCut", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("TextStyles.json")
    }

    /// Loads presets; a missing or unreadable file yields an empty list.
    public static func load(from url: URL) -> [UserTextStylePreset] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([UserTextStylePreset].self, from: data)) ?? []
    }

    /// Saves presets atomically.
    public static func save(_ presets: [UserTextStylePreset], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(presets).write(to: url, options: .atomic)
    }
}
