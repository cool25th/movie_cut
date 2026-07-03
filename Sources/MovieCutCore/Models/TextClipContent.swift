import Foundation

/// Text alignment options for generated text clips.
public enum TextAlignment: String, Codable, Sendable, Equatable, Hashable {
    /// Align text to the leading edge.
    case leading

    /// Center text.
    case center

    /// Align text to the trailing edge.
    case trailing

    /// Justify text.
    case justified
}

/// Identifies the semantic role of generated text-backed overlay content.
public enum TextClipContentKind: String, Codable, Sendable, Equatable, Hashable {
    /// Ordinary editable text, including titles, captions, templates, and subtitles.
    case text

    /// A sticker overlay that currently uses the text payload for built-in emoji stickers.
    case sticker
}

/// Editable text payload and style values for a text clip.
public struct TextClipContent: Codable, Sendable, Equatable {
    /// The displayed text.
    public var text: String

    /// The font family name.
    public var fontFamily: String

    /// The font size in points.
    public var fontSize: Double

    /// The foreground color as a hex string.
    public var fontColor: String

    /// The text alignment.
    public var alignment: TextAlignment

    /// The optional background color as a hex string.
    public var backgroundColor: String?

    /// The text position on the canvas.
    public var position: CGPoint

    /// Optional animation applied when rendering this text clip.
    public var animation: TextAnimation?

    /// The semantic role of this content.
    public var contentKind: TextClipContentKind

    /// Optional source sticker asset identifier.
    public var stickerAssetID: UUID?

    /// Optional image source for image-backed sticker overlays.
    public var stickerImageURL: URL?

    /// Optional outline color hex. Nil disables the stroke (F-12R).
    public var strokeColor: String?

    /// Outline width in points. Used only when `strokeColor` is set.
    public var strokeWidth: Double?

    /// Optional drop-shadow color hex. Nil disables the shadow (F-12R).
    public var shadowColor: String?

    /// Shadow offset in canvas points (positive y draws downward).
    public var shadowOffset: CGPoint?

    /// Shadow blur radius in points.
    public var shadowBlur: Double?

    /// Renders the font with a bold trait when available.
    public var isBold: Bool

    /// Renders the font with an italic trait when available.
    public var isItalic: Bool

    /// Optional word timings relative to this text clip's source/timeline start.
    public var wordTimings: [WordTiming]?

    /// Whether this text payload should be treated as a sticker overlay.
    public var isSticker: Bool {
        contentKind == .sticker
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case fontFamily
        case fontSize
        case fontColor
        case alignment
        case backgroundColor
        case position
        case animation
        case contentKind
        case stickerAssetID
        case stickerImageURL
        case strokeColor
        case strokeWidth
        case shadowColor
        case shadowOffset
        case shadowBlur
        case isBold
        case isItalic
        case wordTimings
    }

    private struct LegacyPoint: Decodable {
        var x: Double
        var y: Double
    }

    /// Creates text clip content.
    public init(
        text: String,
        fontFamily: String = "System",
        fontSize: Double = 48,
        fontColor: String = "#FFFFFF",
        alignment: TextAlignment = .center,
        backgroundColor: String? = nil,
        position: CGPoint = .zero,
        animation: TextAnimation? = nil,
        contentKind: TextClipContentKind = .text,
        stickerAssetID: UUID? = nil,
        stickerImageURL: URL? = nil,
        strokeColor: String? = nil,
        strokeWidth: Double? = nil,
        shadowColor: String? = nil,
        shadowOffset: CGPoint? = nil,
        shadowBlur: Double? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        wordTimings: [WordTiming]? = nil
    ) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontColor = fontColor
        self.alignment = alignment
        self.backgroundColor = backgroundColor
        self.position = position
        self.animation = animation
        self.contentKind = contentKind
        self.stickerAssetID = stickerAssetID
        self.stickerImageURL = stickerImageURL
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.shadowColor = shadowColor
        self.shadowOffset = shadowOffset
        self.shadowBlur = shadowBlur
        self.isBold = isBold
        self.isItalic = isItalic
        self.wordTimings = wordTimings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "System"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 48
        fontColor = try container.decodeIfPresent(String.self, forKey: .fontColor) ?? "#FFFFFF"
        alignment = try container.decodeIfPresent(TextAlignment.self, forKey: .alignment) ?? .center
        backgroundColor = try container.decodeIfPresent(String.self, forKey: .backgroundColor)
        position = Self.decodePosition(from: container)
        animation = try container.decodeIfPresent(TextAnimation.self, forKey: .animation)
        contentKind = try container.decodeIfPresent(TextClipContentKind.self, forKey: .contentKind) ?? .text
        stickerAssetID = try container.decodeIfPresent(UUID.self, forKey: .stickerAssetID)
        stickerImageURL = try container.decodeIfPresent(URL.self, forKey: .stickerImageURL)
        strokeColor = try container.decodeIfPresent(String.self, forKey: .strokeColor)
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth)
        shadowColor = try container.decodeIfPresent(String.self, forKey: .shadowColor)
        shadowOffset = try Self.decodePointIfPresent(in: container, forKey: .shadowOffset)
        shadowBlur = try container.decodeIfPresent(Double.self, forKey: .shadowBlur)
        isBold = try container.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try container.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        wordTimings = try container.decodeIfPresent([WordTiming].self, forKey: .wordTimings)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontColor, forKey: .fontColor)
        try container.encode(alignment, forKey: .alignment)
        try container.encodeIfPresent(backgroundColor, forKey: .backgroundColor)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(animation, forKey: .animation)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encodeIfPresent(stickerAssetID, forKey: .stickerAssetID)
        try container.encodeIfPresent(stickerImageURL, forKey: .stickerImageURL)
        try container.encodeIfPresent(strokeColor, forKey: .strokeColor)
        try container.encodeIfPresent(strokeWidth, forKey: .strokeWidth)
        try container.encodeIfPresent(shadowColor, forKey: .shadowColor)
        try container.encodeIfPresent(shadowOffset, forKey: .shadowOffset)
        try container.encodeIfPresent(shadowBlur, forKey: .shadowBlur)
        if isBold { try container.encode(isBold, forKey: .isBold) }
        if isItalic { try container.encode(isItalic, forKey: .isItalic) }
        try container.encodeIfPresent(wordTimings, forKey: .wordTimings)
    }

    private static func decodePointIfPresent(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> CGPoint? {
        if let point = try? container.decodeIfPresent(CGPoint.self, forKey: key) {
            return point
        }
        if let point = try? container.decodeIfPresent(LegacyPoint.self, forKey: key) {
            return CGPoint(x: point.x, y: point.y)
        }
        return nil
    }

    private static func decodePosition(from container: KeyedDecodingContainer<CodingKeys>) -> CGPoint {
        if let point = try? container.decodeIfPresent(CGPoint.self, forKey: .position) {
            return point
        }

        if let point = try? container.decodeIfPresent(LegacyPoint.self, forKey: .position) {
            return CGPoint(x: point.x, y: point.y)
        }

        return CGPoint(x: 0, y: 0)
    }
}
