import Foundation

/// Pure-math HSL secondary correction builder for G-02 Inc 2.
/// Produces RGBA float cube data shaped for a future CIColorCube integration.
public enum HSLCubeBuilder {
    public struct RGB: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red.clamped(to: 0...1, fallback: 0)
            self.green = green.clamped(to: 0...1, fallback: 0)
            self.blue = blue.clamped(to: 0...1, fallback: 0)
        }
    }

    private struct HSL {
        var hue: Double
        var saturation: Double
        var luminance: Double
    }

    public static func cube(size: Int = 64, bands: [HSLBand]) -> [Float] {
        let size = max(size, 2)
        var data: [Float] = []
        data.reserveCapacity(size * size * size * 4)

        for blueIndex in 0..<size {
            for greenIndex in 0..<size {
                for redIndex in 0..<size {
                    let rgb = RGB(
                        red: Double(redIndex) / Double(size - 1),
                        green: Double(greenIndex) / Double(size - 1),
                        blue: Double(blueIndex) / Double(size - 1)
                    )
                    let adjusted = apply(rgb, bands: bands)
                    data.append(Float(adjusted.red))
                    data.append(Float(adjusted.green))
                    data.append(Float(adjusted.blue))
                    data.append(1)
                }
            }
        }
        return data
    }

    public static func apply(_ rgb: RGB, bands: [HSLBand]) -> RGB {
        let activeBands = bands.filter { !$0.isIdentity }
        guard !activeBands.isEmpty else { return rgb }

        var hsl = toHSL(rgb)
        var totalWeight = 0.0
        var hueShift = 0.0
        var saturationDelta = 0.0
        var luminanceDelta = 0.0

        for band in activeBands {
            let weight = falloffWeight(hue: hsl.hue, center: band.center.hueDegrees)
            guard weight > 0 else { continue }
            totalWeight += weight
            hueShift += band.hueShift * weight
            saturationDelta += band.saturation * weight
            luminanceDelta += band.luminance * weight
        }

        guard totalWeight > 0 else { return rgb }
        let normalizer = min(totalWeight, 1)
        hsl.hue = wrappedHue(hsl.hue + hueShift / totalWeight * normalizer)
        hsl.saturation = (hsl.saturation + saturationDelta / totalWeight * normalizer).clamped(to: 0...1, fallback: 0)
        hsl.luminance = (hsl.luminance + luminanceDelta / totalWeight * normalizer).clamped(to: 0...1, fallback: 0)
        return toRGB(hsl)
    }

    public static func falloffWeight(hue: Double, center: Double, halfWidth: Double = 45) -> Double {
        let distance = hueDistance(hue, center)
        guard distance < halfWidth else { return 0 }
        return 0.5 + 0.5 * cos(.pi * distance / halfWidth)
    }

    private static func toHSL(_ rgb: RGB) -> HSL {
        let maxValue = max(rgb.red, rgb.green, rgb.blue)
        let minValue = min(rgb.red, rgb.green, rgb.blue)
        let delta = maxValue - minValue
        let luminance = (maxValue + minValue) / 2

        guard delta > 0 else {
            return HSL(hue: 0, saturation: 0, luminance: luminance)
        }

        let saturation = delta / (1 - abs(2 * luminance - 1))
        let hue: Double
        if maxValue == rgb.red {
            hue = 60 * (((rgb.green - rgb.blue) / delta).truncatingRemainder(dividingBy: 6))
        } else if maxValue == rgb.green {
            hue = 60 * (((rgb.blue - rgb.red) / delta) + 2)
        } else {
            hue = 60 * (((rgb.red - rgb.green) / delta) + 4)
        }
        return HSL(hue: wrappedHue(hue), saturation: saturation.clamped(to: 0...1, fallback: 0), luminance: luminance.clamped(to: 0...1, fallback: 0))
    }

    private static func toRGB(_ hsl: HSL) -> RGB {
        let c = (1 - abs(2 * hsl.luminance - 1)) * hsl.saturation
        let hPrime = hsl.hue / 60
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let base: (Double, Double, Double)
        switch hPrime {
        case 0..<1: base = (c, x, 0)
        case 1..<2: base = (x, c, 0)
        case 2..<3: base = (0, c, x)
        case 3..<4: base = (0, x, c)
        case 4..<5: base = (x, 0, c)
        default: base = (c, 0, x)
        }
        let m = hsl.luminance - c / 2
        return RGB(red: base.0 + m, green: base.1 + m, blue: base.2 + m)
    }

    private static func hueDistance(_ lhs: Double, _ rhs: Double) -> Double {
        let delta = abs(wrappedHue(lhs) - wrappedHue(rhs)).truncatingRemainder(dividingBy: 360)
        return min(delta, 360 - delta)
    }

    private static func wrappedHue(_ hue: Double) -> Double {
        let wrapped = hue.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
