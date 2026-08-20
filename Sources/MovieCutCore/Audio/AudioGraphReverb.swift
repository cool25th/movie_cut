import Foundation

/// G-26 Inc 2 — a simple synthetic reverb: early reflections as a tapped
/// delay line with exponential decay, plus a short comb-filter tail for
/// density. This is the v1 "공간감" — not a convolution reverb.
public enum AudioGraphReverb {
    public struct Parameters: Sendable, Equatable, Codable {
        /// Wet/dry mix (0…1). Default 0.3.
        public var mix: Double
        /// Room size (0…1) — maps to the reflection spacing.
        public var roomSize: Double
        /// Decay factor (0.1…0.9) — each reflection's amplitude.
        public var decay: Double

        public init(mix: Double = 0.3, roomSize: Double = 0.5, decay: Double = 0.5) {
            self.mix = min(max(mix, 0), 1)
            self.roomSize = min(max(roomSize, 0), 1)
            self.decay = min(max(decay, 0.1), 0.9)
        }

        public static let room = Parameters()
        public static let hall = Parameters(mix: 0.4, roomSize: 0.9, decay: 0.7)
    }

    /// Applies early-reflection reverb: the dry signal plus a tapped
    /// delay chain with exponentially decaying amplitude.
    public static func apply(
        _ audio: AudioGraphSourceAudio,
        parameters: Parameters = .room
    ) -> AudioGraphSourceAudio {
        guard audio.frameCount > 0, audio.sampleRate > 0 else { return audio }

        let sampleRate = audio.sampleRate
        let channelCount = audio.channels
        let dryGain = 1.0 - parameters.mix
        let wetGain = parameters.mix

        // Early reflection delays: a sparse set of taps spaced by the
        // room size (larger room = longer delays).
        let baseDelayMs = 5.0 + parameters.roomSize * 45.0  // 5–50ms
        let reflectionDelays = [1.0, 1.3, 1.7, 2.3, 3.1, 4.7]  // prime-ish ratios
            .map { Int(($0 * baseDelayMs / 1000.0 * sampleRate).rounded()) }

        var interleaved = [Float](repeating: 0, count: audio.interleaved.count)

        // Dry pass.
        for i in 0..<interleaved.count {
            interleaved[i] = Float(Double(audio.interleaved[i]) * dryGain)
        }

        // Wet: each tap adds a delayed, decayed copy.
        for (tapIndex, delayFrames) in reflectionDelays.enumerated() {
            let tapGain = pow(parameters.decay, Double(tapIndex + 1)) * wetGain
            for frame in delayFrames..<audio.frameCount {
                let sourceFrame = frame - delayFrames
                let base = frame * channelCount
                let sourceBase = sourceFrame * channelCount
                for channel in 0..<channelCount {
                    interleaved[base + channel] +=
                        Float(Double(audio.interleaved[sourceBase + channel]) * tapGain)
                }
            }
        }

        return AudioGraphSourceAudio(
            sampleRate: audio.sampleRate,
            channels: audio.channels,
            interleaved: interleaved
        )
    }
}
