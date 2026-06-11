import Foundation

/// Pure-math planning for range-based audio ducking (F-14): voice intervals
/// are derived from silence analysis on a speech clip, then translated into
/// clip-local ducking ranges on overlapping music/audio clips. Both engines
/// turn these ranges into identical volume ramps, so preview and export stay
/// in sync by construction.
public enum AudioDuckingPlanner {
    /// Default ducked-volume multiplier (~ -12 dB).
    public static let defaultDuckingLevel: Double = 0.25

    /// Ramp time used when entering a ducked range.
    public static let attackDuration: TimeInterval = 0.12

    /// Ramp time used when leaving a ducked range.
    public static let releaseDuration: TimeInterval = 0.25

    /// Returns the speech (non-silent) intervals of a clip in timeline space.
    ///
    /// - Parameters:
    ///   - speechTimelineRange: The speech clip's timeline range.
    ///   - silenceRangesInTimeline: Silence ranges already mapped to timeline
    ///     space (clamped to the speech range internally).
    ///   - minimumDuration: Voice intervals shorter than this are dropped.
    public static func voiceIntervals(
        speechTimelineRange: TimeRange,
        silenceRangesInTimeline: [TimeRange],
        minimumDuration: TimeInterval = 0.2
    ) -> [TimeRange] {
        guard speechTimelineRange.duration > 0 else { return [] }

        let clampedSilences = silenceRangesInTimeline
            .compactMap { intersection($0, speechTimelineRange) }
            .sorted { $0.start < $1.start }

        var intervals: [TimeRange] = []
        var cursor = speechTimelineRange.start
        for silence in clampedSilences {
            if silence.start > cursor {
                intervals.append(TimeRange(start: cursor, duration: silence.start - cursor))
            }
            cursor = max(cursor, silence.end)
        }
        if cursor < speechTimelineRange.end {
            intervals.append(TimeRange(start: cursor, duration: speechTimelineRange.end - cursor))
        }

        return intervals.filter { $0.duration >= minimumDuration }
    }

    /// Converts timeline-space voice intervals into clip-local ducking ranges
    /// for one target clip: pads each interval, merges overlaps, intersects
    /// with the target's timeline range, then rebases onto the clip start.
    public static func duckingRanges(
        forTarget targetTimelineRange: TimeRange,
        voiceIntervals: [TimeRange],
        padding: TimeInterval = 0.15
    ) -> [TimeRange] {
        guard targetTimelineRange.duration > 0, !voiceIntervals.isEmpty else { return [] }

        let padded = voiceIntervals.map { interval in
            TimeRange(
                start: max(0, interval.start - padding),
                duration: interval.duration + padding * 2
            )
        }

        let merged = mergeOverlapping(padded)

        return merged.compactMap { interval -> TimeRange? in
            guard let clipped = intersection(interval, targetTimelineRange) else { return nil }
            return TimeRange(
                start: clipped.start - targetTimelineRange.start,
                duration: clipped.duration
            )
        }
    }

    /// Merges overlapping or touching ranges into a sorted minimal set.
    public static func mergeOverlapping(_ ranges: [TimeRange]) -> [TimeRange] {
        let sorted = ranges
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }

        var merged: [TimeRange] = [sorted[0]]
        for range in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if range.start <= last.end {
                let end = max(last.end, range.end)
                merged[merged.count - 1] = TimeRange(start: last.start, duration: end - last.start)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func intersection(_ a: TimeRange, _ b: TimeRange) -> TimeRange? {
        let start = max(a.start, b.start)
        let end = min(a.end, b.end)
        guard end > start else { return nil }
        return TimeRange(start: start, duration: end - start)
    }
}
