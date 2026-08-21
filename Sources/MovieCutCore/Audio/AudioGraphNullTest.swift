import Foundation

/// G-25 spec §9 — the preview↔export null test, as pure Core functions so
/// `swift test` and the E2E gate share ONE judgment (실측 판정은 E2E만, §9.5).
public enum AudioGraphNullTest {
    public struct Result: Sendable, Equatable {
        /// Timeline-frame offset of `candidate` relative to `reference` that
        /// minimized the deviation (searched within ±maxOffsetSamples).
        ///
        /// The historical API name says "samples" because the graph timebase
        /// is sample based. For interleaved stereo this value is still a TIME
        /// offset (one stereo frame), never a raw Float-array index offset.
        public var bestOffsetSamples: Int
        /// Maximum absolute deviation over the aligned overlap.
        public var maxAbsoluteDeviation: Float
        /// One 16-bit LSB at the comparison magnitude scale.
        public var lsb16: Float
        /// Number of aligned stereo frames compared at the winning offset.
        public var alignedFrameCount: Int
        public var passed: Bool
    }

    /// Compares two interleaved-stereo PCM renders of the SAME graph.
    /// Spec §9: search the best alignment within ±1 timeline sample/frame
    /// (configurable for diagnostics), then require the maximum absolute
    /// deviation over the whole aligned overlap to stay within one 16-bit LSB.
    ///
    /// IMPORTANT: offsets are applied in STEREO FRAMES, not scalar Float
    /// indexes. Applying an offset of 1 directly to the interleaved array
    /// would compare L↔R and R↔next-L, allowing a channel-skewed signal to
    /// masquerade as a valid one-sample timing shift.
    ///
    /// Magnitude convention: inputs are Float PCM where 1.0 = 0 dBFS, so
    /// one 16-bit LSB = 1/32,768.
    public static func compare(
        reference: [Float],
        candidate: [Float],
        maxOffsetSamples: Int = 1
    ) -> Result {
        let lsb: Float = 1.0 / 32_768.0
        let channels = 2
        guard !reference.isEmpty,
              reference.count == candidate.count,
              reference.count.isMultiple(of: channels),
              maxOffsetSamples >= 0
        else {
            return Result(
                bestOffsetSamples: 0,
                maxAbsoluteDeviation: .infinity,
                lsb16: lsb,
                alignedFrameCount: 0,
                passed: false
            )
        }

        let frameCount = reference.count / channels
        var bestOffset = 0
        var bestDeviation = Float.infinity
        var bestComparedFrames = 0

        for frameOffset in -maxOffsetSamples...maxOffsetSamples {
            var deviation: Float = 0
            var comparedFrames = 0

            for referenceFrame in 0..<frameCount {
                let candidateFrame = referenceFrame + frameOffset
                guard candidateFrame >= 0, candidateFrame < frameCount else { continue }

                let referenceBase = referenceFrame * channels
                let candidateBase = candidateFrame * channels
                for channel in 0..<channels {
                    deviation = max(
                        deviation,
                        abs(reference[referenceBase + channel] - candidate[candidateBase + channel])
                    )
                }
                comparedFrames += 1
            }

            if comparedFrames > 0, deviation < bestDeviation {
                bestDeviation = deviation
                bestOffset = frameOffset
                bestComparedFrames = comparedFrames
            }
        }

        let passed = bestDeviation.isFinite && bestDeviation <= lsb
        return Result(
            bestOffsetSamples: bestOffset,
            maxAbsoluteDeviation: bestDeviation.isFinite ? bestDeviation : .infinity,
            lsb16: lsb,
            alignedFrameCount: bestComparedFrames,
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
