import Foundation

/// Built-in equalizer preset identifiers shared by UI, preview, and export.
public enum EqualizerPresetID: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    /// No equalizer gain changes.
    case flat

    /// Midrange emphasis tuned for spoken voice clarity.
    case voiceEnhance

    /// Low-frequency emphasis for fuller audio.
    case bassBoost

    /// High-frequency emphasis for brighter audio.
    case trebleBoost

    /// User-edited band gains.
    case custom

    /// The preset identifier.
    public var id: String { rawValue }

    /// The user-visible preset name.
    public var displayName: String {
        switch self {
        case .flat:
            return "Flat"
        case .voiceEnhance:
            return "Voice Enhance"
        case .bassBoost:
            return "Bass Boost"
        case .trebleBoost:
            return "Treble Boost"
        case .custom:
            return "Custom"
        }
    }
}

/// A single equalizer band gain.
public struct EQBand: Codable, Sendable, Equatable {
    /// The band center frequency in hertz.
    public var frequency: Float

    /// The band gain in decibels, clamped to -12...12.
    public var gain: Float {
        didSet {
            gain = Self.clampedGain(gain)
        }
    }

    /// Creates an equalizer band.
    public init(frequency: Float, gain: Float) {
        self.frequency = frequency
        self.gain = Self.clampedGain(gain)
    }

    private static func clampedGain(_ gain: Float) -> Float {
        min(max(gain, -12), 12)
    }
}

/// A named five-band equalizer preset.
public struct EqualizerPreset: Codable, Sendable, Equatable, Identifiable {
    /// Shared band center frequencies used by timeline EQ.
    public static let bandFrequencies: [Float] = [60, 250, 1_000, 4_000, 12_000]

    /// The preset identifier.
    public var id: UUID

    /// The user-visible preset name.
    public var name: String

    /// Five equalizer bands at 60, 250, 1000, 4000, and 12000 Hz.
    public var bands: [EQBand]

    /// Creates an equalizer preset.
    public init(id: UUID = UUID(), name: String, bands: [EQBand]) {
        self.id = id
        self.name = name
        self.bands = bands
    }

    /// No equalizer gain changes.
    public static let flat = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001001")!,
        name: "Flat",
        bands: Self.bands(gains: [0, 0, 0, 0, 0])
    )

    /// Low-frequency emphasis for fuller audio.
    public static let bassBoost = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001002")!,
        name: "Bass Boost",
        bands: Self.bands(gains: [6, 4, 1, 0, 0])
    )

    /// High-frequency emphasis for brighter audio.
    public static let trebleBoost = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001003")!,
        name: "Treble Boost",
        bands: Self.bands(gains: [0, 0, 1, 4, 6])
    )

    /// Midrange emphasis tuned for spoken voice clarity.
    public static let voiceEnhance = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001004")!,
        name: "Voice Enhance",
        bands: Self.bands(gains: [-3, -1, 3, 4, 1])
    )

    /// User-edited gains, initialized flat.
    public static let custom = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001005")!,
        name: "Custom",
        bands: Self.bands(gains: [0, 0, 0, 0, 0])
    )

    /// All built-in equalizer presets.
    public static var all: [EqualizerPreset] {
        [flat, voiceEnhance, bassBoost, trebleBoost, custom]
    }

    /// Returns the preset for a shared identifier.
    public static func preset(for id: EqualizerPresetID) -> EqualizerPreset {
        switch id {
        case .flat:
            return .flat
        case .voiceEnhance:
            return .voiceEnhance
        case .bassBoost:
            return .bassBoost
        case .trebleBoost:
            return .trebleBoost
        case .custom:
            return .custom
        }
    }

    private static func bands(gains: [Float]) -> [EQBand] {
        zip(bandFrequencies, gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: gain)
        }
    }
}

/// Per-clip equalizer settings persisted with a timeline clip.
public struct ClipEqualizerSettings: Codable, Sendable, Equatable {
    /// The selected preset identity. `.custom` means `bands` were user edited.
    public var preset: EqualizerPresetID

    /// Five equalizer bands persisted as gain values at fixed center frequencies.
    public var bands: [EQBand]

    private enum CodingKeys: String, CodingKey {
        case preset
        case bands
    }

    /// Creates clip equalizer settings.
    public init(preset: EqualizerPresetID = .flat, bands: [EQBand]? = nil) {
        self.preset = preset
        let sourceBands = bands ?? EqualizerPreset.preset(for: preset).bands
        self.bands = Self.normalizedBands(sourceBands)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decodeIfPresent(EqualizerPresetID.self, forKey: .preset) ?? .custom
        bands = Self.normalizedBands(
            try container.decodeIfPresent([EQBand].self, forKey: .bands)
                ?? EqualizerPreset.preset(for: preset).bands
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(preset, forKey: .preset)
        try container.encode(bands, forKey: .bands)
    }

    /// A render-ready preset carrying this clip's exact band gains.
    public var equalizerPreset: EqualizerPreset {
        EqualizerPreset(
            id: EqualizerPreset.preset(for: preset).id,
            name: preset.displayName,
            bands: Self.normalizedBands(bands)
        )
    }

    /// Whether these settings are effectively flat.
    public var isFlat: Bool {
        Self.normalizedBands(bands).allSatisfy { abs($0.gain) <= 0.0001 }
    }

    /// Returns normalized five-band settings for a built-in preset.
    public static func settings(for preset: EqualizerPresetID) -> ClipEqualizerSettings {
        ClipEqualizerSettings(preset: preset, bands: EqualizerPreset.preset(for: preset).bands)
    }

    /// Returns normalized custom settings.
    public static func custom(bands: [EQBand]) -> ClipEqualizerSettings {
        ClipEqualizerSettings(preset: .custom, bands: bands)
    }

    /// Ensures persisted bands always use the shared five frequencies and clamped gains.
    public static func normalizedBands(_ bands: [EQBand]) -> [EQBand] {
        EqualizerPreset.bandFrequencies.enumerated().map { index, frequency in
            let gain = index < bands.count ? bands[index].gain : 0
            return EQBand(frequency: frequency, gain: gain)
        }
    }
}
