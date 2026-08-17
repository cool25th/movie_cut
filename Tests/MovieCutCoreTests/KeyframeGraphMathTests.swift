import Foundation
import MovieCutCore
import Testing

/// G-06 graph math coverage: the drawn curve must be the renderer's curve
/// (both route through `Keyframe.interpolate`), each interpolation mode must
/// be visually distinguishable in the polyline, and the gesture transforms
/// must preserve the editors' sort convention with clamped times.
@Suite("Keyframe Graph Math")
struct KeyframeGraphMathTests {
    private func curve() -> [Keyframe] {
        [
            Keyframe(property: .opacity, time: 0, value: 0),
            Keyframe(property: .opacity, time: 1, value: 1, interpolation: .hold),
            Keyframe(property: .opacity, time: 2, value: 0.5)
        ]
    }

    // MARK: - Evaluation

    @Test("value evaluation matches the renderer's piecewise rule")
    func evaluationMatchesRendererRule() {
        let keyframes = curve()
        #expect(KeyframeGraphMath.value(at: -1, keyframes: keyframes) == 0,
                "before the first keyframe holds the first value")
        #expect(KeyframeGraphMath.value(at: 0.5, keyframes: keyframes) == 0.5,
                "linear midpoint")
        #expect(KeyframeGraphMath.value(at: 1.5, keyframes: keyframes) == 1,
                "hold segment keeps the left value")
        #expect(KeyframeGraphMath.value(at: 2, keyframes: keyframes) == 0.5,
                "at the last keyframe")
        #expect(KeyframeGraphMath.value(at: 3, keyframes: keyframes) == 0.5,
                "after the last keyframe holds the last value")
        #expect(KeyframeGraphMath.value(at: 1, keyframes: []) == nil,
                "no keyframes → nil")
    }

    @Test("eased evaluation matches Keyframe.interpolate at the segment midpoint")
    func easedEvaluationMatchesInterpolate() {
        // easeIn (asymmetric): midpoint eases to 0.25 progress, not 0.5 —
        // easeInOut would be exactly 0.5 at the midpoint by symmetry.
        let keyframes = [
            Keyframe(property: .scaleX, time: 0, value: 0, interpolation: .easeIn),
            Keyframe(property: .scaleX, time: 2, value: 4)
        ]
        let expected = Keyframe.interpolate(from: 0, to: 4, progress: 0.5, mode: .easeIn)
        let evaluated = KeyframeGraphMath.value(at: 1, keyframes: keyframes)
        #expect(evaluated != nil && abs(evaluated! - expected) < 1.0e-12)
        #expect(evaluated! != 2.0, "eased midpoint must differ from the linear midpoint")
    }

    // MARK: - Polyline

    @Test("hold segments draw a right-angle step at the next keyframe")
    func holdPolylineIsAStep() {
        // The segment's mode belongs to its LEFT keyframe.
        let keyframes = [
            Keyframe(property: .opacity, time: 0, value: 0, interpolation: .hold),
            Keyframe(property: .opacity, time: 1, value: 1)
        ]
        let points = KeyframeGraphMath.polyline(for: keyframes)
        // Step: (0,0) → (1,0) [held value] → (1,1) [jump].
        #expect(points.count == 3
                && points[1].time == 1 && points[1].value == 0
                && points[2].time == 1 && points[2].value == 1)
    }

    @Test("linear segments stay two points and eased segments are sampled")
    func polylineShapePerMode() {
        let linear = KeyframeGraphMath.polyline(for: [
            Keyframe(property: .opacity, time: 0, value: 0, interpolation: .linear),
            Keyframe(property: .opacity, time: 1, value: 1)
        ])
        #expect(linear.count == 2)

        let eased = KeyframeGraphMath.polyline(for: [
            Keyframe(property: .opacity, time: 0, value: 0, interpolation: .easeIn),
            Keyframe(property: .opacity, time: 1, value: 1)
        ])
        #expect(eased.count == 25, "24 samples + the starting point")
        #expect(eased.allSatisfy { $0.time >= 0 && $0.time <= 1 })
    }

    // MARK: - Display range

    @Test("display range auto-fits with margin and a minimum span")
    func displayRangeFitsValues() {
        #expect(KeyframeGraphMath.displayRange(for: []) == 0...1,
                "empty falls back to 0…1")
        let wide = KeyframeGraphMath.displayRange(for: [
            Keyframe(property: .rotation, time: 0, value: -90),
            Keyframe(property: .rotation, time: 1, value: 90)
        ])
        #expect(wide.lowerBound < -90 && wide.upperBound > 90,
                "15% margin beyond the value span")
        let flat = KeyframeGraphMath.displayRange(for: [
            Keyframe(property: .opacity, time: 0, value: 0.5),
            Keyframe(property: .opacity, time: 1, value: 0.5)
        ])
        #expect(flat.upperBound - flat.lowerBound >= 0.1,
                "single-value curves widen to the minimum span")
    }

    // MARK: - Gestures

    @Test("hit test picks the nearest keyframe within both tolerances")
    func hitTestNearestWithinTolerances() {
        let keyframes = [
            Keyframe(property: .opacity, time: 0, value: 0),
            Keyframe(property: .opacity, time: 1, value: 1)
        ]
        #expect(KeyframeGraphMath.hitTest(
            time: 0.95, value: 1.05, keyframes: keyframes,
            timeTolerance: 0.2, valueTolerance: 0.2
        )?.time == 1)
        #expect(KeyframeGraphMath.hitTest(
            time: 0.5, value: 5, keyframes: keyframes,
            timeTolerance: 0.2, valueTolerance: 0.2
        ) == nil, "outside the value tolerance")
    }

    @Test("move clamps time and keeps values; add/remove preserve sort order")
    func gestureTransformsPreserveInvariants() {
        let base = [
            Keyframe(property: .opacity, time: 1, value: 1),
            Keyframe(property: .opacity, time: 0, value: 0)
        ]
        let moved = KeyframeGraphMath.moved(
            keyframes: base, id: base[0].id, time: -5, value: 2
        )
        let movedTarget = moved.first { $0.id == base[0].id }
        #expect(movedTarget?.time == 0, "negative times clamp to zero")
        #expect(movedTarget?.value == 2)

        let withNew = KeyframeGraphMath.added(
            keyframes: base, property: .volume, time: 0.5, value: 0.25
        )
        #expect(withNew.count == 3)
        #expect(Keyframe.sortedByPropertyThenTime(withNew) == withNew,
                "added array already follows the editors' sort convention")

        let removed = KeyframeGraphMath.removed(keyframes: withNew, id: base[1].id)
        #expect(removed.count == 2 && !removed.contains { $0.id == base[1].id })
    }
}
