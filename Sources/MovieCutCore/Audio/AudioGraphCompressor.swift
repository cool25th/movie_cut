import AVFoundation
import Foundation

/// G-26 Inc 1 — the compressor as a pure DSP over `AudioGraphSourceAudio`
/// (the same in-memory interleaved model the graph renderer consumes).
/// This implements a standard feed-forward compressor with:
///
/// - threshold (dBFS below which no compression)
/// - ratio (input dB over output dB above the threshold)
/// - attack (how fast gain reduction engages, in seconds)
/// - release (how fast it disengages)
/// - makeup gain (output compensation, in dB)
///
/// The math is deterministic per-sample — same input → same output — so
/// unit tests pin analytic values and the §8 E2E measures real LUFS.
public enum AudioGraphCompressor {
    public struct Parameters: Sendable, Equatable, Codable {
        /// Threshold in dBFS (0…−60). Default −24 dB.
        public var thresholdDb: Double
        /// Compression ratio (1…20). Default 3:1.
        public var ratio: Double
        /// Attack time in seconds (0.001…0.5). Default 0.01.
        public var attackSeconds: Double
        /// Release time in seconds (0.01…2.0). Default 0.25.
        public var releaseSeconds: Double
        /// Makeup gain in dB (0…24). Default 0.
        public var makeupGainDb: Double

        public init(
            thresholdDb: Double = -24,
            ratio: Double = 3,
            attackSeconds: Double = 0.01,
            releaseSeconds: Double = 0.25,
            makeupGainDb: Double = 0
        ) {
            self.thresholdDb = min(max(thresholdDb, -60), 0)
            self.ratio = min(max(ratio, 1), 20)
            self.attackSeconds = min(max(attackSeconds, 0.001), 0.5)
            self.releaseSeconds = min(max(releaseSeconds, 0.01), 2.0)
            self.makeupGainDb = min(max(makeupGainDb, 0), 24)
        }

        /// A gentle default for SNS content.
        public static let sns = Parameters()
    }

    /// Applies feed-forward compression to interleaved audio. The gain
    /// envelope follows the signal with attack/release smoothing, and the
    /// makeup gain is applied at the output.
    public static func apply(
        _ audio: AudioGraphSourceAudio,
        parameters: Parameters = .sns
    ) -> AudioGraphSourceAudio {
        guard audio.frameCount > 0, audio.sampleRate > 0 else { return audio }

        let sampleRate = audio.sampleRate
        let channelCount = audio.channels
        let attackCoeff = exp(-1.0 / (parameters.attackSeconds * sampleRate))
        let releaseCoeff = exp(-1.0 / (parameters.releaseSeconds * sampleRate))
        let makeupLinear = pow(10.0, parameters.makeupGainDb / 20.0)

        var interleaved = audio.interleaved
        var envelopeDb: Double = 0  // the smoothed gain-reduction level

        for frame in 0..<audio.frameCount {
            // Peak magnitude across channels (the sidechain signal).
            var peak: Double = 0
            for channel in 0..<channelCount {
                let sample = abs(Double(audio.sample(frame: frame, channel: channel)))
                peak = max(peak, sample)
            }

            // Convert to dB, compute the static gain reduction.
            let peakDb = peak > 0 ? 20 * log10(peak) : -120
            var gainReductionDb: Double = 0
            if peakDb > parameters.thresholdDb {
                let excessDb = peakDb - parameters.thresholdDb
                let compressedDb = excessDb / parameters.ratio
                gainReductionDb = -(excessDb - compressedDb)
            }

            // Smooth: fast attack (coefficient toward the target when the
            // target is MORE reduction), slow release (when less).
            if gainReductionDb < envelopeDb {
                envelopeDb = attackCoeff * envelopeDb + (1 - attackCoeff) * gainReductionDb
            } else {
                envelopeDb = releaseCoeff * envelopeDb + (1 - releaseCoeff) * gainReductionDb
            }

            // Apply gain reduction + makeup to every channel.
            let linearGain = pow(10.0, envelopeDb / 20.0) * makeupLinear
            let base = frame * channelCount
            for channel in 0..<channelCount {
                let index = base + channel
                interleaved[index] = Float(Double(interleaved[index]) * linearGain)
            }
        }

        return AudioGraphSourceAudio(
            sampleRate: audio.sampleRate,
            channels: audio.channels,
            interleaved: interleaved
        )
    }

    /// The theoretical output level for a given input level — the static
    /// transfer curve the unit tests pin (deterministic, no smoothing).
    public static func staticOutputDb(
        inputDb: Double,
        thresholdDb: Double,
        ratio: Double,
        makeupGainDb: Double = 0
    ) -> Double {
        guard inputDb > thresholdDb else { return inputDb + makeupGainDb }
        let excess = inputDb - thresholdDb
        let compressed = thresholdDb + excess / ratio
        return compressed + makeupGainDb
    }
}
