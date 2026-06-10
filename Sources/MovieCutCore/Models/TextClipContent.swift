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
        stickerImageURL: URL? = nil
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
