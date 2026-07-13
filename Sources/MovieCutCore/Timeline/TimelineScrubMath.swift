import Foundation

/// Pure coordinate conversion shared by the timeline UI and behavioral tests.
public enum TimelineScrubMath {
    public static func time(
        forLocalX localX: Double,
        pixelsPerSecond: Double,
        duration: TimeInterval
    ) -> TimeInterval {
        guard localX.isFinite,
              pixelsPerSecond.isFinite,
              pixelsPerSecond > 0,
              duration.isFinite,
              duration > 0 else {
            return 0
        }

        return min(duration, max(0, localX / pixelsPerSecond))
    }
}
