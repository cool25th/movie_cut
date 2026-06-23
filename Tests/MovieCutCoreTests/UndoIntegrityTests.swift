import Foundation
import Testing
@testable import MovieCutCore

/// Stability coverage (Phase 0.6): every step of a realistic multi-command edit
/// undoes to the exact prior project state and redoes to the exact next state.
///
/// `EditorSession` undo is snapshot-based (it restores whole-project value
/// snapshots rather than relying on each command's `invert()`), so this locks
/// that the snapshots are captured at the right points and that `Project`
/// equality round-trips across diverse commands.
@Suite("Undo Integrity")
struct UndoIntegrityTests {
    @Test("a diverse command sequence undoes and redoes to exact states")
    func stepwiseUndoRedoRestoresExactStates() async throws {
        let trackId = UUID()
        let clip1Id = UUID()
        let clip2Id = UUID()
        let assetId = UUID()
        let clip1 = makeClip(id: clip1Id, assetId: assetId,
                             sourceRange: TimeRange(start: 0, duration: 4),
                             timelineRange: TimeRange(start: 0, duration: 4))
        let clip2 = makeClip(id: clip2Id, assetId: assetId,
                             sourceRange: TimeRange(start: 0, duration: 4),
                             timelineRange: TimeRange(start: 4, duration: 4))
        let track = Track(id: trackId, kind: .video, name: "Video 1", zIndex: 0, clips: [clip1])
        let session = EditorSession(project: makeProject(tracks: [track], assets: [assetId]))

        let commands: [any EditorCommand] = [
            AddClipCommand(trackId: trackId, clip: clip2),
            SetVolumeCommand(clipId: clip1Id, volume: 0.5),
            SetColorCorrectionCommand(clipId: clip1Id,
                                      colorCorrection: ColorCorrection(brightness: 0.2, warmth: 0.3)),
            SplitClipCommand(clipId: clip1Id, trackId: trackId, splitTime: 2, newClipId: UUID()),
            AddMarkerCommand(marker: Marker(time: 3, name: "M1")),
            SetVolumeCommand(clipId: clip2Id, volume: 0.7),
            DeleteClipCommand(clipId: clip2Id)
        ]

        let original = await session.snapshot()
        var states: [Project] = []
        for command in commands {
            try await session.dispatch(command)
            states.append(await session.snapshot())
        }
        let final = states.last!
        #expect(final != original)

        // Undo stepwise: each undo must restore the exact previous snapshot.
        for index in stride(from: states.count - 1, through: 0, by: -1) {
            try await session.undo()
            let expected = index == 0 ? original : states[index - 1]
            #expect(await session.snapshot() == expected, "undo step \(index) did not restore exact state")
        }

        // Redo stepwise: each redo must restore the exact next snapshot.
        for index in 0..<states.count {
            try await session.redo()
            #expect(await session.snapshot() == states[index], "redo step \(index) did not restore exact state")
        }
        #expect(await session.snapshot() == final)
    }

    @Test("a new command after undo clears the redo stack")
    func newCommandAfterUndoClearsRedo() async throws {
        let trackId = UUID()
        let track = Track(id: trackId, kind: .video, name: "Video 1", zIndex: 0, clips: [])
        let session = EditorSession(project: makeProject(tracks: [track]))

        try await session.dispatch(AddClipCommand(trackId: trackId, clip: makeClip()))
        try await session.undo()
        try await session.dispatch(AddMarkerCommand(marker: Marker(time: 1, name: "X")))

        await #expect(throws: EditorCommandError.self) {
            try await session.redo()
        }
    }

    // MARK: - Builders

    private func makeProject(tracks: [Track], assets: [UUID] = []) -> Project {
        var library = MediaLibrary()
        for assetId in assets {
            library.assets[assetId] = MediaAsset(
                id: assetId,
                originalURL: URL(fileURLWithPath: "/tmp/moviecut-\(assetId.uuidString).mov"),
                kind: .video,
                duration: 12.5,
                metadata: MediaMetadata(width: 1920, height: 1080, frameRate: 30, codec: "h264", fileSize: 1_024)
            )
        }
        return Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!,
            name: "Undo Integrity Project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            appVersion: "0.1.0",
            schemaVersion: 1,
            mediaLibrary: library,
            timeline: Timeline(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!,
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: tracks,
                markers: []
            ),
            markers: [],
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    private func makeClip(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind = .video,
        sourceRange: TimeRange = TimeRange(start: 0, duration: 4),
        timelineRange: TimeRange = TimeRange(start: 0, duration: 4)
    ) -> Clip {
        Clip(id: id, assetId: assetId, kind: kind, sourceRange: sourceRange, timelineRange: timelineRange, effects: [])
    }
}
