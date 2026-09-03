import Foundation
import Testing
@testable import MovieCutCore

/// CA-25 generator (explicit, never in CI): rebuilds the bundled sample
/// `.mctemplate` into `App/MovieCutMac/Resources`. Env-gated so normal runs
/// never touch the working tree.
///
/// Regeneration recipe:
///   swift scripts/gen_sample_media.swift /tmp/sample_media.mov
///   MOVIECUT_GEN_SAMPLE_TEMPLATE=1 MOVIECUT_SAMPLE_MEDIA=/tmp/sample_media.mov \
///     swift test --filter SampleProjectTemplateGeneration
/// then commit the regenerated package.
@Suite("Sample project template generation")
struct SampleProjectTemplateGenerationTests {
    private static func makeSampleProject(mediaURL: URL) -> Project {
        let assetID = UUID(uuidString: "00000000-0000-0000-0000-00000000C25A")!
        let asset = MediaAsset(
            id: assetID,
            originalURL: mediaURL,
            kind: .video,
            duration: 12
        )
        let clip = Clip(
            assetId: asset.id,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 12),
            timelineRange: TimeRange(start: 0, duration: 12)
        )
        let track = Track(kind: .video, name: "Sample Clip", clips: [clip])
        let timeline = Timeline(
            frameRate: Rational(numerator: 30, denominator: 1),
            canvasSize: CGSize(width: 720, height: 1280),
            aspectRatio: .portrait9x16,
            tracks: [track],
            markers: []
        )
        var mediaLibrary = MediaLibrary()
        mediaLibrary.assets[asset.id] = asset
        return Project(
            id: UUID(),
            name: "MovieCut Sample — Talking Head",
            createdAt: Date(timeIntervalSince1970: 1_780_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_780_000_000),
            appVersion: "0.1.0",
            mediaLibrary: mediaLibrary,
            timeline: timeline,
            markers: [],
            canvas: CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    @Test("regenerate bundled template", .enabled(if: ProcessInfo.processInfo.environment["MOVIECUT_GEN_SAMPLE_TEMPLATE"] == "1"))
    func regenerateBundledTemplate() throws {
        let env = ProcessInfo.processInfo.environment
        let media = try #require(
            env["MOVIECUT_SAMPLE_MEDIA"].map { URL(fileURLWithPath: $0) },
            "MOVIECUT_SAMPLE_MEDIA must point at the generated sample media"
        )
        let destination = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // …/Tests/MovieCutCoreTests
            .deletingLastPathComponent()  // …/Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("App/MovieCutMac/Resources/SampleProject.mctemplate")

        let packaged = try ProjectPackage.export(Self.makeSampleProject(mediaURL: media), to: destination)

        #expect(packaged.mediaLibrary.assets.count == 1)
        #expect(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(ProjectPackage.manifestName).path
        ))
        print("sample template regenerated at \(destination.path)")
    }
}
