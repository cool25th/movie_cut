import Foundation

/// Professional 3-way (lift / gamma / gain) color grade, modeled on the ASC CDL
/// formula `out = (in * slope + offset) ^ power`:
///
/// - ``lift`` is the per-channel **offset** (shadows / black point).
/// - ``gain`` is the per-channel **slope** (highlights / white point).
/// - ``gamma`` is the master **power** (midtones); `power < 1` brightens midtones,
///   `power > 1` darkens them.
///
/// This is the grading model CapCut lacks; it sits alongside the simpler
/// `ColorCorrection` controls.
public struct ColorGrade: Codable, Sendable, Equatable {
    /// A per-channel RGB triplet.
    public struct RGB: Codable, Sendable, Equatable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public static let zero = RGB(red: 0, green: 0, blue: 0)
        public static let one = RGB(red: 1, green: 1, blue: 1)
    }

    /// Shadow offset, per channel. Identity is `0`.
    public var lift: RGB
    /// Midtone power. Identity is `1`.
    public var gamma: Double
    /// Highlight slope, per channel. Identity is `1`.
    public var gain: RGB
    /// Optional HSL secondary correction bands. `nil` and identity-only bands
    /// are both render identity.
    public var hslBands: [HSLBand]?
    /// Optional master/R/G/B tone curves. `nil` and identity curves are both
    /// render identity.
    public var curves: ColorCurves?

    public init(
        lift: RGB = .zero,
        gamma: Double = 1,
        gain: RGB = .one,
        hslBands: [HSLBand]? = nil,
        curves: ColorCurves? = nil
    ) {
        self.lift = RGB(
            red: Self.clamp(lift.red, -1, 1),
            green: Self.clamp(lift.green, -1, 1),
            blue: Self.clamp(lift.blue, -1, 1)
        )
        self.gamma = Self.clamp(gamma, 0.1, 4)
        self.gain = RGB(
            red: Self.clamp(gain.red, 0, 4),
            green: Self.clamp(gain.green, 0, 4),
            blue: Self.clamp(gain.blue, 0, 4)
        )
        self.hslBands = Self.sanitizedHSLBands(hslBands)
        self.curves = curves
    }

    public var isIdentity: Bool {
        lift == .zero
            && gamma == 1
            && gain == .one
            && (hslBands?.allSatisfy(\.isIdentity) ?? true)
            && (curves?.isIdentity ?? true)
    }

    private enum CodingKeys: String, CodingKey {
        case lift, gamma, gain, hslBands, curves
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lift: try container.decodeIfPresent(RGB.self, forKey: .lift) ?? .zero,
            gamma: try container.decodeIfPresent(Double.self, forKey: .gamma) ?? 1,
            gain: try container.decodeIfPresent(RGB.self, forKey: .gain) ?? .one,
            hslBands: try container.decodeIfPresent([HSLBand].self, forKey: .hslBands),
            curves: try container.decodeIfPresent(ColorCurves.self, forKey: .curves)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lift, forKey: .lift)
        try container.encode(gamma, forKey: .gamma)
        try container.encode(gain, forKey: .gain)
        try container.encodeIfPresent(hslBands, forKey: .hslBands)
        try container.encodeIfPresent(curves, forKey: .curves)
    }

    private static func sanitizedHSLBands(_ bands: [HSLBand]?) -> [HSLBand]? {
        guard let bands else { return nil }
        var byCenter: [HSLBandCenter: HSLBand] = [:]
        for band in bands {
            byCenter[band.center] = HSLBand(
                center: band.center,
                hueShift: band.hueShift,
                saturation: band.saturation,
                luminance: band.luminance
            )
        }
        let sanitized = HSLBandCenter.allCases.compactMap { byCenter[$0] }.filter { !$0.isIdentity }
        return sanitized.isEmpty ? nil : sanitized
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        guard value.isFinite else { return minimum }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}

public struct ColorCurves: Codable, Sendable, Equatable, Hashable {
    public static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]
    public static let identity = ColorCurves()

    public var master: [CurvePoint]
    public var red: [CurvePoint]
    public var green: [CurvePoint]
    public var blue: [CurvePoint]

    public init(
        master: [CurvePoint] = Self.identityPoints,
        red: [CurvePoint] = Self.identityPoints,
        green: [CurvePoint] = Self.identityPoints,
        blue: [CurvePoint] = Self.identityPoints
    ) {
        self.master = Self.normalizedPoints(master)
        self.red = Self.normalizedPoints(red)
        self.green = Self.normalizedPoints(green)
        self.blue = Self.normalizedPoints(blue)
    }

    public var isIdentity: Bool {
        master == Self.identityPoints
            && red == Self.identityPoints
            && green == Self.identityPoints
            && blue == Self.identityPoints
    }

    private enum CodingKeys: String, CodingKey {
        case master, red, green, blue
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            master: try container.decodeIfPresent([CurvePoint].self, forKey: .master) ?? Self.identityPoints,
            red: try container.decodeIfPresent([CurvePoint].self, forKey: .red) ?? Self.identityPoints,
            green: try container.decodeIfPresent([CurvePoint].self, forKey: .green) ?? Self.identityPoints,
            blue: try container.decodeIfPresent([CurvePoint].self, forKey: .blue) ?? Self.identityPoints
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(master, forKey: .master)
        try container.encode(red, forKey: .red)
        try container.encode(green, forKey: .green)
        try container.encode(blue, forKey: .blue)
    }

    private static func normalizedPoints(_ points: [CurvePoint]) -> [CurvePoint] {
        var byX: [Double: CurvePoint] = [:]
        for point in points {
            let clamped = CurvePoint(x: point.x, y: point.y)
            byX[clamped.x] = clamped
        }
        byX[0] = CurvePoint(x: 0, y: 0)
        byX[1] = CurvePoint(x: 1, y: 1)
        return byX.values.sorted { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
    }
}

/// A normalized tone-curve control point. Both axes are clamped to 0...1.
public struct CurvePoint: Codable, Sendable, Equatable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = Self.clamp(x)
        self.y = Self.clamp(y)
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}

public enum HSLBandCenter: String, Codable, Sendable, CaseIterable, Equatable, Hashable {
    case red, orange, yellow, green, aqua, blue, purple, magenta

    public var hueDegrees: Double {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .aqua: 180
        case .blue: 240
        case .purple: 270
        case .magenta: 315
        }
    }
}

public struct HSLBand: Codable, Sendable, Equatable, Hashable {
    public var center: HSLBandCenter
    public var hueShift: Double
    public var saturation: Double
    public var luminance: Double

    public init(center: HSLBandCenter, hueShift: Double = 0, saturation: Double = 0, luminance: Double = 0) {
        self.center = center
        self.hueShift = Self.clamp(hueShift, -60, 60)
        self.saturation = Self.clamp(saturation, -1, 1)
        self.luminance = Self.clamp(luminance, -1, 1)
    }

    public var isIdentity: Bool {
        hueShift == 0 && saturation == 0 && luminance == 0
    }

    private static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max(value, minimum), maximum)
    }
}
