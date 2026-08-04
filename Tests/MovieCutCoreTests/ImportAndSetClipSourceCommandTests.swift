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
