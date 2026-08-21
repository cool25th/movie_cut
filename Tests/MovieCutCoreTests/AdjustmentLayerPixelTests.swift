import CoreImage
import Foundation
import Testing
@testable import MovieCutCore

/// G-03 Inc 2 pixel half — the locked render-order contract measured on
/// pixels: an adjustment's color correction/grade applies AFTER the clip's
/// own chain, affects every visible clip below, and changes NOTHING outside
/// the adjustment's time range (no adjustment = pixel identity).
@Suite("Adjustment Layer Pixels (G-03 Inc 2)")
struct AdjustmentLayerPixelTests {
    private func solidImage(_ color: SIMD4<Float>) -> CIImage {
        CIImage(color: CIColor(red: CGFloat(color.x), green: CGFloat(color.y), blue: CGFloat(color.z), alpha: CGFloat(color.w)))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func averageRGBA(_ image: CIImage, context: CIContext) -> SIMD4<Float> {
        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(image, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return SIMD4(Float(pixel[0]) / 255, Float(pixel[1]) / 255, Float(pixel[2]) / 255, Float(pixel[3]) / 255)
    }

    private func adjustment(contrast: Double? = nil, brightness: Double? = nil, gamma: Double? = nil) -> Clip {
        var clip = Clip(
            assetId: UUID(),
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 1, duration: 2)
        )
        clip.isAdjustmentLayer = true
        if let contrast {
            clip.colorCorrection = ColorCorrection(
                brightness: brightness ?? 0,
                contrast: contrast,
                saturation: 1,
                warmth: 0,
                tint: 0
            )
        }
        if let gamma {
            clip.colorGrade = ColorGrade(gamma: gamma)
        }
        return clip
    }

    @Test("no adjustment chain is pixel identity")
    func identity() {
        let image = solidImage(SIMD4(0.5, 0.5, 0.5, 1))
        let result = AdjustmentLayerChain.applyAdjustments([], to: image)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let input = averageRGBA(image, context: context)
        let output = averageRGBA(result, context: context)
        #expect(abs(input.x - output.x) < 0.01)
        #expect(abs(input.y - output.y) < 0.01)
        #expect(abs(input.z - output.z) < 0.01)
    }

    @Test("an adjustment measurably shifts the pixels under it")
    func appliesToPixels() {
        let image = solidImage(SIMD4(0.5, 0.5, 0.5, 1))
        let boosted = AdjustmentLayerChain.applyAdjustments(
            [adjustment(contrast: 2.0)], to: image
        )
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let before = averageRGBA(image, context: context)
        let after = averageRGBA(boosted, context: context)
        #expect(abs(after.x - before.x) > 0.05, "contrast 2× must shift mid-gray")
    }

    @Test("the chain applies bottom-first: two adjustments stack")
    func stacksBottomFirst() {
        let image = solidImage(SIMD4(0.4, 0.4, 0.4, 1))
        let bottom = adjustment(gamma: 0.5)
        let top = adjustment(contrast: 1.5)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let stacked = AdjustmentLayerChain.applyAdjustments([bottom, top], to: image)
        let onlyBottom = AdjustmentLayerChain.applyAdjustments([bottom], to: image)
        let stackedRGBA = averageRGBA(stacked, context: context)
        let bottomRGBA = averageRGBA(onlyBottom, context: context)
        #expect(abs(stackedRGBA.x - bottomRGBA.x) > 0.01, "the top adjustment must further change the bottom's result")
    }

    @Test("range gating: outside the adjustment's range nothing is active")
    func rangeGating() {
        let adjust = adjustment(contrast: 2.0) // timeline 1..<3
        let tracks = [Track(kind: .video, name: "V", zIndex: 0, clips: [adjust])]
        #expect(AdjustmentLayerChain.activeAdjustments(at: 0.5, in: tracks).isEmpty)
        #expect(AdjustmentLayerChain.activeAdjustments(at: 2.0, in: tracks).count == 1)
        #expect(AdjustmentLayerChain.activeAdjustments(at: 3.0, in: tracks).isEmpty)
    }
}
