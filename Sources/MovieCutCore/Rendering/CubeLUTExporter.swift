import Foundation
#if canImport(CoreImage)
import CoreImage
import CoreGraphics

/// CA-26 LUT export failures — surfaced explicitly instead of silently
/// substituting an identity LUT or crashing on malformed input.
public enum CubeLUTExportError: Error, Equatable, Sendable {
    /// Dimension outside the format/parser-supported range 2…65.
    case dimensionOutOfRange(Int)
    /// `data.count` does not match `dimension³ × 4`; serializing would read
    /// past the end of the array.
    case dataCountMismatch(dimension: Int, dataCount: Int)
}

/// Serializes `CubeLUT` into Adobe `.cube` text (CA-26).
///
/// This is a NORMALIZED re-serialization at `%.6f` precision — NOT a
/// lossless round-trip: DOMAIN lines, comments, the original title, source
/// precision, and out-of-`0…1` values do not survive. It is only for cubes
/// the app itself generated (color-correction bakes). Re-exporting an
/// imported LUT must instead copy the managed original file byte-for-byte.
///
/// Rows are written red-fastest — the exact order `CubeLUTParser` reads.
/// The alpha channel is not written (`.cube` is RGB-only).
public enum CubeLUTExporter {
    /// Serializes a cube. The title is quoted; embedded double quotes are
    /// stripped so the header line stays a single quoted string.
    /// Throws instead of crashing when dimension/data are inconsistent.
    public static func serialize(_ lut: CubeLUT, title: String) throws -> String {
        try validate(lut)
        let safeTitle = title.split(separator: "\"", omittingEmptySubsequences: false).joined()
        var lines: [String] = [
            "TITLE \"\(safeTitle)\"",
            "",
            "LUT_3D_SIZE \(lut.dimension)",
            "",
        ]
        let entryCount = lut.dimension * lut.dimension * lut.dimension
        lines.reserveCapacity(5 + entryCount)
        for index in 0..<entryCount {
            let base = index * 4
            lines.append("\(fmt(lut.data[base])) \(fmt(lut.data[base + 1])) \(fmt(lut.data[base + 2]))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// A public `CubeLUT` can be built with any dimension/data combination;
    /// serialization would otherwise index past the array's end. Validate
    /// BEFORE touching `data`.
    public static func validate(_ lut: CubeLUT) throws {
        guard lut.dimension >= 2, lut.dimension <= CubeLUTParser.maximumDimension else {
            throw CubeLUTExportError.dimensionOutOfRange(lut.dimension)
        }
        let expected = lut.dimension * lut.dimension * lut.dimension * 4
        guard lut.data.count == expected else {
            throw CubeLUTExportError.dataCountMismatch(dimension: lut.dimension, dataCount: lut.data.count)
        }
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
    ///
    /// Invalid dimensions are rejected explicitly — an out-of-range request
    /// must never silently produce an identity/clamped cube.
    public static func bake(
        dimension: Int = 33,
        colorCorrection: ColorCorrection
    ) throws -> CubeLUT {
        guard dimension >= 2, dimension <= CubeLUTParser.maximumDimension else {
            throw CubeLUTExportError.dimensionOutOfRange(dimension)
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

    private static func clamp(_ value: Float) -> Float {
        Swift.min(Swift.max(value, 0), 1)
    }

    private static func fmt(_ value: Float) -> String {
        String(format: "%.6f", value)
    }
}
#endif
