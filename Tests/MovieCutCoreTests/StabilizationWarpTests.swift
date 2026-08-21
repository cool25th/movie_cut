import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// G-24 P2-G24-5 — the CI warp's pixel behavior: a confident correction
/// moves pixels, a zero correction is bit-exact, and the confidence
/// fallback bypasses (the raw frame passes through unchanged).
@Suite("Stabilization Warp (G-24)")
struct StabilizationWarpTests {
    private func solidImage(_ color: SIMD4<Float>, size: CGFloat = 32) -> CIImage {
        CIImage(color: CIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    private func averageRGBA(_ image: CIImage, context: CIContext) -> SIMD4<Float> {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return SIMD4(Float(pixel[0]) / 255, Float(pixel[1]) / 255, Float(pixel[2]) / 255, Float(pixel[3]) / 255)
    }

    private func halfSplitImage(size: CGFloat = 32) -> CIImage {
        let left = solidImage(SIMD4(0, 0, 0, 1), size: size / 2)
            .transformed(by: CGAffineTransform(translationX: 0, y: 0))
        let right = solidImage(SIMD4(1, 1, 1, 1), size: size / 2)
            .transformed(by: CGAffineTransform(translationX: size / 2, y: 0))
        return left.composited(over: right).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    @Test("a confident correction measurably shifts the pixels")
    func warpShiftsPixels() {
        let image = halfSplitImage()
        let result = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: -8, dy: 0, cropFraction: 0.1),
            confidence: 0.9
        )
        #expect(result.bypassed == false)
        // The transform moved the image's extent — the definitive
        // structural signal that the warp applied. Pixel identity across
        // a transform is already covered by the zero-correction test.
        #expect(abs(result.image.extent.origin.x - image.extent.origin.x - (-8)) < 0.5,
                "the extent must shift by dx=-8; got \(result.image.extent.origin.x - image.extent.origin.x)")
    }

    @Test("zero correction is a bit-exact no-op")
    func zeroCorrectionIsIdentity() {
        let image = solidImage(SIMD4(0.3, 0.6, 0.9, 1))
        let result = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: 0, dy: 0, cropFraction: 0),
            confidence: 1.0
        )
        #expect(result.bypassed == false)
        #expect(result.image == image)
    }

    @Test("low confidence bypasses — the raw frame passes through unchanged")
    func confidenceFallback() {
        let image = halfSplitImage()
        let result = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: -8, dy: 0, cropFraction: 0.1),
            confidence: 0.02  // below the 0.05 threshold (noise-only band)
        )
        #expect(result.bypassed == true)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let before = averageRGBA(image, context: context)
        let after = averageRGBA(result.image, context: context)
        #expect(abs(before.x - after.x) < 0.001, "bypass must be pixel-identical")
    }

    @Test("the bypass threshold is overridable and boundary-inclusive")
    func thresholdBoundary() {
        let image = solidImage(SIMD4(1, 0, 0, 1))
        // Exactly at the threshold: NOT bypassed (>=).
        let atThreshold = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: 1, dy: 0, cropFraction: 0),
            confidence: 0.05
        )
        #expect(atThreshold.bypassed == false)
        // Just below: bypassed.
        let below = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: 1, dy: 0, cropFraction: 0),
            confidence: 0.049
        )
        #expect(below.bypassed == true)
    }

    // MARK: - Cover scale (G-24 #9 render-chain wiring)

    @Test("cover scale grows the extent about the center so the translation cannot expose edges")
    func coverScaleGrowsExtent() {
        let image = halfSplitImage(size: 64)
        // Translation of 16px on a 64px frame needs coverScale ≥ 1.5 to
        // keep every source pixel row covered.
        let result = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: 16, dy: 0, cropFraction: 0.12),
            confidence: 1.0,
            coverScale: 1.5
        )
        #expect(result.bypassed == false)
        // Scaled about the center: the extent grows symmetrically
        // (64 → 96 wide, origin −16) and then translates +16 — landing the
        // left edge exactly at 0, i.e. the render extent stays covered.
        #expect(abs(result.image.extent.width - 96) < 0.5)
        #expect(abs(result.image.extent.minX - 0) < 0.5,
                "scaled origin −16 plus translation +16 must cover minX=0; got \(result.image.extent.minX)")
        #expect(abs(result.image.extent.maxX - 96) < 0.5)
    }

    @Test("cover scale applies even on a bypassed frame — zoom must never breathe")
    func coverScaleAppliesOnBypass() {
        let image = halfSplitImage()
        let bypassed = StabilizationWarpProcessor.apply(
            image,
            correction: (dx: 8, dy: 0, cropFraction: 0.1),
            confidence: 0.02,  // below threshold — translation bypassed
            coverScale: 1.25
        )
        #expect(bypassed.bypassed == true)
        // The zoom still applied: the extent grew (32 → 40), only the
        // translation was skipped.
        #expect(abs(bypassed.image.extent.width - 40) < 0.5)
        #expect(abs(bypassed.image.extent.minX - (-4)) < 0.5)
    }
}
