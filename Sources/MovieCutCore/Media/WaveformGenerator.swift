import Foundation

/// Serialized waveform samples for an audio asset.
public struct WaveformData: Codable, Sendable, Equatable {
    /// Normalized audio samples.
    public var samples: [Float]

    /// The number of source samples represented by this waveform.
    public var sampleCount: Int

    /// Creates waveform data.
    public init(samples: [Float], sampleCount: Int) {
        self.samples = samples
        self.sampleCount = sampleCount
    }
}

/// Placeholder waveform generation API until audio decoding is introduced.
public struct WaveformGenerator: Sendable {
    /// Generates waveform sample data for an imported media asset.
    public static func generate(for asset: MediaAsset) -> WaveformData? {
        nil
    }
}
