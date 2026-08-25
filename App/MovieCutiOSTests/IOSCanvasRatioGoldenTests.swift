import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// CANVAS-01: a project whose only change was the canvas used to export at
/// the SOURCE's natural size — the videoComposition (whose renderSize comes
/// from the canvas) was only attached when a clip effect triggered the
/// compositor. The render plan now always attaches it, so the canvas ratio
/// and background are guaranteed on every export/preview.
@MainActor
@Suite("iOS canvas ratio export goldens (CANVAS-01)")
struct IOSCanvasRatioGoldenTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    private func project(canvas: CanvasPreset, background: CanvasBackground? = nil) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        let clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        var project = Project(
            name: "canvas-golden",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: canvas.size, tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        project.canvas = canvas
        project.canvasBackground = background
        return project
    }

    @Test("a canvas-only change to 9:16 exports at 1080×1920")
    func portraitCanvasExportSize() async throws {
        let project = project(canvas: CanvasPreset(aspectRatio: .portrait9x16))
        let url = try await IOSExportEngine().exportProject(project)
        defer { try? FileManager.default.removeItem(at: url) }

        let track = try #require(
            try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        )
        let size = try await track.load(.naturalSize)
        #expect(size.width == 1080 && size.height == 1920,
                "canvas ratio must drive the export size, got \(size)")
    }

    @Test("a canvas-only change to 1:1 exports at 1080×1080")
    func squareCanvasExportSize() async throws {
        let project = project(canvas: CanvasPreset(aspectRatio: .square1x1))
        let url = try await IOSExportEngine().exportProject(project)
        defer { try? FileManager.default.removeItem(at: url) }

        let track = try #require(
            try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first
        )
        let size = try await track.load(.naturalSize)
        #expect(size.width == 1080 && size.height == 1080,
                "square canvas must export square, got \(size)")
    }

    @Test("the plan's renderSize follows the canvas even with no clip effects")
    func planRenderSizeFollowsCanvas() async throws {
        let plan = try await IOSExportEngine().makeRenderPlan(
            for: project(canvas: CanvasPreset(aspectRatio: .portrait4x5))
        )
        let videoComposition = try #require(plan.videoComposition,
                                            "CANVAS-01: the videoComposition must exist even without clip effects")
        #expect(videoComposition.renderSize == CGSize(width: 1080, height: 1350),
                "renderSize must follow the canvas preset, got \(videoComposition.renderSize)")
    }

    @Test("a canvas background fills the letterbox region")
    func canvasBackgroundVisible() async throws {
        // 4:3 red source in a 9:16 canvas → pillarbox top/bottom regions show
        // the background; the center shows the fitted red content.
        let background = CanvasBackground.color(hex: "#0000FF")
        let project = project(
            canvas: CanvasPreset(aspectRatio: .portrait9x16),
            background: background
        )
        let url = try await IOSExportEngine().exportProject(project)
        defer { try? FileManager.default.removeItem(at: url) }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )

        // Downscale grid: 8x6 over 1080x1920 → center rows 2-3 are content.
        let w = 8, h = 12
        guard let context = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Issue.record("grid context failed"); return
        }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = context.data else { return }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            (r: Int(px[(y * w + x) * 4]), g: Int(px[(y * w + x) * 4 + 1]), b: Int(px[(y * w + x) * 4 + 2]))
        }
        // Top edge: background blue-dominant.
        let top = rgb(4, 0)
        #expect(top.b > 120 && top.r < 80, "top letterbox must show the blue canvas background, got \(top)")
        // Center: fitted red content.
        let center = rgb(4, 6)
        #expect(center.r > 150 && center.b < 100, "center must show the fitted red content, got \(center)")
    }
}
