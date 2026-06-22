import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Non-skippable golden coverage for the background-removal compositing helper
/// (Phase 0.2 🟡 sweep / Phase 0.1 pattern).
///
/// `BackgroundRemovalTests.removeBackgroundComposites` asserts the same behaviour
/// but *silently skips* its alpha checks when the GPU renderer returns
/// transparent black. This renders through the deterministic software
/// `GoldenPixel.context` and fails loudly instead, so the alpha composite is
/// actually verified in headless runs.
///
/// Scope note: this proves the shared `PersonSegmentationCompositor` mask
/// composite (synthetic mask). The Vision `VNGeneratePersonSegmentationRequest`
/// that produces real masks lives in the app compositors and still needs a
/// real-person fixture / device check — see the roadmap F-08 verdict.
@Suite("Background Removal Golden")
struct BackgroundRemovalGoldenTests {
    private let size = 16

    /// White center square (keep) on black edges (drop).
    private func centerMask() -> CIImage {
        let full = CGRect(x: 0, y: 0, width: size, height: size)
        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: full)
        let inset = CGFloat(size) * 0.25
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
            .cropped(to: CGRect(x: inset, y: inset, width: CGFloat(size) * 0.5, height: CGFloat(size) * 0.5))
        return white.composited(over: black)
    }

    @Test("foreground stays opaque and background becomes transparent")
    func maskCompositeAlpha() {
        GoldenPixel.assertRendererFunctional()

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let red = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: bounds)
        let masked = PersonSegmentationCompositor.removeBackground(from: red, mask: centerMask())

        #expect(masked.extent == bounds)
        let center = GoldenPixel.pixel(masked, atX: size / 2, y: size / 2)
        let corner = GoldenPixel.pixel(masked, atX: 1, y: 1)
        print("BG removal alpha — center=\(center.a) corner=\(corner.a)")

        #expect(center.a > 200, "foreground should stay opaque (alpha \(center.a))")
        #expect(corner.a < 40, "background should become transparent (alpha \(corner.a))")
    }

    @Test("an empty mask leaves the frame unchanged")
    func emptyMaskPassthrough() {
        GoldenPixel.assertRendererFunctional()

        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let red = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.1)).cropped(to: bounds)
        let result = PersonSegmentationCompositor.removeBackground(from: red, mask: CIImage.empty())

        #expect(result.extent == bounds)
        let center = GoldenPixel.pixel(result, atX: size / 2, y: size / 2)
        #expect(center.a > 200, "no mask must not erase the frame (alpha \(center.a))")
    }
}
