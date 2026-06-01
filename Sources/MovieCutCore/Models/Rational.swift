import Foundation

/// A small rational number type used for frame-rate presets and exact timeline math.
public struct Rational: Codable, Sendable, Equatable, Hashable {
    /// The numerator component.
    public var numerator: Int

    /// The non-zero denominator component.
    public var denominator: Int

    /// Creates a rational value.
    public init(numerator: Int, denominator: Int) {
        precondition(denominator != 0, "Rational denominator must not be zero.")
        self.numerator = numerator
        self.denominator = denominator
    }

    /// Returns the rational value as a floating-point number.
    public var doubleValue: Double {
        Double(numerator) / Double(denominator)
    }

    private enum CodingKeys: String, CodingKey {
        case numerator
        case denominator
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let numerator = try container.decode(Int.self, forKey: .numerator)
        let denominator = try container.decode(Int.self, forKey: .denominator)
        guard denominator != 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .denominator,
                in: container,
                debugDescription: "Rational denominator must not be zero."
            )
        }
        self.numerator = numerator
        self.denominator = denominator
    }
}
