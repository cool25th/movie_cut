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
            to: source,
            canvasSize: bounds.size,
            renderSize: bounds.size
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
            canvasSize: bounds.size,
            renderSize: bounds.size,
            backgroundRemoval: syntheticRemoval
        )

        #expect(callbackCount == 1)
        #expect(pixelDistance(sample(actual), sample(expected)) <= 2)
    }

    @Test("canvas-space masks scale onto the bounded preview surface")
    func maskCoordinatesScaleFromCanvas() {
        let mask = Mask(
            shape: .rectangle,
            position: CGPoint(x: 960, y: 540),
            size: CGSize(width: 960, height: 540),
            brushPoints: [CGPoint(x: 0, y: 0), CGPoint(x: 1920, y: 1080)]
        )

        let scaled = EffectBrowserPreviewPipeline.scaledMask(
            mask,
            from: CGSize(width: 1920, height: 1080),
            to: CGSize(width: 320, height: 180)
        )

        #expect(abs(scaled.position.x - 160) < 0.001)
        #expect(abs(scaled.position.y - 90) < 0.001)
        #expect(abs(scaled.size.width - 160) < 0.001)
        #expect(abs(scaled.size.height - 90) < 0.001)
        #expect(abs((scaled.brushPoints.last?.x ?? 0) - 320) < 0.001)
        #expect(abs((scaled.brushPoints.last?.y ?? 0) - 180) < 0.001)
    }

    @Test("crop output uses the canvas-aspect preview render size")
    func cropUsesCanvasRenderSize() {
        let source = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.6)).cropped(
            to: CGRect(x: 0, y: 0, width: 400, height: 300)
        )
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            cropRect: NormalizedRect(x: 0.25, y: 0, width: 0.5, height: 1)
        )
        let renderSize = CGSize(width: 180, height: 320)

        let output = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: [],
            to: source,
            canvasSize: CGSize(width: 1080, height: 1920),
            renderSize: renderSize
        )

        #expect(output.extent == CGRect(origin: .zero, size: renderSize))
    }

    @Test("stabilization runs before crop using representative local time")
    func stabilizationIsPartOfPreviewPipeline() {
        let source = CIImage(color: CIColor.white).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))
        let plan = StabilizationPlan(
            frameRate: 30,
            corrections: [
                .init(dx: 0.1, dy: 0, cropFraction: 0, confidence: 1)
            ]
        )
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            stabilization: plan
        )

        let output = EffectBrowserPreviewPipeline.apply(
            clip: clip,
            effects: [],
            to: source,
            canvasSize: CGSize(width: 10, height: 10),
            renderSize: CGSize(width: 10, height: 10),
            at: 0
        )

        #expect(output.extent == CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    @Test("atomic append command preserves sequential browser applies")
    func appendCommandPreservesEarlierEffects() async throws {
        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
        let track = Track(kind: .video, clips: [clip])
        let session = EditorSession(project: Project(name: "Browser", timeline: Timeline(tracks: [track])))
        let first = Effect(type: .brightness, parameters: ["amount": 0.2])
        let second = Effect(type: .contrast, parameters: ["amount": 1.4])

        try await session.dispatch(AppendClipEffectCommand(clipId: clip.id, effect: first))
        try await session.dispatch(AppendClipEffectCommand(clipId: clip.id, effect: second))

        let snapshot = await session.snapshot()
        let stored = snapshot.timeline.tracks[0].clips[0].effects
        #expect(stored == [first, second])
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
