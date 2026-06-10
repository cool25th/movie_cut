import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

@Suite("Text Overlay Pixel Processor")
struct TextOverlayPixelProcessorTests {
    private let context = CIContext()
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private let imageBounds = CGRect(x: 0, y: 0, width: 160, height: 80)

    @Test("text overlay changes sampled pixels over a solid background")
    func textOverlayChangesSampledPixelsOverSolidBackground() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0.85, green: 0.12, blue: 0.08)
        let textContent = TextClipContent(
            text: "TEXT",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#000000",
            position: CGPoint(x: 80, y: 40)
        )
        let original = samplePixel(from: image, at: CGPoint(x: 80, y: 40))
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)
        let rendered = samplePixel(from: processed, at: CGPoint(x: 80, y: 40))

        #expect(pixelDistance(original, rendered) > 20)
        #expect(rendered.a > 240)
    }

    @Test("background color draws a non-transparent rectangle")
    func backgroundColorDrawsNonTransparentRectangle() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "I",
            fontFamily: "Helvetica Neue",
            fontSize: 36,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#00FF00",
            position: CGPoint(x: 80, y: 40)
        )
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)
        let rendered = samplePixel(from: processed, at: CGPoint(x: 12, y: 40))

        #expect(rendered.a > 180)
        #expect(Int(rendered.g) > Int(rendered.r) + 40)
        #expect(Int(rendered.g) > Int(rendered.b) + 40)
    }

    @Test("fade in animation increases visible overlay over time")
    func fadeInAnimationIncreasesVisibleOverlayOverTime() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "FADE",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#FFFFFF",
            position: CGPoint(x: 80, y: 40),
            animation: TextAnimation(type: .fadeIn, duration: 1)
        )

        let nearStart = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0.1)
        let afterDuration = TextOverlayPixelProcessor.apply(textContent, to: image, at: 1.0)

        let nearStartAlpha = totalAlpha(in: nearStart)
        let afterDurationAlpha = totalAlpha(in: afterDuration)
        #expect(afterDurationAlpha > nearStartAlpha)
        #expect(afterDurationAlpha > 0)
    }

    @Test("typewriter animation emits less overlay before full progress")
    func typewriterAnimationEmitsLessOverlayBeforeFullProgress() {
        guard coreImageRenderingAvailable() else { return }

        let image = solidColorImage(red: 0, green: 0, blue: 0, alpha: 0)
        let textContent = TextClipContent(
            text: "MMMMMMMMMMMM",
            fontFamily: "Helvetica Neue",
            fontSize: 42,
            fontColor: "#FFFFFF",
            alignment: .center,
            position: CGPoint(x: 80, y: 40),
            animation: TextAnimation(type: .typewriter, duration: 1)
        )

        let early = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0.2)
        let late = TextOverlayPixelProcessor.apply(textContent, to: image, at: 1.0)

        let earlyAlpha = totalAlpha(in: early)
        let lateAlpha = totalAlpha(in: late)
        #expect(earlyAlpha > 0)
        #expect(lateAlpha > earlyAlpha)
    }

    @Test("output extent equals input extent")
    func outputExtentEqualsInputExtent() {
        let image = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            .cropped(to: CGRect(x: 12, y: 34, width: 64, height: 48))
        let textContent = TextClipContent(
            text: "Extent",
            fontSize: 24,
            backgroundColor: "#000000"
        )
        let processed = TextOverlayPixelProcessor.apply(textContent, to: image, at: 0)

        #expect(processed.extent == image.extent)
    }

    private func coreImageRenderingAvailable() -> Bool {
        let sentinel = samplePixel(
            from: solidColorImage(red: 0.35, green: 0.35, blue: 0.35),
            at: CGPoint(x: 0, y: 0)
        )
        if sentinel.r == 0 && sentinel.g == 0 && sentinel.b == 0 && sentinel.a == 0 {
            print("Skipping CIContext pixel assertion: renderer returned transparent black for a non-black fixture.")
            return false
        }
        return true
    }

    private func solidColorImage(
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat,
        alpha: CGFloat = 1
    ) -> CIImage {
        let pixel = [
            UInt8((red * 255).rounded()),
            UInt8((green * 255).rounded()),
            UInt8((blue * 255).rounded()),
            UInt8((alpha * 255).rounded())
        ]
        let pixels = Array(repeating: pixel, count: Int(imageBounds.width * imageBounds.height)).flatMap { $0 }
        return CIImage(
            bitmapData: Data(pixels),
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

    private func totalAlpha(in image: CIImage) -> Int {
        var bytes = [UInt8](repeating: 0, count: Int(imageBounds.width * imageBounds.height) * 4)
        bytes.withUnsafeMutableBytes { buffer in
            context.render(
                image.cropped(to: imageBounds),
                toBitmap: buffer.baseAddress!,
                rowBytes: Int(imageBounds.width) * 4,
                bounds: imageBounds,
                format: .RGBA8,
                colorSpace: colorSpace
            )
        }

        return stride(from: 3, to: bytes.count, by: 4).reduce(0) { total, offset in
            total + Int(bytes[offset])
        }
    }

    private func pixelDistance(_ lhs: Pixel, _ rhs: Pixel) -> Int {
        abs(Int(lhs.r) - Int(rhs.r))
            + abs(Int(lhs.g) - Int(rhs.g))
            + abs(Int(lhs.b) - Int(rhs.b))
            + abs(Int(lhs.a) - Int(rhs.a))
    }

    private struct Pixel {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        var a: UInt8
    }
}

@Suite("Text Overlay Static Contract")
struct TextOverlayStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("Mac custom compositor delegates text pixels to the shared processor")
    func macCustomCompositorUsesSharedTextOverlayProcessor() throws {
        let source = try source("App/MovieCutMac/Export/CustomVideoCompositor.swift")

        #expect(source.contains("TextOverlayPixelProcessor.apply"))
    }

    @Test("iOS custom compositor delegates text pixels to the shared processor")
    func iosCustomCompositorUsesSharedTextOverlayProcessor() throws {
        let source = try source("App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift")

        #expect(source.contains("TextOverlayPixelProcessor.apply"))
    }

    @Test("Mac export routes text clips through custom compositor metadata")
    func macExportRoutesTextClipsThroughCustomCompositorMetadata() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("textContent: exportTextContent"))
        #expect(source.contains("textContent: clip.textContent"))
        #expect(source.contains("CustomCompositionClipEffect("))
        #expect(source.contains("|| clip.textContent != nil"))
    }

    @Test("Mac playback keeps Core Animation preview path for text and subtitles")
    func macPlaybackKeepsCoreAnimationPreviewPathForTextAndSubtitles() throws {
        let source = try source("App/MovieCutMac/Playback/PlaybackEngine.swift")

        #expect(source.contains("CATextLayer"))
        #expect(source.contains("AVVideoCompositionCoreAnimationTool"))
        #expect(source.contains("TextAnimationRenderer.applyCoreAnimation"))
    }
}
