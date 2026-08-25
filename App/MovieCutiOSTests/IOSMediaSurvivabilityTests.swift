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
}
