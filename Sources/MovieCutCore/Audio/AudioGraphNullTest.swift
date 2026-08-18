import Foundation

/// G-25 spec §9 — the preview↔export null test, as pure Core functions so
/// `swift test` and the E2E gate share ONE judgment (실측 판정은 E2E만, §9.5).
public enum AudioGraphNullTest {
    public struct Result: Sendable, Equatable {
        /// Sample offset of `candidate` relative to `reference` that
        /// minimized the deviation (searched within ±maxOffsetSamples).
        public var bestOffsetSamples: Int
        /// Maximum absolute deviation over the aligned overlap.
        public var maxAbsoluteDeviation: Float
        /// One 16-bit LSB at the comparison magnitude scale.
        public var lsb16: Float
        public var alignedFrameCount: Int
        public var passed: Bool
    }

    /// Compares two interleaved-stereo PCM renders of the SAME graph.
    /// Spec §9: search the best alignment within ±1 sample (configurable
    /// for diagnostics), then require the maximum absolute deviation over
    /// the whole aligned overlap to stay within one 16-bit LSB.
    ///
    /// Magnitude convention: inputs are Float PCM where 1.0 = 0 dBFS, so
    /// one 16-bit LSB = 1/32,768.
    public static func compare(
        reference: [Float],
        candidate: [Float],
        maxOffsetSamples: Int = 1
    ) -> Result {
        let lsb: Float = 1.0 / 32_768.0
        guard !reference.isEmpty, reference.count == candidate.count else {
            return Result(bestOffsetSamples: 0, maxAbsoluteDeviation: .infinity, lsb16: lsb, alignedFrameCount: 0, passed: false)
        }

        var bestOffset = 0
        var bestDeviation = Float.infinity
        for offset in -maxOffsetSamples...maxOffsetSamples {
            var deviation: Float = 0
            var compared = 0
            for i in 0..<reference.count {
                let j = i + offset
                guard j >= 0, j < candidate.count else { continue }
                deviation = max(deviation, abs(reference[i] - candidate[j]))
                compared += 1
            }
            if compared > 0, deviation < bestDeviation {
                bestDeviation = deviation
                bestOffset = offset
            }
        }

        let passed = bestDeviation.isFinite && bestDeviation <= lsb
        return Result(
            bestOffsetSamples: bestOffset,
            maxAbsoluteDeviation: bestDeviation.isFinite ? bestDeviation : .infinity,
            lsb16: lsb,
            alignedFrameCount: reference.count,
            passed: passed
        )
    }

    /// Spec §9.4 foundation: a timeline END position expressed in GRAPH
    /// samples survives a round trip through another rate's timebase (how
    /// mixed-rate sources see the timeline) EXACTLY under the Int64 sample
    /// math — the property the 60-minute drift gate builds on. The drift
    /// MEASUREMENT itself is E2E-only (spec §9.5); a seconds-based or
    /// accumulating implementation would fail here while the exact math
    /// cannot.
    public static func mixedRateRoundTripIsExact(
        timelineEnd: Int64,
        graphRate: Double,
        otherRate: Double
    ) -> Bool {
        let graphTimebase = AudioGraphTimebase(sampleRate: graphRate)
        let otherTimebase = AudioGraphTimebase(sampleRate: otherRate)
        // graph position → instant → other-domain position → instant → graph.
        let otherPosition = otherTimebase.samplePosition(
            at: graphTimebase.time(atSamplePosition: timelineEnd)
        )
        let graphAgain = graphTimebase.samplePosition(
            at: otherTimebase.time(atSamplePosition: otherPosition)
        )
        return graphAgain == timelineEnd
    }
}
