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

    /// Audio fade-in duration in seconds.
    public var fadeInDuration: TimeInterval

    /// Audio fade-out duration in seconds.
    public var fadeOutDuration: TimeInterval

    /// Constant playback speed multiplier from 0.25x to 4.0x.
    public var playbackRate: Double

    /// Optional speed-ramp points. Empty means the clip uses `playbackRate`.
    public var speedRampPoints: [SpeedRampPoint]

    /// Source-relative animation keyframes.
    public var keyframes: [Keyframe]

    /// Optional transition applied at this clip boundary.
    public var transition: Transition?

    /// Text payload for generated text clips.
    public var textContent: TextClipContent?

    /// Optional chroma key settings for green/blue screen removal.
    public var chromaKey: ChromaKeySettings?

    /// Effects applied to the clip.
    public var effects: [Effect]

    /// Whether the clip should be played in reverse.
    public var isReversed: Bool

    /// Optional color correction adjustments.
    public var colorCorrection: ColorCorrection?

    private enum CodingKeys: String, CodingKey {
        case id
        case assetId
        case kind
        case sourceRange
        case timelineRange
        case transform
        case opacity
        case volume
        case fadeInDuration
        case fadeOutDuration
        case playbackRate
        case speedRampPoints
        case keyframes
        case transition
        case textContent
        case chromaKey
        case effects
        case isReversed
        case colorCorrection
    }

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
        fadeInDuration: TimeInterval = 0,
        fadeOutDuration: TimeInterval = 0,
        playbackRate: Double = 1.0,
        speedRampPoints: [SpeedRampPoint] = [],
        keyframes: [Keyframe] = [],
        transition: Transition? = nil,
        textContent: TextClipContent? = nil,
        chromaKey: ChromaKeySettings? = nil,
        effects: [Effect] = [],
        isReversed: Bool = false,
        colorCorrection: ColorCorrection? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.kind = kind
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
        self.transform = transform
        self.opacity = opacity
        self.volume = volume
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.playbackRate = playbackRate
        self.speedRampPoints = speedRampPoints
        self.keyframes = keyframes
        self.transition = transition
        self.textContent = textContent
        self.chromaKey = chromaKey
        self.effects = effects
        self.isReversed = isReversed
        self.colorCorrection = colorCorrection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        assetId = try container.decodeIfPresent(UUID.self, forKey: .assetId)
        kind = try container.decode(ClipKind.self, forKey: .kind)
        sourceRange = try container.decode(TimeRange.self, forKey: .sourceRange)
        timelineRange = try container.decode(TimeRange.self, forKey: .timelineRange)
        transform = try container.decode(ClipTransform.self, forKey: .transform)
        opacity = try container.decode(Double.self, forKey: .opacity)
        volume = try container.decode(Double.self, forKey: .volume)
        fadeInDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeInDuration) ?? 0
        fadeOutDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .fadeOutDuration) ?? 0
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1.0
        speedRampPoints = try container.decodeIfPresent([SpeedRampPoint].self, forKey: .speedRampPoints) ?? []
        keyframes = try container.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        transition = try container.decodeIfPresent(Transition.self, forKey: .transition)
        textContent = try container.decodeIfPresent(TextClipContent.self, forKey: .textContent)
        chromaKey = try container.decodeIfPresent(ChromaKeySettings.self, forKey: .chromaKey)
        effects = try container.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        isReversed = try container.decodeIfPresent(Bool.self, forKey: .isReversed) ?? false
        colorCorrection = try container.decodeIfPresent(ColorCorrection.self, forKey: .colorCorrection)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(assetId, forKey: .assetId)
        try container.encode(kind, forKey: .kind)
        try container.encode(sourceRange, forKey: .sourceRange)
        try container.encode(timelineRange, forKey: .timelineRange)
        try container.encode(transform, forKey: .transform)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(volume, forKey: .volume)
        try container.encode(fadeInDuration, forKey: .fadeInDuration)
        try container.encode(fadeOutDuration, forKey: .fadeOutDuration)
        try container.encode(playbackRate, forKey: .playbackRate)
        try container.encode(speedRampPoints, forKey: .speedRampPoints)
        try container.encode(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(transition, forKey: .transition)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(chromaKey, forKey: .chromaKey)
        try container.encode(effects, forKey: .effects)
        try container.encode(isReversed, forKey: .isReversed)
        try container.encodeIfPresent(colorCorrection, forKey: .colorCorrection)
    }
}
