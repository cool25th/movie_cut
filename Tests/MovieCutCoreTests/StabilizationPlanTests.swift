import Foundation
import Testing
@testable import MovieCutCore

/// G-24 #9 — the render-side plan: time→correction lookup, the constant
/// cover-translation bound the compositor's zoom derives from, and the
/// Codable round-trip through `Clip.stabilization` (schema v7).
@Suite("Stabilization Plan (G-24 #9)")
struct StabilizationPlanTests {
    private func samplePlan() -> StabilizationPlan {
        StabilizationPlan(frameRate: 30, corrections: [
            .init(dx: 0, dy: 0, cropFraction: 0, confidence: 0.9),
            .init(dx: -0.02, dy: 0.01, cropFraction: 0.02, confidence: 0.8),
            .init(dx: 0.03, dy: -0.04, cropFraction: 0.05, confidence: 0.95)
        ])
    }

    @Test("correction(atLocalTime:) maps time to the rounded frame index")
    func timeLookup() {
        let plan = samplePlan()
        // t=0 → frame 0.
        #expect(plan.correction(atLocalTime: 0)?.dx == 0)
        // Halfway between frames 0 and 1 (1/60s) rounds to frame 1.
        #expect(plan.correction(atLocalTime: 1.0 / 60)?.dx ?? 0 != 0)
        // t = 2/30 → frame 2.
        #expect(plan.correction(atLocalTime: 2.0 / 30)?.cropFraction ?? 0 == 0.05)
        // t = 3/30 → frame 3, out of range → clamps to the LAST correction.
        #expect(plan.correction(atLocalTime: 3.0 / 30)?.cropFraction ?? 0 == 0.05)
        // Negative time clamps to the FIRST correction.
        #expect(plan.correction(atLocalTime: -1)?.dx == 0)
    }

    @Test("empty plan and zero frame rate produce no correction")
    func degeneratePlans() {
        #expect(StabilizationPlan(frameRate: 30, corrections: []).isEmpty)
        #expect(StabilizationPlan(frameRate: 30, corrections: []).correction(atLocalTime: 1) == nil)
        #expect(StabilizationPlan(frameRate: 0, corrections: samplePlan().corrections).correction(atLocalTime: 1) == nil)
    }

    @Test("maxNormalizedTranslation bounds both axes for the constant cover zoom")
    func maxTranslation() {
        let bound = samplePlan().maxNormalizedTranslation
        #expect(abs(bound.x - 0.03) < 1.0e-9)
        #expect(abs(bound.y - 0.04) < 1.0e-9)
        // The compositor's cover scale 1 + 2·max(x, y) then guarantees the
        // translated frame still covers the render extent on both axes.
        let coverScale = 1 + 2 * Swift.max(bound.x, bound.y)
        #expect(coverScale > 1.07 && coverScale < 1.09)
    }

    @Test("plan round-trips through Clip Codable — a nil plan encodes no key and decodes nil")
    func clipCodableRoundTrip() throws {
        var clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        clip.stabilization = samplePlan()

        let data = try JSONEncoder().encode(clip)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.stabilization == samplePlan())

        // An unstabilized clip (the legacy/pre-v7 shape): encodeIfPresent
        // omits the key entirely and decode comes back nil — never-cropped
        // JSON stays byte-identical to its pre-feature form.
        clip.stabilization = nil
        let plainData = try JSONEncoder().encode(clip)
        let plainJSON = String(data: plainData, encoding: .utf8) ?? ""
        #expect(!plainJSON.contains("stabilization"))
        let plainDecoded = try JSONDecoder().decode(Clip.self, from: plainData)
        #expect(plainDecoded.stabilization == nil)
    }
}
