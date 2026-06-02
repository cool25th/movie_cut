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
    public func snap(time: TimeInterval, timeline: Timeline) -> TimeInterval? {
        clipBoundaryPoints(from: timeline)
            .map { point in (point: point, distance: abs(point - time)) }
            .filter { $0.distance <= threshold }
            .min { lhs, rhs in
                if lhs.distance == rhs.distance {
                    return lhs.point < rhs.point
                }
                return lhs.distance < rhs.distance
            }?
            .point
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
