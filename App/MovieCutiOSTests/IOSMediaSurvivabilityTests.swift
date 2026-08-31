import AVFoundation
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// SURV-01 (review 2026-08-26): imported media must outlive the session.
/// Photo-picker imports previously landed in temporaryDirectory — the OS
/// purges it, leaving a recovered project whose originals are gone. Imports
/// now copy into the managed Application Support Imports root
/// (per-project subdirectory), and a restore whose originals are missing
/// surfaces the loss instead of silently playing empty clips.
@MainActor
@Suite("iOS media survivability (SURV-01)")
struct IOSMediaSurvivabilityTests {
    private func temporaryDirectory(_ label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("surv01-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A minimal valid WAV (RIFF header) the validated importer accepts.
    private func temporaryWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("surv01-\(UUID().uuidString).wav")
        var bytes: [UInt8] = Array("RIFF".utf8) + [0x24, 0x08, 0x00, 0x00] + Array("WAVEfmt ".utf8)
        bytes += Array(repeating: 0, count: 16)
        try Data(bytes).write(to: url)
        return url
    }

    @Test("photo imports land in the managed per-project Imports directory")
    func stagedImportsLandUnderManagedRoot() throws {
        let importsRoot = try temporaryDirectory("imports")
        defer { try? FileManager.default.removeItem(at: importsRoot) }
        let autosave = try temporaryDirectory("autosave")
        defer { try? FileManager.default.removeItem(at: autosave) }

        let vm = IOSEditorViewModel(autosaveDirectory: autosave, importsDirectory: importsRoot)
        let destination = vm.stagedImportDestination(fileExtension: "wav")

        // The destination must sit under <importsRoot>/<projectId>/ and
        // OUTSIDE temporaryDirectory — the OS never purges Application
        // Support, so the original survives alongside the recovery project.
        #expect(destination.path.hasPrefix(importsRoot.path),
                "the staged import must live under the managed root, got \(destination)")
        #expect(destination.deletingLastPathComponent().lastPathComponent == vm.currentProject.id.uuidString,
                "the staged import must sit in the project's subdirectory, got \(destination)")
        #expect(!destination.path.hasPrefix(FileManager.default.temporaryDirectory.path)
                || importsRoot.path.hasPrefix(FileManager.default.temporaryDirectory.path),
                "production roots must not fall back to the purged temp directory")
    }

    @Test("a restore whose originals are missing surfaces the loss (SURV-01)")
    func restoreSurfacesMissingMedia() async throws {
        let importsRoot = try temporaryDirectory("imports")
        let autosave = try temporaryDirectory("autosave")
        defer {
            try? FileManager.default.removeItem(at: importsRoot)
            try? FileManager.default.removeItem(at: autosave)
        }

        // Session 1: import through the managed root, wait for the autosave.
        let first = IOSEditorViewModel(autosaveDirectory: autosave, importsDirectory: importsRoot)
        let wav = try temporaryWAV()
        let destination = first.stagedImportDestination(fileExtension: "wav")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: wav, to: destination)
        await first.importMedia(from: destination)
        #expect(first.currentProject.mediaLibrary.assets.count == 1)

        let recoveryURL = autosave.appendingPathComponent("recovery.moviecut")
        for _ in 0..<500 where !FileManager.default.fileExists(atPath: recoveryURL.path) {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        #expect(FileManager.default.fileExists(atPath: recoveryURL.path),
                "the autosave must have written the recovery file")
        try? FileManager.default.removeItem(at: wav)

        // Evict the managed original (simulates an external wipe), relaunch,
        // restore: the loss must be surfaced, not silently accepted.
        try FileManager.default.removeItem(at: destination)
        let second = IOSEditorViewModel(autosaveDirectory: autosave, importsDirectory: importsRoot)
        await second.restoreAutosaveIfAvailable()

        #expect(second.recoveredUnsavedWork == true, "the project itself must restore")
        #expect(second.currentProject.mediaLibrary.assets.count == 1,
                "the asset entry survives (the file did not)")
        #expect(second.lastErrorMessage?.contains("missing") == true,
                "missing originals must be surfaced, got: \(second.lastErrorMessage ?? "nil")")
    }

    // MARK: - SURV-01 2차: relative references, relink, cleanup policy

    private func makeProject(asset: MediaAsset) -> Project {
        Project(
            name: "surv01-2",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [])
        )
    }

    @Test("a dead absolute URL rebases through the relative reference")
    func rebaseThroughRelativeReference() throws {
        let importsRoot = try temporaryDirectory("imports")
        defer { try? FileManager.default.removeItem(at: importsRoot) }

        let projectId = UUID()
        let relative = "\(projectId.uuidString)/original.wav"
        let live = importsRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: live.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: live)

        // The container moved (reinstall/restore): the saved absolute URL is
        // dead but the managed copy lives at the current root.
        let dead = URL(fileURLWithPath: "/stale-container/MovieCut/Imports/\(relative)")
        var project = makeProject(asset: MediaAsset(
            originalURL: dead,
            kind: .audio,
            managedImportPath: relative
        ))

        let rebased = ProjectStore.rebaseManagedImports(in: &project, importsRoot: importsRoot)
        #expect(rebased == 1)
        let asset = project.mediaLibrary.assets.values.first!
        #expect(asset.originalURL.path == live.path,
                "the URL must re-point at the current location, got \(asset.originalURL)")
        #expect(FileManager.default.fileExists(atPath: asset.originalURL.path))
    }

    @Test("a legacy absolute-only save rebases via the Imports suffix match")
    func legacyRebaseViaSuffix() throws {
        let importsRoot = try temporaryDirectory("imports")
        defer { try? FileManager.default.removeItem(at: importsRoot) }

        let projectId = UUID()
        let relative = "\(projectId.uuidString)/legacy.mov"
        let live = importsRoot.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: live.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("media".utf8).write(to: live)

        // A pre-2차 save: absolute URL only (pointing at a dead container).
        let dead = URL(fileURLWithPath: "/old-container-path/Application Support/MovieCut/Imports/\(relative)")
        var project = makeProject(asset: MediaAsset(originalURL: dead, kind: .video))

        let rebased = ProjectStore.rebaseManagedImports(in: &project, importsRoot: importsRoot)
        #expect(rebased == 1)
        let asset = project.mediaLibrary.assets.values.first!
        #expect(asset.originalURL.path == live.path)
        #expect(asset.managedImportPath == relative,
                "the suffix rebase must stamp the relative reference for next time")
    }

    @Test("relink copies the replacement into the managed root and clears the missing state")
    func relinkRestoresMissingAsset() async throws {
        let importsRoot = try temporaryDirectory("imports")
        let autosave = try temporaryDirectory("autosave")
        defer {
            try? FileManager.default.removeItem(at: importsRoot)
            try? FileManager.default.removeItem(at: autosave)
        }

        let vm = IOSEditorViewModel(autosaveDirectory: autosave, importsDirectory: importsRoot)
        let original = try temporaryWAV()
        await vm.importMedia(from: original)
        guard let asset = vm.mediaAssets.first else {
            Issue.record("the import must add the asset"); return
        }
        // The original vanishes (OS purge / container move gone wrong).
        try FileManager.default.removeItem(at: original)
        #expect(vm.missingMediaAssets.map(\.id) == [asset.id])

        let replacement = try temporaryWAV()
        let libraryBeforeRelink = vm.currentProject.mediaLibrary
        let linked = await vm.relinkMedia(vm.missingMediaAssets[0], to: replacement)
        #expect(linked == true)

        #expect(vm.missingMediaAssets.isEmpty, "the relinked asset must resolve")
        let relinked = vm.mediaAssets.first { $0.id == asset.id }
        #expect(relinked != nil, "the asset UUID survives so clip references hold")
        #expect(relinked!.originalURL.path.hasPrefix(importsRoot.path),
                "the replacement must live under the managed root, got \(relinked!.originalURL)")
        #expect(FileManager.default.fileExists(atPath: relinked!.originalURL.path))
        #expect(relinked!.managedImportPath?.hasPrefix(vm.currentProject.id.uuidString) == true,
                "the relinked copy must carry the relative reference")
        #expect(vm.lastErrorMessage == nil)

        // CODEX-07: the preview rebuild rides
        // `.onChange(of: currentProject.mediaLibrary)` — pin the firing
        // PREMISE: relink must actually CHANGE the library value under
        // Equatable (the URL swap), or the observation would stay silent
        // and the plan built while the asset was missing would persist.
        // (The SwiftUI wiring itself needs device/manual verification,
        // STAB-03 precedent.)
        #expect(vm.currentProject.mediaLibrary != libraryBeforeRelink,
                "relink must mutate mediaLibrary so the preview observation fires")
    }

    @Test("the cleanup policy removes only unreferenced, stale import directories")
    func cleanupRemovesOnlyStaleOrphans() throws {
        let importsRoot = try temporaryDirectory("imports")
        defer { try? FileManager.default.removeItem(at: importsRoot) }

        let keptId = UUID()
        let staleOrphan = importsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let freshOrphan = importsRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let kept = importsRoot.appendingPathComponent(keptId.uuidString, isDirectory: true)
        for directory in [staleOrphan, freshOrphan, kept] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appendingPathComponent("placeholder"))
        }
        // Push the stale orphan past the grace period.
        let old = Date().addingTimeInterval(-30 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: old],
            ofItemAtPath: staleOrphan.path
        )

        let removed = ProjectStore.cleanupOrphanedImports(
            importsRoot: importsRoot,
            keepingProjectIds: [keptId],
            olderThanDays: 7
        )
        #expect(removed == 1, "exactly the stale orphan goes, got \(removed)")
        #expect(!FileManager.default.fileExists(atPath: staleOrphan.path))
        #expect(FileManager.default.fileExists(atPath: freshOrphan.path),
                "the grace period must protect recent orphans")
        #expect(FileManager.default.fileExists(atPath: kept.path),
                "referenced project directories are never cleaned")
    }
}
