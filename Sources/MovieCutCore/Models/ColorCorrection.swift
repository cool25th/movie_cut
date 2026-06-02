import Foundation

/// Per-clip color correction controls.
public struct ColorCorrection: Codable, Sendable, Equatable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var tint: Double

    public init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        warmth: Double = 0,
        tint: Double = 0
    ) {
        self.brightness = Self.clamp(brightness, min: -1, max: 1)
        self.contrast = Self.clamp(contrast, min: 0, max: 2)
        self.saturation = Self.clamp(saturation, min: 0, max: 2)
        self.warmth = Self.clamp(warmth, min: -1, max: 1)
        self.tint = Self.clamp(tint, min: -1, max: 1)
    }

    private static func clamp(_ value: Double, min minimum: Double, max maximum: Double) -> Double {
        Swift.min(Swift.max(value, minimum), maximum)
    }
}
