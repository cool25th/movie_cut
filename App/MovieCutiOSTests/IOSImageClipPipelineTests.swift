import AVFoundation
import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// G-15 (AC5/AC6): image clips must ride the shared render plan end to end.
/// The engine previously filtered tracks to `.video` only, so photo-only
/// projects threw `noExportableMedia` at export and rendered nothing in the
/// preview. Image assets now pre-render into H.264 segments via the shared
/// Core `ImageVideoRenderService` (Mac parity), which also bakes EXIF
/// orientation upright at load.
@MainActor
@Suite("iOS image clip pipeline (G-15)")
struct IOSImageClipPipelineTests {
    private static func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MovieCutiOSTests
            .deletingLastPathComponent()  // App
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Tests/Fixtures")
            .appendingPathComponent(name)
    }

    /// A one-image project on a 4:3 canvas.
    private func photoProject(
        fixture: String,
        kind: MediaKind,
        canvasWidth: Int = 320,
        canvasHeight: Int = 240
    ) -> Project {
        let assetId = UUID()
        let asset = MediaAsset(
            originalURL: Self.fixtureURL(fixture),
            kind: kind,
            duration: 2
        )
        let clip = Clip(
            assetId: assetId,
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        var project = Project(
            name: "photo",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(
                canvasSize: CGSize(width: canvasWidth, height: canvasHeight),
                tracks: [Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])]
            )
        )
        project.canvas = CanvasPreset(
            aspectRatio: .custom,
            customWidth: canvasWidth,
            customHeight: canvasHeight
        )
        return project
    }

    private static func meanFrameRGB(
        of project: Project,
        at seconds: Double = 0.5
    ) async throws -> (r: Double, g: Double, b: Double) {
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 640, height: 640)
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: seconds, preferredTimescale: 600), actualTime: nil)
        )
        return Self.meanRGB(of: frame)
    }

    private static func meanRGB(of image: CGImage) -> (r: Double, g: Double, b: Double) {
        let width = 32, height = 24
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(width * height) {
            r += Double(pixels[i * 4])
            g += Double(pixels[i * 4 + 1])
            b += Double(pixels[i * 4 + 2])
        }
        let count = Double(width * height)
        return (r / count, g / count, b / count)
    }

    @Test("photo-only PNG project renders in the plan (G-15)")
    func pngPhotoOnlyRendersInPlan() async throws {
        // The solid swatch letterboxes inside the 4:3 canvas — blue dominates
        // but margins darken it; assert a clear blue majority.
        let mean = try await Self.meanFrameRGB(of: photoProject(
            fixture: "swatch_blue_64x64.png", kind: .image
        ))
        #expect(mean.b > 80, "the PNG photo must render — got \(mean)")
        #expect(mean.b > mean.r + 30, "blue must dominate red, got \(mean)")
    }

    @Test("HEIC image clip renders in the plan (G-15 AC5)")
    func heicImageClipRenders() async throws {
        let mean = try await Self.meanFrameRGB(of: photoProject(
            fixture: "swatch_green_64x64.heic", kind: .image
        ))
        #expect(mean.g > 80, "the HEIC photo must render — got \(mean)")
        #expect(mean.g > mean.r + 30 && mean.g > mean.b + 30, "green must dominate, got \(mean)")
    }

    @Test("EXIF-oriented photo renders upright in the plan (G-15 AC5)")
    func exifOrientedPhotoRendersUpright() async throws {
        // Storage: 320×240 left-red/right-blue carrying EXIF orientation 6
        // (Rotate 90 CW). Upright display is 240×320 with RED on top — the
        // same ground truth as the ca04_rotated_asym video fixture.
        let project = photoProject(
            fixture: "exif_orient6_asym_320x240.jpg",
            kind: .image,
            canvasWidth: 240,
            canvasHeight: 320
        )
        let plan = try await IOSExportEngine().makeRenderPlan(for: project)
        let videoComposition = try #require(plan.videoComposition)
        let generator = AVAssetImageGenerator(asset: plan.composition)
        generator.videoComposition = videoComposition
        generator.maximumSize = CGSize(width: 240, height: 320)
        let frame = try #require(
            try generator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )

        let width = 24, height = 32
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)

        func bandMean(_ rows: Range<Int>) -> (r: Double, b: Double) {
            var r = 0.0, b = 0.0
            for row in rows {
                for column in 0..<width {
                    let offset = (row * width + column) * 4
                    r += Double(pixels[offset])
                    b += Double(pixels[offset + 2])
                }
            }
            let count = Double(rows.count * width)
            return (r / count, b / count)
        }

        let top = bandMean(5..<14)
        let bottom = bandMean(18..<27)
        #expect(top.r > 150 && top.b < 90, "EXIF orientation must render RED on top, got top=\(top)")
        #expect(bottom.b > 150 && bottom.r < 90, "EXIF orientation must render BLUE on bottom, got bottom=\(bottom)")
    }

    @Test("photo-only project exports a playable video (G-15 AC6)")
    func photoOnlyProjectExports() async throws {
        let project = photoProject(
            fixture: "exif_orient6_asym_320x240.jpg",
            kind: .image,
            canvasWidth: 240,
            canvasHeight: 320
        )
        // AC6: the photo-only E2E — previously threw noExportableMedia.
        let outputURL = try await IOSExportEngine().exportProject(project)

        let outputAsset = AVURLAsset(url: outputURL)
        let duration = try await outputAsset.load(.duration)
        #expect(abs(duration.seconds - 2.0) < 0.3, "export duration must match the clip, got \(duration.seconds)")
        let decodeGenerator = AVAssetImageGenerator(asset: outputAsset)
        decodeGenerator.appliesPreferredTrackTransform = true
        decodeGenerator.maximumSize = CGSize(width: 240, height: 320)
        let frame = try #require(
            try decodeGenerator.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        )
        let mean = Self.meanRGB(of: frame)
        // Upright asymmetric content: red and blue each occupy about half.
        #expect(mean.r > 80 && mean.b > 80, "exported photo video must carry both halves, got \(mean)")
    }
}
