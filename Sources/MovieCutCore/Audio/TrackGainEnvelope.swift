import Foundation

/// One linear-amplitude gain segment of a clip's composed envelope, in
/// ABSOLUTE track time (the same coordinates `AVMutableAudioMixInputParameters`
/// volume ramps live in).
///
/// `TrackGainEnvelope` composes a clip's volume × fades × baked ducking into
/// ONE ordered, non-overlapping segment list so a single
/// `AVMutableAudioMixInputParameters` can never receive overlapping ramps
/// (the NSInvalidArgumentException the montage E2E hit). It mirrors the graph
/// builder's semantics — `AudioGraphProjectBuilder.gainAutomation`/
/// `fadeAutomation`: amplitude-linear fades, dB-linear duck attack/hold/
/// release from `AudioDuckingPlanner`, duck ranges too short for both ramps
/// ducking nothing — so the legacy preview audioMix path and the export graph
/// apply the same gain curve, each in its own representation.
public enum TrackGainEnvelope {

    public static let silenceGain: Double = 0.0

    /// Composes the envelope for one clip.
    ///
    /// - Parameters:
    ///   - clip: the clip whose `volume`, `fadeInDuration`, `fadeOutDuration`,
    ///     `duckingLevel`, and `duckingRanges` (clip-local seconds) compose
    ///     the curve.
    ///   - timelineStart: the clip's start in track time — transition-
    ///     adjusted where the composition path shifts clips.
    ///   - timelineDuration: the clip's EFFECTIVE timeline duration (speed-
    ///     scaled where the composition path scales it).
    public static func segments(
        for clip: Clip,
        timelineStart: TimeInterval,
        timelineDuration: TimeInterval
    ) -> [Segment] {
        guard timelineDuration.isFinite, timelineDuration > 0 else { return [] }

        let fade = fadeFactor(clip: clip, duration: timelineDuration)
        let duck = duckFactor(clip: clip, duration: timelineDuration)

        var times: Set<TimeInterval> = [0, timelineDuration]
        if clip.fadeInDuration > 0 { times.insert(min(clip.fadeInDuration, timelineDuration)) }
        if clip.fadeOutDuration > 0 { times.insert(max(0, timelineDuration - clip.fadeOutDuration)) }
        for t in duck.breakpoints {
            times.insert(max(0, min(t, timelineDuration)))
        }

        let sorted = times.sorted()
        var segments: [Segment] = []
        for (a, b) in zip(sorted, sorted.dropFirst()) {
            guard b > a else { continue }
            segments.append(Segment(
                start: timelineStart + a,
                end: timelineStart + b,
                startGain: gain(at: a, volume: clip.volume, fade: fade, duck: duck),
                endGain: gain(at: b, volume: clip.volume, fade: fade, duck: duck)
            ))
        }
        return segments
    }

    /// A gain segment. Constant stretches are expressed as ramps whose start
    /// and end gains are equal — legal for `setVolumeRamp` and keeps the
    /// emission uniform.
    public struct Segment: Equatable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var startGain: Double
        public var endGain: Double

        public init(start: TimeInterval, end: TimeInterval, startGain: Double, endGain: Double) {
            self.start = start
            self.end = end
            self.startGain = startGain
            self.endGain = endGain
        }
    }

    // MARK: - Factor curves (clip-local seconds)

    private struct FadeFactor {
        var fadeIn: TimeInterval
        var fadeOut: TimeInterval
        var duration: TimeInterval

        func value(at t: TimeInterval) -> Double {
            if fadeIn > 0, t < fadeIn {
                return max(0, t / fadeIn)
            }
            if fadeOut > 0, t > duration - fadeOut {
                return max(0, (duration - t) / fadeOut)
            }
            return 1
        }
    }

    private struct DuckFactor {
        struct Range {
            var start: TimeInterval
            var attackEnd: TimeInterval
            var releaseStart: TimeInterval
            var end: TimeInterval
            var depthDb: Double
        }

        var ranges: [Range] = []

        var isEmpty: Bool { ranges.isEmpty }

        var breakpoints: [TimeInterval] {
            ranges.flatMap { [$0.start, $0.attackEnd, $0.releaseStart, $0.end] }
        }

        /// Multiplicative factor at `t` (1 outside every range). Each ramp is
        /// dB-linear between its breakpoints — matching the graph builder —
        /// approximated here by evaluating the exact curve at every requested
        /// time; callers that also sample ramp midpoints keep the emitted
        /// piecewise-linear error small.
        func value(at t: TimeInterval) -> Double {
            var factor: Double = 1
            for range in ranges where t > range.start && t < range.end {
                let db: Double
                if t < range.attackEnd {
                    db = range.depthDb * ((t - range.start) / max(range.attackEnd - range.start, .ulpOfOne))
                } else if t > range.releaseStart {
                    db = range.depthDb * ((range.end - t) / max(range.end - range.releaseStart, .ulpOfOne))
                } else {
                    db = range.depthDb
                }
                factor *= pow(10, db / 20)
            }
            return factor
        }
    }

    private static func fadeFactor(clip: Clip, duration: TimeInterval) -> FadeFactor {
        FadeFactor(
            fadeIn: min(max(clip.fadeInDuration, 0), duration),
            fadeOut: min(max(clip.fadeOutDuration, 0), duration),
            duration: duration
        )
    }

    private static func duckFactor(clip: Clip, duration: TimeInterval) -> DuckFactor {
        var factor = DuckFactor()
        guard let duckingLevel = clip.duckingLevel,
              duckingLevel < 1,
              clip.duckingRanges.isEmpty == false else {
            return factor
        }

        let depthDb = 20 * log10(max(duckingLevel, 0.0001))
        let attack = AudioDuckingPlanner.attackDuration
        let release = AudioDuckingPlanner.releaseDuration

        for range in AudioDuckingPlanner.mergeOverlapping(clip.duckingRanges) {
            // Clip-local bounds first; a range too short for both ramps ducks
            // nothing (the graph builder's and the legacy path's behavior).
            let start = max(0, range.start)
            let end = min(range.end, duration)
            guard end - start > attack + release else { continue }
            factor.ranges.append(.init(
                start: start,
                attackEnd: start + attack,
                releaseStart: end - release,
                end: end,
                depthDb: depthDb
            ))
        }
        return factor
    }

    private static func gain(
        at t: TimeInterval,
        volume: Double,
        fade: FadeFactor,
        duck: DuckFactor
    ) -> Double {
        max(0, volume) * fade.value(at: t) * duck.value(at: t)
    }
}
