import Foundation

/// Builds deterministic tone-curve lookup tables for RGB/luma curves.
///
/// The evaluator uses monotone cubic Hermite interpolation with Fritsch-Carlson
/// style tangents. For monotone control points this preserves monotonicity; for
/// arbitrary user input every sample is still clamped to 0...1 so the curve never
/// overshoots the legal pixel range. Rendering integration happens in later
/// G-02 increments; this type is pure math for deterministic unit tests.
public enum CurveEvaluator {
    public static let defaultLUTSize = 256
    public static let identityPoints = [CurvePoint(x: 0, y: 0), CurvePoint(x: 1, y: 1)]

    public static func normalizedPoints(_ points: [CurvePoint]) -> [CurvePoint] {
        var byX: [Double: CurvePoint] = [:]
        for point in points {
            let clamped = CurvePoint(x: point.x, y: point.y)
            byX[clamped.x] = clamped
        }

        // Tone curves keep black/white pinned in Inc 1. Endpoint dragging can be
        // introduced deliberately later, but G-02 AC requires (0,0)/(1,1)
        // invariance for the first renderer pass.
        byX[0] = CurvePoint(x: 0, y: 0)
        byX[1] = CurvePoint(x: 1, y: 1)

        return byX.values.sorted { lhs, rhs in
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
    }

    public static func evaluate(points: [CurvePoint], at x: Double) -> Double {
        let points = normalizedPoints(points)
        let x = clamp(x)

        guard points.count > 1 else { return x }
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        let tangents = monotoneTangents(points)
        let upperIndex = points.firstIndex { $0.x >= x } ?? (points.count - 1)
        let lowerIndex = max(0, upperIndex - 1)
        let lower = points[lowerIndex]
        let upper = points[upperIndex]

        guard upper.x > lower.x else { return clamp(lower.y) }

        let h = upper.x - lower.x
        let t = (x - lower.x) / h
        let t2 = t * t
        let t3 = t2 * t

        let h00 = 2 * t3 - 3 * t2 + 1
        let h10 = t3 - 2 * t2 + t
        let h01 = -2 * t3 + 3 * t2
        let h11 = t3 - t2

        let y = h00 * lower.y
            + h10 * h * tangents[lowerIndex]
            + h01 * upper.y
            + h11 * h * tangents[upperIndex]

        return clamp(y)
    }

    public static func lut(points: [CurvePoint], size: Int = defaultLUTSize) -> [Double] {
        let sampleCount = max(size, 2)
        return (0..<sampleCount).map { index in
            if index == 0 { return 0 }
            if index == sampleCount - 1 { return 1 }
            return evaluate(points: points, at: Double(index) / Double(sampleCount - 1))
        }
    }

    private static func monotoneTangents(_ points: [CurvePoint]) -> [Double] {
        let count = points.count
        guard count > 1 else { return [1] }
        if count == 2 {
            let slope = secant(points[0], points[1])
            return [slope, slope]
        }

        let slopes = zip(points, points.dropFirst()).map(secant)
        var tangents = Array(repeating: 0.0, count: count)
        tangents[0] = slopes[0]
        tangents[count - 1] = slopes[count - 2]

        for index in 1..<(count - 1) {
            let previousSlope = slopes[index - 1]
            let nextSlope = slopes[index]
            if previousSlope == 0 || nextSlope == 0 || previousSlope.sign != nextSlope.sign {
                tangents[index] = 0
            } else {
                let previousWidth = points[index].x - points[index - 1].x
                let nextWidth = points[index + 1].x - points[index].x
                let w1 = 2 * nextWidth + previousWidth
                let w2 = nextWidth + 2 * previousWidth
                tangents[index] = (w1 + w2) / (w1 / previousSlope + w2 / nextSlope)
            }
        }

        return tangents
    }

    private static func secant(_ lhs: CurvePoint, _ rhs: CurvePoint) -> Double {
        let width = rhs.x - lhs.x
        guard width > 0 else { return 0 }
        return (rhs.y - lhs.y) / width
    }

    private static func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return Swift.min(Swift.max(value, 0), 1)
    }
}
