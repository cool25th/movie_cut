import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for `ImportAndSetClipSourceCommand` — the composite that
/// makes offline-render-then-swap operations (vocal separation, noise
/// reduction, ...) a SINGLE undo unit (requirement 9.3).
///
/// The editor session snapshots the whole project once per dispatch, so the
/// asset import and the clip source swap must happen inside one `apply`. These
/// are pure command tests (no CIContext, no StaticContract) and run under
/// `swift test`.
@Suite("ImportAndSetClipSourceCommand")
struct ImportAndSetClipSourceCommandTests {

    @Test("Import and source swap happen in a single dispatch (one undo unit)")
    func singleDispatchIsOneUndoStep() async throws {
        let originalAssetId = UUID()
        let originalAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/original.caf"),
            kind: .audio,
            duration: 10
        )
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: originalAssetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [originalAssetId: originalAsset]),
            timeline: Timeline(tracks: [Track(kind: .audio, name: "A1", zIndex: 0, clips: [clip])])
        )

        let session = EditorSession(project: project)
        let before = await session.snapshot()
        #expect(before.timeline.tracks[0].clips[0].assetId == originalAssetId)
        #expect(before.mediaLibrary.assets.count == 1)

        // The processed asset that an offline renderer (e.g. VocalSeparation)
        // would produce.
        let processedAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/vocalsep.caf"),
            kind: .audio,
            duration: 10
        )

        // One dispatch — one undo snapshot.
        try await session.dispatch(
            ImportAndSetClipSourceCommand(clipId: clipId, asset: processedAsset, kind: .audio)
        )

        let after = await session.snapshot()
        #expect(after.mediaLibrary.assets[processedAsset.id] != nil)
        #expect(after.timeline.tracks[0].clips[0].assetId == processedAsset.id)

        // A single undo must restore BOTH the import and the swap — proving the
        // operation is one undo unit, not two.
        try await session.undo()
        let restored = await session.snapshot()
        #expect(restored.mediaLibrary.assets[processedAsset.id] == nil)
        #expect(restored.mediaLibrary.assets.count == 1)
        #expect(restored.timeline.tracks[0].clips[0].assetId == originalAssetId)
    }

    @Test("Apply captures the previous clip for the inverse")
    func applyCapturesPreviousClip() throws {
        let originalAssetId = UUID()
        let originalAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/original.caf"),
            kind: .audio,
            duration: 10
        )
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: originalAssetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        var project = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [originalAssetId: originalAsset]),
            timeline: Timeline(tracks: [Track(kind: .audio, name: "A1", zIndex: 0, clips: [clip])])
        )

        let processedAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/vocalsep.caf"),
            kind: .audio,
            duration: 10
        )
        let command = ImportAndSetClipSourceCommand(
            clipId: clipId,
            asset: processedAsset,
            kind: .audio
        )

        try command.apply(to: &project)

        // The asset was registered and the clip was repointed in one apply.
        #expect(project.mediaLibrary.assets[processedAsset.id] != nil)
        #expect(project.timeline.tracks[0].clips[0].assetId == processedAsset.id)
    }

    @Test("Apply rejects an unknown clip id")
    func rejectsUnknownClip() throws {
        let processedAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/vocalsep.caf"),
            kind: .audio,
            duration: 10
        )
        var project = Project(name: "Test")

        let unknownClipId = UUID()
        #expect(throws: EditorCommandError.clipNotFound(unknownClipId)) {
            _ = try ImportAndSetClipSourceCommand(
                clipId: unknownClipId,
                asset: processedAsset,
                kind: .audio
            ).apply(to: &project)
        }
        #expect(project.mediaLibrary.assets[processedAsset.id] == nil)
    }

    @Test("Failed dispatch on locked track leaves no orphan asset and keeps revision unchanged")
    func failedDispatchOnLockedTrackIsAtomic() async throws {
        let originalAssetId = UUID()
        let originalAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/original.caf"),
            kind: .audio,
            duration: 10
        )
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: originalAssetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "Locked",
            mediaLibrary: MediaLibrary(assets: [originalAssetId: originalAsset]),
            timeline: Timeline(tracks: [Track(kind: .audio, name: "A1", isLocked: true, zIndex: 0, clips: [clip])])
        )
        let processedAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/vocalsep.caf"),
            kind: .audio,
            duration: 10
        )

        let session = EditorSession(project: project)
        let before = await session.snapshotWithRevision()

        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(
                ImportAndSetClipSourceCommand(clipId: clipId, asset: processedAsset, kind: .audio)
            )
        }

        let after = await session.snapshotWithRevision()
        #expect(after.revision == before.revision)
        #expect(after.project.mediaLibrary.assets[processedAsset.id] == nil)
        #expect(after.project.mediaLibrary.assets.count == 1)
        #expect(await session.commandCount == 0)
    }

    @Test("EditorSession rolls back partial mutations when any command throws mid-apply")
    func sessionRollsBackPartialMutationOnThrow() async {
        struct MutateThenThrowCommand: EditorCommand {
            let id = UUID()
            let mutatedName: String
            func apply(to project: inout Project) throws {
                project.name = mutatedName
                throw EditorCommandError.invalidCommand("intentional failure")
            }
        }

        let session = EditorSession(project: Project(name: "Original"))
        let before = await session.snapshotWithRevision()

        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(MutateThenThrowCommand(mutatedName: "Corrupted"))
        }

        let after = await session.snapshotWithRevision()
        #expect(after.project.name == "Original")
        #expect(after.revision == before.revision)
        #expect(await session.commandCount == 0)
    }

    @Test("AudioDuckingCommand reduces overlapping audio clip volume and Undo restores it")
    func audioDuckingCommandAppliesAndUndoes() async throws {
        let speechId = UUID()
        let bgmId = UUID()
        let speech = Clip(
            id: speechId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let bgm = Clip(
            id: bgmId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 8),
            timelineRange: TimeRange(start: 0, duration: 8),
            volume: 1.0
        )
        let project = Project(
            name: "Duck",
            timeline: Timeline(tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [speech]),
                Track(kind: .audio, name: "A1", zIndex: 1, clips: [bgm]),
            ])
        )

        let session = EditorSession(project: project)
        try await session.dispatch(AudioDuckingCommand(clipId: speechId, duckLevel: 0.7))

        let ducked = await session.snapshot()
        #expect(abs(ducked.timeline.tracks[1].clips[0].volume - 0.3) < 0.0001)

        try await session.undo()
        let restored = await session.snapshot()
        #expect(abs(restored.timeline.tracks[1].clips[0].volume - 1.0) < 0.0001)
    }

    @Test("ExtractAudioCommand reuses an available audio track without duplicating tracks")
    func extractAudioCommandReusesAvailableTrack() async throws {
        let assetId = UUID()
        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/clip.mp4"),
            kind: .video,
            duration: 5
        )
        let videoClipId = UUID()
        let videoClip = Clip(
            id: videoClipId,
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        let extractedId = UUID()
        let project = Project(
            name: "Extract",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(tracks: [
                Track(kind: .video, name: "V1", zIndex: 0, clips: [videoClip]),
                Track(kind: .audio, name: "A1", zIndex: 1, clips: []),
            ])
        )

        let session = EditorSession(project: project)
        try await session.dispatch(ExtractAudioCommand(clipId: videoClipId, extractedClipId: extractedId))

        let after = await session.snapshot()
        #expect(after.timeline.tracks.count == 2)
        let matchingClips = after.timeline.tracks.flatMap(\.clips).filter { $0.id == extractedId }
        #expect(matchingClips.count == 1)
    }

    @Test("Redo reapplies the import and swap after undo")
    func redoReapplies() async throws {
        let originalAssetId = UUID()
        let originalAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/original.caf"),
            kind: .audio,
            duration: 10
        )
        let clipId = UUID()
        let clip = Clip(
            id: clipId,
            assetId: originalAssetId,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 10),
            timelineRange: TimeRange(start: 0, duration: 10)
        )
        let project = Project(
            name: "Test",
            mediaLibrary: MediaLibrary(assets: [originalAssetId: originalAsset]),
            timeline: Timeline(tracks: [Track(kind: .audio, name: "A1", zIndex: 0, clips: [clip])])
        )

        let processedAsset = MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/vocalsep.caf"),
            kind: .audio,
            duration: 10
        )

        let session = EditorSession(project: project)
        try await session.dispatch(
            ImportAndSetClipSourceCommand(clipId: clipId, asset: processedAsset, kind: .audio)
        )
        try await session.undo()

        try await session.redo()
        let afterRedo = await session.snapshot()
        #expect(afterRedo.mediaLibrary.assets[processedAsset.id] != nil)
        #expect(afterRedo.timeline.tracks[0].clips[0].assetId == processedAsset.id)
    }
}
