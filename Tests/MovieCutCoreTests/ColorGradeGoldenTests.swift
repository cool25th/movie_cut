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

    private func luma(_ pixel: RGBA) -> Double {
        0.2126 * Double(pixel.r) + 0.7152 * Double(pixel.g) + 0.0722 * Double(pixel.b)
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

    @Test("red HSL saturation minus one desaturates red and leaves blue unchanged")
    func redHSLSaturationMinusOneDesaturatesRedOnly() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(hslBands: [HSLBand(center: .red, saturation: -1)])

        let red = graded(grade, RGBA(255, 0, 0))
        #expect(abs(Int(red.r) - Int(red.g)) <= 3)
        #expect(abs(Int(red.g) - Int(red.b)) <= 3)
        #expect(red.r > 80 && red.r < 220)

        GoldenPixel.expectClose(graded(grade, RGBA(0, 0, 255)), RGBA(0, 0, 255), tolerance: 4, "red-hsl-blue")
    }

    @Test("master curve midtone raise lifts luma while preserving endpoints")
    func masterCurveRaisesMidtonesAndPinsEndpoints() {
        GoldenPixel.assertRendererFunctional()
        let grade = ColorGrade(curves: ColorCurves(master: [
            CurvePoint(x: 0.5, y: 0.65)
        ]))

        let mid = graded(grade, RGBA(128, 128, 128))
        #expect(luma(mid) > luma(RGBA(128, 128, 128)) + 8)
        GoldenPixel.expectClose(graded(grade, RGBA(0, 0, 0)), RGBA(0, 0, 0), "curve-black")
        GoldenPixel.expectClose(graded(grade, RGBA(255, 255, 255)), RGBA(255, 255, 255), "curve-white")
    }

    @Test("red channel curve leaves green and blue unchanged")
    func redCurveOnlyChangesRed() {
        GoldenPixel.assertRendererFunctional()
        let source = RGBA(128, 96, 64)
        let grade = ColorGrade(curves: ColorCurves(red: [
            CurvePoint(x: 0.5, y: 0.8)
        ]))

        let output = graded(grade, source)
        #expect(output.r > source.r + 8)
        #expect(abs(Int(output.g) - Int(source.g)) <= 3)
        #expect(abs(Int(output.b) - Int(source.b)) <= 3)
    }

    @Test("legacy three-way grade JSON decodes without HSL or curves and keeps old golden")
    func legacyThreeWayGradeDecodeKeepsOldRendererOutput() throws {
        GoldenPixel.assertRendererFunctional()
        let json = """
        {
          "lift": { "red": 0.02, "green": 0, "blue": -0.02 },
          "gamma": 1,
          "gain": { "red": 1.1, "green": 1.0, "blue": 0.9 }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ColorGrade.self, from: json)
        #expect(decoded.hslBands == nil)
        #expect(decoded.curves == nil)
        #expect(decoded == ColorGrade(
            lift: .init(red: 0.02, green: 0, blue: -0.02),
            gain: .init(red: 1.1, green: 1.0, blue: 0.9)
        ))
        GoldenPixel.expectClose(graded(decoded, RGBA(128, 128, 128)), RGBA(139, 128, 116), "legacy-warm")
    }
}
