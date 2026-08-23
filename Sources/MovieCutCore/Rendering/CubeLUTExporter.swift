import Foundation
#if canImport(CoreImage)
import CoreImage
import CoreGraphics

/// Serializes `CubeLUT` back into Adobe `.cube` text (CA-26).
///
/// Rows are written red-fastest — the exact order `CubeLUTParser` reads —
/// so parse → serialize → parse round-trips losslessly at `%.6f`
/// precision. The alpha channel is not written (`.cube` is RGB-only).
public enum CubeLUTExporter {
    /// Serializes a cube. The title is quoted; embedded double quotes are
    /// stripped so the header line stays a single quoted string.
    public static func serialize(_ lut: CubeLUT, title: String) -> String {
        let safeTitle = title.split(separator: "\"", omittingEmptySubsequences: false).joined()
        var lines: [String] = [
            "TITLE \"\(safeTitle)\"",
            "",
            "LUT_3D_SIZE \(lut.dimension)",
            "",
        ]
        lines.reserveCapacity(5 + lut.dimension * lut.dimension * lut.dimension)
        for index in 0..<(lut.dimension * lut.dimension * lut.dimension) {
            let base = index * 4
            lines.append("\(fmt(lut.data[base])) \(fmt(lut.data[base + 1])) \(fmt(lut.data[base + 2]))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Bakes a clip's color correction into an identity cube by rendering
    /// the cube grid through `ColorCorrectionPixelProcessor` itself — the
    /// baked LUT matches preview/export pixel math by construction.
    ///
    /// Scope (v1, deliberate): basic correction only — brightness, contrast,
    /// saturation, warmth, tint. 3-way grade, HSL curves, masks, and stacked
    /// LUTs are excluded; callers must surface this scope when writing the
    /// file so users do not assume a full-grade bake.
    ///
    /// Precision: the grid renders through a half-float bitmap (standard
    /// LUT precision, ~1e-3 per channel).
    public static func bake(
        dimension: Int = 33,
        colorCorrection: ColorCorrection
    ) -> CubeLUT {
        let clampedDimension = max(2, min(dimension, CubeLUTParser.maximumDimension))
        guard clampedDimension == dimension else {
            return CubeLUT(dimension: clampedDimension, data: identityData(dimension: clampedDimension))
        }

        let width = dimension * dimension
        let height = dimension

        // Identity grid: pixel (x, y) = (r, g, b) with x = g*N + r, y = b.
        var grid = [Float16](repeating: 0, count: width * height * 4)
        let scale = Float16(dimension - 1)
        for y in 0..<height {
            for x in 0..<width {
                let r = Float16(x % dimension) / scale
                let g = Float16(x / dimension) / scale
                let b = Float16(y) / scale
                let offset = ((y * width) + x) * 4
                grid[offset] = r
                grid[offset + 1] = g
                grid[offset + 2] = b
                grid[offset + 3] = 1
            }
        }

        let inputData = grid.withUnsafeBufferPointer { Data(buffer: $0) }
        let input = CIImage(
            bitmapData: inputData,
            bytesPerRow: width * 8,
            size: CGSize(width: width, height: height),
            format: .RGBAh,
            colorSpace: nil
        )

        let corrected = ColorCorrectionPixelProcessor.apply(colorCorrection, to: input)

        var output = [Float16](repeating: 0, count: width * height * 4)
        _ = output.withUnsafeMutableBytes { buffer in
            CIContext(options: [.useSoftwareRenderer: true]).render(
                corrected,
                toBitmap: buffer.baseAddress!,
                rowBytes: width * 8,
                bounds: corrected.extent,
                format: .RGBAh,
                colorSpace: nil
            )
        }

        var data = [Float]()
        data.reserveCapacity(width * height * 4)
        for index in 0..<(width * height) {
            let offset = index * 4
            data.append(clamp(Float(output[offset])))
            data.append(clamp(Float(output[offset + 1])))
            data.append(clamp(Float(output[offset + 2])))
            data.append(1)
        }
        return CubeLUT(dimension: dimension, data: data)
    }

    private static func identityData(dimension: Int) -> [Float] {
        let count = dimension * dimension * dimension
        var data = [Float](repeating: 0, count: count * 4)
        let scale = Float(dimension - 1)
        for index in 0..<count {
            let r = Float(index % dimension) / scale
            let g = Float((index / dimension) % dimension) / scale
            let b = Float(index / (dimension * dimension)) / scale
            let offset = index * 4
            data[offset] = r
            data[offset + 1] = g
            data[offset + 2] = b
            data[offset + 3] = 1
        }
        return data
    }

    private static func clamp(_ value: Float) -> Float {
        Swift.min(Swift.max(value, 0), 1)
    }

    private static func fmt(_ value: Float) -> String {
        String(format: "%.6f", value)
    }
}
#endif
