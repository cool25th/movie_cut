import Foundation

/// A simple time interval range used before adopting Core Media time ranges.
public struct TimeRange: Codable, Sendable, Equatable, Hashable {
    /// The start time in seconds.
    public var start: TimeInterval

    /// The duration in seconds.
    public var duration: TimeInterval

    /// Creates a time range in seconds.
    public init(start: TimeInterval = 0, duration: TimeInterval = 0) {
        self.start = start
        self.duration = duration
    }

    /// The exclusive end time in seconds.
    public var end: TimeInterval {
        start + duration
    }

    /// Returns true when the range contains the supplied timeline time.
    public func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}
