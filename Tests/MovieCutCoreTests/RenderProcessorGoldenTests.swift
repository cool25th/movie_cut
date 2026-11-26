import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import MovieCutCore
import Testing

/// Golden pixel coverage for render processors that previously had only
/// source-string "is wired" assertions (req 15.3 / task 8.3).
///
/// Each processor below was exercised only through a StaticContract that
/// `contains(...)`-checked the call site in `App/.../CustomVideoCompositor.swift`.
/// A passing string check proves the call exists, not that the pixels are right.
/// These tests render through the software `CIContext` exposed by
/// `GoldenPixelHarness` and assert against committed golden pixel values
/// (channel tolerance 2, matching `design.md` §2.2). Every test calls
/// `GoldenPixel.assertRendererFunctional()` first so a broken renderer fails
/// loudly instead of being silently skipped — the failure mode that let the
/// drag-and-drop regression slip past a "passing" suite (see
/// `GoldenPixelHarness.swift` header).
///
/// Mapping (string assertion -> golden test) is recorded in
/// `.kiro/specs/capcut-parity-and-bugfix/verification-debt-8.md` §3.
@Suite("Render Processor Golden")
struct RenderProcessorGoldenTests {

    // MARK: - TransitionPixelProcessor

    @Test("cross dissolve at the midpoint blends both sources toward the golden")
    func crossDissolveMidpointBlendsBothSources() {
        GoldenPixel.assertRendererFunctional()

        let outgoing = GoldenPixel.solid(GoldenPixel.RGBA(220, 30, 30))
        let incoming = GoldenPixel.solid(GoldenPixel.RGBA(30, 30, 220))
        let blended = TransitionPixelProcessor.apply(
            type: .crossDissolve,
            from: outgoing,
            to: incoming,
            progress: 0.5
        )

        // CoreImage dissolves in linear light, so the sRGB midpoint is brighter
        // than a naive byte average (125). This golden pins the actual software
        // renderer output; a regression in the dissolve math moves off it.
        GoldenPixel.expectClose(
            GoldenPixel.sample(blended),
            GoldenPixel.RGBA(163, 30, 163, 255),
            tolerance: 2,
            "crossDissolve@0.5"
        )
    }

    @Test("fade through black reaches pure black at the midpoint")
    func fadeThroughBlackReachesBlackAtMidpoint() {
        GoldenPixel.assertRendererFunctional()

        let outgoing = GoldenPixel.solid(GoldenPixel.RGBA(220, 30, 30))
        let incoming = GoldenPixel.solid(GoldenPixel.RGBA(30, 30, 220))
        let faded = TransitionPixelProcessor.apply(
            type: .fadeThroughBlack,
            from: outgoing,
            to: incoming,
            progress: 0.5
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(faded),
            GoldenPixel.RGBA(0, 0, 0, 255),
            tolerance: 2,
            "fadeThroughBlack@0.5"
        )
    }

    // MARK: - VisualEffectPixelProcessor

    @Test("sepia effect maps a saturated source to the golden warm tone")
    func sepiaEffectMapsToGoldenWarmTone() {
        GoldenPixel.assertRendererFunctional()

        let source = GoldenPixel.solid(GoldenPixel.RGBA(180, 90, 40))
        let sepia = VisualEffectPixelProcessor.apply([Effect.sepia], to: source)

        GoldenPixel.expectClose(
            GoldenPixel.sample(sepia),
            GoldenPixel.RGBA(142, 105, 49, 255),
            tolerance: 2,
            "sepia"
        )
    }

    @Test("grayscale effect collapses a saturated source to the golden luma")
    func grayscaleEffectCollapsesToGoldenLuma() {
        GoldenPixel.assertRendererFunctional()

        let source = GoldenPixel.solid(GoldenPixel.RGBA(180, 90, 40))
        let grayscale = VisualEffectPixelProcessor.apply([Effect.grayscale], to: source)

        GoldenPixel.expectClose(
            GoldenPixel.sample(grayscale),
            GoldenPixel.RGBA(115, 115, 115, 255),
            tolerance: 2,
            "grayscale"
        )
    }

    // MARK: - CanvasBackgroundPixelProcessor

    @Test("solid color background fills the canvas with the exact hex value")
    func solidColorBackgroundFillsCanvasWithHexValue() {
        GoldenPixel.assertRendererFunctional()

        // A fully transparent frame over an opaque color fill must reveal the
        // fill exactly — this is the letterbox-band path preview/export share.
        let transparent = GoldenPixel.solid(GoldenPixel.RGBA(0, 0, 0, 0))
        let composed = CanvasBackgroundPixelProcessor.compose(
            frame: transparent,
            over: .color(hex: "3366CC"),
            renderSize: CGSize(width: 1, height: 1)
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(composed),
            GoldenPixel.RGBA(51, 102, 204, 255),
            tolerance: 2,
            "canvas.color(3366CC)"
        )
    }

    // MARK: - MaskPixelProcessor

    @Test("rectangle mask keeps the covered pixel opaque at the golden source")
    func rectangleMaskKeepsCoveredPixelOpaque() {
        GoldenPixel.assertRendererFunctional()

        let source = GoldenPixel.solid(GoldenPixel.RGBA(200, 100, 50))
        let masked = MaskPixelProcessor.apply(
            Mask(shape: .rectangle, position: CGPoint(x: 0.5, y: 0.5), size: CGSize(width: 1, height: 1)),
            to: source
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(masked),
            GoldenPixel.RGBA(200, 100, 50, 255),
            tolerance: 2,
            "mask.rectangle keep"
        )
    }

    @Test("inverted rectangle mask makes the covered pixel fully transparent")
    func invertedRectangleMaskMakesCoveredPixelTransparent() {
        GoldenPixel.assertRendererFunctional()

        let source = GoldenPixel.solid(GoldenPixel.RGBA(200, 100, 50))
        let masked = MaskPixelProcessor.apply(
            Mask(
                shape: .rectangle,
                position: CGPoint(x: 0.5, y: 0.5),
                size: CGSize(width: 1, height: 1),
                inverted: true
            ),
            to: source
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(masked),
            GoldenPixel.RGBA(0, 0, 0, 0),
            tolerance: 2,
            "mask.rectangle inverted"
        )
    }

    // MARK: - ChromaKeyPixelProcessor

    @Test("chroma key removes a pixel that matches the key color")
    func chromaKeyRemovesMatchingPixel() {
        GoldenPixel.assertRendererFunctional()

        // A pure-green pixel keyed against green must become transparent. This
        // exercises the CIColorKernel; if the kernel fails to load the processor
        // returns the input unchanged and this golden fails loudly.
        let green = GoldenPixel.solid(GoldenPixel.RGBA(0, 230, 0))
        let keyed = ChromaKeyPixelProcessor.apply(
            keyColor: SIMD3<Float>(0, 1, 0),
            threshold: 0.4,
            to: green
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(keyed),
            GoldenPixel.RGBA(0, 0, 0, 0),
            tolerance: 2,
            "chromaKey green on green"
        )
    }

    @Test("chroma key leaves a non-matching pixel at the golden source")
    func chromaKeyLeavesNonMatchingPixelUnchanged() {
        GoldenPixel.assertRendererFunctional()

        let red = GoldenPixel.solid(GoldenPixel.RGBA(220, 30, 30))
        let keyed = ChromaKeyPixelProcessor.apply(
            keyColor: SIMD3<Float>(0, 1, 0),
            threshold: 0.4,
            to: red
        )

        GoldenPixel.expectClose(
            GoldenPixel.sample(keyed),
            GoldenPixel.RGBA(220, 30, 30, 255),
            tolerance: 2,
            "chromaKey green on red"
        )
    }

    // MARK: - SharedVideoCompositorCore & FrameSSIMComparator Parity Gate

    @Test("SharedCanvasGeometry orients cardinal rotations and aspect-fits into canvas")
    func sharedCanvasGeometryOrientsAndFits() {
        GoldenPixel.assertRendererFunctional()
        let portrait = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 64, height: 32))
        let rotated = SharedCanvasGeometry.orientedForDisplay(
            portrait,
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        #expect(abs(rotated.extent.width - 32) < 0.5)
        #expect(abs(rotated.extent.height - 64) < 0.5)

        let fitted = SharedCanvasGeometry.fittedToCanvas(rotated, canvasSize: CGSize(width: 128, height: 128))
        #expect(abs(fitted.extent.width - 64) < 0.5)
        #expect(abs(fitted.extent.height - 128) < 0.5)
        #expect(abs(fitted.extent.origin.x - 32) < 0.5)
        #expect(abs(fitted.extent.origin.y) < 0.5)
    }

    @Test("SharedTextOverlayResolver evaluates text animations consistently for Mac and iOS")
    func sharedTextOverlayResolverEvaluatesAnimation() {
        let animatedText = TextClipContent(
            text: "HelloWorld",
            fontSize: 48,
            animation: TextAnimation(type: .typewriter, duration: 2.0)
        )
        let timeRange = CMTimeRange(
            start: CMTime(seconds: 0, preferredTimescale: 600),
            duration: CMTime(seconds: 4, preferredTimescale: 600)
        )
        let items = SharedTextOverlayResolver.renderItems(
            clipEffects: [],
            instructionTextContent: animatedText,
            instructionTimeRange: timeRange,
            at: CMTime(seconds: 1.0, preferredTimescale: 600),
            renderSize: CGSize(width: 1920, height: 1080)
        )
        #expect(items.count == 1)
        #expect(items[0].textContent.animation == nil)
        #expect(items[0].textContent.text.count < animatedText.text.count)
        #expect(!items[0].textContent.text.isEmpty)
    }

    @Test("SharedStickerOverlayRenderer caches emoji rasters and produces identical SSIM across repeated renders")
    func sharedStickerRendererCachesAndPassesSSIMParity() throws {
        GoldenPixel.assertRendererFunctional()
        let renderer = SharedStickerOverlayRenderer()
        let firstRaster = try #require(renderer.cachedStickerEmojiImage("🔥", fontSize: 48))
        let secondRaster = try #require(renderer.cachedStickerEmojiImage("🔥", fontSize: 48))
        #expect(firstRaster === secondRaster, "Second lookup must hit the bounded NSCache without re-rasterizing")

        let size = CGSize(width: 128, height: 128)
        let bounds = CGRect(origin: .zero, size: size)
        let backdrop = CIImage(color: CIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)).cropped(to: bounds)
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: 2, preferredTimescale: 600)
        )

        let pass1 = renderer.renderOverlay(
            clipEffects: [],
            instructionEmoji: "🔥",
            instructionImageURL: nil,
            instructionTimeRange: timeRange,
            onto: backdrop,
            at: CMTime(seconds: 0.5, preferredTimescale: 600)
        )
        let pass2 = renderer.renderOverlay(
            clipEffects: [],
            instructionEmoji: "🔥",
            instructionImageURL: nil,
            instructionTimeRange: timeRange,
            onto: backdrop,
            at: CMTime(seconds: 0.5, preferredTimescale: 600)
        )

        let parity = try FrameSSIMComparator.compare(pass1, pass2, extent: bounds)
        #expect(parity.ssim >= 0.9999)
        #expect(parity.maxChannelDelta == 0)

        let vsBackdrop = try FrameSSIMComparator.compare(backdrop, pass1, extent: bounds)
        #expect(vsBackdrop.ssim < 0.99, "Sticker overlay must visibly alter the rendered frame")
    }
}
