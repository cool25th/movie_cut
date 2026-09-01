import Foundation
import CoreGraphics
import MovieCutCore
import Testing

/// G-06 Inc 2 — custom cubic-bezier keyframe interpolation (model + evaluation).
///
/// Pins the bezier evaluation used when `InterpolationMode == .custom`:
/// endpoints, overshoot, monotone ease, the nil-curve fallback, and the
/// Codable backward compatibility (legacy projects decode without the
/// `customCurve` key). AC2/AC4 of the G-06 spec are covered here.
@Suite("Keyframe custom bezier (G-06 Inc 2)")
struct KeyframeBezierTests {

    // MARK: - Endpoints (AC: curve passes through 0 and 1)

    @Test("custom curve returns `from` at progress 0 and `to` at progress 1")
    func endpointsExact() {
        let curve = CubicBezierControl(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0)
        let from = 0.0
        let to = 100.0

        let at0 = Keyframe.interpolate(from: from, to: to, progress: 0, mode: .custom, customCurve: curve)
        let at1 = Keyframe.interpolate(from: from, to: to, progress: 1, mode: .custom, customCurve: curve)

        #expect(at0 == from)
        #expect(at1 == to)
    }

    // MARK: - Overshoot (AC2)

    @Test("overshoot curve (0.34,1.56,0.64,1) exceeds the target then settles")
    func overshootExceedsTarget() {
        // CSS overshoot preset. y1 = 1.56 > 1 means the eased progress exceeds
        // 1 partway, so the interpolated value goes past `to` before returning.
        let curve = CubicBezierControl(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0)
        let from = 0.0
        let to = 10.0

        var maxVal = -Double.infinity
        var didExceed = false
        // Sample densely; the overshoot occurs mid-segment.
        for step in 0...200 {
            let p = Double(step) / 200.0
            let v = Keyframe.interpolate(from: from, to: to, progress: p, mode: .custom, customCurve: curve)
            maxVal = max(maxVal, v)
            if v > to { didExceed = true }
        }
        #expect(didExceed, "overshoot curve never exceeded the target")
        #expect(maxVal > to)
        // And it must settle back to `to` by the end (already checked in endpoints).
    }

    // MARK: - Monotone ease (no overshoot)

    @Test("standard ease (0.25,0.1,0.25,1) stays within [from, to]")
    func standardEaseNoOvershoot() {
        let curve = CubicBezierControl(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        let from = 0.0
        let to = 10.0

        for step in 0...100 {
            let p = Double(step) / 100.0
            let v = Keyframe.interpolate(from: from, to: to, progress: p, mode: .custom, customCurve: curve)
            #expect(v >= from - 1e-9)
            #expect(v <= to + 1e-9)
        }
    }

    // MARK: - Nil-curve fallback

    @Test(".custom with nil curve falls back to linear")
    func customNilFallsBackToLinear() {
        let from = 0.0
        let to = 10.0
        let p = 0.4

        let custom = Keyframe.interpolate(from: from, to: to, progress: p, mode: .custom, customCurve: nil)
        let linear = Keyframe.interpolate(from: from, to: to, progress: p, mode: .linear)
        #expect(custom == linear)
    }

    // MARK: - Monotonic in time (x increasing → value increasing for a positive ramp)

    @Test("custom ease is monotonic for a rising ramp")
    func monotonicRising() {
        let curve = CubicBezierControl(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0)
        let from = 0.0
        let to = 10.0

        var prev = -Double.infinity
        for step in 0...100 {
            let p = Double(step) / 100.0
            let v = Keyframe.interpolate(from: from, to: to, progress: p, mode: .custom, customCurve: curve)
            #expect(v >= prev - 1e-9, "value decreased at progress \(p)")
            prev = v
        }
    }

    // MARK: - Codable backward compatibility (AC4)

    @Test("legacy keyframe JSON without customCurve decodes with nil")
    func legacyDecodeWithoutCustomCurve() throws {
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "property": "positionX",
          "time": 1.0,
          "value": 5.0,
          "interpolation": "linear"
        }
        """.data(using: .utf8)!

        let kf = try JSONDecoder().decode(Keyframe.self, from: json)
        #expect(kf.property == .positionX)
        #expect(kf.interpolation == .linear)
        #expect(kf.customCurve == nil)
    }

    @Test("keyframe with custom curve round-trips through Codable")
    func customCurveRoundTrips() throws {
        let kf = Keyframe(
            property: .scaleX,
            time: 2.0,
            value: 1.5,
            interpolation: .custom,
            customCurve: CubicBezierControl(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0)
        )
        let decoded = try JSONDecoder().decode(Keyframe.self, from: JSONEncoder().encode(kf))
        #expect(decoded == kf)
        #expect(decoded.interpolation == .custom)
        #expect(decoded.customCurve?.p1.x == 0.34)
        #expect(decoded.customCurve?.p1.y == 1.56)
    }

    @Test("legacy keyframe without interpolation decodes to linear")
    func legacyDecodeWithoutInterpolation() throws {
        let json = """
        {
          "id": "22222222-2222-4222-8222-222222222222",
          "property": "opacity",
          "time": 0.5,
          "value": 0.8
        }
        """.data(using: .utf8)!

        let kf = try JSONDecoder().decode(Keyframe.self, from: json)
        #expect(kf.interpolation == .linear)
        #expect(kf.customCurve == nil)
    }

    // MARK: - CubicBezierControl convenience init

    @Test("CubicBezierControl convenience init matches CGPoint form")
    func convenienceInitMatches() {
        let a = CubicBezierControl(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0)
        let b = CubicBezierControl(p1: CGPoint(x: 0.25, y: 0.1), p2: CGPoint(x: 0.25, y: 1.0))
        #expect(a == b)
    }
}
