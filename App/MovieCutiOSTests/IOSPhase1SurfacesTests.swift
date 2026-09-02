import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// Phase-1 remaining surfaces (review #3, 2026-08-28): frame stepping, loop
/// playback state, track management (add/mute/lock/delete), project
/// open/save round-trip, and export presets — all through the real command
/// paths the UI drives.
@MainActor
@Suite("iOS Phase-1 surfaces (review #3)")
struct IOSPhase1SurfacesTests {
    private static let fixtureURL: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MovieCutiOSTests
        .deletingLastPathComponent()  // App
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Tests/Fixtures/solid_red_320x240_2s_30fps.mp4")

    private func freshViewModel() -> IOSEditorViewModel {
        IOSEditorViewModel(
            autosaveDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("phase1-\(UUID().uuidString)", isDirectory: true)
        )
    }

    // MARK: Frame stepping

    @Test("frame stepping moves one frame at the project rate and clamps")
    func frameStepping() async throws {
        let vm = freshViewModel()
        let asset = MediaImporter.probe(url: Self.fixtureURL)
        await vm.importMedia(from: Self.fixtureURL)
        await vm.addClipToTimeline(asset: asset)
        let duration = vm.currentProject.timeline.duration
        #expect(duration > 1.9)

        vm.playheadTime = 1.0
        vm.stepFrame(forward: true)
        #expect(abs(vm.playheadTime - (1.0 + 1.0 / 30.0)) < 0.0001)
        // STAB-03①: every explicit step bumps the tick the view observes
        // with a forced zero-tolerance seek — otherwise a ~0.033 s move is
        // swallowed by the 0.25 s observer-coalescing threshold and the
        // rendered frame stays behind the playhead number.
        #expect(vm.frameStepTick == 1)
        vm.stepFrame(forward: false)
        vm.stepFrame(forward: false)
        #expect(abs(vm.playheadTime - (1.0 - 1.0 / 30.0)) < 0.0001)
        #expect(vm.frameStepTick == 3)

        // Stepping pauses playback rather than fighting the time observer.
        vm.isPlaying = true
        vm.stepFrame(forward: true)
        #expect(vm.isPlaying == false)

        // Clamped at both ends.
        vm.playheadTime = 0
        vm.stepFrame(forward: false)
        #expect(vm.playheadTime == 0)
        vm.playheadTime = duration
        vm.stepFrame(forward: true)
        #expect(abs(vm.playheadTime - duration) < 0.0001)
    }

    // MARK: Loop playback

    @Test("loop playback is off by default and toggles")
    func loopToggle() {
        let vm = freshViewModel()
        #expect(vm.isLooping == false)
        vm.isLooping = true
        #expect(vm.isLooping == true)
    }

    // STAB-03②: end-of-playback is decided from the deterministic
    // AVPlayerItemDidPlayToEndTime notification (forwarded by PreviewView),
    // not from the periodic observer sampling the exact end.
    @Test("playback end handler loops to zero or stops")
    func playbackEndHandling() async throws {
        let vm = freshViewModel()
        let asset = MediaImporter.probe(url: Self.fixtureURL)
        await vm.importMedia(from: Self.fixtureURL)
        await vm.addClipToTimeline(asset: asset)
        let duration = vm.currentProject.timeline.duration
        #expect(duration > 1.9)

        // Non-looping: playback stops.
        vm.playheadTime = duration
        vm.isPlaying = true
        vm.handlePlaybackReachedEnd()
        #expect(vm.isPlaying == false)

        // Looping: playhead resets to zero and stays "playing" — the view
        // performs the player-side seek and resume.
        vm.isLooping = true
        vm.isPlaying = true
        vm.playheadTime = duration
        vm.handlePlaybackReachedEnd()
        #expect(vm.playheadTime == 0)
        #expect(vm.isPlaying == true)
    }

    // MARK: Track management

    @Test("add, mute, lock, and delete tracks through real commands")
    func trackManagement() async throws {
        let vm = freshViewModel()
        let before = vm.currentProject.timeline.tracks.count

        await vm.addTrack(kind: .video)
        #expect(vm.currentProject.timeline.tracks.count == before + 1)
        let added = vm.currentProject.timeline.tracks.last
        #expect(added?.kind == .video)
        #expect(added?.clips.isEmpty == true)

        await vm.addTrack(kind: .audio)
        #expect(vm.currentProject.timeline.tracks.count == before + 2)

        guard let trackId = added?.id else {
            Issue.record("missing added track")
            return
        }
        await vm.setTrackMuted(trackId, true)
        #expect(vm.currentProject.timeline.tracks.first { $0.id == trackId }?.isMuted == true)

        await vm.setTrackLocked(trackId, true)
        #expect(vm.currentProject.timeline.tracks.first { $0.id == trackId }?.isLocked == true)

        // CODEX-20 contract: RemoveTrackCommand honors the track lock (the
        // same guard every other mutating command applies) — a locked track
        // refuses removal, so both the track and the count survive.
        await vm.deleteTrack(trackId)
        #expect(vm.currentProject.timeline.tracks.first { $0.id == trackId } != nil,
                "a locked track must refuse deletion")
        #expect(vm.currentProject.timeline.tracks.count == before + 2)

        // Unlocked, the same delete goes through.
        await vm.setTrackLocked(trackId, false)
        await vm.deleteTrack(trackId)
        #expect(vm.currentProject.timeline.tracks.first { $0.id == trackId } == nil)
        #expect(vm.currentProject.timeline.tracks.count == before + 1)
    }

    // MARK: Project save/open round-trip

    @Test("saving then opening a .moviecut file restores the project")
    func projectSaveOpenRoundTrip() async throws {
        let first = freshViewModel()
        let asset = MediaImporter.probe(url: Self.fixtureURL)
        await first.importMedia(from: Self.fixtureURL)
        await first.addClipToTimeline(asset: asset)
        await first.addTrack(kind: .audio)
        let clipCount = first.currentProject.timeline.tracks.flatMap(\.clips).count
        #expect(clipCount == 1)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase1-\(UUID().uuidString).moviecut")
        defer { try? FileManager.default.removeItem(at: url) }

        await first.saveProject(to: url)
        #expect(first.lastErrorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let second = freshViewModel()
        await second.openProject(from: url)
        #expect(second.lastErrorMessage == nil)
        #expect(second.currentProject.timeline.tracks.flatMap(\.clips).count == clipCount)
        #expect(second.currentProject.mediaLibrary.assets.count
                == first.currentProject.mediaLibrary.assets.count)
    }

    @Test("opening a corrupt file surfaces an explicit error")
    func corruptProjectErrors() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase1-corrupt-\(UUID().uuidString).moviecut")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a moviecut project".utf8).write(to: url)

        let vm = freshViewModel()
        await vm.openProject(from: url)
        #expect(vm.lastErrorMessage != nil)
    }

    // MARK: Export presets

    @Test("export preset updates reach the engine's export settings")
    func exportPresets() async throws {
        let vm = freshViewModel()
        #expect(vm.currentProject.exportSettings.resolution == .p1080)

        await vm.updateExportSettings(resolution: .p4K)
        #expect(vm.currentProject.exportSettings.resolution == .p4K)

        await vm.updateExportSettings(containerFormat: .mov)
        #expect(vm.currentProject.exportSettings.containerFormat == .mov)
        #expect(vm.currentProject.exportSettings.resolution == .p4K,
                "an unrelated preset must not clobber the resolution")
    }
}
