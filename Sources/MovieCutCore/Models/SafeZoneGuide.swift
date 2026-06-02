import Foundation

/// Percentage-based margins from each canvas edge.
public struct EdgeInsets: Codable, Sendable, Equatable {
    /// Top inset as a fraction of canvas height.
    public var top: Double

    /// Leading inset as a fraction of canvas width.
    public var leading: Double

    /// Bottom inset as a fraction of canvas height.
    public var bottom: Double

    /// Trailing inset as a fraction of canvas width.
    public var trailing: Double

    /// Creates percentage-based edge insets.
    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = min(max(top, 0), 0.5)
        self.leading = min(max(leading, 0), 0.5)
        self.bottom = min(max(bottom, 0), 0.5)
        self.trailing = min(max(trailing, 0), 0.5)
    }

    /// Creates equal percentage-based edge insets.
    public init(_ value: Double) {
        self.init(top: value, leading: value, bottom: value, trailing: value)
    }
}

/// A visual guide showing a safe composition region on the canvas.
public struct SafeZoneGuide: Codable, Sendable, Equatable {
    /// User-visible guide name.
    public var name: String

    /// Percentage-based guide margins from each edge.
    public var insets: EdgeInsets

    /// Overlay color as a hex string.
    public var colorHex: String

    /// Creates a safe-zone guide.
    public init(name: String, insets: EdgeInsets, colorHex: String) {
        self.name = name
        self.insets = insets
        self.colorHex = colorHex
    }

    /// Standard broadcast-style title and action safe guides.
    public static var standard: [SafeZoneGuide] {
        [
            SafeZoneGuide(name: "Title Safe", insets: EdgeInsets(0.10), colorHex: "#FFD60A"),
            SafeZoneGuide(name: "Action Safe", insets: EdgeInsets(0.05), colorHex: "#30D158")
        ]
    }

    /// Social-platform UI safe guides.
    public static var socialSafe: [SafeZoneGuide] {
        [
            SafeZoneGuide(
                name: "Instagram",
                insets: EdgeInsets(top: 0.15, leading: 0, bottom: 0.15, trailing: 0),
                colorHex: "#FF2D55"
            ),
            SafeZoneGuide(
                name: "TikTok",
                insets: EdgeInsets(top: 0.20, leading: 0, bottom: 0.10, trailing: 0),
                colorHex: "#64D2FF"
            )
        ]
    }
}
