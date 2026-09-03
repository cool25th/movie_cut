import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Clip properties that can be animated with keyframes.
public enum AnimatableProperty: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case positionX
    case positionY
    case scaleX
    case scaleY
    case rotation
    case opacity
    case volume

    /// User-visible display name, shared by the Mac and iOS keyframe editors.
    public var displayName: String {
        switch self {
        case .positionX:
            return "Position X"
        case .positionY:
            return "Position Y"
        case .scaleX:
            return "Scale X"
        case .scaleY:
            return "Scale Y"
        case .rotation:
            return "Rotation"
        case .opacity:
            return "Opacity"
        case .volume:
            return "Volume"
        }
    }
}

/// Interpolation modes used between adjacent keyframes.
public enum InterpolationMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case hold

    /// A user-authored cubic-bezier curve (CSS cubic-bezier convention).
    /// The curve's two control points are read from the keyframe's
    /// `customCurve`; if that is nil the mode falls back to linear.
    case custom

    /// User-visible display name, shared by the Mac and iOS keyframe editors.
    public var displayName: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In Out"
        case .hold:
            return "Hold"
        case .custom:
            return "Custom"
        }
    }
}

/// Two cubic-bezier control points (P1, P2) in the CSS cubic-bezier
/// convention, where P0 = (0,0) and P3 = (1,1). `x` is the normalized time
/// progress through the segment and `y` is the normalized value progress.
///
/// `x` should be in [0,1] for a well-formed curve (monotonic in time); `y`
/// may exceed [0,1] to produce overshoot — e.g. `(0.34, 1.56, 0.64, 1)` rises
/// past the target and settles back. Properties clamped to a range at the
/// render layer (opacity, volume) clip the overshoot automatically.
public struct CubicBezierControl: Codable, Sendable, Equatable {
    /// First control point (P1).
    public var p1: CGPoint
    /// Second control point (P2).
    public var p2: CGPoint

    public init(p1: CGPoint, p2: CGPoint) {
        self.p1 = p1
        self.p2 = p2
    }

    /// Convenience initializer matching the CSS `cubic-bezier(x1, y1, x2, y2)`
    /// argument order.
    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.p1 = CGPoint(x: x1, y: y1)
        self.p2 = CGPoint(x: x2, y: y2)
    }
}

/// A value for an animatable clip property at a source-relative time.
public struct Keyframe: Codable, Sendable, Equatable, Identifiable {
    /// The keyframe identifier.
    public var id: UUID

    /// The animated property.
    public var property: AnimatableProperty

    /// Time in seconds within the clip source range.
    public var time: TimeInterval

    /// The property value at `time`.
    public var value: Double

    /// The interpolation mode leaving this keyframe.
    public var interpolation: InterpolationMode

    /// The cubic-bezier control points used when `interpolation == .custom`.
    /// Nil for every other mode (and for legacy/custom keyframes that did not
    /// author a curve — `.custom` then falls back to linear).
    public var customCurve: CubicBezierControl?

    /// Creates a keyframe.
    public init(
        id: UUID = UUID(),
        property: AnimatableProperty,
        time: TimeInterval,
        value: Double,
        interpolation: InterpolationMode = .linear,
        customCurve: CubicBezierControl? = nil
    ) {
        self.id = id
        self.property = property
        self.time = max(0, time)
        self.value = value
        self.interpolation = interpolation
        self.customCurve = customCurve
    }

    private enum CodingKeys: String, CodingKey {
        case id, property, time, value, interpolation, customCurve
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        property = try c.decode(AnimatableProperty.self, forKey: .property)
        time = max(0, try c.decode(TimeInterval.self, forKey: .time))
        value = try c.decode(Double.self, forKey: .value)
        interpolation = try c.decodeIfPresent(InterpolationMode.self, forKey: .interpolation) ?? .linear
        // Legacy projects predate the customCurve key; absence is nil.
        customCurve = try c.decodeIfPresent(CubicBezierControl.self, forKey: .customCurve)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(property, forKey: .property)
        try c.encode(time, forKey: .time)
        try c.encode(value, forKey: .value)
        try c.encode(interpolation, forKey: .interpolation)
        try c.encodeIfPresent(customCurve, forKey: .customCurve)
    }

    /// Interpolates between two values using the selected interpolation mode.
    /// When `mode == .custom`, pass the segment's `customCurve`; nil falls
    /// back to linear so a custom keyframe without a curve is never broken.
    public static func interpolate(
        from: Double,
        to: Double,
        progress: Double,
        mode: InterpolationMode,
        customCurve: CubicBezierControl? = nil
    ) -> Double {
        let clampedProgress = min(max(progress, 0), 1)

        let easedProgress: Double
        switch mode {
        case .linear:
            easedProgress = clampedProgress
        case .easeIn:
            easedProgress = clampedProgress * clampedProgress
        case .easeOut:
            let inverse = 1 - clampedProgress
            easedProgress = 1 - (inverse * inverse)
        case .easeInOut:
            if clampedProgress < 0.5 {
                easedProgress = 2 * clampedProgress * clampedProgress
            } else {
                let inverse = -2 * clampedProgress + 2
                easedProgress = 1 - ((inverse * inverse) / 2)
            }
        case .hold:
            return clampedProgress >= 1 ? to : from
        case .custom:
            // No curve authored → safe linear fallback.
            guard let curve = customCurve else {
                easedProgress = clampedProgress
                break
            }
            easedProgress = cubicBezierY(atX: clampedProgress, curve: curve)
        }

        return from + ((to - from) * easedProgress)
    }

    /// Sorts keyframes by property (rawValue) then time, matching the Mac and iOS editors.
    public static func sortedByPropertyThenTime(_ keyframes: [Keyframe]) -> [Keyframe] {
        keyframes.sorted {
            if $0.property.rawValue == $1.property.rawValue {
                return $0.time < $1.time
            }
            return $0.property.rawValue < $1.property.rawValue
        }
    }

    /// Evaluates the cubic-bezier y for a given x (normalized time progress),
    /// with P0 = (0,0) and P3 = (1,1). Uses Newton-Raphson to solve for the
    /// parameter t at which the curve's x equals `x`, then returns the y at
    /// that t. Falls back to bisection when Newton diverges (non-monotonic x,
    /// e.g. overshoot control points).
    private static func cubicBezierY(atX x: Double, curve: CubicBezierControl) -> Double {
        // Clamp the time axis: x outside [0,1] is clamped (y may still overshoot).
        let targetX = min(max(x, 0), 1)

        let x1 = curve.p1.x
        let y1 = curve.p1.y
        let x2 = curve.p2.x
        let y2 = curve.p2.y

        // B(t) for a single axis with P0=0, P3=1: 3(1-t)^2 t·c1 + 3(1-t) t^2·c2 + t^3
        @inline(__always) func bx(_ t: Double) -> Double {
            let oneMinusT = 1 - t
            return 3 * oneMinusT * oneMinusT * t * x1 + 3 * oneMinusT * t * t * x2 + t * t * t
        }
        @inline(__always) func by(_ t: Double) -> Double {
            let oneMinusT = 1 - t
            return 3 * oneMinusT * oneMinusT * t * y1 + 3 * oneMinusT * t * t * y2 + t * t * t
        }
        // Derivative of the x component for Newton's method.
        @inline(__always) func dbx(_ t: Double) -> Double {
            let oneMinusT = 1 - t
            return 3 * oneMinusT * oneMinusT * x1 + 6 * oneMinusT * t * (x2 - x1) + 3 * t * t * (1 - x2)
        }

        // Newton-Raphson with a bisection fallback. 8 Newton iterations are
        // ample for well-formed curves; bisection guarantees convergence even
        // for non-monotonic-x (overshoot) control points.
        var t = targetX
        for _ in 0..<8 {
            let xAtT = bx(t) - targetX
            if abs(xAtT) < 1e-6 { return by(t) }
            let d = dbx(t)
            if abs(d) < 1e-6 { break }
            let next = t - xAtT / d
            // Keep t in range; if Newton overshoots, fall through to bisection.
            guard (0...1).contains(next) else { break }
            t = next
        }

        // Bisection fallback.
        var lo = 0.0
        var hi = 1.0
        t = targetX
        for _ in 0..<60 {
            let xAtT = bx(t)
            if abs(xAtT - targetX) < 1e-6 { return by(t) }
            if xAtT < targetX { lo = t } else { hi = t }
            t = (lo + hi) * 0.5
        }
        return by(t)
    }
}
