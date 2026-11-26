import Foundation

/// Finds nearby edit points for timeline snapping.
public struct SnapEngine: Sendable {
    /// Maximum distance in seconds for a snap candidate.
    public var threshold: TimeInterval {
        didSet {
            threshold = max(0, threshold)
        }
    }

    /// Creates a snap engine.
    public init(threshold: TimeInterval = 0.1) {
        self.threshold = max(0, threshold)
    }

    /// Returns the nearest clip boundary within the snap threshold.
    ///
    /// Allocation-free two-level loop: the previous implementation built
    /// three temporary arrays per call (flatMap → map → filter → min) on
    /// every drag tick. Same contract: nearest distance wins, ties pick
    /// the smaller point.
    public func snap(time: TimeInterval, timeline: Timeline) -> TimeInterval? {
        var bestPoint: TimeInterval?
        var bestDistance = TimeInterval.greatestFiniteMagnitude

        func consider(_ point: TimeInterval) {
            let distance = abs(point - time)
            guard distance <= threshold else { return }
            if distance < bestDistance
                || (distance == bestDistance && point < (bestPoint ?? .greatestFiniteMagnitude)) {
                bestDistance = distance
                bestPoint = point
            }
        }

        for track in timeline.tracks {
            for clip in track.clips {
                consider(clip.timelineRange.start)
                consider(clip.timelineRange.end)
            }
        }
        return bestPoint
    }

    /// Returns sorted unique clip boundary and marker times.
    public func snapPoints(from timeline: Timeline) -> [TimeInterval] {
        Array(Set(clipBoundaryPoints(from: timeline) + timeline.markers.map(\.time))).sorted()
    }

    private func clipBoundaryPoints(from timeline: Timeline) -> [TimeInterval] {
        timeline.tracks
            .flatMap(\.clips)
            .flatMap { clip in
                [clip.timelineRange.start, clip.timelineRange.end]
            }
    }
}
