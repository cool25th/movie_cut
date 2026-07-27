import Foundation

public extension Array where Element == SpeedRampPoint {
    /// Re-normalizes speed-ramp points from a parent source range into a
    /// sub-range, so each resulting clip's ramp curve spans [0,1] of its own
    /// source sub-range after a split (Step 5 of the core-editing repair).
    ///
    /// `SpeedRampPoint.time` is normalized to [0,1] of the *whole* original
    /// source range. After a split, the first/second clip covers only a
    /// sub-interval of that source range, so their inherited points must be
    /// mapped from the parent normalized domain into the sub-range normalized
    /// domain: a parent point at `t` inside sub-interval `[a, b]` becomes
    /// `(t - a) / (b - a)`.
    ///
    /// Points outside `[a, b]` are dropped; if a boundary point is missing it
    /// is synthesized from the nearest point's rate so the curve always spans
    /// [0,1].
    ///
    /// - Parameters:
    ///   - parentSourceStart: absolute source start of the original clip.
    ///   - parentSourceDuration: absolute source duration of the original clip.
    ///   - subSourceRange: the absolute source sub-range the new clip covers.
    /// - Returns: re-normalized points spanning [0,1] of `subSourceRange`,
    ///   or an empty array if fewer than two points survive (caller treats
    ///   empty as "no ramp").
    func renormalized(
        fromParentSourceStart parentSourceStart: TimeInterval,
        parentSourceDuration: TimeInterval,
        intoSubSourceRange subSourceRange: TimeRange
    ) -> [SpeedRampPoint] {
        guard parentSourceDuration > 0 else { return [] }
        guard subSourceRange.duration > 0 else { return [] }

        let a = (subSourceRange.start - parentSourceStart) / parentSourceDuration
        let b = (subSourceRange.end - parentSourceStart) / parentSourceDuration
        guard b > a else { return [] }

        let span = b - a

        // Map each point's normalized time into the sub-domain, keeping only
        // those inside [a, b].
        var mapped: [(norm: TimeInterval, rate: Double)] = []
        for point in self {
            guard point.time >= a - 0.0001, point.time <= b + 0.0001 else { continue }
            // Use Swift.min/Swift.max: inside an Array extension the bare
            // min()/max() resolve to the Sequence instance methods, not the
            // free functions we need here.
            let clamped = Swift.min(Swift.max(point.time, a), b)
            let norm = (clamped - a) / span
            mapped.append((norm, point.rate))
        }

        guard !mapped.isEmpty else { return [] }

        // Ensure the curve spans [0,1]: synthesize boundary points from the
        // nearest rate if none land exactly at the edges.
        let hasStart = mapped.contains { abs($0.norm) < 0.0001 }
        let hasEnd = mapped.contains { abs($0.norm - 1.0) < 0.0001 }
        let firstRate = mapped.first!.rate
        let lastRate = mapped.last!.rate
        if !hasStart {
            mapped.insert((0.0, firstRate), at: 0)
        }
        if !hasEnd {
            mapped.append((1.0, lastRate))
        }

        // Deduplicate by normalized time (keep last) and clamp.
        var seen: Set<Int> = []
        var result: [SpeedRampPoint] = []
        for entry in mapped {
            let bucket = Int((entry.norm * 1_000_000).rounded())
            if seen.contains(bucket) {
                if let lastIndex = result.indices.last, abs(result[lastIndex].time - entry.norm) < 0.0001 {
                    result[lastIndex] = SpeedRampPoint(time: entry.norm, rate: entry.rate)
                }
                continue
            }
            seen.insert(bucket)
            result.append(SpeedRampPoint(time: entry.norm, rate: entry.rate))
        }

        // Need at least two points (start + end) for a ramp.
        return result.count >= 2 ? result : []
    }
}
