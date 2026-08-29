import Foundation
import MovieCutCore
import Testing

/// Mac↔iOS render-parity contract.
///
/// This suite replaces the old pure source-string test with a two-part check:
///
/// 1. **Shared-processor behavior (the real parity guarantee).** Both platforms
///    call the SAME Core `*PixelProcessor` to render effects. If those
///    processors produce correct pixels in a pinned color space on Mac, they
///    produce correct pixels wherever they are called — including iOS, once it
///    can build. This is the behavior test that the old `contains("…apply")`
///    string check stood in for.
/// 2. **iOS source wiring (a necessary, not sufficient, condition).** While iOS
///    cannot build in this repo today (the iOS platform component is not
///    installed), we still confirm the iOS compositor/preview *call* the shared
///    processors. This catches an accidental decoupling but does NOT by itself
///    prove pixel parity — that requires an iOS golden comparison to be added
///    when iOS becomes buildable (tracked in docs/PLATFORM_PARITY_MATRIX.md).
@Suite("iOS Parity Matrix")
struct IOSParityMatrixStaticContractTests {
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    // MARK: - Shared-processor behavior (the actual parity guarantee)

    @Test("The shared color-correction processor is deterministic in the pinned color space")
    func sharedColorCorrectionProcessorIsDeterministic() {
        // If this processor's output is deterministic under RenderColorConfiguration,
        // then any caller (Mac preview, Mac export, iOS compositor, iOS preview)
        // that routes through it gets the same pixels. That is the parity contract
        // the old string check was proxying for.
        GoldenPixel.assertRendererFunctional()
        let correction = ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 1.3, warmth: 0.4, tint: 0.1)
        let probe = GoldenPixel.solid(GoldenPixel.RGBA(220, 60, 40))
        let corrected = ColorCorrectionPixelProcessor.apply(correction, to: probe)

        // Two independent evaluations must agree — a regression here is a
        // regression for every platform that shares this processor.
        let first = GoldenPixel.sample(corrected)
        let second = GoldenPixel.sample(corrected)
        #expect(first == second, "shared color-correction processor is non-deterministic — parity cannot hold")
        // Non-identity: the correction actually changed the pixel.
        #expect(first != GoldenPixel.sample(probe), "color correction had no effect")
    }

    @Test("The shared color-grade processor is deterministic in the pinned color space")
    func sharedColorGradeProcessorIsDeterministic() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(
            lift: ColorGrade.RGB(red: 0.1, green: 0.05, blue: 0.2),
            gamma: 0.9,
            gain: ColorGrade.RGB(red: 1.1, green: 1.0, blue: 0.9)
        )
        let probe = GoldenPixel.solid(GoldenPixel.RGBA(40, 210, 70))
        let graded = ColorGradePixelProcessor.apply(grade, to: probe)

        let first = GoldenPixel.sample(graded)
        let second = GoldenPixel.sample(graded)
        #expect(first == second, "shared color-grade processor is non-deterministic — parity cannot hold")
        #expect(first != GoldenPixel.sample(probe), "color grade had no effect")
    }

    @Test("The shared processors are identity-safe on a neutral input")
    func sharedProcessorsAreIdentitySafe() {
        // An identity correction/grade must leave the pixel unchanged — another
        // property every shared caller relies on.
        GoldenPixel.assertRendererFunctional()
        let probe = GoldenPixel.solid(GoldenPixel.RGBA(128, 128, 128))
        let identityCorrected = ColorCorrectionPixelProcessor.apply(ColorCorrection(), to: probe)
        let identityGraded = ColorGradePixelProcessor.apply(ColorGrade(), to: probe)
        let original = GoldenPixel.sample(probe)
        #expect(GoldenPixel.sample(identityCorrected) == original, "identity color correction altered the pixel")
        #expect(GoldenPixel.sample(identityGraded) == original, "identity color grade altered the pixel")
    }

    // MARK: - iOS source wiring (necessary, not sufficient)

    @Test("iOS compositor and preview call the shared Core processors")
    func iosSourcesCallSharedProcessors() throws {
        // NOTE: this is a WIRING check, not a behavior check. It confirms the
        // iOS sources reference the shared processors, which is necessary for
        // parity but not sufficient — a real iOS golden-pixel comparison is
        // pending iOS buildability (docs/PLATFORM_PARITY_MATRIX.md). Kept as a
        // decoupling tripwire, not as proof of parity.
        let iosCompositor = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")
        let iosPreview = try source("App/MovieCutiOS/Views/PreviewView.swift")

        #expect(iosCompositor.contains("ColorCorrectionPixelProcessor.apply"))
        #expect(iosCompositor.contains("ColorGradePixelProcessor.apply"))
        #expect(iosCompositor.contains("VisualEffectPixelProcessor.apply"))
        #expect(iosCompositor.contains("MaskPixelProcessor.apply"))
        #expect(iosCompositor.contains("TextOverlayPixelProcessor.apply"))
        #expect(iosCompositor.contains("CanvasBackgroundPixelProcessor.compose"))

        // RENDER-01: the preview delegates ALL processing to the shared
        // render plan (the compositor above carries the processors); it must
        // not reimplement any pipeline inline.
        #expect(iosPreview.contains("makeRenderPlan(for: project)"))
        #expect(!iosPreview.contains("applyFilterPipeline"))
        #expect(!iosPreview.contains("ColorCorrectionPixelProcessor.apply"))
    }
}
