import Foundation

/// Reduces an RGBA8 pixel buffer to color-scope data (histogram, luma waveform).
/// Pure and platform-neutral so the reductions are unit-testable; the app feeds
/// it a downsampled, graded preview frame and renders the result.
public enum ScopeAnalyzer {
    /// Per-channel and luma histograms, each `binCount` long.
    public struct Histogram: Sendable, Equatable {
        public var red: [Int]
        public var green: [Int]
        public var blue: [Int]
        public var luma: [Int]

        public init(red: [Int], green: [Int], blue: [Int], luma: [Int]) {
            self.red = red
            self.green = green
            self.blue = blue
            self.luma = luma
        }
    }

    /// Rec. 709 luma of an 8-bit RGB sample.
    public static func luma(red: UInt8, green: UInt8, blue: UInt8) -> Int {
        let r: Double = Double(red) * 0.2126
        let g: Double = Double(green) * 0.7152
        let b: Double = Double(blue) * 0.0722
        return Int((r + g + b).rounded())
    }

    private static func bin(_ value: Int, _ binCount: Int) -> Int {
        Swift.min(binCount - 1, Swift.max(0, value) * binCount / 256)
    }

    /// Builds per-channel + luma histograms from tightly-packed RGBA8 pixels.
    public static func histogram(rgba: [UInt8], binCount: Int = 64) -> Histogram {
        var red = [Int](repeating: 0, count: binCount)
        var green = [Int](repeating: 0, count: binCount)
        var blue = [Int](repeating: 0, count: binCount)
        var luma = [Int](repeating: 0, count: binCount)

        let pixelCount = rgba.count / 4
        for index in 0..<pixelCount {
            let offset = index * 4
            let r = Int(rgba[offset])
            let g = Int(rgba[offset + 1])
            let b = Int(rgba[offset + 2])
            red[bin(r, binCount)] += 1
            green[bin(g, binCount)] += 1
            blue[bin(b, binCount)] += 1
            luma[bin(ScopeAnalyzer.luma(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2]), binCount)] += 1
        }
        return Histogram(red: red, green: green, blue: blue, luma: luma)
    }

    /// A square chroma-scatter grid for a vectorscope.
    public struct Vectorscope: Sendable, Equatable {
        public var size: Int
        /// `size * size` cell counts, row-major; x = B-Y (blue), y = R-Y (red),
        /// centered at `size/2`.
        public var counts: [Int]

        public init(size: Int, counts: [Int]) {
            self.size = size
            self.counts = counts
        }
    }

    /// Bins each pixel's chroma (B-Y, R-Y) into a `size × size` grid. Neutral
    /// (gray) pixels land at the center; saturated hues spread outward.
    public static func vectorscope(rgba: [UInt8], size: Int = 48) -> Vectorscope {
        var counts = [Int](repeating: 0, count: size * size)
        let scale = 0.5 / 200.0
        let pixelCount = rgba.count / 4
        for index in 0..<pixelCount {
            let offset = index * 4
            let r = Double(rgba[offset])
            let g = Double(rgba[offset + 1])
            let b = Double(rgba[offset + 2])
            let yr: Double = r * 0.2126
            let yg: Double = g * 0.7152
            let yb: Double = b * 0.0722
            let y = yr + yg + yb
            let u = (b - y) * scale + 0.5
            let v = (r - y) * scale + 0.5
            let gx = Swift.min(size - 1, Swift.max(0, Int(u * Double(size))))
            let gy = Swift.min(size - 1, Swift.max(0, Int(v * Double(size))))
            counts[gy * size + gx] += 1
        }
        return Vectorscope(size: size, counts: counts)
    }

    /// Luma waveform: for each of `columns` evenly-spaced image columns, the pixel
    /// count at each of `levels` luma levels (luma distribution vs. x).
    public static func lumaWaveform(
        rgba: [UInt8],
        width: Int,
        height: Int,
        columns: Int,
        levels: Int
    ) -> [[Int]] {
        guard width > 0, height > 0, columns > 0, levels > 0 else { return [] }
        var result = Array(repeating: Array(repeating: 0, count: levels), count: columns)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard offset + 2 < rgba.count else { continue }
                let yLuma = ScopeAnalyzer.luma(red: rgba[offset], green: rgba[offset + 1], blue: rgba[offset + 2])
                let column = Swift.min(columns - 1, x * columns / width)
                let level = Swift.min(levels - 1, yLuma * levels / 256)
                result[column][level] += 1
            }
        }
        return result
    }
}
