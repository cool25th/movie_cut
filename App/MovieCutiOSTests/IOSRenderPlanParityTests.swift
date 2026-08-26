import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// RENDER-01: iOS preview and export must consume the SAME render plan.
/// These tests drive the real `IOSExportEngine.makeRenderPlan` and pin:
///
/// 1. Structural parity — the plan's composition carries the timeline's
///    duration (speed, ramps, freeze all bake in) and attaches the custom
///    compositor exactly when the project needs it.
/// 2. PIXEL parity — a frame generated through the plan's composition +
///    videoComposition (exactly what PreviewView's generator renders) must
///    match the frame decoded from the REAL exported file at the same
///    timestamp. The old preview built its own composition and post-filtered
///    single-clip frames, so this equality never held.
@MainActor
@Suite("iOS preview/export render-plan parity (RENDER-01)")
struct IOSRenderPlanParityTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    private static let blueFixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_blue_320x240_2s_30fps.mp4")

    /// 320×240 storage with a +90° display matrix and left-red/right-blue
    /// content — the ca04_rotated_asym layout. Upright display shows RED on
    /// top and BLUE on bottom (BUG-07 ground truth on Mac, now pinned on iOS).
    private static let rotatedAsymFixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/ca04_rotated_asym_320x240_2s_90deg.mp4")

    /// The render size comes from the PROJECT canvas preset — set a 4:3
    /// custom preset matching the fixture so the frame has no letterbox.
    private static let canvas = CanvasPreset(aspectRatio: .custom, customWidth: 320, customHeight: 240)

    private func gradedProject() -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        var clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        // Force the custom compositor (the path whose preview divergence
        // mattered) with a real color correction.
        clip.colorCorrection = ColorCorrection(brightness: 0.2, contrast: 1.1)
        var project = Project(
            name: "render-plan",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = Self.canvas
        return project
    }

    @Test("the plan's composition carries the timeline duration and compositor")
    func planStructure() async throws {
        let engine = IOSExportEngine()
        let plan = try await engine.makeRenderPlan(for: gradedProject())

        #expect(abs(plan.composition.duration.seconds - 2.0) < 0.05,
                "composition duration must reflect the timeline (speeds/ramps bake in)")
        let videoComposition = try #require(plan.videoComposition,
                                            "a graded clip requires the custom compositor")
        #expect(videoComposition.customVideoCompositorClass == CustomVideoCompositor.self,
                "the plan attaches the same compositor the export uses")
    }

    @Test("2x speed bakes into the preview plan's composition duration")
    func speedBakesIntoPlan() async throws {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        var clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 1)
        )
        clip.playbackRate = 2
        var project = Project(
            name: "speed-plan",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = Self.canvas
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        #expect(abs(plan.composition.duration.seconds - 1.0) < 0.05,
                "the PREVIEW plan must halve the duration exactly like the export")
    }

    @Test("preview-plan frame matches the decoded export frame (pixel parity)")
    func previewFrameMatchesExport() async throws {
        let engine = IOSExportEngine()
        let project = gradedProject()
        let plan = try await engine.makeRenderPlan(for: project)
        let exportURL = try await engine.exportProject(project)
        defer { try? FileManager.default.removeItem(at: exportURL) }

        // The exact generation path PreviewView uses.
        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = plan.videoComposition
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.maximumSize = CGSize(width: 320, height: 240)

        let previewFrame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil),
            "the plan-based generator must produce a composited frame"
        )
        let exportFrame = try #require(
            try AVAssetImageGenerator(asset: AVURLAsset(url: exportURL))
                .copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )

        let preview = Self.meanRGB(of: previewFrame)
        let exported = Self.meanRGB(of: exportFrame)
        // Luma comparison: the same composited pixels feed the encoder, so the
        // remaining delta is decode-side only — now codec-roundtrip residue
        // since the writer tags the range/matrix explicitly (RENDER-02).
        let previewY = 0.299 * preview.r + 0.587 * preview.g + 0.114 * preview.b
        let exportedY = 0.299 * exported.r + 0.587 * exported.g + 0.114 * exported.b
        // RENDER-02 RESOLVED (2026-08-26): the export drives an AVAssetWriter
        // with the planner's output settings — SDR H.264 tagged explicitly
        // Rec.709. The old preset path (AVAssetExportSession, no tag control)
        // drifted ~21/255 because the decoder picked its default YUV
        // matrix/range; the tagged writer collapses that to codec-roundtrip
        // residue (measured 3.09). If the tagging ever regresses, the drift
        // returns to ~21 and fails this tight band immediately.
        let drift = previewY - exportedY
        #expect(abs(drift) < 8,
                "luma drift \(drift) must stay near codec-roundtrip residue (~3, measured 2026-08-26): \(preview) vs \(exported)")
        // And the grade actually applied on BOTH legs (not raw red).
        #expect(preview.r > 180 && exported.r > 180,
                "the brightness lift must show on both legs: \(preview) / \(exported)")
    }

    @Test("multi-track compositing appears in the plan-generated frame")
    func multiTrackCompositesInPlanFrame() async throws {
        // BUG-08: the layers must use DIFFERENT colors (blue base, red top).
        // The 2026-08-26 review caught the old test reusing solid_red on BOTH
        // tracks, which cannot detect the compositor dropping the lower track
        // beneath a `.normal`-blend overlay.
        let baseId = UUID(), topId = UUID()
        let base = MediaAsset(originalURL: Self.blueFixtureURL, kind: .video, duration: 2)
        let top = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        var topClip = Clip(
            assetId: topId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        topClip.opacity = 0.5
        var project = Project(
            name: "multi-track",
            mediaLibrary: MediaLibrary(assets: [baseId: base, topId: top]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [Clip(
                    assetId: baseId, kind: .video,
                    sourceRange: TimeRange(start: 0, duration: 2),
                    timelineRange: TimeRange(start: 0, duration: 2)
                )]),
                Track(kind: .video, name: "V2", zIndex: 1, clips: [topClip])
            ])
        )
        project.canvas = Self.canvas

        let mean = try await Self.meanPlanFrameRGB(of: project, at: 0.5)
        // Half-opacity red over solid blue must show BOTH layers: the red top
        // halves toward the blue beneath and the blue base shows through
        // (both channels land near ~130). With the dropped-layer defect the
        // blue channel collapses toward the canvas background (~20).
        #expect(mean.r > 90, "the half-opacity red top must contribute, got \(mean)")
        #expect(mean.b > 80, "BUG-08: the blue base track must show through the half-opacity top, got \(mean)")
        #expect(mean.g < 70, "neither fixture has meaningful green, got \(mean)")
    }

    @Test("masked overlay reveals the track beneath outside the mask (BUG-08)")
    func maskedOverlayShowsLowerTrack() async throws {
        let baseId = UUID(), topId = UUID()
        let base = MediaAsset(originalURL: Self.blueFixtureURL, kind: .video, duration: 2)
        let top = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        var topClip = Clip(
            assetId: topId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        topClip.mask = Mask(
            shape: .ellipse,
            // MaskPixelProcessor interprets position/size in RENDERED PIXEL
            // coordinates (not normalized) — a 320×240 canvas needs pixel units.
            position: CGPoint(x: 160, y: 120),
            size: CGSize(width: 160, height: 120)
        )
        var project = Project(
            name: "masked-overlay",
            mediaLibrary: MediaLibrary(assets: [baseId: base, topId: top]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [Clip(
                    assetId: baseId, kind: .video,
                    sourceRange: TimeRange(start: 0, duration: 2),
                    timelineRange: TimeRange(start: 0, duration: 2)
                )]),
                Track(kind: .video, name: "V2", zIndex: 1, clips: [topClip])
            ])
        )
        project.canvas = Self.canvas

        let mean = try await Self.meanPlanFrameRGB(of: project, at: 0.5)
        // The centered half-size ellipse covers ~20% of the canvas with red;
        // the remaining ~80% must show the BLUE base. With the dropped-layer
        // defect the outside-mask region falls through to the canvas
        // background and blue collapses (~5).
        #expect(mean.b > 150, "BUG-08: the blue base must dominate outside the mask, got \(mean)")
        #expect(mean.r < 120, "red must appear only inside the ellipse mask, got \(mean)")
    }

    /// Renders one frame through the real render plan (composition +
    /// videoComposition — exactly what PreviewView's generator drives) and
    /// returns its downsampled mean RGB.
    private static func meanPlanFrameRGB(
        of project: Project,
        at seconds: Double
    ) async throws -> (r: Double, g: Double, b: Double) {
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)

        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 320, height: 240)
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        )
        return meanRGB(of: frame)
    }

    /// BUG-IOS-08: a rotated source must render UPRIGHT through the shared
    /// render plan (custom compositor receives storage-oriented frames — the
    /// effect must carry the source preferredTransform) AND the exported file
    /// must decode upright through an autorotating player view.
    @Test("rotated source renders upright in the plan frame and the export (BUG-IOS-08)")
    func rotatedSourceRendersUpright() async throws {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.rotatedAsymFixtureURL, kind: .video, duration: 2)
        let clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        var project = Project(
            name: "rotated",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 240, height: 320), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = CanvasPreset(aspectRatio: .custom, customWidth: 240, customHeight: 320)

        // Plan frame (the preview path): the compositor orients the storage
        // frame before the canvas fit.
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let planGenerator = AVAssetImageGenerator(asset: plan.composition)
        planGenerator.videoComposition = videoComposition
        planGenerator.maximumSize = CGSize(width: 240, height: 320)
        let planFrame = try #require(
            try planGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )
        let planBands = Self.bandMeanRGB(of: planFrame)
        #expect(planBands.top.r > 150 && planBands.top.b < 90,
                "plan frame must show RED on top (upright), got \(planBands)")
        #expect(planBands.bottom.b > 150 && planBands.bottom.r < 90,
                "plan frame must show BLUE on bottom (upright), got \(planBands)")

        // Export leg: decode the real file the way a player would (applying
        // the output's own track transform) — catches double rotation, where
        // pre-oriented pixels plus a carried rotation metadata cancel out.
        let engine = IOSExportEngine()
        let outputURL = try await engine.exportProject(project)
        let outputAsset = AVURLAsset(url: outputURL)
        let decodeGenerator = AVAssetImageGenerator(asset: outputAsset)
        decodeGenerator.appliesPreferredTrackTransform = true
        decodeGenerator.maximumSize = CGSize(width: 240, height: 320)
        let decodedFrame = try #require(
            try decodeGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )
        let exportBands = Self.bandMeanRGB(of: decodedFrame)
        #expect(exportBands.top.r > 150 && exportBands.top.b < 90,
                "exported file must decode upright (RED on top), got \(exportBands)")
        #expect(exportBands.bottom.b > 150 && exportBands.bottom.r < 90,
                "exported file must decode upright (BLUE on bottom), got \(exportBands)")
    }

    /// Mean RGB for the top and bottom bands of a portrait frame (rows
    /// 15–45% and 55–85%), downsampled to 24×32 for stable measurements.
    private static func bandMeanRGB(
        of image: CGImage
    ) -> (top: (r: Double, g: Double, b: Double), bottom: (r: Double, g: Double, b: Double)) {
        let width = 24, height = 32
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

        func mean(rows: Range<Int>) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0
            for row in rows {
                for column in 0..<width {
                    let offset = (row * width + column) * 4
                    r += Double(pixels[offset])
                    g += Double(pixels[offset + 1])
                    b += Double(pixels[offset + 2])
                }
            }
            let count = Double(rows.count * width)
            return (r / count, g / count, b / count)
        }

        return (
            mean(rows: Int(Double(height) * 0.15)..<Int(Double(height) * 0.45)),
            mean(rows: Int(Double(height) * 0.55)..<Int(Double(height) * 0.85))
        )
    }

    private static func meanRGB(of image: CGImage) -> (r: Double, g: Double, b: Double) {
        let width = 32, height = 24
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (0, 0, 0) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return (0, 0, 0) }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(width * height) {
            r += Double(pixels[i * 4])
            g += Double(pixels[i * 4 + 1])
            b += Double(pixels[i * 4 + 2])
        }
        let count = Double(width * height)
        return (r / count, g / count, b / count)
    }
}
