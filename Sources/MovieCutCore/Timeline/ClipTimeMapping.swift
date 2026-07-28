import Foundation

/// Single source of truth for converting between a clip's timeline time and
/// its source media time.
///
/// Before this type existed, the conversion was duplicated across at least ten
/// call sites (trim, motion tracking, playhead sync, subtitles, keyframes,
/// filmstrip hover, highlight sequencing, split, drag trim) with three
/// incompatible formulas (`delta * rate`, `delta / rate`, and a duration-ratio
/// fallback) and inconsistent rate clamps — and none of them handled speed
/// ramps, reverse, freeze-frames, or image clips. Step 3 of the core-editing
/// repair handoff centralizes the math here.
///
/// The composition pipeline (Playback/Export segment walkers) is intentionally
/// NOT routed through this type: AVFoundation already renders those precisely.
/// This type unifies the *query* paths that sit outside the composition, so a
/// 2× clip's timeline split point maps to the same source offset in the
/// scrubber, the trim handles, the keyframe editor, the filmstrip hover, and
/// the split command.
public struct ClipTimeMapping: Sendable, Equatable {
    /// The source media range the clip covers (absolute source seconds).
    public let sourceRange: TimeRange

    /// The absolute timeline time at which the clip's rendered output begins.
    public let timelineStart: TimeInterval

    /// Constant playback rate. Used directly when there are fewer than two
    /// speed-ramp points; otherwise the ramp curve governs the mapping.
    public let playbackRate: Double

    /// Speed-ramp control points (normalized source time + rate). When there
    /// are at least two, the mapping is non-linear and `playbackRate` is only
    /// a fallback / identity baseline.
    public let speedRampPoints: [SpeedRampPoint]

    /// Whether the source media is played in reverse. Reverse is implemented in
    /// the composition pipeline by substituting a pre-rendered reversed asset,
    /// so for query purposes a forward-advancing timeline time maps to a
    /// source time that decreases from `sourceRange.end`.
    public let isReversed: Bool

    /// The clip kind. Image clips have no temporal source: every timeline time
    /// maps to `sourceRange.start` (a held still).
    public let kind: ClipKind

    /// Creates a mapping from a clip's stored fields. Prefer `Clip.makeTimeMapping()`
    /// which constructs this from a `Clip` directly. `timelineDuration` is the
    /// clip's own rendered timeline span — the authority for freeze-frame and
    /// image clips whose source duration is meaningless.
    public init(
        sourceRange: TimeRange,
        timelineStart: TimeInterval,
        timelineDuration: TimeInterval,
        playbackRate: Double,
        speedRampPoints: [SpeedRampPoint],
        isReversed: Bool,
        kind: ClipKind
    ) {
        self.sourceRange = sourceRange
        self.timelineStart = timelineStart
        self.playbackRate = playbackRate
        self.speedRampPoints = speedRampPoints
        self.isReversed = isReversed
        self.kind = kind
        self.freezeFrameTimelineDuration = timelineDuration
    }

    // MARK: - Public mapping API

    /// Converts an absolute timeline time to the corresponding source media time.
    ///
    /// - Parameter timelineTime: absolute timeline seconds (not clip-local).
    /// - Returns: absolute source seconds, clamped to `sourceRange`. For image
    ///   clips this is always `sourceRange.start`. Invalid inputs (NaN,
    ///   infinity, non-positive rate with no ramp) fail closed to
    ///   `sourceRange.start`.
    public func sourceTime(forTimelineTime timelineTime: TimeInterval) -> TimeInterval {
        guard timelineTime.isFinite else { return sourceRange.start }

        // Image clips display a single still for the whole timeline range.
        if kind == .image {
            return sourceRange.start
        }

        // Clamp the timeline time into the clip's rendered span.
        let timelineEnd = timelineStart + renderedTimelineDuration
        let clampedTimeline = min(max(timelineTime, timelineStart), timelineEnd)
        let localTimelineOffset = clampedTimeline - timelineStart
        guard localTimelineOffset >= 0 else { return sourceRange.start }

        // Freeze-frame policy (matches the composition heuristic): a tiny source
        // range held over a long timeline maps every timeline time to the same
        // source instant.
        if isFreezeFrame {
            return sourceRange.start
        }

        let sourceOffset = sourceOffsetForLocalTimelineOffset(localTimelineOffset)
        let absoluteSourceTime = sourceRange.start + sourceOffset

        if isReversed {
            // Reverse: timeline advances forward, source walks backward from end.
            return max(sourceRange.start, sourceRange.end - sourceOffset)
        }
        return min(absoluteSourceTime, sourceRange.end)
    }

    /// Converts an absolute source media time to the corresponding timeline time.
    ///
    /// - Parameter sourceTime: absolute source seconds.
    /// - Returns: absolute timeline seconds, clamped to the clip's rendered
    ///   span. For image clips every source time maps to `timelineStart`.
    public func timelineTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval {
        guard sourceTime.isFinite else { return timelineStart }

        if kind == .image {
            return timelineStart
        }

        let clampedSource = min(max(sourceTime, sourceRange.start), sourceRange.end)

        if isFreezeFrame {
            return timelineStart
        }

        let sourceOffset: TimeInterval
        if isReversed {
            sourceOffset = max(0, sourceRange.end - clampedSource)
        } else {
            sourceOffset = clampedSource - sourceRange.start
        }

        let localTimelineOffset = timelineOffsetForLocalSourceOffset(sourceOffset)
        return min(timelineStart + localTimelineOffset, timelineStart + renderedTimelineDuration)
    }

    /// The rendered duration of the clip on the timeline, in seconds. For a
    /// constant-rate clip this is `sourceRange.duration / playbackRate`; for a
    /// speed-ramped clip it integrates the ramp curve; for a freeze-frame it is
    /// `sourceRange.duration` is meaningless so the timeline duration is taken
    /// as the stored timeline span ( callers must supply it via the clip).
    public var renderedTimelineDuration: TimeInterval {
        if isFreezeFrame {
            // Freeze spans whatever timeline duration the clip declares; the
            // source range is a single frame. The clip's own timelineRange is
            // the authority here, so expose a sentinel that callers translate.
            return freezeFrameTimelineDuration
        }

        if kind == .image {
            // Image clips have no intrinsic source duration; the timeline
            // duration is whatever the clip declares. Expose a sentinel.
            return freezeFrameTimelineDuration
        }

        if speedRampPoints.count >= 2 {
            let curve = SpeedRampCurve(points: speedRampPoints)
            let normalizedOutput = curve.timeMapping(sourceTime: 1.0)
            let duration = normalizedOutput * sourceRange.duration
            return duration.isFinite && duration > 0 ? duration : sourceRange.duration
        }

        let rate = sanitizedRate
        guard rate > 0 else { return sourceRange.duration }
        return sourceRange.duration / rate
    }

    /// Returns true when two times are within `frames` frames of each other at
    /// `fps`. Used for frame-tolerant round-trip assertions (the handoff's
    /// "1 frame or less" acceptance criterion).
    public static func isWithinFrames(_ a: TimeInterval, _ b: TimeInterval, frames: Double, fps: Double) -> Bool {
        guard fps > 0 else { return false }
        let frameDuration = 1.0 / fps
        return abs(a - b) <= frameDuration * frames
    }

    // MARK: - Internals

    /// Sentinel timeline duration for freeze/image clips. Set from the clip's
    /// own `timelineRange.duration` at construction (see `Clip.makeTimeMapping`).
    /// Kept as a stored property so `renderedTimelineDuration` stays a pure
    /// function of the mapping's fields.
    private let freezeFrameTimelineDuration: TimeInterval

    /// Whether the mapping represents a freeze-frame (tiny source range held
    /// over a meaningful timeline span). Mirrors the composition heuristic in
    /// PlaybackEngine.isFreezeFrameClip / ExportEngine.
    private var isFreezeFrame: Bool {
        sourceRange.duration < 0.1 && freezeFrameTimelineDuration > 0.5
    }

    private var sanitizedRate: Double {
        let rate = playbackRate
        guard rate.isFinite, rate > 0 else { return 1 }
        return max(rate, 0.25)
    }

    private var rampCurve: SpeedRampCurve? {
        speedRampPoints.count >= 2 ? SpeedRampCurve(points: speedRampPoints) : nil
    }

    /// Maps a clip-local timeline offset (0 at clip start) to a clip-local
    /// source offset (0 at source start, increasing forward).
    private func sourceOffsetForLocalTimelineOffset(_ timelineOffset: TimeInterval) -> TimeInterval {
        guard timelineOffset > 0 else { return 0 }

        if isFreezeFrame {
            return 0
        }

        if let curve = rampCurve {
            // The ramp curve integrates 1/rate over normalized [0,1] source
            // time, so a pure slow-mo segment produces a normalized output
            // GREATER than 1 (e.g. a 0.5x ramp maps source 1.0 -> output 2.0).
            // The normalized-output domain therefore spans [0, rampOutputSpan],
            // NOT [0,1]. Clamping the timeline offset to 1 collapsed the
            // entire second half of a slow-mo clip onto the final source frame.
            let sourceDuration = sourceRange.duration
            guard sourceDuration > 0 else { return 0 }
            let rampOutputSpan = curve.timeMapping(sourceTime: 1.0)
            guard rampOutputSpan.isFinite, rampOutputSpan > 0 else { return 0 }
            let normalizedOutput = min(max(timelineOffset / sourceDuration, 0), rampOutputSpan)
            let normalizedSource = curve.inverseMapping(outputTime: normalizedOutput)
            return min(max(normalizedSource * sourceDuration, 0), sourceDuration)
        }

        // Constant rate: source offset = timeline offset * rate.
        return min(timelineOffset * sanitizedRate, sourceRange.duration)
    }

    /// Maps a clip-local source offset to a clip-local timeline offset.
    private func timelineOffsetForLocalSourceOffset(_ sourceOffset: TimeInterval) -> TimeInterval {
        guard sourceOffset > 0 else { return 0 }

        if isFreezeFrame {
            return 0
        }

        let sourceDuration = sourceRange.duration
        guard sourceDuration > 0 else { return 0 }

        if let curve = rampCurve {
            let normalizedSource = min(max(sourceOffset / sourceDuration, 0), 1)
            let normalizedOutput = curve.timeMapping(sourceTime: normalizedSource)
            // timeMapping returns normalized output on the ramp's output scale;
            // scaling by sourceDuration gives timeline seconds. For a slow-mo
            // ramp this exceeds sourceDuration (e.g. 0.5x -> 2x), so the upper
            // bound is the rendered timeline span, not sourceDuration. The old
            // clamp to sourceDuration truncated the clip's slow tail.
            let timelineSpan = renderedTimelineDuration
            return min(max(normalizedOutput * sourceDuration, 0), timelineSpan)
        }

        let rate = sanitizedRate
        guard rate > 0 else { return 0 }
        return sourceOffset / rate
    }
}

public extension Clip {
    /// Builds the canonical time mapping for this clip from its stored fields.
    /// Returns nil only if the clip's ranges are non-finite (a degenerate state
    /// that should never persist). All timeline<->source conversions outside
    /// the composition pipeline should go through this.
    func makeTimeMapping() -> ClipTimeMapping? {
        guard sourceRange.start.isFinite,
              sourceRange.duration.isFinite,
              timelineRange.start.isFinite,
              timelineRange.duration.isFinite,
              playbackRate.isFinite else {
            return nil
        }
        return ClipTimeMapping(
            sourceRange: sourceRange,
            timelineStart: timelineRange.start,
            timelineDuration: timelineRange.duration,
            playbackRate: playbackRate,
            speedRampPoints: speedRampPoints,
            isReversed: isReversed,
            kind: kind
        )
    }
}
