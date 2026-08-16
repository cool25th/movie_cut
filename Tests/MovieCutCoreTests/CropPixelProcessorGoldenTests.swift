import CoreGraphics
import CoreImage
import Foundation
import MovieCutCore
import Testing

/// Golden + math coverage for the dedicated crop feature (G-23).
///
/// The pixel goldens pin the two behaviors users would immediately notice if
/// they regressed: the top-leading → bottom-left coordinate flip (a wrong
/// flip crops the mirror-image region), and the aspect-fill-to-canvas scale
/// (a wrong scale letterboxes or distorts instead of covering the frame).
@Suite("Crop Pixel Processor Golden")
struct CropPixelProcessorGoldenTests {
    private typealias RGBA = GoldenPixel.RGBA

    private let red = RGBA(255, 0, 0)
    private let green = RGBA(0, 255, 0)
    private let blue = RGBA(0, 0, 255)
    private let yellow = RGBA(255, 255, 0)

    /// A 2×2 image with four distinct solid quadrants. CoreImage's extent uses
    /// a bottom-left origin, so the translations below place each color in the
    /// quadrant its name says in TOP-LEFT terms (what a user sees).
    private func quadrantImage() -> CIImage {
        let topLeft = GoldenPixel.solid(red).transformed(by: CGAffineTransform(translationX: 0, y: 1))
        let topRight = GoldenPixel.solid(green).transformed(by: CGAffineTransform(translationX: 1, y: 1))
        let bottomLeft = GoldenPixel.solid(blue).transformed(by: CGAffineTransform(translationX: 0, y: 0))
        let bottomRight = GoldenPixel.solid(yellow).transformed(by: CGAffineTransform(translationX: 1, y: 0))

        let canvas = topLeft
            .composited(over: topRight)
            .composited(over: bottomLeft)
            .composited(over: bottomRight)
        return canvas.cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    @Test("top-leading crop selects the visually top-left quadrant (flip pinned)")
    func topLeftCropPicksRed() {
        GoldenPixel.assertRendererFunctional()
        // NormalizedRect counts y from the top: (0, 0, 0.5, 0.5) is the
        // visually top-left (red) quadrant. A wrong flip yields blue.
        let crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5).unsafelyUnwrapped
        let output = CropPixelProcessor.apply(crop, to: quadrantImage(), renderSize: CGSize(width: 1, height: 1))
        GoldenPixel.expectClose(GoldenPixel.sample(output), red, tolerance: 3, "top-left crop")
    }

    @Test("bottom-trailing crop selects the visually bottom-right quadrant")
    func bottomRightCropPicksYellow() {
        GoldenPixel.assertRendererFunctional()
        let crop = NormalizedRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5).unsafelyUnwrapped
        let output = CropPixelProcessor.apply(crop, to: quadrantImage(), renderSize: CGSize(width: 1, height: 1))
        GoldenPixel.expectClose(GoldenPixel.sample(output), yellow, tolerance: 3, "bottom-right crop")
    }

    @Test("cropped region fills the canvas: taller-than-canvas region centers vertically")
    func cropFillsAndCenters() {
        GoldenPixel.assertRendererFunctional()
        // Left half of the image (normalized x 0…0.5, full height): a 1×2
        // region with red on top, blue beneath. Filling a square 2×2 canvas
        // scales it 2×4 and centers, so the output's top row is red and the
        // bottom row is blue across BOTH columns.
        let crop = NormalizedRect(x: 0, y: 0, width: 0.5, height: 1).unsafelyUnwrapped
        let output = CropPixelProcessor.apply(crop, to: quadrantImage(), renderSize: CGSize(width: 2, height: 2))

        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 0, y: 1), red, tolerance: 3, "fill top-left")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 1, y: 1), red, tolerance: 3, "fill top-right")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 0, y: 0), blue, tolerance: 3, "fill bottom-left")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 1, y: 0), blue, tolerance: 3, "fill bottom-right")
    }

    @Test("full-frame crop is a pixel no-op")
    func fullFrameCropIsIdentity() {
        GoldenPixel.assertRendererFunctional()
        let full = NormalizedRect(x: 0, y: 0, width: 1, height: 1).unsafelyUnwrapped
        #expect(CropPixelProcessor.isFullFrame(full))

        let image = quadrantImage()
        let output = CropPixelProcessor.apply(full, to: image, renderSize: CGSize(width: 2, height: 2))
        // The untouched-image gate must reproduce each quadrant exactly.
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 0, y: 1), red, tolerance: 0, "identity top-left")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 1, y: 1), green, tolerance: 0, "identity top-right")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 0, y: 0), blue, tolerance: 0, "identity bottom-left")
        GoldenPixel.expectClose(GoldenPixel.pixel(output, atX: 1, y: 0), yellow, tolerance: 0, "identity bottom-right")
    }

    // MARK: - Preset math

    @Test("centeredCropRect: width-limited when the source is wider than the target ratio")
    func widthLimitedCropRect() {
        // 16:9 source cropped to 9:16: full height, narrowed width.
        let rect = CropPixelProcessor.centeredCropRect(sourceAspect: 16.0 / 9.0, targetAspect: 9.0 / 16.0)
        #expect(rect != nil)
        let unwrapped = rect.unsafelyUnwrapped
        #expect(abs(unwrapped.height - 1) < 1.0e-9)
        #expect(abs(unwrapped.width - (9.0 / 16.0) / (16.0 / 9.0)) < 1.0e-9)
        #expect(abs(unwrapped.x - (1 - unwrapped.width) / 2) < 1.0e-9)
        #expect(abs(unwrapped.y) < 1.0e-9)

        // The selected region's PIXEL aspect must equal the target ratio.
        let pixelAspect = (unwrapped.width * (16.0 / 9.0)) / unwrapped.height
        #expect(abs(pixelAspect - 9.0 / 16.0) < 1.0e-9)
    }

    @Test("centeredCropRect: height-limited when the target ratio is wider")
    func heightLimitedCropRect() {
        // 9:16 source cropped to 16:9: full width, narrowed height.
        let rect = CropPixelProcessor.centeredCropRect(sourceAspect: 9.0 / 16.0, targetAspect: 16.0 / 9.0)
        #expect(rect != nil)
        let unwrapped = rect.unsafelyUnwrapped
        #expect(abs(unwrapped.width - 1) < 1.0e-9)
        #expect(abs(unwrapped.height - (9.0 / 16.0) / (16.0 / 9.0)) < 1.0e-9)
    }

    @Test("centeredCropRect: same ratio returns the full frame; invalid aspects return nil")
    func cropRectEdgeCases() {
        let same = CropPixelProcessor.centeredCropRect(sourceAspect: 16.0 / 9.0, targetAspect: 16.0 / 9.0)
        #expect(CropPixelProcessor.isFullFrame(same.unsafelyUnwrapped))

        let square = CropPixelProcessor.centeredCropRect(sourceAspect: 1, targetAspect: 1)
        #expect(CropPixelProcessor.isFullFrame(square.unsafelyUnwrapped))

        #expect(CropPixelProcessor.centeredCropRect(sourceAspect: 0, targetAspect: 1) == nil)
        #expect(CropPixelProcessor.centeredCropRect(sourceAspect: 1, targetAspect: -1) == nil)
        #expect(CropPixelProcessor.centeredCropRect(sourceAspect: .nan, targetAspect: 1) == nil)
    }
}

/// Model + command coverage: the crop rect persists, clears, and decodes from
/// legacy JSON without the key (G-23).
@Suite("Clip Crop Property")
struct ClipCropPropertyTests {
    private func makeProject(clip: Clip) -> Project {
        let track = Track(kind: .video, name: "Video Track", clips: [clip])
        return Project(name: "Crop Test", timeline: Timeline(tracks: [track]))
    }

    private func makeClip() -> Clip {
        Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
    }

    @Test("SetClipPropertyCommand(.cropRect) sets, clears, and inverts")
    func cropPropertyCommandRoundTrip() throws {
        let clip = makeClip()
        var project = makeProject(clip: clip)
        let crop = NormalizedRect(x: 0.1, y: 0.2, width: 0.5, height: 0.6).unsafelyUnwrapped

        try SetClipPropertyCommand(clipId: clip.id, property: .cropRect(crop)).apply(to: &project)
        #expect(project.timeline.tracks[0].clips[0].cropRect == crop)

        try SetClipPropertyCommand(clipId: clip.id, property: .cropRect(nil)).apply(to: &project)
        #expect(project.timeline.tracks[0].clips[0].cropRect == nil)
    }

    @Test("cropRect encodes only when set and decodes from legacy JSON as nil")
    func cropRectCodability() throws {
        // A never-cropped clip must stay byte-identical to pre-feature JSON:
        // no cropRect key is written.
        let plainJSON = String(data: try JSONEncoder().encode(makeClip()), encoding: .utf8).unsafelyUnwrapped
        #expect(!plainJSON.contains("cropRect"))

        // A legacy payload without the key decodes to nil.
        let legacyCropless = try JSONDecoder().decode(Clip.self, from: Data(plainJSON.utf8))
        #expect(legacyCropless.cropRect == nil)

        // Round-trip preserves the rect.
        var cropped = makeClip()
        cropped.cropRect = NormalizedRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        let data = try JSONEncoder().encode(cropped)
        let decoded = try JSONDecoder().decode(Clip.self, from: data)
        #expect(decoded.cropRect == cropped.cropRect)
    }
}
