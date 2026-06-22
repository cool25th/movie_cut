import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Deterministic golden-pixel coverage for color correction.
///
/// Unlike `ColorCorrectionPixelProcessorTests` — which *skips* its pixel
/// assertions when the GPU renderer is unavailable — these render through the
/// software `GoldenPixel.context` and assert **committed golden values**, so a
/// regression in the real `ColorCorrectionPixelProcessor` output fails here
/// instead of passing silently. Goldens were captured via the software renderer
/// (see `scripts/` evidence) and are stable within a ±2/255 tolerance.
@Suite("Color Correction Golden")
struct ColorCorrectionGoldenTests {
    private typealias RGBA = GoldenPixel.RGBA

    private func corrected(_ correction: ColorCorrection, _ source: RGBA) -> RGBA {
        GoldenPixel.sample(
            ColorCorrectionPixelProcessor.apply(correction, to: GoldenPixel.solid(source))
        )
    }

    @Test("software renderer is functional (no silent skip)")
    func rendererFunctional() {
        GoldenPixel.assertRendererFunctional()
    }

    @Test("identity correction reproduces the source pixel")
    func identityReproducesSource() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(), RGBA(107, 130, 161)),
            RGBA(107, 130, 161),
            "identity"
        )
    }

    @Test("brightness +0.2 brightens mid-gray to the golden value")
    func brightnessGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(brightness: 0.2), RGBA(89, 89, 89)),
            RGBA(149, 149, 149),
            "brightness+0.2"
        )
    }

    @Test("saturation 0 collapses a saturated red to the golden gray")
    func desaturateGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(saturation: 0), RGBA(230, 46, 26)),
            RGBA(120, 120, 120),
            "saturation0"
        )
    }

    @Test("saturation 2 boosts a saturated red to the golden clamp")
    func boostSaturationGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(saturation: 2), RGBA(230, 46, 26)),
            RGBA(255, 0, 0),
            "saturation2"
        )
    }

    @Test("combined brightness/contrast/saturation matches the golden")
    func combinedGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(
                ColorCorrection(brightness: 0.1, contrast: 1.2, saturation: 0.5),
                RGBA(107, 130, 161)
            ),
            RGBA(129, 140, 158),
            "combined"
        )
    }

    @Test("positive warmth renders the golden warm shift (red up, blue down)")
    func warmthGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(warmth: 1), RGBA(150, 150, 150)),
            RGBA(166, 148, 121),
            "warmth+1"
        )
    }

    @Test("positive tint renders the golden magenta shift")
    func tintGolden() {
        GoldenPixel.assertRendererFunctional()
        GoldenPixel.expectClose(
            corrected(ColorCorrection(tint: 1), RGBA(150, 150, 150)),
            RGBA(191, 124, 185),
            "tint+1"
        )
    }
}
