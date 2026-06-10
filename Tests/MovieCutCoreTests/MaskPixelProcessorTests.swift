import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Mask Pixel Processor")
struct MaskPixelProcessorTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let imageBounds = CGRect(x: 0, y: 0, width: 8, height: 8)

    @Test("rectangle mask keeps center opaque and outside transparent")
    func rectangleMaskKeepsCenterOpaqueAndOutsideTransparent() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage()
        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 4, y: 4),
            size: CGSize(width: 4, height: 4)
        )
        let processed = MaskPixelProcessor.apply(mask, to: image)

        #expect(samplePixel(from: processed, at: CGPoint(x: 4, y: 4)).a > 245)
        #expect(samplePixel(from: processed, at: CGPoint(x: 0, y: 0)).a < 16)
    }

    @Test("inverted rectangle makes center transparent and outside opaque")
    func invertedRectangleMakesCenterTransparentAndOutsideOpaque() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage()
        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 4, y: 4),
            size: CGSize(width: 4, height: 4),
            inverted: true
        )
        let processed = MaskPixelProcessor.apply(mask, to: image)

        #expect(samplePixel(from: processed, at: CGPoint(x: 4, y: 4)).a < 16)
        #expect(samplePixel(from: processed, at: CGPoint(x: 0, y: 0)).a > 245)
    }

    @Test("ellipse mask keeps center opaque and outside transparent")
    func ellipseMaskKeepsCenterOpaqueAndOutsideTransparent() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage()
        let mask = Mask(
            shape: .ellipse,
            position: CGPoint(x: 4, y: 4),
            size: CGSize(width: 4, height: 4)
        )
        let processed = MaskPixelProcessor.apply(mask, to: image)

        #expect(samplePixel(from: processed, at: CGPoint(x: 4, y: 4)).a > 245)
        #expect(samplePixel(from: processed, at: CGPoint(x: 0, y: 0)).a < 16)
    }

    @Test("brush mask produces an opaque sampled stroke pixel")
    func brushMaskProducesOpaqueSampledStrokePixel() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage()
        let mask = Mask(
            shape: .brush,
            position: CGPoint(x: 4, y: 4),
            size: CGSize(width: 2, height: 2),
            brushPoints: [
                CGPoint(x: 1, y: 1),
                CGPoint(x: 6, y: 1)
            ]
        )
        let processed = MaskPixelProcessor.apply(mask, to: image)

        #expect(samplePixel(from: processed, at: CGPoint(x: 3, y: 1)).a > 180)
    }

    @Test("output extent equals input extent")
    func outputExtentEqualsInputExtent() {
        let image = CIImage(color: CIColor(red: 0.9, green: 0.1, blue: 0.2, alpha: 1))
            .cropped(to: CGRect(x: 12, y: 34, width: 64, height: 48))
        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 44, y: 58),
            size: CGSize(width: 20, height: 20)
        )
        let processed = MaskPixelProcessor.apply(mask, to: image)

        #expect(processed.extent == image.extent)
    }

    private func coreImageRenderingAvailable() -> Bool {
        let sentinel = samplePixel(from: solidColorImage(red: 0.35, green: 0.35, blue: 0.35), at: CGPoint(x: 0, y: 0))
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black for a non-black fixture.")
            return false
        }
        return true
    }

    private func solidColorImage(
        red: CGFloat = 0.9,
        green: CGFloat = 0.1,
        blue: CGFloat = 0.2
    ) -> CIImage {
        let pixel = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8.max
        ]
        let bytes = Array(repeating: pixel, count: Int(imageBounds.width * imageBounds.height)).flatMap { $0 }
        return CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: Int(imageBounds.width) * 4,
            size: imageBounds.size,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private func samplePixel(from image: CIImage, at point: CGPoint) -> Pixel {
        var bytes = [UInt8](repeating: 0, count: 4)
        let bounds = CGRect(x: point.x, y: point.y, width: 1, height: 1)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
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

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}

@Suite("Mask Static Contract")
struct MaskStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("mac custom compositor delegates mask pixels to the shared processor")
    func macCustomCompositorUsesSharedMaskProcessor() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")

        #expect(source.contains("MaskPixelProcessor.apply"))
    }

    @Test("iOS custom compositor delegates mask pixels to the shared processor")
    func iosCustomCompositorUsesSharedMaskProcessor() throws {
        let source = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")

        #expect(source.contains("MaskPixelProcessor.apply"))
    }

    @Test("export routes masked clips through the custom compositor")
    func exportRoutesMaskedClipsThroughCustomCompositor() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("|| clip.mask != nil"))
        #expect(source.contains("mask: clip.mask"))
        #expect(source.contains("videoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
    }

    @Test("playback routes masked clips through the custom compositor")
    func playbackRoutesMaskedClipsThroughCustomCompositor() throws {
        let source = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(source.contains("|| clipInstruction.mask != nil"))
        #expect(source.contains("mask: clipInstruction.mask"))
        #expect(source.contains("mutableVideoComposition.customVideoCompositorClass = CustomVideoCompositor.self"))
    }
}
