import Foundation
import Testing
@testable import MovieCutCore

/// G-24 P2-G24-2 — the scene-change → measurement bridge, on the
/// deterministic fixture's known boundary (t = 2.0 s @ 30 fps = frame 60)
/// and on the REAL provider's detection over the fixture.
@Suite("Stabilization Segmentation (G-24)")
struct StabilizationSegmentationTests {
    @Test("a detected change time marks the exact frame ± tolerance")
    func toleranceWindow() {
        // 4s @ 30fps = 120 frames; change at 2.0s → frame 60 ± 2.
        let flags = StabilizationSegmentation.sceneCutFlags(
            changeTimes: [2.0], frameCount: 120, frameRate: 30
        )
        #expect(flags.count == 120)
        #expect(flags[58] && flags[60] && flags[62], "±2 window around frame 60")
        #expect(flags[57] == false, "outside the window on the low side")
        #expect(flags[63] == false, "outside the window on the high side")
        #expect(flags.filter(\.self).count == 5, "exactly 5 marked frames")
    }

    @Test("multiple changes mark disjoint windows; clamping at the edges")
    func multipleAndClamped() {
        let flags = StabilizationSegmentation.sceneCutFlags(
            changeTimes: [0.0, 3.9], frameCount: 120, frameRate: 30
        )
        // t=0 → frames 0…2 (clamped at the low edge).
        #expect(flags[0] && flags[2])
        // t=3.9 → frame 117 ± 2 → 115…119 (clamped at the high edge).
        #expect(flags[115] && flags[119])
        #expect(flags[60] == false, "t=2.0 was not a change here")
    }

    @Test("no changes = all clear; degenerate inputs are safe")
    func noChangesAndDegenerate() {
        let clear = StabilizationSegmentation.sceneCutFlags(changeTimes: [], frameCount: 90, frameRate: 30)
        #expect(clear.allSatisfy { $0 == false })
        #expect(StabilizationSegmentation.sceneCutFlags(changeTimes: [1.0], frameCount: 0, frameRate: 30).isEmpty)
        #expect(StabilizationSegmentation.sceneCutFlags(changeTimes: [1.0], frameCount: 10, frameRate: 0).count == 10)
    }

    @Test("frames() fuses displacements with the cut flags")
    func frameFusion() {
        let displacements = Array(repeating: 0.01, count: 120)
        let frames = StabilizationSegmentation.frames(
            displacements: displacements,
            changeTimes: [2.0],
            frameRate: 30
        )
        #expect(frames.count == 120)
        #expect(frames[60].isSceneCut)
        #expect(frames[10].isSceneCut == false)
        #expect(frames[60].displacement == 0.01)
    }

    // The PROVIDER integration test lives in the P2-G24-6 E2E: the
    // provider's AVAssetImageGenerator path produces no frames under
    // `swift test` (the same environment limitation the noise-reduction
    // DSP hit — app context required for offline rendering). The bridge
    // math above is fully unit-tested; the provider itself is exercised
    // where images actually decode.
}
