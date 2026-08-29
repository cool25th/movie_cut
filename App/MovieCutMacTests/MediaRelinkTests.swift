import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// Behavior regression test for missing-media re-link (P0 #6).
///
/// The bug this pins: when a media file went missing, the only workaround was
/// "Re-import Media," which creates a NEW asset with a new UUID and silently
/// orphans every clip still referencing the old asset. `relinkMedia(_:to:)`
/// instead updates the asset in place (stable UUID) so clip references survive.
/// These tests assert that contract at the ViewModel level — they use real
/// temp files and the real `SecurityScopedAccess` bookmark path.
@MainActor
@Suite("Missing media re-link")
struct MediaRelinkTests {
    /// Two real temp files: an "original" (which will go missing) and a
    /// "relocated" copy (the new location the user picks).
    private func makeFilePair() throws -> (original: URL, relocated: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutRelinkTests", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let original = dir.appendingPathComponent("\(UUID().uuidString)-original.mp4")
        let relocated = dir.appendingPathComponent("\(UUID().uuidString)-moved.mp4")
        // Minimal mp4 header (ftyp at offset 4) — the relink probe validates
        // content signatures since BUG-02; bare placeholder bytes are rejected.
        let mp4Header = Data([0x00, 0x00, 0x00, 0x18] + Array("ftypisom".utf8))
        try mp4Header.write(to: original)
        try mp4Header.write(to: relocated)
        return (original, relocated)
    }

    @Test("relink preserves the asset UUID so clips keep their reference")
    func relinkPreservesAssetUUID() async throws {
        let (originalURL, relocatedURL) = try makeFilePair()
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: relocatedURL)
        }

        let assetId = UUID()
        let asset = MediaAsset(
            id: assetId,
            originalURL: originalURL,
            kind: .video,
            originalBookmark: SecurityScopedAccess.makeBookmark(for: originalURL)
        )
        // A clip pointing at this asset — this is what must NOT be orphaned.
        let clip = Clip(
            assetId: assetId,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1)
        )

        let vm = EditorViewModel(project: Project(
            name: "relink-test",
            mediaLibrary: MediaLibrary(assets: [assetId: asset]),
            timeline: Timeline(
                canvasSize: CGSize(width: 100, height: 100),
                tracks: [Track(kind: .video, name: "V1", zIndex: 0, clips: [clip])]
            )
        ))

        // Simulate the original going missing, then re-link to the relocated copy.
        try FileManager.default.removeItem(at: originalURL)
        // Sanity: before relink, the asset is flagged missing.
        vm.evaluateMissingMedia(in: vm.currentProject)
        #expect(vm.missingMediaAssets.count == 1)

        let linked = await vm.relinkMedia(asset, to: relocatedURL)
        #expect(linked, "relink should succeed against an existing relocated file")

        // THE CONTRACT: the asset UUID is unchanged, so the clip still resolves.
        let after = vm.currentProject
        #expect(after.mediaLibrary.assets[assetId] != nil, "relinked asset must keep its UUID")
        #expect(after.mediaLibrary.assets[assetId]?.originalURL.lastPathComponent == relocatedURL.lastPathComponent,
                "asset URL must point at the relocated file")
        // The clip still references the same asset id; nothing was orphaned.
        let timelineClip = after.timeline.tracks.flatMap { $0.clips }.first { $0.assetId == assetId }
        #expect(timelineClip != nil, "clip referencing the relinked asset must still exist")
    }

    @Test("relink clears the asset from the missing list")
    func relinkClearsFromMissingList() async throws {
        let (originalURL, relocatedURL) = try makeFilePair()
        defer {
            try? FileManager.default.removeItem(at: originalURL)
            try? FileManager.default.removeItem(at: relocatedURL)
        }

        let assetId = UUID()
        let asset = MediaAsset(
            id: assetId,
            originalURL: originalURL,
            kind: .video,
            originalBookmark: SecurityScopedAccess.makeBookmark(for: originalURL)
        )
        let vm = EditorViewModel(project: Project(
            name: "relink-clear-test",
            mediaLibrary: MediaLibrary(assets: [assetId: asset])
        ))

        try FileManager.default.removeItem(at: originalURL)
        vm.evaluateMissingMedia(in: vm.currentProject)
        #expect(vm.missingMediaAssets.count == 1)

        _ = await vm.relinkMedia(asset, to: relocatedURL)
        // relinkMedia re-evaluates missing media internally.
        #expect(vm.missingMediaAssets.isEmpty, "relinked asset should leave the missing list")
    }
}
