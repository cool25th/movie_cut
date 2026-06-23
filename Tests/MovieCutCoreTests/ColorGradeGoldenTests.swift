import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Deterministic golden coverage for the 3-way (lift/gamma/gain) color grade
/// (Phase 2A Pro color). Renders through the software `GoldenPixel.context` and
/// asserts committed pixel values, so the ASC CDL math fails loudly on a
/// regression. Goldens captured via the software renderer.
@Suite("Color Grade Golden")
struct ColorGradeGoldenTests {
    private typealias RGBA = GoldenPixel.RGBA

    private func graded(_ grade: ColorGrade, _ source: RGBA) -> RGBA {
        GoldenPixel.sample(ColorGradePixelProcessor.apply(grade, to: GoldenPixel.solid(source)))
    }

    @Test("identity grade reproduces the source pixel")
    func identity() {
        GoldenPixel.assertRendererFunctional()
        #expect(ColorGrade().isIdentity)
        GoldenPixel.expectClose(graded(ColorGrade(), RGBA(128, 128, 128)), RGBA(128, 128, 128), "identity")
    }

    @Test("lift raises shadows toward the golden value")
    func liftRaisesShadows() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(lift: .init(red: 0.1, green: 0.1, blue: 0.1))
        GoldenPixel.expectClose(graded(grade, RGBA(51, 51, 51)), RGBA(102, 102, 102), "lift+0.1")
    }

    @Test("gain lifts highlights more than shadows")
    func gainAffectsHighlights() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(gain: .init(red: 1.2, green: 1.2, blue: 1.2))
        GoldenPixel.expectClose(graded(grade, RGBA(204, 204, 204)), RGBA(221, 221, 221), "gain1.2-bright")
        // The same gain barely moves a shadow pixel (highlight-weighted).
        GoldenPixel.expectClose(graded(grade, RGBA(51, 51, 51)), RGBA(56, 56, 56), "gain1.2-dark")
    }

    @Test("gamma below 1 brightens midtones to the golden value")
    func gammaBrightensMidtones() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(gamma: 0.7)
        GoldenPixel.expectClose(graded(grade, RGBA(128, 128, 128)), RGBA(158, 158, 158), "gamma0.7")
    }

    @Test("per-channel lift tints shadows (red only)")
    func perChannelLiftTintsShadows() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(lift: .init(red: 0.15, green: 0, blue: 0))
        GoldenPixel.expectClose(graded(grade, RGBA(51, 51, 51)), RGBA(119, 51, 51), "liftR")
    }

    @Test("a warm grade shifts midtones toward the golden warm value")
    func warmGrade() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(
            lift: .init(red: 0.02, green: 0, blue: -0.02),
            gain: .init(red: 1.1, green: 1.0, blue: 0.9)
        )
        GoldenPixel.expectClose(graded(grade, RGBA(128, 128, 128)), RGBA(139, 128, 116), "warm")
    }
}
