import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// Review-fix behavioral tests (2026-08-28 external feedback):
/// - P0 export container honors the resolved plan (default MP4, not .mov)
/// - P0 playhead trims reach the real TrimClipCommand math
/// - P1 the text sheet's background color persists into TextClipContent
/// - P1 the canvas Frame Rate picker syncs project.exportSettings.frameRate
@MainActor
@Suite("iOS review P0/P1 fixes")
struct IOSReviewP0FixesTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    private func freshViewModel() -> IOSEditorViewModel {
        IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("revfix-\(UUID().uuidString)", isDirectory: true)
        )
    }

    // MARK: P0 container

    @Test("default export honors the MP4 container contract")
    func exportUsesMP4Container() async throws {
        let assetId = UUID()
        let asset = MediaAsset(originalURL: Self.fixtureURL, kind: .video, duration: 2)
        let clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 0.5),
            timelineRange: TimeRange(start: 0, duration: 0.5)
        )
        let project = Project(
            name: "revfix-container",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])
            ])
        )
        #expect(project.exportSettings.containerFormat == .mp4,
                "the default container must be MP4 for this contract to mean anything")

        let url = try await IOSExportEngine().exportProject(project)
        #expect(url.pathExtension.lowercased() == "mp4",
                "expected an .mp4 output, got \(url.lastPathComponent)")
    }

    // MARK: P0 playhead trims

    @Test("playhead trims shrink the selected clip through TrimClipCommand math")
    func playheadTrims() async throws {
        let vm = freshViewModel()
        let asset = MediaImporter.probe(url: Self.fixtureURL)
        await vm.importMedia(from: Self.fixtureURL)
        await vm.addClipToTimeline(asset: asset)
        let clip = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.assetId == asset.id }
        )
        vm.selectedClipId = clip.id

        // End trim at 1.0s on a 2s clip → duration 1.0, start unchanged.
        vm.playheadTime = 1.0
        await vm.trimSelectedClipEndToPlayhead()
        var trimmed = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == clip.id }
        )
        #expect(abs(trimmed.timelineRange.start - 0) < 0.001)
        #expect(abs(trimmed.timelineRange.duration - 1.0) < 0.05)

        // Start trim at 0.5s → start 0.5, duration shrinks to 0.5.
        vm.playheadTime = 0.5
        await vm.trimSelectedClipStartToPlayhead()
        trimmed = try #require(
            vm.currentProject.timeline.tracks.flatMap(\.clips).first { $0.id == clip.id }
        )
        #expect(abs(trimmed.timelineRange.start - 0.5) < 0.05)
        #expect(abs(trimmed.timelineRange.duration - 0.5) < 0.1)
        #expect(vm.lastErrorMessage == nil)
    }

    @Test("trims outside the clip report an explicit error instead of no-op")
    func trimOutsideClipErrors() async throws {
        let vm = freshViewModel()
        await vm.trimSelectedClipEndToPlayhead()
        #expect(vm.lastErrorMessage != nil)
    }

    // MARK: P1 text background persistence

    @Test("addTextClip persists the sheet's background color choice")
    func textBackgroundPersists() async throws {
        let vm = freshViewModel()
        await vm.addTextClip(
            text: "revfix",
            fontName: "Helvetica Neue",
            fontSize: 28,
            color: "#FFFFFF",
            backgroundColor: "#00FF00"
        )
        let textClip = try #require(
            vm.currentProject.timeline.tracks
                .flatMap(\.clips)
                .compactMap(\.textContent)
                .first
        )
        #expect(textClip.backgroundColor == "#00FF00")
    }

    // MARK: P1 export frame-rate sync

    @Test("canvas frame-rate selection syncs the export settings")
    func frameRateSyncsExportSettings() async throws {
        let vm = freshViewModel()
        #expect(vm.currentProject.exportSettings.frameRate != .fps60)

        var preset = vm.currentProject.canvas
        preset.frameRate = .fps60
        await vm.updateCanvasPreset(preset)

        #expect(vm.currentProject.canvas.frameRate == .fps60)
        #expect(vm.currentProject.exportSettings.frameRate == .fps60,
                "the export engine reads exportSettings.frameRate — the picker must reach it")
    }
}
