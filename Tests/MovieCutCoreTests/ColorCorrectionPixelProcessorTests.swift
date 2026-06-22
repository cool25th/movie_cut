import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Color Correction Pixel Processor")
struct ColorCorrectionPixelProcessorTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let pixelBounds = CGRect(x: 0, y: 0, width: 1, height: 1)

    @Test("identity color correction leaves a sampled pixel unchanged")
    func identityColorCorrectionLeavesPixelUnchanged() {
        let image = solidColor(red: 0.42, green: 0.51, blue: 0.63)
        let identityImage = ColorCorrectionPixelProcessor.apply(ColorCorrection(), to: image)
        #expect(identityImage === image)
        #expect(ColorCorrectionPixelProcessor.isIdentity(ColorCorrection()))

        guard coreImageRenderingAvailable() else { return }

        let original = samplePixel(from: image)
        let processed = samplePixel(from: identityImage)

        #expect(abs(Int(original.r) - Int(processed.r)) <= 1)
        #expect(abs(Int(original.g) - Int(processed.g)) <= 1)
        #expect(abs(Int(original.b) - Int(processed.b)) <= 1)
        #expect(abs(Int(original.a) - Int(processed.a)) <= 1)
    }

    @Test("positive brightness increases sampled RGB values on mid gray")
    func positiveBrightnessIncreasesMidGrayRGB() {
        #expect(ColorCorrectionPixelProcessor.hasSupportedAdjustments(in: ColorCorrection(brightness: 0.2)))
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0.35, green: 0.35, blue: 0.35)
        let original = samplePixel(from: image)
        let processed = samplePixel(
            from: ColorCorrectionPixelProcessor.apply(
                ColorCorrection(brightness: 0.2),
                to: image
            )
        )

        #expect(processed.r > original.r)
        #expect(processed.g > original.g)
        #expect(processed.b > original.b)
    }

    @Test("saturation reduction moves colorful channels closer together")
    func saturationReductionMovesChannelsCloserTogether() {
        #expect(ColorCorrectionPixelProcessor.hasSupportedAdjustments(in: ColorCorrection(saturation: 0)))
        guard coreImageRenderingAvailable() else { return }

        let image = solidColor(red: 0.9, green: 0.18, blue: 0.1)
        let original = samplePixel(from: image)
        let processed = samplePixel(
            from: ColorCorrectionPixelProcessor.apply(
                ColorCorrection(saturation: 0),
                to: image
            )
        )

        #expect(channelSpread(processed) < channelSpread(original))
    }

    @Test("warmth and tint are now applied to rendered pixels")
    func warmthAndTintAreApplied() {
        let warmthTintOnly = ColorCorrection(warmth: 1, tint: -1)
        #expect(!ColorCorrectionPixelProcessor.isIdentity(ColorCorrection(warmth: 1)))
        #expect(ColorCorrectionPixelProcessor.hasSupportedAdjustments(in: warmthTintOnly))

        let neutral = solidColor(red: 0.59, green: 0.59, blue: 0.59)
        // An identity correction is still a no-op (same reference).
        #expect(ColorCorrectionPixelProcessor.apply(ColorCorrection(), to: neutral) === neutral)

        guard coreImageRenderingAvailable() else { return }

        let original = samplePixel(from: neutral)
        let warmed = samplePixel(from: ColorCorrectionPixelProcessor.apply(ColorCorrection(warmth: 1), to: neutral))

        // Positive warmth renders warmer: more red, less blue.
        #expect(warmed.r > original.r)
        #expect(warmed.b < original.b)
    }

    private func coreImageRenderingAvailable() -> Bool {
        let sentinel = samplePixel(from: solidColor(red: 0.35, green: 0.35, blue: 0.35))
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black for a non-black fixture.")
            return false
        }
        return true
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
            size: pixelBounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func samplePixel(from image: CIImage) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: pixelBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: 4,
                bounds: pixelBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }
        return Pixel(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    private func channelSpread(_ pixel: Pixel) -> UInt8 {
        let channels = [pixel.r, pixel.g, pixel.b]
        return channels.max()! - channels.min()!
    }

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}

@Suite("Color Correction Static Contract")
struct ColorCorrectionStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("custom compositor delegates color correction pixels to the shared processor")
    func customCompositorUsesSharedPixelProcessor() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")

        #expect(source.contains("ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)"))
        #expect(!source.contains("private func apply(colorCorrection: ColorCorrection"))
    }

    @Test("playback routes color-corrected clips through the custom compositor")
    func playbackRoutesColorCorrectedClipsThroughCustomCompositor() throws {
        let source = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(source.contains("clipInstruction.colorCorrection != nil"))
        #expect(source.contains("mutableVideoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
        #expect(source.contains("colorCorrection: clipInstruction.colorCorrection"))
    }

    @Test("export routes color-corrected clips through the custom compositor")
    func exportRoutesColorCorrectedClipsThroughCustomCompositor() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("clip.colorCorrection != nil"))
        #expect(source.contains("videoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
        #expect(source.contains("colorCorrection: clip.colorCorrection"))
        #expect(source.contains("|| colorCorrection != nil"))
    }
}
