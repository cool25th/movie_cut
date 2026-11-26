import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// CA-38: Preview ↔ Export structural similarity (SSIM) contract tests.
@Suite("Frame SSIM Comparator (CA-38)")
struct FrameSSIMComparatorTests {

    @Test("Identical frames produce SSIM = 1.0, infinite PSNR, and 0 channel delta")
    func identicalFramesScoreOne() throws {
        let width = 32
        let height = 32
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                buffer[idx] = UInt8((x * 7) & 0xFF)
                buffer[idx + 1] = UInt8((y * 7) & 0xFF)
                buffer[idx + 2] = UInt8(((x + y) * 4) & 0xFF)
                buffer[idx + 3] = 255
            }
        }

        let metrics = try FrameSSIMComparator.compareRGBA8(buffer, buffer, width: width, height: height)
        #expect(abs(metrics.ssim - 1.0) < 1e-9)
        #expect(metrics.psnrDecibels.isInfinite)
        #expect(metrics.maxChannelDelta == 0)
    }

    @Test("Shared preview and export PixelProcessor chains achieve SSIM >= 0.999 and detect perturbations")
    func sharedProcessorChainParityAndRegressionDetection() throws {
        let extent = CGRect(x: 0, y: 0, width: 32, height: 32)
        let base = CIImage(color: CIColor(red: 0.65, green: 0.35, blue: 0.25, alpha: 1.0)).cropped(to: extent)

        let correction = ColorCorrection(brightness: 0.08, contrast: 1.12, saturation: 1.15, warmth: 0.1, tint: -0.05)
        let grade = ColorGrade(
            lift: ColorGrade.RGB(red: 0.02, green: 0.0, blue: -0.02),
            gamma: 1.05,
            gain: ColorGrade.RGB(red: 1.05, green: 1.0, blue: 0.95)
        )

        // Simulate Preview vs Export executing the shared Core processor pipeline
        let previewFrame = ColorGradePixelProcessor.apply(
            grade,
            to: ColorCorrectionPixelProcessor.apply(correction, to: base)
        )
        let exportFrame = ColorGradePixelProcessor.apply(
            grade,
            to: ColorCorrectionPixelProcessor.apply(correction, to: base)
        )

        let parityMetrics = try FrameSSIMComparator.compare(previewFrame, exportFrame, extent: extent)
        #expect(parityMetrics.ssim >= 0.999)
        #expect(parityMetrics.maxChannelDelta <= 1)

        // Now perturb the grade (simulating a preview/export parameter divergence) and verify SSIM drops
        let driftedCorrection = ColorCorrection(brightness: -0.45, contrast: 0.6, saturation: 0.3, warmth: -0.4, tint: 0.3)
        let driftedFrame = ColorCorrectionPixelProcessor.apply(driftedCorrection, to: base)
        let driftedMetrics = try FrameSSIMComparator.compare(previewFrame, driftedFrame, extent: extent)
        #expect(driftedMetrics.ssim < 0.85)
        #expect(driftedMetrics.maxChannelDelta > 40)
    }
}
