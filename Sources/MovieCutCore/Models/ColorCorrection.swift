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
        self.brightness = brightness.clamped(to: -1...1)
        self.contrast = contrast.clamped(to: 0...2)
        self.saturation = saturation.clamped(to: 0...2)
        self.warmth = warmth.clamped(to: -1...1)
        self.tint = tint.clamped(to: -1...1)
    }
}
