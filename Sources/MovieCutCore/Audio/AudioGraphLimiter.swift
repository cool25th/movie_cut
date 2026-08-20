import Foundation

/// G-26 Inc 2 — the limiter: a look-ahead peak clamp that guarantees the
/// output never exceeds a ceiling. The look-ahead buffer lets the gain
/// reduction engage BEFORE the peak arrives (zero-overshoot), unlike a
/// reactive compressor — this is the §8 true-peak gate's enforcement arm.
public enum AudioGraphLimiter {
    public struct Parameters: Sendable, Equatable, Codable {
        /// Output ceiling in dBFS (−12…0). Default −1 dBTP.
        public var ceilingDb: Double
        /// Look-ahead time in seconds (0.001…0.05). Default 5ms.
        public var lookAheadSeconds: Double
        /// Release time in seconds (0.01…1.0). Default 50ms.
        public var releaseSeconds: Double

        public init(
            ceilingDb: Double = -1,
            lookAheadSeconds: Double = 0.005,
            releaseSeconds: Double = 0.05
        ) {
            self.ceilingDb = min(max(ceilingDb, -12), 0)
            self.lookAheadSeconds = min(max(lookAheadSeconds, 0.001), 0.05)
            self.releaseSeconds = min(max(releaseSeconds, 0.01), 1.0)
        }

        /// The SNS-safe default (true-peak ≤ −1 dBTP).
        public static let sns = Parameters()
    }

    /// Applies look-ahead limiting. The algorithm:
    /// 1. Scan the look-ahead window for the max peak magnitude.
    /// 2. Compute the gain needed to bring that peak to the ceiling.
    /// 3. Smooth the gain with the release time (attack is instant —
    ///    look-ahead provides the "pre-roll").
    /// 4. Apply the smoothed gain.
    public static func apply(
        _ audio: AudioGraphSourceAudio,
        parameters: Parameters = .sns
    ) -> AudioGraphSourceAudio {
        guard audio.frameCount > 0, audio.sampleRate > 0 else { return audio }

        let sampleRate = audio.sampleRate
        let channelCount = audio.channels
        let lookAheadFrames = Int(parameters.lookAheadSeconds * sampleRate)
        let releaseCoeff = exp(-1.0 / (parameters.releaseSeconds * sampleRate))
        let ceilingLinear = pow(10.0, parameters.ceilingDb / 20.0)

        var interleaved = audio.interleaved
        var smoothedGain: Double = 1.0

        for frame in 0..<audio.frameCount {
            // Find the max peak in the look-ahead window (frames ahead).
            var windowPeak: Double = 0
            let scanEnd = min(frame + lookAheadFrames, audio.frameCount - 1)
            var scanFrame = frame
            while scanFrame <= scanEnd {
                for channel in 0..<channelCount {
                    let magnitude = abs(Double(audio.sample(frame: scanFrame, channel: channel)))
                    windowPeak = max(windowPeak, magnitude)
                }
                scanFrame += 1
            }

            // The target gain: never above 1, bring the peak to the ceiling.
            let targetGain = min(1.0, windowPeak > 0 ? ceilingLinear / windowPeak : 1.0)

            // Instant attack (look-ahead already pre-rolled); smooth release.
            if targetGain < smoothedGain {
                smoothedGain = targetGain
            } else {
                smoothedGain = releaseCoeff * smoothedGain + (1 - releaseCoeff) * targetGain
            }

            // Apply.
            let base = frame * channelCount
            for channel in 0..<channelCount {
                let index = base + channel
                interleaved[index] = Float(Double(interleaved[index]) * smoothedGain)
            }
        }

        return AudioGraphSourceAudio(
            sampleRate: audio.sampleRate,
            channels: audio.channels,
            interleaved: interleaved
        )
    }
}
