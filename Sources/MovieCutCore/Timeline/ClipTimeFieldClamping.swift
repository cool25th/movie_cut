import Foundation

public extension Clip {
    /// Reconciles the clip-local time fields that go stale when the clip's
    /// rendered timeline duration changes (e.g. after a speed change in
    /// `SetClipSpeedCommand`).
    ///
    /// - `duckingRanges`: clip-local timeline ranges — drop ranges past the new
    ///   end and clamp ones that straddle it.
    /// - `fadeInDuration` / `fadeOutDuration`: clamp to the new duration.
    /// - `transition?.duration`: clamp to the new duration.
    ///
    /// Keyframes are intentionally NOT touched: they are stored source-relative
    /// (`Keyframe.time` is "within the clip source range") and a speed change
    /// does not move source positions. Step 4 of the core-editing repair handoff.
    ///
    /// - Parameter timelineDuration: the clip's new rendered timeline duration.
    mutating func clampTimeFields(to timelineDuration: TimeInterval) {
        guard timelineDuration.isFinite, timelineDuration >= 0 else { return }

        // duckingRanges are clip-local (seconds from the clip's timeline start).
        duckingRanges = duckingRanges.compactMap { range in
            let clampedStart = min(max(range.start, 0), timelineDuration)
            let rawEnd = range.end
            let clampedEnd = min(max(rawEnd, clampedStart), timelineDuration)
            let duration = clampedEnd - clampedStart
            // Drop zero/negative-duration ranges that became empty after clamping.
            guard duration > 0 else { return nil }
            return TimeRange(start: clampedStart, duration: duration)
        }

        if fadeInDuration > timelineDuration {
            fadeInDuration = timelineDuration
        }
        if fadeOutDuration > timelineDuration {
            fadeOutDuration = timelineDuration
        }

        if var transition, transition.duration > timelineDuration {
            transition.duration = timelineDuration
            self.transition = transition
        }
    }
}
