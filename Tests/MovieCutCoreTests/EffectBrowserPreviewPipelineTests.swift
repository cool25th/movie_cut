import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Effect Browser Preview Pipeline (G-28)")
struct EffectBrowserPreviewPipelineTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    @Test("preview applies existing+draft effects before downstream clip correction")
    func previewMatchesClipProcessorOrder() {
        GoldenPixel.assertRendererFunctional()

        let source = solidColor(red: 0.20, green: 0.35, blue: 0.55)
        let effects = [
            Effect(type: .brightness, parameters: ["amount": 0.10]),
            Effect(type: .contrast, parameters: ["amount": 1.25])
        ]
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            effects: [],
            colorCorrection: ColorCorrection(
                brightness: -0.08,
                contrast: 1.10,
                saturation: 0.85,
                warmth: 0.12,
                tint: -0.05
            )
        )

        var expected = VisualEffectPixelProcessor.apply(effects, to: source)
        expected = ColorCorrectionPixelProcessor.apply(clip.colorCorrection!, to: expected)

        let actual = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: effects,
            to: source
        )

        #expect(pixelDistance(sample(actual), sample(expected)) <= 2)
    }

    @Test("background removal callback runs between effects and color correction")
    func backgroundRemovalOrderingIsLocked() {
        GoldenPixel.assertRendererFunctional()

        let source = solidColor(red: 0.35, green: 0.45, blue: 0.65)
        let effects = [Effect(type: .sepia, parameters: ["intensity": 0.7])]
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            isBackgroundRemoved: true,
            colorCorrection: ColorCorrection(brightness: 0.10, contrast: 1.05)
        )
        var callbackCount = 0
        let syntheticRemoval: (CIImage) -> CIImage = { image in
            callbackCount += 1
            return VisualEffectPixelProcessor.apply(
                [Effect(type: .grayscale, parameters: ["intensity": 0.5])],
                to: image
            )
        }

        var expected = VisualEffectPixelProcessor.apply(effects, to: source)
        expected = syntheticRemoval(expected)
        expected = ColorCorrectionPixelProcessor.apply(clip.colorCorrection!, to: expected)
        callbackCount = 0

        let actual = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: effects,
            to: source,
            backgroundRemoval: syntheticRemoval
        )

        #expect(callbackCount == 1)
        #expect(pixelDistance(sample(actual), sample(expected)) <= 2)
    }

    private func solidColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> CIImage {
        let bytes = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8.max
        ]
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: 4,
            size: bounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func sample(_ image: CIImage) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            GoldenPixel.context.render(
                image.cropped(to: bounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return Pixel(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    private func pixelDistance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
        abs(Int(lhs.r) - Int(rhs.r))
            + abs(Int(lhs.g) - Int(rhs.g))
            + abs(Int(lhs.b) - Int(rhs.b))
            + abs(Int(lhs.a) - Int(rhs.a))
    }

    private struct Pixel {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }
}
