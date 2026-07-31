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

    /// Optional five-band equalizer settings. Nil is equivalent to flat EQ.
    public var equalizer: ClipEqualizerSettings?

    /// Constant playback speed multiplier from 0.25x to 4.0x.
    public var playbackRate: Double

    /// Optional speed-ramp points. Empty means the clip uses `playbackRate`.
    public var speedRampPoints: [SpeedRampPoint]

    /// Whether export should request smoother frame interpolation for slow motion.
    public var useOpticalFlow: Bool

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

    /// Optional 3-way (lift/gamma/gain) color grade.
    public var colorGrade: ColorGrade?

    /// Optional link group. Clips sharing a group identifier are selected and
    /// edited together (CapCut-style linked clips). Nil means ungrouped.
    public var groupId: UUID?

    /// Clip-local time ranges (seconds from the clip's timeline start) where
    /// audio volume is ducked under speech (F-14). Empty means no ducking.
    public var duckingRanges: [TimeRange]

    /// Ducked volume multiplier from 0.0 to 1.0 applied inside
    /// `duckingRanges` (0.25 is roughly -12 dB). Nil disables ducking.
    public var duckingLevel: Double?

    /// The compositing blend mode applied when this clip overlays another clip.
    /// Defaults to `.normal` (source-over), matching the layering behavior that
    /// predated this field. Projects saved before the field existed decode to
    /// `.normal`, and the value is only written when it differs from the
    /// default so `.normal` clips stay byte-identical to their pre-feature JSON.
    /// (Requirements 4.4 / 4.7 — CapCut clip-blending parity.)
    public var blendMode: BlendMode

    /// When non-nil, this clip is a container for the referenced
    /// `CompoundDefinition` (Requirement 7). The flatten pass (task 5.8)
    /// replaces this clip in the rendered timeline with the definition's child
    /// clips, shifted by this clip's timeline start. **Inc 1 forbids nesting**:
    /// a clip carrying a `compoundId` is rejected at creation time and at load
    /// time, and it may not itself appear inside another compound's children.
    /// Decodes to nil for legacy projects. The schema bump is deferred to task 6.
    public var compoundId: UUID?

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
        case equalizer
        case playbackRate
        case speedRampPoints
        case useOpticalFlow
        case keyframes
        case transition
        case textContent
        case chromaKey
        case mask
        case effects
        case isReversed
        case isBackgroundRemoved
        case colorCorrection
        case colorGrade
        case groupId
        case duckingRanges
        case duckingLevel
        case blendMode
        case compoundId
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
        equalizer: ClipEqualizerSettings? = nil,
        playbackRate: Double = 1.0,
        speedRampPoints: [SpeedRampPoint] = [],
        useOpticalFlow: Bool = false,
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
        colorGrade: ColorGrade? = nil,
        groupId: UUID? = nil,
        duckingRanges: [TimeRange] = [],
        duckingLevel: Double? = nil,
        blendMode: BlendMode = .normal,
        compoundId: UUID? = nil
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
        self.equalizer = equalizer
        self.playbackRate = playbackRate
        self.speedRampPoints = speedRampPoints
        self.useOpticalFlow = useOpticalFlow
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
        self.colorGrade = colorGrade
        self.groupId = groupId
        self.duckingRanges = duckingRanges
        self.duckingLevel = duckingLevel
        self.blendMode = blendMode
        self.compoundId = compoundId
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
        equalizer = try container.decodeIfPresent(ClipEqualizerSettings.self, forKey: .equalizer)
        playbackRate = try container.decodeIfPresent(Double.self, forKey: .playbackRate) ?? 1.0
        speedRampPoints = try container.decodeIfPresent([SpeedRampPoint].self, forKey: .speedRampPoints) ?? []
        useOpticalFlow = try container.decodeIfPresent(Bool.self, forKey: .useOpticalFlow) ?? false
        keyframes = try container.decodeIfPresent([Keyframe].self, forKey: .keyframes) ?? []
        transition = try container.decodeIfPresent(Transition.self, forKey: .transition)
        textContent = try container.decodeIfPresent(TextClipContent.self, forKey: .textContent)
        chromaKey = try container.decodeIfPresent(ChromaKeySettings.self, forKey: .chromaKey)
        mask = try container.decodeIfPresent(Mask.self, forKey: .mask)
        effects = try container.decodeIfPresent([Effect].self, forKey: .effects) ?? []
        isReversed = try container.decodeIfPresent(Bool.self, forKey: .isReversed) ?? false
        isBackgroundRemoved = try container.decodeIfPresent(Bool.self, forKey: .isBackgroundRemoved) ?? false
        colorCorrection = try container.decodeIfPresent(ColorCorrection.self, forKey: .colorCorrection)
        colorGrade = try container.decodeIfPresent(ColorGrade.self, forKey: .colorGrade)
        groupId = try container.decodeIfPresent(UUID.self, forKey: .groupId)
        duckingRanges = try container.decodeIfPresent([TimeRange].self, forKey: .duckingRanges) ?? []
        duckingLevel = try container.decodeIfPresent(Double.self, forKey: .duckingLevel)
        // Projects predating the blendMode field carry no key; decode to .normal
        // so multi-track layering matches the historical source-over behavior.
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .defaultValue
        // decodeIfPresent ?? nil so a clip carrying no compoundId (the legacy
        // and the common case) loads with a nil reference. No-nesting and
        // broken-ref validation happens in `Project.validateCompounds` at load.
        compoundId = try container.decodeIfPresent(UUID.self, forKey: .compoundId) ?? nil
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
        try container.encodeIfPresent(equalizer, forKey: .equalizer)
        try container.encode(playbackRate, forKey: .playbackRate)
        try container.encode(speedRampPoints, forKey: .speedRampPoints)
        if useOpticalFlow { try container.encode(useOpticalFlow, forKey: .useOpticalFlow) }
        try container.encode(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(transition, forKey: .transition)
        try container.encodeIfPresent(textContent, forKey: .textContent)
        try container.encodeIfPresent(chromaKey, forKey: .chromaKey)
        try container.encodeIfPresent(mask, forKey: .mask)
        try container.encode(effects, forKey: .effects)
        try container.encode(isReversed, forKey: .isReversed)
        if isBackgroundRemoved { try container.encode(isBackgroundRemoved, forKey: .isBackgroundRemoved) }
        try container.encodeIfPresent(colorCorrection, forKey: .colorCorrection)
        try container.encodeIfPresent(colorGrade, forKey: .colorGrade)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        if !duckingRanges.isEmpty {
            try container.encode(duckingRanges, forKey: .duckingRanges)
        }
        try container.encodeIfPresent(duckingLevel, forKey: .duckingLevel)
        // Only persist the blend mode when it is not the default, so a .normal
        // clip stays byte-identical to its pre-feature JSON (Requirement 4.4).
        if blendMode != .defaultValue {
            try container.encode(blendMode, forKey: .blendMode)
        }
        // Persist the compound reference only when set, so a plain clip stays
        // byte-identical to its pre-feature JSON (Requirement 7.6).
        try container.encodeIfPresent(compoundId, forKey: .compoundId)
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
