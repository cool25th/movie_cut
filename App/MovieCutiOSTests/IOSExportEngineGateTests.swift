import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// First iOS app-hosted unit tests (kiro 9.2 increment 1).
///
/// The headline regression: `needsCustomCompositor` omitted `isBackgroundRemoved`
/// until W5 — a clip whose ONLY effect was background removal silently exported
/// with no removal at all (the custom compositor was never attached). These
/// tests pin the gate so every effect that the compositor can render also
/// forces the compositor ON.
@MainActor
@Suite("iOS export compositor gate")
struct IOSExportEngineGateTests {
    private let engine = IOSExportEngine()

    /// A minimal project with one video track holding the given clips.
    private func project(with clips: [Clip]) -> Project {
        Project(
            name: "gate-test",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(
                canvasSize: CGSize(width: 100, height: 100),
                tracks: [Track(kind: .video, name: "V1", zIndex: 0, clips: clips)]
            )
        )
    }

    private func videoClip() -> Clip {
        Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
    }

    @Test("a plain clip does not require the custom compositor")
    func plainClipDoesNotNeedCompositor() {
        #expect(engine.needsCustomCompositor(for: project(with: [videoClip()])) == false)
    }

    @Test("background removal alone requires the custom compositor (W5 regression)")
    func backgroundRemovalAloneRequiresCompositor() {
        var clip = videoClip()
        clip.isBackgroundRemoved = true
        #expect(engine.needsCustomCompositor(for: project(with: [clip])) == true)
    }

    @Test("chroma key alone requires the custom compositor")
    func chromaKeyAloneRequiresCompositor() {
        var clip = videoClip()
        clip.chromaKey = ChromaKeySettings(keyColor: "#00FF00", tolerance: 0.3, softness: 0.15, spillSuppression: 0.4)
        #expect(engine.needsCustomCompositor(for: project(with: [clip])) == true)
    }

    @Test("every other effect-bearing clip still requires the compositor")
    func effectClipsRequireCompositor() {
        var corrected = videoClip()
        corrected.colorCorrection = ColorCorrection(brightness: 0.1)
        #expect(engine.needsCustomCompositor(for: project(with: [corrected])) == true)

        var masked = videoClip()
        masked.mask = Mask(shape: .rectangle, position: .zero, size: CGSize(width: 10, height: 10))
        #expect(engine.needsCustomCompositor(for: project(with: [masked])) == true)

        var text = videoClip()
        text.textContent = TextClipContent(text: "hello")
        #expect(engine.needsCustomCompositor(for: project(with: [text])) == true)
    }

    @Test("a color-grade-only clip requires the custom compositor")
    func colorGradeAloneRequiresCompositor() {
        // Promoted from IOSColorGradeParityStaticContractTests (source-string
        // check). This closes a real hole: the gate previously asserted every
        // other effect but never colorGrade alone.
        var graded = videoClip()
        graded.colorGrade = ColorGrade(
            lift: ColorGrade.RGB(red: 0.1, green: 0, blue: -0.05),
            gamma: 0.8,
            gain: ColorGrade.RGB(red: 1.2, green: 1.0, blue: 0.8)
        )
        #expect(engine.needsCustomCompositor(for: project(with: [graded])) == true)
    }
}
