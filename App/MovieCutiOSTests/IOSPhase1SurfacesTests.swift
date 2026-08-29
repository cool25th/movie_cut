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

        vm.stepFrame(forward: false)
        vm.stepFrame(forward: false)
        #expect(abs(vm.playheadTime - (1.0 - 1.0 / 30.0)) < 0.0001)

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
