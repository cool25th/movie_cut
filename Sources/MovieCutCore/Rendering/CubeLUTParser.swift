import Foundation

/// A parsed 3D color LUT in the layout Core Image's `CIColorCube` expects:
/// `dimension`-cubed RGBA float entries with the red index varying fastest
/// (F-09).
public struct CubeLUT: Sendable, Equatable {
    /// Cube edge size (e.g. 17, 33, 65).
    public let dimension: Int
    /// `dimension^3 * 4` floats, RGBA per entry, red fastest.
    public let data: [Float]

    public init(dimension: Int, data: [Float]) {
        self.dimension = dimension
        self.data = data
    }
}

/// Parses Adobe `.cube` 3D LUT files into `CubeLUT` data. Comments, the title,
/// and domain lines are tolerated; only 3D LUTs are supported.
public enum CubeLUTParser {
    public enum ParseError: Error, Equatable, Sendable {
        case missingSize
        case unsupported1D
        case sizeOutOfRange(Int)
        case entryCountMismatch(expected: Int, found: Int)
        case malformedEntry(String)
    }

    /// Maximum cube edge accepted (CIColorCube becomes very large beyond this).
    public static let maximumDimension = 65

    public static func parse(contentsOf url: URL) throws -> CubeLUT {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    public static func parse(_ text: String) throws -> CubeLUT {
        var dimension: Int?
        var entries: [(Float, Float, Float)] = []

        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let upper = line.uppercased()
            if upper.hasPrefix("LUT_1D_SIZE") {
                throw ParseError.unsupported1D
            }
            if upper.hasPrefix("LUT_3D_SIZE") {
                let parts = line.split(separator: " ").compactMap { Int($0) }
                guard let size = parts.last else { throw ParseError.missingSize }
                guard size >= 2, size <= maximumDimension else { throw ParseError.sizeOutOfRange(size) }
                dimension = size
                entries.reserveCapacity(size * size * size)
                continue
            }
            // Skip known non-data keywords.
            if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_") || upper.hasPrefix("LUT_3D_INPUT_RANGE") {
                continue
            }

            // Data line: three floats.
            let components = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard components.count >= 3,
                  let r = Float(components[0]),
                  let g = Float(components[1]),
                  let b = Float(components[2]) else {
                // A non-numeric line before the table (extra metadata) is skipped;
                // once entries exist, a malformed line is an error.
                if entries.isEmpty { continue }
                throw ParseError.malformedEntry(line)
            }
            entries.append((r, g, b))
        }

        guard let dimension else { throw ParseError.missingSize }
        let expected = dimension * dimension * dimension
        guard entries.count == expected else {
            throw ParseError.entryCountMismatch(expected: expected, found: entries.count)
        }

        var data = [Float]()
        data.reserveCapacity(expected * 4)
        for entry in entries {
            data.append(clamp(entry.0))
            data.append(clamp(entry.1))
            data.append(clamp(entry.2))
            data.append(1.0)
        }

        return CubeLUT(dimension: dimension, data: data)
    }

    private static func clamp(_ value: Float) -> Float {
        Swift.min(Swift.max(value, 0), 1)
    }
}

#if canImport(CoreImage)
import CoreImage

/// Reference wrapper so parsed cubes (with precomputed `CIColorCube` data) can
/// live in an `NSCache`.
final class CubeLUTBox {
    let dimension: Int
    let dataObject: Data

    init(lut: CubeLUT) {
        self.dimension = lut.dimension
        self.dataObject = lut.data.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
#endif
