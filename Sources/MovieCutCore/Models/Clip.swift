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

    /// The clip's ordering inside its track.
    public var zIndex: Int

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

    /// The keyed chroma color as RGB components from 0.0 to 1.0.
    public var chromaKeyColor: SIMD3<Float>? {
        get {
            chromaKey.flatMap { Self.rgb(fromHex: $0.keyColor) }
        }
        set {
            guard let newValue else {
                chromaKey = nil
                return
            }

            let defaults = chromaKey ?? .greenScreen()
            chromaKey = ChromaKeySettings(
                keyColor: Self.hexRGB(from: newValue),
                tolerance: Double(chromaKeyThreshold),
                softness: defaults.softness,
                spillSuppression: defaults.spillSuppression
            )
        }
    }

    /// The chroma key matching threshold from 0.0 to 1.0.
    public var chromaKeyThreshold: Float {
        get {
            Float(chromaKey?.tolerance ?? 0.3)
        }
        set {
            guard var settings = chromaKey else {
                return
            }

            settings.tolerance = Double(min(max(newValue, 0), 1))
            chromaKey = settings
        }
    }

    /// Optional mask applied to the clip.
    public var mask: Mask?

    /// Effects applied to the clip.
    public var effects: [Effect]

    /// Whether the clip should be played in reverse.
    public var isReversed: Bool

    /// Whether the background is removed via person segmentation (F-08).
    public var isBackgroundRemoved: Bool

    /// Optional color correction adjustments.
    public var colorCorrection: ColorCorrection?

    /// Optional link group. Clips sharing a group identifier are selected and
    /// edited together (CapCut-style linked clips). Nil means ungrouped.
    public var groupId: UUID?

    /// Clip-local time ranges (seconds from the clip's timeline start) where
    /// audio volume is ducked under speech (F-14). Empty means no ducking.
    public var duckingRanges: [TimeRange]

    /// Ducked volume multiplier from 0.0 to 1.0 applied inside
    /// `duckingRanges` (0.25 is roughly -12 dB). Nil disables ducking.
    public var duckingLevel: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case assetId
        case kind
        case sourceRange
        case timelineRange
        case zIndex
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
        case mask
        case effects
        case isReversed
        case isBackgroundRemoved
        case colorCorrection
        case groupId
        case duckingRanges
        case duckingLevel
    }

    /// Creates a clip.
    public init(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        zIndex: Int = 0,
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
        chromaKeyColor: SIMD3<Float>? = nil,
        chromaKeyThreshold: Float = 0.3,
        mask: Mask? = nil,
        effects: [Effect] = [],
        isReversed: Bool = false,
        isBackgroundRemoved: Bool = false,
        colorCorrection: ColorCorrection? = nil,
        groupId: UUID? = nil,
        duckingRanges: [TimeRange] = [],
        duckingLevel: Double? = nil
    ) {
        self.id = id
        self.assetId = assetId
        self.kind = kind
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
        self.zIndex = zIndex
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
        if let chromaKey {
            self.chromaKey = chromaKey
        } else if let chromaKeyColor {
            self.chromaKey = ChromaKeySettings(
                keyColor: Self.hexRGB(from: chromaKeyColor),
                tolerance: Double(min(max(chromaKeyThreshold, 0), 1)),
                softness: ChromaKeySettings.greenScreen().softness,
                spillSuppression: ChromaKeySettings.greenScreen().spillSuppression
            )
        } else {
            self.chromaKey = nil
        }
        self.mask = mask
        self.effects = effects
        self.isReversed = isReversed
        self.isBackgroundRemoved = isBackgroundRemoved
        self.colorCorrection = colorCorrection
        self.groupId = groupId
        self.duckingRanges = duckingRanges
        self.duckingLevel = duckingLevel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        assetId = try container.decodeIfPresent(UUID.self, forKey: .assetId)
        kind = try container.decode(ClipKind.self, forKey: .kind)
        sourceRange = try container.decode(TimeRange.self, forKey: .sourceRange)
        timelineRange = try container.decode(TimeRange.self, forKey: .timelineRange)
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
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
        mask = try container.decodeIfPresent(Mask.self, forKey: .mask)
        effects = try container.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        isReversed = try container.decodeIfPresent(Bool.self, forKey: .isReversed) ?? false
        isBackgroundRemoved = try container.decodeIfPresent(Bool.self, forKey: .isBackgroundRemoved) ?? false
        colorCorrection = try container.decodeIfPresent(ColorCorrection.self, forKey: .colorCorrection)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        duckingRanges = try container.decodeIfPresent([TimeRange].self, forKey: .duckingRanges) ?? []
        duckingLevel = try container.decodeIfPresent(Double.self, forKey: .duckingLevel)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(assetId, forKey: .assetId)
        try container.encode(kind, forKey: .kind)
        try container.encode(sourceRange, forKey: .sourceRange)
        try container.encode(timelineRange, forKey: .timelineRange)
        try container.encode(zIndex, forKey: .zIndex)
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
        try container.encodeIfPresent(mask, forKey: .mask)
        try container.encode(effects, forKey: .effects)
        try container.encode(isReversed, forKey: .isReversed)
        if isBackgroundRemoved { try container.encode(isBackgroundRemoved, forKey: .isBackgroundRemoved) }
        try container.encodeIfPresent(colorCorrection, forKey: .colorCorrection)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        if !duckingRanges.isEmpty {
            try container.encode(duckingRanges, forKey: .duckingRanges)
        }
        try container.encodeIfPresent(duckingLevel, forKey: .duckingLevel)
    }

    private static func rgb(fromHex hexRGB: String) -> SIMD3<Float>? {
        let clean = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return nil
        }

        return SIMD3<Float>(
            Float((value >> 16) & 0xFF) / 255,
            Float((value >> 8) & 0xFF) / 255,
            Float(value & 0xFF) / 255
        )
    }

    private static func hexRGB(from color: SIMD3<Float>) -> String {
        let red = byteValue(color.x)
        let green = byteValue(color.y)
        let blue = byteValue(color.z)
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func byteValue(_ component: Float) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}
