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

    /// RGB parade: one waveform per channel (R, G, B value distribution vs. x),
    /// the data for the classic side-by-side parade scope. Binning mirrors
    /// ``lumaWaveform(rgba:width:height:columns:levels:)`` so the two scopes
    /// stay directly comparable.
    public struct RGBParade: Sendable, Equatable {
        /// `columns × levels` counts for the red channel.
        public var red: [[Int]]
        /// `columns × levels` counts for the green channel.
        public var green: [[Int]]
        /// `columns × levels` counts for the blue channel.
        public var blue: [[Int]]

        public init(red: [[Int]], green: [[Int]], blue: [[Int]]) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// For each of `columns` evenly-spaced image columns, the per-channel pixel
    /// count at each of `levels` channel levels.
    public static func rgbParade(
        rgba: [UInt8],
        width: Int,
        height: Int,
        columns: Int,
        levels: Int
    ) -> RGBParade {
        guard width > 0, height > 0, columns > 0, levels > 0 else {
            return RGBParade(red: [], green: [], blue: [])
        }
        var red = Array(repeating: Array(repeating: 0, count: levels), count: columns)
        var green = red
        var blue = red
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                guard offset + 2 < rgba.count else { continue }
                let column = Swift.min(columns - 1, x * columns / width)
                red[column][Swift.min(levels - 1, Int(rgba[offset]) * levels / 256)] += 1
                green[column][Swift.min(levels - 1, Int(rgba[offset + 1]) * levels / 256)] += 1
                blue[column][Swift.min(levels - 1, Int(rgba[offset + 2]) * levels / 256)] += 1
            }
        }
        return RGBParade(red: red, green: green, blue: blue)
    }

    // MARK: - Single-pass aggregation

    /// All four scopes from one pixel pass. Feeding a frame through the four
    /// individual reducers walked the same bytes four times; this struct and
    /// ``analyzeAll(rgba:width:height:histogramBins:waveformColumns:waveformLevels:vectorscopeSize:)``
    /// accumulate every scope in a single loop.
    public struct AllScopes: Sendable, Equatable {
        public var histogram: Histogram
        public var lumaWaveform: [[Int]]
        public var rgbParade: RGBParade
        public var vectorscope: Vectorscope

        public init(
            histogram: Histogram,
            lumaWaveform: [[Int]],
            rgbParade: RGBParade,
            vectorscope: Vectorscope
        ) {
            self.histogram = histogram
            self.lumaWaveform = lumaWaveform
            self.rgbParade = rgbParade
            self.vectorscope = vectorscope
        }
    }

    /// One-pass equivalent of `histogram` + `lumaWaveform` + `rgbParade` +
    /// `vectorscope`. Luma uses an integer Rec.709 approximation
    /// (`(2126r + 7152g + 722b + 5000) / 10000`), which matches the Double
    /// reducer to within one rounding step at 8-bit precision.
    public static func analyzeAll(
        rgba: [UInt8],
        width: Int,
        height: Int,
        histogramBins: Int = 64,
        waveformColumns: Int,
        waveformLevels: Int = 48,
        vectorscopeSize: Int = 48
    ) -> AllScopes {
        guard width > 0, height > 0, histogramBins > 0,
              waveformColumns > 0, waveformLevels > 0, vectorscopeSize > 0 else {
            return AllScopes(
                histogram: Histogram(red: [], green: [], blue: [], luma: []),
                lumaWaveform: [],
                rgbParade: RGBParade(red: [], green: [], blue: []),
                vectorscope: Vectorscope(size: 0, counts: [])
            )
        }

        var histRed = [Int](repeating: 0, count: histogramBins)
        var histGreen = [Int](repeating: 0, count: histogramBins)
        var histBlue = [Int](repeating: 0, count: histogramBins)
        var histLuma = [Int](repeating: 0, count: histogramBins)
        var waveform = Array(repeating: Array(repeating: 0, count: waveformLevels), count: waveformColumns)
        var paradeRed = waveform
        var paradeGreen = waveform
        var paradeBlue = waveform
        var vectorscopeCounts = [Int](repeating: 0, count: vectorscopeSize * vectorscopeSize)
        let chromaScale = 0.5 / 200.0

        let pixelCount = rgba.count / 4
        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            guard offset + 2 < rgba.count else { continue }
            let r = Int(rgba[offset])
            let g = Int(rgba[offset + 1])
            let b = Int(rgba[offset + 2])

            // Histogram (single integer luma, reused by the waveform).
            histRed[Swift.min(histogramBins - 1, r * histogramBins / 256)] += 1
            histGreen[Swift.min(histogramBins - 1, g * histogramBins / 256)] += 1
            histBlue[Swift.min(histogramBins - 1, b * histogramBins / 256)] += 1
            let lumaValue = (r * 2126 + g * 7152 + b * 722 + 5000) / 10000
            histLuma[Swift.min(histogramBins - 1, Swift.max(0, lumaValue) * histogramBins / 256)] += 1

            // Column scopes (waveform + parade) need the pixel's x position,
            // which only exists when the buffer matches the declared geometry.
            if pixel < width * height {
                let x = pixel % width
                let column = Swift.min(waveformColumns - 1, x * waveformColumns / width)
                waveform[column][Swift.min(waveformLevels - 1, lumaValue * waveformLevels / 256)] += 1
                paradeRed[column][Swift.min(waveformLevels - 1, r * waveformLevels / 256)] += 1
                paradeGreen[column][Swift.min(waveformLevels - 1, g * waveformLevels / 256)] += 1
                paradeBlue[column][Swift.min(waveformLevels - 1, b * waveformLevels / 256)] += 1
            }

            // Vectorscope (same chroma math as the standalone reducer).
            let dr = Double(r)
            let dg = Double(g)
            let db = Double(b)
            let y = dr * 0.2126 + dg * 0.7152 + db * 0.0722
            let u = (db - y) * chromaScale + 0.5
            let v = (dr - y) * chromaScale + 0.5
            let gx = Swift.min(vectorscopeSize - 1, Swift.max(0, Int(u * Double(vectorscopeSize))))
            let gy = Swift.min(vectorscopeSize - 1, Swift.max(0, Int(v * Double(vectorscopeSize))))
            vectorscopeCounts[gy * vectorscopeSize + gx] += 1
        }

        return AllScopes(
            histogram: Histogram(red: histRed, green: histGreen, blue: histBlue, luma: histLuma),
            lumaWaveform: waveform,
            rgbParade: RGBParade(red: paradeRed, green: paradeGreen, blue: paradeBlue),
            vectorscope: Vectorscope(size: vectorscopeSize, counts: vectorscopeCounts)
        )
    }
}
