import CoreGraphics
import Foundation
import MovieCutCore
import Testing

/// Extended undo round-trips, selectively ported from capcut-surpass
/// (233dee7 / 7b240d4). The source suite covered 12+ commands; only the
/// commands whose apply→undo→redo round-trip was pinned NOWHERE else in the
/// current tree are ported here — SetClipSpeed, SetClipMask,
/// SetCanvasBackground, SlipClip, CreateTrack, AddMarker and the card
/// commands already assert undo in their own suites and are deliberately
/// not duplicated.
///
/// Template (same as UndoRoundTripTests): whole-Project snapshot, dispatch,
/// assert a visible change, undo, assert the exact snapshot was restored,
/// redo, assert the change re-applies.
@Suite("Undo round-trip extended (capcut-surpass selective port)")
struct UndoRoundTripExtendedTests {

    // MARK: - Duplicate clip

    @Test("duplicate clip undo restores the exact pre-duplicate project")
    func duplicateClipUndoRestoresExactState() async throws {
        let clip = makeClip()
        let track = makeTrack(clips: [])
        let session = EditorSession(project: makeProject(tracks: [track]))
        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        let before = await session.snapshot()

        try await session.dispatch(DuplicateClipCommand(clipId: clip.id))

        let after = await session.snapshot()
        #expect(after != before, "duplicate did not alter project state")
        #expect(after.timeline.tracks[0].clips.count == 2, "duplicate did not add a clip")

        try await session.undo()
        #expect(await session.snapshot() == before, "undo after duplicate did not restore exact state")

        try await session.redo()
        #expect(await session.snapshot() == after, "redo did not re-apply the duplicate")
    }

    // MARK: - Project export settings

    @Test("set project export settings undo restores the exact pre-change project")
    func setProjectExportSettingsUndoRestoresExactState() async throws {
        let session = EditorSession(project: makeProject(tracks: []))
        let before = await session.snapshot()

        let newSettings = ExportSettings(
            resolution: .p4K,
            frameRate: .fps60,
            codec: .hevc,
            audioCodec: .aac
        )
        try await session.dispatch(SetProjectExportSettingsCommand(exportSettings: newSettings))

        let after = await session.snapshot()
        #expect(after != before, "export settings change did not alter project state")

        try await session.undo()
        #expect(await session.snapshot() == before, "undo after export settings did not restore exact state")

        try await session.redo()
        #expect(await session.snapshot() == after, "redo did not re-apply export settings")
    }

    // MARK: - Project playback settings

    @Test("set project playback settings undo restores the exact pre-change project")
    func setProjectPlaybackSettingsUndoRestoresExactState() async throws {
        let session = EditorSession(project: makeProject(tracks: []))
        let before = await session.snapshot()

        let newSettings = PlaybackSettings(
            useProxyPlayback: true,
            proxyResolution: .p720,
            autoProxyOnThermalPressure: true
        )
        try await session.dispatch(SetProjectPlaybackSettingsCommand(playbackSettings: newSettings))

        let after = await session.snapshot()
        #expect(after != before, "playback settings change did not alter project state")

        try await session.undo()
        #expect(await session.snapshot() == before, "undo after playback settings did not restore exact state")

        try await session.redo()
        #expect(await session.snapshot() == after, "redo did not re-apply playback settings")
    }

    // MARK: - Markers

    @Test("delete marker undo restores the exact pre-delete project")
    func deleteMarkerUndoRestoresExactState() async throws {
        let marker = Marker(time: 1.5, name: "Cut")
        let session = EditorSession(project: makeProject(tracks: []))
        try await session.dispatch(AddMarkerCommand(marker: marker))
        let before = await session.snapshot()

        try await session.dispatch(DeleteMarkerCommand(markerId: marker.id))

        let after = await session.snapshot()
        #expect(after != before, "delete marker did not alter project state")
        #expect(after.markers.isEmpty, "delete marker left a marker behind")

        try await session.undo()
        #expect(await session.snapshot() == before, "undo after delete marker did not restore exact state")

        try await session.redo()
        #expect(await session.snapshot() == after, "redo did not re-apply marker deletion")
    }

    @Test("update marker undo restores the exact pre-update project")
    func updateMarkerUndoRestoresExactState() async throws {
        let marker = Marker(time: 1.5, name: "Cut")
        let session = EditorSession(project: makeProject(tracks: []))
        try await session.dispatch(AddMarkerCommand(marker: marker))
        let before = await session.snapshot()

        let updated = Marker(id: marker.id, time: 2.5, name: "Renamed")
        try await session.dispatch(UpdateMarkerCommand(markerId: marker.id, marker: updated))

        let after = await session.snapshot()
        #expect(after != before, "update marker did not alter project state")
        #expect(after.markers.first?.name == "Renamed", "update marker did not rename")

        try await session.undo()
        #expect(await session.snapshot() == before, "undo after update marker did not restore exact state")

        try await session.redo()
        #expect(await session.snapshot() == after, "redo did not re-apply marker update")
    }

    // MARK: - Helpers

    private func makeProject(tracks: [Track]) -> Project {
        Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!,
            name: "Undo Round-Trip Extended Project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_300),
            appVersion: "0.1.0",
            schemaVersion: 1,
            mediaLibrary: MediaLibrary(),
            timeline: Timeline(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!,
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: tracks,
                markers: []
            ),
            markers: [],
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac),
            canvasBackground: nil
        )
    }

    private func makeTrack(
        id: UUID = UUID(),
        kind: TrackKind = .video,
        name: String = "Video 1",
        zIndex: Int = 0,
        clips: [Clip] = []
    ) -> Track {
        Track(id: id, kind: kind, name: name, zIndex: zIndex, clips: clips)
    }

    private func makeClip(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind = .video,
        sourceRange: TimeRange = TimeRange(start: 0, duration: 4),
        timelineRange: TimeRange = TimeRange(start: 0, duration: 4)
    ) -> Clip {
        Clip(
            id: id,
            assetId: assetId,
            kind: kind,
            sourceRange: sourceRange,
            timelineRange: timelineRange,
            effects: []
        )
    }
}
