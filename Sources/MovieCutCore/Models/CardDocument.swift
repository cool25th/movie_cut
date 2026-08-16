import Foundation

/// A format-independent rectangle whose coordinates are constrained to the
/// unit canvas. Card layout persists this value rather than format-specific
/// pixel coordinates.
public struct NormalizedRect: Codable, Sendable, Equatable {
    /// The normalized leading coordinate.
    public let x: Double

    /// The normalized top coordinate.
    public let y: Double

    /// The normalized width.
    public let width: Double

    /// The normalized height.
    public let height: Double

    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    /// Creates a rectangle fully contained in the normalized 0...1 canvas.
    /// Returns nil for non-finite, negative, or out-of-bounds geometry.
    public init?(x: Double, y: Double, width: Double, height: Double) {
        guard Self.isValid(x: x, y: y, width: width, height: height) else {
            return nil
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        guard Self.isValid(x: x, y: y, width: width, height: height) else {
            throw DecodingError.dataCorruptedError(
                forKey: .width,
                in: container,
                debugDescription: "Normalized rectangle must be finite and contained in 0...1."
            )
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
    }

    /// Trailing horizontal edge (leading + width).
    public var maxX: Double { x + width }

    /// Bottom vertical edge (top + height).
    public var maxY: Double { y + height }

    private static func isValid(x: Double, y: Double, width: Double, height: Double) -> Bool {
        x.isFinite && y.isFinite && width.isFinite && height.isFinite &&
            x >= 0 && y >= 0 && width >= 0 && height >= 0 &&
            x <= 1 && y <= 1 && x + width <= 1 && y + height <= 1
    }
}

/// Supported social-card canvas formats.
public enum CardFormat: String, Codable, Sendable, Equatable {
    /// Square 1:1 cards.
    case square

    /// Portrait 4:5 cards.
    case portrait

    /// Story 9:16 cards.
    case story
}

/// The semantic role of a page within a card set.
public enum CardPageRole: String, Codable, Sendable, Equatable, Hashable {
    /// The opening cover page.
    case cover

    /// A standard body page.
    case body

    /// A page that emphasizes a key point.
    case emphasis

    /// The closing page.
    case closing
}

/// The content role of an element placed on a card page.
public enum CardElementKind: String, Codable, Sendable, Equatable {
    /// Editable text content.
    case text

    /// An imported image.
    case image

    /// A logo image.
    case logo
}

/// Minimal persisted master-style shape shared with the future G-19 resolver.
/// This type intentionally contains no inheritance or template behavior.
public struct CardMasterStyle: Codable, Sendable, Equatable {
    /// Default font family used by inheriting elements.
    public var fontFamily: String

    /// Primary color as a hexadecimal string.
    public var primaryColorHex: String

    /// Secondary color as a hexadecimal string.
    public var secondaryColorHex: String

    /// Optional normalized logo placement.
    public var logoPlacement: NormalizedRect?

    public init(
        fontFamily: String,
        primaryColorHex: String,
        secondaryColorHex: String,
        logoPlacement: NormalizedRect? = nil
    ) {
        self.fontFamily = fontFamily
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.logoPlacement = logoPlacement
    }
}

/// A stable piece of content placed on a card page.
public struct CardElement: Codable, Sendable, Equatable, Identifiable {
    /// The stable element identifier.
    public var id: UUID

    /// The element content role.
    public var kind: CardElementKind

    /// Format-independent source-of-truth geometry.
    public var normalizedFrame: NormalizedRect

    /// Editable text payload for text elements.
    public var text: TextClipContent?

    /// Referenced project media asset for image-backed elements.
    public var mediaAssetID: UUID?

    public init(
        id: UUID = UUID(),
        kind: CardElementKind,
        normalizedFrame: NormalizedRect,
        text: TextClipContent? = nil,
        mediaAssetID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.normalizedFrame = normalizedFrame
        self.text = text
        self.mediaAssetID = mediaAssetID
    }
}

/// An ordered page in a card document.
public struct CardPage: Codable, Sendable, Equatable, Identifiable {
    /// The stable page identifier.
    public var id: UUID

    /// The page's semantic role in the set.
    public var role: CardPageRole

    /// Ordered page elements.
    public var elements: [CardElement]

    /// Optional page-local style. When present, G-19 inheritance resolves this
    /// value ahead of the document master style and the template default.
    public var masterOverride: CardMasterStyle?

    /// Optional future slideshow duration. Nil uses the G-21 default.
    public var duration: TimeInterval?

    public init(
        id: UUID = UUID(),
        role: CardPageRole,
        elements: [CardElement] = [],
        masterOverride: CardMasterStyle? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.role = role
        self.elements = elements
        self.masterOverride = masterOverride
        self.duration = duration
    }
}

/// A persisted, ordered card-news document associated with a MovieCut project.
public struct CardDocument: Codable, Sendable, Equatable, Identifiable {
    /// The stable document identifier.
    public var id: UUID

    /// The user-visible document title.
    public var title: String

    /// The selected social-card format.
    public var format: CardFormat

    /// Ordered card pages.
    public var pages: [CardPage]

    /// Optional future G-19 master style.
    public var masterStyle: CardMasterStyle?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case format
        case pages
        case masterStyle
    }

    public init(
        id: UUID = UUID(),
        title: String,
        format: CardFormat = .square,
        pages: [CardPage] = [],
        masterStyle: CardMasterStyle? = nil
    ) {
        self.id = id
        self.title = title
        self.format = format
        self.pages = pages
        self.masterStyle = masterStyle
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        format = try container.decodeIfPresent(CardFormat.self, forKey: .format) ?? .square
        pages = try container.decodeIfPresent([CardPage].self, forKey: .pages) ?? []
        masterStyle = try container.decodeIfPresent(CardMasterStyle.self, forKey: .masterStyle)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(format, forKey: .format)
        try container.encode(pages, forKey: .pages)
        try container.encodeIfPresent(masterStyle, forKey: .masterStyle)
    }
}
