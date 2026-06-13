import Foundation

/// Editable chroma key controls for removing a keyed background color.
public struct ChromaKeySettings: Codable, Sendable, Equatable {
    /// The keyed color as a hex string, such as "#00FF00".
    public var keyColor: String

    /// Color matching tolerance from 0.0 to 1.0.
    public var tolerance: Double

    /// Edge feathering softness from 0.0 to 1.0.
    public var softness: Double

    /// Spill removal strength from 0.0 to 1.0.
    public var spillSuppression: Double

    /// Matte erosion (shrink) from 0.0 to 1.0 that pulls the foreground edge
    /// inward to remove residual key-colored fringe (F-10). Orthogonal to
    /// `softness`/feathering. Legacy projects decode this as 0.
    public var edgeShrink: Double

    private enum CodingKeys: String, CodingKey {
        case keyColor
        case tolerance
        case softness
        case spillSuppression
        case edgeShrink
    }

    /// Creates chroma key settings.
    public init(
        keyColor: String,
        tolerance: Double,
        softness: Double,
        spillSuppression: Double,
        edgeShrink: Double = 0
    ) {
        self.keyColor = keyColor
        self.tolerance = min(max(tolerance, 0.0), 1.0)
        self.softness = min(max(softness, 0.0), 1.0)
        self.spillSuppression = min(max(spillSuppression, 0.0), 1.0)
        self.edgeShrink = min(max(edgeShrink, 0.0), 1.0)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyColor = try container.decode(String.self, forKey: .keyColor)
        tolerance = try container.decode(Double.self, forKey: .tolerance)
        softness = try container.decode(Double.self, forKey: .softness)
        spillSuppression = try container.decode(Double.self, forKey: .spillSuppression)
        let shrink = try container.decodeIfPresent(Double.self, forKey: .edgeShrink) ?? 0
        edgeShrink = min(max(shrink, 0.0), 1.0)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyColor, forKey: .keyColor)
        try container.encode(tolerance, forKey: .tolerance)
        try container.encode(softness, forKey: .softness)
        try container.encode(spillSuppression, forKey: .spillSuppression)
        if edgeShrink != 0 {
            try container.encode(edgeShrink, forKey: .edgeShrink)
        }
    }

    /// A practical default for green screen footage.
    public static func greenScreen() -> ChromaKeySettings {
        ChromaKeySettings(
            keyColor: "#00FF00",
            tolerance: 0.35,
            softness: 0.15,
            spillSuppression: 0.4
        )
    }

    /// A practical default for blue screen footage.
    public static func blueScreen() -> ChromaKeySettings {
        ChromaKeySettings(
            keyColor: "#0000FF",
            tolerance: 0.35,
            softness: 0.15,
            spillSuppression: 0.4
        )
    }
}
