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

    /// Creates chroma key settings.
    public init(
        keyColor: String,
        tolerance: Double,
        softness: Double,
        spillSuppression: Double
    ) {
        self.keyColor = keyColor
        self.tolerance = min(max(tolerance, 0.0), 1.0)
        self.softness = min(max(softness, 0.0), 1.0)
        self.spillSuppression = min(max(spillSuppression, 0.0), 1.0)
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
