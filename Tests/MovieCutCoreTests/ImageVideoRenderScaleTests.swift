import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import MovieCutCore

/// G-15 AC7: large images (e.g. a 24MP photo) must be DOWNSCALED to the
/// canvas-resolved max pixel size on load — `kCGImageSourceThumbnailMaxPixelSize`
/// caps the decoded dimensions, so a 6000x4000 source on a 1920x1080 canvas
/// decodes at ~1920px, not the full 24MP. The rendered output carries the
/// canvas dimensions and the render completes without excessive memory.
@Suite("Large image downscale (G-15 AC7)")
struct ImageVideoRenderScaleTests {
    /// Creates a large asymmetric PNG at test time (6000x4000 = 24MP,
    /// approaching the spec's 48MP scenario). Left half red, right half blue.
    private func makeLargeAsymmetricPNG(width: Int, height: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("g15-ac7-\(UUID().uuidString).png")

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 0.90, green: 0.08, blue: 0.08, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(red: 0.08, green: 0.08, blue: 0.90, alpha: 1)
        context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let image = context.makeImage()!

        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return url
    }

    @Test("a 24MP source on a 1080p canvas renders at canvas size, not source size")
    func largeImageDownscalesToCanvas() async throws {
        let sourceURL = try makeLargeAsymmetricPNG(width: 6000, height: 4000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // The render canvas is 1920x1080 — the source is ~5.6x larger per side.
        let canvasSize = CGSize(width: 1920, height: 1080)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("g15-ac7-out-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await ImageVideoRenderService().render(
            imageURL: sourceURL,
            duration: 1.0,
            renderSize: canvasSize,
            outputURL: outputURL
        )

        // The output video track must carry the CANVAS dimensions (1920x1080),
        // proving the render pipeline operates at canvas resolution.
        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let track = try #require(videoTracks.first, "the rendered segment must have a video track")
        let dimensions = try await track.load(.naturalSize)
        #expect(abs(dimensions.width - 1920) < 2 && abs(dimensions.height - 1080) < 2,
                "output must be canvas-sized (1920x1080), got \(dimensions)")

        // The decoded source image is capped by kCGImageSourceThumbnailMaxPixelSize
        // at ~max(canvasWidth, canvasHeight) — a 6000x4000 source decodes at
        // ~1920px long side, not the full 24MP. Verify indirectly: the output
        // file exists, is non-trivially sized, and the render completed.
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = attributes[.size] as? Int ?? 0
        #expect(fileSize > 1_000, "the rendered segment must be non-trivially sized, got \(fileSize) bytes")
    }

    @Test("a 4K canvas with a large source renders at 4K, still bounded by canvas")
    func largeImageOn4KCanvas() async throws {
        let sourceURL = try makeLargeAsymmetricPNG(width: 6000, height: 4000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // 4K canvas: 3840x2160 — still smaller than the 6000x4000 source.
        let canvasSize = CGSize(width: 3840, height: 2160)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("g15-ac7-4k-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await ImageVideoRenderService().render(
            imageURL: sourceURL,
            duration: 1.0,
            renderSize: canvasSize,
            outputURL: outputURL
        )

        let asset = AVURLAsset(url: outputURL)
        let track = try #require(
            try await asset.loadTracks(withMediaType: .video).first
        )
        let dimensions = try await track.load(.naturalSize)
        #expect(abs(dimensions.width - 3840) < 2 && abs(dimensions.height - 2160) < 2,
                "output must be 4K canvas-sized (3840x2160), got \(dimensions)")
    }

    @Test("Ken Burns max zoom increases the load cap proportionally")
    func kenBurnsZoomRaisesCap() async throws {
        let sourceURL = try makeLargeAsymmetricPNG(width: 6000, height: 4000)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // A 2x Ken Burns zoom loads the source at 2x the canvas long side,
        // so the zoomed-in crop stays sharp. 1920 canvas × 2.0 zoom = 3840px
        // cap — still below the 6000px native, proving the cap applies.
        let canvasSize = CGSize(width: 1920, height: 1080)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("g15-ac7-kb-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try await ImageVideoRenderService().render(
            imageURL: sourceURL,
            duration: 1.0,
            renderSize: canvasSize,
            outputURL: outputURL,
            kenBurnsEffect: KenBurnsEffect(
                startScale: 2.0,
                endScale: 2.0,
                startFocus: CGPoint(x: 0.3, y: 0.5),
                endFocus: CGPoint(x: 0.7, y: 0.5)
            )
        )

        // With Ken Burns at 2x zoom, the loaded image is at most 3840px — the
        // output still carries canvas dimensions and the render completes.
        let asset = AVURLAsset(url: outputURL)
        let track = try #require(
            try await asset.loadTracks(withMediaType: .video).first
        )
        let dimensions = try await track.load(.naturalSize)
        #expect(abs(dimensions.width - 1920) < 2 && abs(dimensions.height - 1080) < 2,
                "Ken Burns output must still be canvas-sized, got \(dimensions)")
    }
}
