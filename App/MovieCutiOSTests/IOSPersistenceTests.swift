import Foundation
import MovieCutCore
import Testing
@testable import MovieCutiOS

/// BUG-IOS-02 (external review, verified): the iOS app created a fresh
/// project on every launch — termination or OS eviction silently discarded
/// all work. These tests drive the real persistence paths: committed edits
/// autosave through the shared Core ProjectStore, and a later launch
/// restores the unsaved work.
@MainActor
@Suite("iOS crash-recovery persistence (BUG-IOS-02)")
struct IOSPersistenceTests {
    private func temporaryAutosaveDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug-ios02-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// A minimal valid WAV (RIFF header) the validated importer accepts.
    private func temporaryWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug-ios02-\(UUID().uuidString).wav")
        var bytes: [UInt8] = Array("RIFF".utf8) + [0x24, 0x08, 0x00, 0x00] + Array("WAVEfmt ".utf8)
        bytes += Array(repeating: 0, count: 16)
        try Data(bytes).write(to: url)
        return url
    }

    private func until(_ condition: @escaping () -> Bool) async {
        for _ in 0..<500 where !condition() {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @Test("committed edits autosave and a fresh launch restores them")
    func autosaveRoundTripRestoresWork() async throws {
        let dir = try temporaryAutosaveDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = try temporaryWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        // Session 1: import media (a real committed mutation → autosave).
        let first = IOSEditorViewModel(autosaveDirectory: dir)
        await first.importMedia(from: wav)
        #expect(first.lastErrorMessage == nil, "import failed: \(first.lastErrorMessage ?? "")")
        #expect(first.currentProject.mediaLibrary.assets.count == 1)
        await until { first.currentProject.mediaLibrary.assets.count == 1 }
        // Poll for the recovery file instead of a fixed sleep — under
        // full-suite load the 150ms debounce + disk write can exceed any
        // fixed budget (the 2026-08-26 review's flake: passes standalone,
        // fails loaded). 500 × ~2ms covers seconds of scheduling delay.
        let recoveryURL = dir.appendingPathComponent("recovery.moviecut")
        await until { FileManager.default.fileExists(atPath: recoveryURL.path) }
        #expect(FileManager.default.fileExists(atPath: recoveryURL.path),
                "the autosave must have written the recovery file")

        // Session 2 (fresh VM — a relaunch): the recovery file restores the work.
        let second = IOSEditorViewModel(autosaveDirectory: dir)
        #expect(second.currentProject.mediaLibrary.assets.isEmpty,
                "baseline: a fresh VM starts empty before restore")
        await second.restoreAutosaveIfAvailable()

        #expect(second.recoveredUnsavedWork == true, "recovery must be flagged")
        #expect(second.currentProject.mediaLibrary.assets.count == 1,
                "the imported media must survive the relaunch")
        #expect(second.currentProject.timeline.tracks.contains { $0.kind == .video || $0.kind == .audio })
    }

    @Test("a read-only autosave directory surfaces the failure without blocking edits")
    func readOnlyDirectorySurfacesFailure() async throws {
        let dir = try temporaryAutosaveDirectory()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let wav = try temporaryWAV()
        defer { try? FileManager.default.removeItem(at: wav) }

        let vm = IOSEditorViewModel(autosaveDirectory: dir)
        await vm.importMedia(from: wav)
        await until { vm.autosaveFailureMessage != nil }

        #expect(vm.autosaveFailureMessage != nil,
                "a failing crash-recovery autosave must be surfaced")
        // The edit itself succeeded — non-blocking.
        #expect(vm.currentProject.mediaLibrary.assets.count == 1)
    }
}
