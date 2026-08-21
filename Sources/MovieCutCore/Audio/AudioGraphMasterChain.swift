import Foundation

/// G-26 Inc 3 — the master processing chain that composes the processor
/// DSP units into the graph's render path. The chain is the AUDIO
/// counterpart of the video compositor's clip chain: compressor →
/// limiter → reverb, with an SNS preset that wires sensible defaults.
///
/// The chain consumes the graph's in-memory PCM (the encoder-input mix)
/// and returns the processed PCM. The graph's placeholder nodeKinds
/// (.compressor, .limiter) map to these implementations — the SCHEMA is
/// unchanged (spec §5); only the consumption sites grow support.
public enum AudioGraphMasterChain {
    /// The §6 preset algorithm version of the SNS "좋은 소리" preset.
    /// Recorded whenever the preset serializes into a graph save; a
    /// reopen with a different version reuses derived media and surfaces
    /// "rendered with the previous algorithm" (spec §6 — reproducibility
    /// first, regeneration only on explicit user action).
    public static let snsPresetAlgorithmVersion = "1.0.0"

    /// The processors to apply, in chain order.
    public struct Chain: Sendable, Equatable, Codable {
        public var compressor: AudioGraphCompressor.Parameters?
        public var limiter: AudioGraphLimiter.Parameters?
        public var reverb: AudioGraphReverb.Parameters?

        public init(
            compressor: AudioGraphCompressor.Parameters? = nil,
            limiter: AudioGraphLimiter.Parameters? = nil,
            reverb: AudioGraphReverb.Parameters? = nil
        ) {
            self.compressor = compressor
            self.limiter = limiter
            self.reverb = reverb
        }

        /// The SNS "좋은 소리" preset: gentle compression → −1 dBTP
        /// limiting → subtle room reverb. The §7 guideline's processing.
        public static let sns = Chain(
            compressor: .sns,
            limiter: .sns,
            reverb: .room
        )

        /// No processing (bypass).
        public static let bypass = Chain()
    }

    /// The limiter's latency declaration for the graph's master bus (spec
    /// §4: a graph containing a processor MUST declare its latency). The
    /// look-ahead is the SNS limiter's 5ms at the graph's sample rate.
    public static func snsLimiterLatency(sampleRate: Double) -> AudioGraphNodeLatency {
        AudioGraphNodeLatency(
            nodeKind: .limiter,
            algorithmVersion: snsPresetAlgorithmVersion,
            reportedLatencySamples: 0,
            lookAheadSamples: Int64((0.005 * sampleRate).rounded())
        )
    }

    /// Applies the chain in order: compressor → reverb → limiter.
    /// Code-review fix: the limiter MUST be last (spec §1's master bus
    /// topology: `[limiter]* → meter → encoder`) — reverb after the
    /// limiter adds energy that exceeds the ceiling.
    /// Each stage is a no-op when its parameters are nil.
    public static func apply(
        _ audio: AudioGraphSourceAudio,
        chain: Chain
    ) -> AudioGraphSourceAudio {
        var result = audio
        if let compressor = chain.compressor {
            result = AudioGraphCompressor.apply(result, parameters: compressor)
        }
        if let reverb = chain.reverb {
            result = AudioGraphReverb.apply(result, parameters: reverb)
        }
        if let limiter = chain.limiter {
            result = AudioGraphLimiter.apply(result, parameters: limiter)
        }
        return result
    }

    /// Measures the chain's effect: LUFS before and after, plus the
    /// true-peak of the processed output. The §8 ±0.2LU gate's data.
    public static func measureChainEffect(
        _ audio: AudioGraphSourceAudio,
        chain: Chain
    ) -> (inputLufs: Double?, outputLufs: Double?, outputTruePeakDb: Double) {
        let processed = apply(audio, chain: chain)
        let inputMeasurement = AudioGraphLoudness.measure(audio)
        let outputMeasurement = AudioGraphLoudness.measure(processed)
        return (
            inputLufs: inputMeasurement.integratedLufs,
            outputLufs: outputMeasurement.integratedLufs,
            outputTruePeakDb: outputMeasurement.truePeakDbTp
        )
    }
}
