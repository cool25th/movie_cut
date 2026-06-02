import Foundation

/// The supported timeline clip kinds.
public enum ClipKind: String, Codable, Sendable, Equatable, Hashable {
    /// A video clip.
    case video

    /// An audio clip.
    case audio

    /// A still image clip.
    case image

    /// A generated text clip.
    case text
}

/// A timeline placement for media or generated content.
public struct Clip: Codable, Sendable, Equatable, Identifiable {
    /// The clip identifier.
    public var id: UUID

    /// The referenced media asset, if this clip uses imported media.
    public var assetId: UUID?

    /// The clip kind.
    public var kind: ClipKind

    /// The source media range in seconds.
    public var sourceRange: TimeRange

    /// The timeline placement range in seconds.
    public var timelineRange: TimeRange

    /// The visual transform applied to the clip.
    public var transform: ClipTransform

    /// The clip opacity from 0.0 to 1.0.
    public var opacity: Double

    /// The clip audio volume multiplier from 0.0 to 2.0.
    public var volume: Double

    /// Optional transition applied at this clip boundary.
    public var transition: Transition?

    /// Text payload for generated text clips.
    public var textContent: TextClipContent?

    /// Effects applied to the clip.
    public var effects: [Effect]

    /// Creates a clip.
    public init(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        transform: ClipTransform = ClipTransform(),
        opacity: Double = 1.0,
        volume: Double = 1.0,
        transition: Transition? = nil,
        textContent: TextClipContent? = nil,
        effects: [Effect] = []
    ) {
        self.id = id
        self.assetId = assetId
        self.kind = kind
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
        self.transform = transform
        self.opacity = opacity
        self.volume = volume
        self.transition = transition
        self.textContent = textContent
        self.effects = effects
    }
}
