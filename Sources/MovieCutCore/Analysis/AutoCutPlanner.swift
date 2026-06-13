import Foundation

/// Pure-math planning for silence-based auto cut (F-18). Detected silence
/// ranges are shrunk by a padding margin on each side so the cut never eats
/// into the speech onset/offset, then filtered and merged. The result is the
/// set of ranges that will actually be removed, which both the preview
/// highlight and the apply step consume.
public enum AutoCutPlanner {
    /// Converts silence ranges (timeline space) into removable ranges,
    /// clamped to `bounds`, padded inward, and merged.
    ///
    /// - Parameters:
    ///   - silenceRanges: Detected silence ranges in timeline seconds.
    ///   - bounds: The clip's timeline range; removable ranges stay inside it.
    ///   - padding: Seconds trimmed from each side of every silence range so
    ///     speech edges are preserved.
    ///   - minimumRemovable: Ranges shorter than this after padding are dropped.
    public static func removableRanges(
        fromSilence silenceRanges: [TimeRange],
        within bounds: TimeRange,
        padding: TimeInterval,
        minimumRemovable: TimeInterval = 0.1
    ) -> [TimeRange] {
        guard bounds.duration > 0 else { return [] }
        let safePadding = max(0, padding)

        let padded = silenceRanges.compactMap { silence -> TimeRange? in
            guard let clipped = intersection(silence, bounds) else { return nil }
            let start = clipped.start + safePadding
            let end = clipped.end - safePadding
            let duration = end - start
            guard duration >= minimumRemovable else { return nil }
            return TimeRange(start: start, duration: duration)
        }

        return merge(padded)
    }

    /// Total removable duration across the ranges.
    public static func totalDuration(of ranges: [TimeRange]) -> TimeInterval {
        ranges.reduce(0) { $0 + $1.duration }
    }

    /// Merges overlapping or touching ranges into a sorted minimal set.
    public static func merge(_ ranges: [TimeRange]) -> [TimeRange] {
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
