import Foundation
import MovieCutCore
import Testing

@Suite("Curve Evaluator")
struct CurveEvaluatorTests {
    @Test("identity curve produces a diagonal 256 entry LUT")
    func identityCurveProducesDiagonalLUT() {
        let lut = CurveEvaluator.lut(points: CurveEvaluator.identityPoints)
        #expect(lut.count == 256)
        #expect(lut[0] == 0)
        #expect(lut[255] == 1)
        #expect(abs(lut[128] - (128.0 / 255.0)) < 0.0001)
    }

    @Test("unsorted out of range points are sanitized and endpoints are fixed")
    func unsortedOutOfRangePointsAreSanitized() {
        let points = CurveEvaluator.normalizedPoints([
            CurvePoint(x: 0.75, y: 0.8),
            CurvePoint(x: -1, y: -1),
            CurvePoint(x: 0.25, y: 0.3),
            CurvePoint(x: 2, y: 2)
        ])

        #expect(points.first == CurvePoint(x: 0, y: 0))
        #expect(points.last == CurvePoint(x: 1, y: 1))
        #expect(points.map(\.x) == points.map(\.x).sorted())
        #expect(points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    @Test("duplicate x control points resolve deterministically with the last value")
    func duplicateXUsesLastValue() throws {
        let points = CurveEvaluator.normalizedPoints([
            CurvePoint(x: 0.5, y: 0.2),
            CurvePoint(x: 0.5, y: 0.7)
        ])

        let mid = try #require(points.first { abs($0.x - 0.5) < 0.0001 })
        #expect(abs(mid.y - 0.7) < 0.0001)
    }

    @Test("midtone raise lifts the center while preserving endpoints")
    func midtoneRaiseLiftsCenter() {
        let curve = [CurvePoint(x: 0, y: 0), CurvePoint(x: 0.5, y: 0.65), CurvePoint(x: 1, y: 1)]
        #expect(CurveEvaluator.evaluate(points: curve, at: 0) == 0)
        #expect(CurveEvaluator.evaluate(points: curve, at: 1) == 1)
        #expect(CurveEvaluator.evaluate(points: curve, at: 0.5) > 0.64)
        #expect(CurveEvaluator.evaluate(points: curve, at: 0.5) < 0.66)
    }

    @Test("monotone input produces a nondecreasing LUT")
    func monotoneInputProducesNondecreasingLUT() {
        let lut = CurveEvaluator.lut(points: [
            CurvePoint(x: 0, y: 0),
            CurvePoint(x: 0.2, y: 0.15),
            CurvePoint(x: 0.5, y: 0.65),
            CurvePoint(x: 0.8, y: 0.85),
            CurvePoint(x: 1, y: 1)
        ])

        for (previous, next) in zip(lut, lut.dropFirst()) {
            #expect(next + 0.000001 >= previous)
        }
    }

    @Test("arbitrary user points never overshoot the legal output range")
    func arbitraryInputNeverOvershoots() {
        let lut = CurveEvaluator.lut(points: [
            CurvePoint(x: 0.15, y: 0.95),
            CurvePoint(x: 0.35, y: 0.05),
            CurvePoint(x: 0.55, y: 1.5),
            CurvePoint(x: 0.75, y: -0.5)
        ])

        #expect(lut.allSatisfy { value in
            value.isFinite && (0...1).contains(value)
        })
    }
}
