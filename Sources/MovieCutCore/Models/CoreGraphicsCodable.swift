import Foundation

/// Adds JSON coding and equality support for the Core Graphics point type used by timeline models.
extension CGPoint: @retroactive Codable, @retroactive Equatable {
    /// The zero point.
    public static let zero = CGPoint(x: 0, y: 0)

    private enum CodingKeys: String, CodingKey {
        case x
        case y
    }

    public static func == (lhs: CGPoint, rhs: CGPoint) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(Double.self, forKey: .x)
        let y = try container.decode(Double.self, forKey: .y)
        self.init(x: CGFloat(x), y: CGFloat(y))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(x), forKey: .x)
        try container.encode(Double(y), forKey: .y)
    }
}

/// Adds JSON coding and equality support for the Core Graphics size type used by canvas and proxy models.
extension CGSize: @retroactive Codable, @retroactive Equatable {
    /// The zero size.
    public static let zero = CGSize(width: 0, height: 0)

    private enum CodingKeys: String, CodingKey {
        case width
        case height
    }

    public static func == (lhs: CGSize, rhs: CGSize) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let width = try container.decode(Double.self, forKey: .width)
        let height = try container.decode(Double.self, forKey: .height)
        self.init(width: CGFloat(width), height: CGFloat(height))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Double(width), forKey: .width)
        try container.encode(Double(height), forKey: .height)
    }
}
