import Foundation

/// Geometry for a 3-way color-grading wheel: a puck position in the unit disk
/// maps to per-channel RGB offsets and back. The three channel axes sit 120°
/// apart — red up, green lower-left, blue lower-right — so dragging the puck
/// toward a hue pushes that channel.
///
/// Pure math (no UI) so the mapping is unit-testable; the SwiftUI `ColorWheel`
/// renders and drives it.
public enum ColorWheelMath {
    // Axis unit vectors (y up): red at 90°, green at 210°, blue at 330°.
    private static let redAxis = (x: 0.0, y: 1.0)
    private static let greenAxis = (x: -0.8660254037844387, y: -0.5)
    private static let blueAxis = (x: 0.8660254037844387, y: -0.5)

    /// Per-channel offsets for a puck at `(x, y)` in the unit disk, scaled by
    /// `scale` (the control's max magnitude).
    public static func channelOffsets(x: Double, y: Double, scale: Double) -> (red: Double, green: Double, blue: Double) {
        (
            red: (x * redAxis.x + y * redAxis.y) * scale,
            green: (x * greenAxis.x + y * greenAxis.y) * scale,
            blue: (x * blueAxis.x + y * blueAxis.y) * scale
        )
    }

    /// The puck position that produces the given offsets (least-squares inverse;
    /// the 120°-symmetric axes make `AᵀA = 1.5·I`, so this round-trips exactly).
    public static func position(red: Double, green: Double, blue: Double, scale: Double) -> (x: Double, y: Double) {
        guard scale != 0 else { return (0, 0) }
        let x = (2.0 / 3.0) * (red * redAxis.x + green * greenAxis.x + blue * blueAxis.x) / scale
        let y = (2.0 / 3.0) * (red * redAxis.y + green * greenAxis.y + blue * blueAxis.y) / scale
        return (x, y)
    }

    /// Clamps a position to the unit disk (so the puck never leaves the wheel).
    public static func clampedToDisk(x: Double, y: Double) -> (x: Double, y: Double) {
        let magnitude = (x * x + y * y).squareRoot()
        guard magnitude > 1 else { return (x, y) }
        return (x / magnitude, y / magnitude)
    }
}
