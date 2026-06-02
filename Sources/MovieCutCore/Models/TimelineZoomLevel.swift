import Foundation

/// User-selectable timeline zoom setting.
public struct TimelineZoomLevel: Codable, Sendable, Equatable {
    /// User-visible zoom level name.
    public var name: String

    /// Timeline scale multiplier.
    public var scale: Double

    /// Creates a timeline zoom level.
    public init(name: String, scale: Double) {
        self.name = name
        self.scale = scale
    }

    /// User-visible zoom level name.
    public var displayName: String {
        name
    }

    /// Compact timeline zoom.
    public static let compact = TimelineZoomLevel(name: "Compact", scale: 0.5)

    /// Normal timeline zoom.
    public static let normal = TimelineZoomLevel(name: "Normal", scale: 1.0)

    /// Comfortable timeline zoom.
    public static let comfortable = TimelineZoomLevel(name: "Comfortable", scale: 2.0)

    /// Detailed timeline zoom.
    public static let detailed = TimelineZoomLevel(name: "Detailed", scale: 4.0)

    /// Standard timeline zoom presets.
    public static var all: [TimelineZoomLevel] {
        [.compact, .normal, .comfortable, .detailed]
    }
}
