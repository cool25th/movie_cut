import Foundation

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
    /// The preset identifier.
    public var id: UUID

    /// The user-visible preset name.
    public var name: String

    /// Five equalizer bands at 60, 250, 1000, 4000, and 16000 Hz.
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

    /// Gentle bass and treble lift for perceived loudness.
    public static let loudness = EqualizerPreset(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001005")!,
        name: "Loudness",
        bands: Self.bands(gains: [4, 2, 0, 2, 4])
    )

    /// All built-in equalizer presets.
    public static var all: [EqualizerPreset] {
        [flat, bassBoost, trebleBoost, voiceEnhance, loudness]
    }

    private static func bands(gains: [Float]) -> [EQBand] {
        zip([Float(60), 250, 1_000, 4_000, 16_000], gains).map { frequency, gain in
            EQBand(frequency: frequency, gain: gain)
        }
    }
}
