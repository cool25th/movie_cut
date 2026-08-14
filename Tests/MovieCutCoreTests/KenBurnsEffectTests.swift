import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

/// Tests for the Ken Burns pan-and-zoom effect (Task 3).
///
/// These verify the effect model's interpolation semantics — the runtime math
/// that the image-to-video rasterizer (`ImageVideoRenderService`) samples per
/// frame. The draw geometry itself is exercised indirectly through the static
/// contract checks; here we lock the resolution math so a zoom-in stays a
/// zoom-in and a pan lands where intended.
@Suite("Ken Burns Effect")
struct KenBurnsEffectTests {
    @Test("Default zoom-in preset moves from 1.0x to 1.12x with no pan")
    func defaultZoomInPreset() {
        let effect = KenBurnsEffect.defaultZoomIn()
        #expect(effect.startScale == 1.0)
        #expect(effect.endScale == 1.12)
        #expect(effect.startFocus == CGPoint(x: 0.5, y: 0.5))
        #expect(effect.endFocus == CGPoint(x: 0.5, y: 0.5))
    }

    @Test("transform(at:) interpolates scale linearly across progress")
    func scaleInterpolatesLinearly() {
        let effect = KenBurnsEffect(startScale: 1.0, endScale: 2.0)
        let atStart = effect.transform(at: 0)
        let atMid = effect.transform(at: 0.5)
        let atEnd = effect.transform(at: 1)

        #expect(atStart.scale == 1.0)
        #expect(atMid.scale == 1.5)
        #expect(atEnd.scale == 2.0)
    }

    @Test("transform(at:) interpolates focus linearly across progress")
    func focusInterpolatesLinearly() {
        let effect = KenBurnsEffect(
            startScale: 1.0,
            endScale: 1.0,
            startFocus: CGPoint(x: 0.0, y: 0.0),
            endFocus: CGPoint(x: 1.0, y: 1.0)
        )
        let atStart = effect.transform(at: 0)
        let atMid = effect.transform(at: 0.5)
        let atEnd = effect.transform(at: 1)

        #expect(atStart.focus == CGPoint(x: 0.0, y: 0.0))
        #expect(atMid.focus == CGPoint(x: 0.5, y: 0.5))
        #expect(atEnd.focus == CGPoint(x: 1.0, y: 1.0))
    }

    @Test("transform(at:) clamps progress outside 0...1 so motion holds at ends")
    func progressClampsToEndpoints() {
        let effect = KenBurnsEffect(startScale: 1.0, endScale: 2.0)
        // Before the clip and after the clip the motion should hold, not
        // extrapolate — otherwise a reversed or extended clip would overshoot.
        #expect(effect.transform(at: -0.5).scale == 1.0)
        #expect(effect.transform(at: 1.5).scale == 2.0)
    }

    @Test("A pure zoom-in with centered focus never pans")
    func centeredZoomHasNoPan() {
        let effect = KenBurnsEffect.defaultZoomIn()
        for progress in stride(from: 0.0, through: 1.0, by: 0.25) {
            let motion = effect.transform(at: progress)
            #expect(motion.focus == CGPoint(x: 0.5, y: 0.5))
        }
    }

    @Test("KenBurnsEffect is Codable round-trip stable")
    func codableRoundTrip() throws {
        let original = KenBurnsEffect(
            startScale: 1.1,
            endScale: 1.3,
            startFocus: CGPoint(x: 0.2, y: 0.3),
            endFocus: CGPoint(x: 0.8, y: 0.7)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KenBurnsEffect.self, from: data)
        #expect(decoded == original)
    }

    @Test("Clip carries an optional Ken Burns effect through its initializer")
    func clipCarriesEffect() {
        let effect = KenBurnsEffect.defaultZoomIn()
        let clip = Clip(
            assetId: UUID(),
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 0, duration: 3),
            kenBurnsEffect: effect
        )
        #expect(clip.kenBurnsEffect == effect)

        // Clips default to no Ken Burns effect when none is specified.
        let plainClip = Clip(
            assetId: UUID(),
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 0, duration: 3)
        )
        #expect(plainClip.kenBurnsEffect == nil)
    }
}
