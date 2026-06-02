import Foundation

/// A normalized speed-ramp control point within a clip source range.
public struct SpeedRampPoint: Codable, Sendable, Equatable, Identifiable {
    /// The speed-ramp point identifier.
    public var id: UUID

    /// Normalized source time from 0.0 to 1.0 within the clip source range.
    public var time: TimeInterval

    /// Playback rate multiplier from 0.25x to 4.0x.
    public var rate: Double

    /// Creates a speed-ramp point.
    public init(id: UUID = UUID(), time: TimeInterval, rate: Double) {
        self.id = id
        self.time = min(max(time, 0), 1)
        self.rate = min(max(rate, 0.25), 4.0)
    }
}
