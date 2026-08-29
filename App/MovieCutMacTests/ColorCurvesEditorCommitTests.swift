import MovieCutCore
import Testing
@testable import MovieCutMac

/// G-02 Inc 6: the tone-curve editor's commit contract — an all-identity
/// curve set commits `nil` (ungraded project JSON stays byte-stable; the
/// same normalization the HSL band editor applies), and a real edit
/// round-trips through `ColorCurves` normalization with the (0,0)/(1,1)
/// endpoints pinned by construction.
@Suite("Color curve editor commit mapping (G-02 Inc 6)")
struct ColorCurvesEditorCommitTests {
    @Test("an identity curve set commits nil")
    func identityCommitsNil() {
        #expect(ColorCurvesView.committedValue(ColorCurves.identity) == nil)
        // A channel that was edited and reverted back to identity must also
        // clear the whole grade's curves — the editor owns all four channels.
        #expect(ColorCurvesView.committedValue(ColorCurves()) == nil)
    }

    @Test("a non-identity curve set commits the full four-channel value")
    func editCommitsWholeSet() {
        let edited = ColorCurves(
            master: [CurvePoint(x: 0.25, y: 0.15), CurvePoint(x: 0.75, y: 0.85)],
            red: [CurvePoint(x: 0.5, y: 0.7)]
        )
        let committed = ColorCurvesView.committedValue(edited)
        #expect(committed != nil)
        #expect(committed?.master == edited.master)
        #expect(committed?.red == edited.red)
        #expect(committed?.green == ColorCurves.identityPoints)
        #expect(committed?.blue == ColorCurves.identityPoints)
    }

    @Test("the evaluator consumes the editor's committed points monotonically")
    func committedCurveIsMonotone() {
        // The exact points the harness's curves_only parity scenario
        // applies — the renderer chain must sample them without surprise.
        let points = ColorCurves(
            master: [CurvePoint(x: 0.25, y: 0.15), CurvePoint(x: 0.75, y: 0.85)],
            red: [CurvePoint(x: 0.5, y: 0.7)]
        ).master
        var previous = -1.0
        for index in 0...20 {
            let x = Double(index) / 20
            let y = CurveEvaluator.evaluate(points: points, at: x)
            #expect(y >= 0 && y <= 1)
            #expect(y >= previous - 1.0e-9,
                    "the master S-curve must be non-decreasing; dropped at x=\(x)")
            previous = y
        }
    }
}
