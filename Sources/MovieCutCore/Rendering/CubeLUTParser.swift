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
        var data: [Float] = []
        var entryCount = 0

        // Allocation-light parsing: a 65³ LUT carries ~275k data lines, and
        // the previous implementation paid two String heap allocations per
        // line (trimmingCharacters + uppercased). Here trimming walks the
        // substring in place, the uppercase copy is built only for lines
        // that START with a letter (metadata keywords — a handful per file),
        // and floats append straight into the final RGBA buffer.
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = trimHorizontalWhitespace(rawLine)
            guard let first = line.first, first != "#" else { continue }

            if first.isLetter {
                let upper = line.uppercased()
                if upper.hasPrefix("LUT_1D_SIZE") {
                    throw ParseError.unsupported1D
                }
                if upper.hasPrefix("LUT_3D_SIZE") {
                    let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Int($0) }
                    guard let size = parts.last else { throw ParseError.missingSize }
                    guard size >= 2, size <= maximumDimension else { throw ParseError.sizeOutOfRange(size) }
                    dimension = size
                    data.reserveCapacity(size * size * size * 4)
                    continue
                }
                // Skip known non-data keywords.
                if upper.hasPrefix("TITLE") || upper.hasPrefix("DOMAIN_") || upper.hasPrefix("LUT_3D_INPUT_RANGE") {
                    continue
                }
            }

            // Data line: three floats.
            var iterator = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).makeIterator()
            guard let c0 = iterator.next(),
                  let c1 = iterator.next(),
                  let c2 = iterator.next(),
                  let r = Float(c0),
                  let g = Float(c1),
                  let b = Float(c2) else {
                // A non-numeric line before the table (extra metadata) is skipped;
                // once entries exist, a malformed line is an error.
                if entryCount == 0 { continue }
                throw ParseError.malformedEntry(String(line))
            }
            data.append(r.clamped(to: 0...1))
            data.append(g.clamped(to: 0...1))
            data.append(b.clamped(to: 0...1))
            data.append(1.0)
            entryCount += 1
        }

        guard let dimension else { throw ParseError.missingSize }
        let expected = dimension * dimension * dimension
        guard entryCount == expected else {
            throw ParseError.entryCountMismatch(expected: expected, found: entryCount)
        }

        return CubeLUT(dimension: dimension, data: data)
    }

    /// Trims spaces/tabs from both ends of a substring without allocating a
    /// new String.
    private static func trimHorizontalWhitespace(_ slice: Substring) -> Substring {
        var start = slice.startIndex
        var end = slice.endIndex
        while start < end && (slice[start] == " " || slice[start] == "\t") {
            slice.formIndex(after: &start)
        }
        while end > start {
            let previous = slice.index(before: end)
            if slice[previous] == " " || slice[previous] == "\t" {
                end = previous
            } else {
                break
            }
        }
        return slice[start..<end]
    }
}

#if canImport(CoreImage)

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
