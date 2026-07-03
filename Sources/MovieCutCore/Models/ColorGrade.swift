import Foundation

/// Professional 3-way (lift / gamma / gain) color grade, modeled on the ASC CDL
/// formula `out = (in * slope + offset) ^ power`:
///
/// - ``lift`` is the per-channel **offset** (shadows / black point).
/// - ``gain`` is the per-channel **slope** (highlights / white point).
/// - ``gamma`` is the master **power** (midtones); `power < 1` brightens midtones,
///   `power > 1` darkens them.
///
/// This is the grading model CapCut lacks; it sits alongside the simpler
/// `ColorCorrection` controls.
public struct ColorGrade: Codable, Sendable, Equatable {
    /// A per-channel RGB triplet.
    public struct RGB: Codable, Sendable, Equatable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static let zero = RGB(red: 0, green: 0, blue: 0)
        public static let one = RGB(red: 1, green: 1, blue: 1)
    }

    /// Shadow offset, per channel. Identity is `0`.
    public var lift: RGB
    /// Midtone power. Identity is `1`.
    public var gamma: Double
    /// Highlight slope, per channel. Identity is `1`.
    public var gain: RGB

    public init(lift: RGB = .zero, gamma: Double = 1, gain: RGB = .one) {
        self.lift = RGB(
            red: Self.clamp(lift.red, -1, 1),
            green: Self.clamp(lift.green, -1, 1),
            blue: Self.clamp(lift.blue, -1, 1)
        )
        self.gamma = Self.clamp(gamma, 0.1, 4)
        self.gain = RGB(
            red: Self.clamp(gain.red, 0, 4),
            green: Self.clamp(gain.green, 0, 4),
            blue: Self.clamp(gain.blue, 0, 4)
        )
    }

    public var isIdentity: Bool {
        lift == .zero && gamma == 1 && gain == .one
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}

/// A normalized tone-curve control point. Both axes are clamped to 0...1.
public struct CurvePoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}
