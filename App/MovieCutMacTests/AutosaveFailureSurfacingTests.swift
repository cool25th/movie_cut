import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// BUG-01 (CA-03 audit): the crash-recovery autosave used to swallow every
/// failure with `try?` — under disk-full the user kept editing with a broken
/// crash-recovery promise and no signal. These tests drive the REAL
/// EditorViewModel autosave path against an injected autosave directory:
///
/// 1. A read-only directory surfaces the failure via `autosaveFailureMessage`
///    WITHOUT blocking edits (no `lastErrorMessage`).
/// 2. Restoring writability clears the warning on the next successful save.
/// 3. `flushAutosave()` (the pre-quit path) surfaces the same failure.
@MainActor
@Suite("Autosave failure surfacing (BUG-01)")
struct AutosaveFailureSurfacingTests {
    private func makeViewModel(autosaveDirectory: URL) -> EditorViewModel {
        EditorViewModel(project: Project(
            name: "autosave-failure",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [])
        ), autosaveDirectory: autosaveDirectory)
    }

    /// Yields until the condition holds (bounded so a stuck path fails
    /// instead of hanging).
    private func until(_ condition: @escaping () -> Bool) async {
        for _ in 0..<500 where !condition() {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    @Test("read-only autosave directory surfaces a warning without blocking edits")
    func readOnlyDirectorySurfacesWarning() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca03-bug01-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // r-x: readable/traversable but NOT writable → saveAutosave throws.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let vm = makeViewModel(autosaveDirectory: dir)
        #expect(vm.autosaveFailureMessage == nil)

        // A committed mutation schedules the autosave.
        await vm.apply(SetAudioDuckingCommand(
            duckingRangesByClip: [:],
            level: AudioDuckingPlanner.defaultDuckingLevel
        ))
        await until { vm.autosaveFailureMessage != nil }

        #expect(vm.autosaveFailureMessage != nil,
                "a failing crash-recovery autosave must be surfaced, not swallowed")
        // The localized format string varies by test-host locale; the embedded
        // classified reason (plain English from FileOperationError) does not.
        #expect(vm.autosaveFailureMessage?.contains(":") == true,
                "the warning should carry the classified failure reason")
        // Non-blocking: the edit itself succeeded; no fatal error is set.
        #expect(vm.lastErrorMessage == nil)
    }

    @Test("restoring writability clears the warning on the next autosave")
    func warningClearsAfterRecovery() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca03-bug01-recover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }

        let vm = makeViewModel(autosaveDirectory: dir)
        await vm.apply(SetAudioDuckingCommand(
            duckingRangesByClip: [:],
            level: AudioDuckingPlanner.defaultDuckingLevel
        ))
        await until { vm.autosaveFailureMessage != nil }
        #expect(vm.autosaveFailureMessage != nil)

        // Free the disk situation; the next committed mutation autosaves fine.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        await vm.apply(SetAudioDuckingCommand(
            duckingRangesByClip: [:],
            level: nil
        ))
        await until { vm.autosaveFailureMessage == nil }

        #expect(vm.autosaveFailureMessage == nil,
                "the warning must clear once autosaves succeed again")
        #expect(vm.lastErrorMessage == nil)
    }

    @Test("flushAutosave surfaces the same failure (pre-quit path)")
    func flushSurfacesFailure() async throws {
        // /dev/null/sub cannot be created — createDirectory fails immediately
        // regardless of permissions, deterministic on every machine.
        let vm = makeViewModel(autosaveDirectory: URL(fileURLWithPath: "/dev/null/moviecut-test"))

        await vm.flushAutosave()
        #expect(vm.autosaveFailureMessage != nil,
                "flushAutosave must report a failing autosave instead of try?-swallowing it")
        #expect(vm.lastErrorMessage == nil, "the warning is non-blocking")
    }
}

/// Coalescing semantics (capcut-surpass 9304e8b rewrite): a burst of edits
/// must settle into the LATEST snapshot, and `flushAutosave()` must persist
/// immediately without waiting out the debounce. Exact write-counting needs
/// store injection; these pin the externally observable contract against the
/// real recovery file.
@MainActor
@Suite("Autosave coalescing (capcut-surpass 9304e8b)")
struct AutosaveCoalescingTests {
    private func makeViewModel(autosaveDirectory: URL) -> EditorViewModel {
        EditorViewModel(project: Project(
            name: "autosave-coalesce",
            mediaLibrary: MediaLibrary(assets: [:]),
            timeline: Timeline(canvasSize: CGSize(width: 100, height: 100), tracks: [])
        ), autosaveDirectory: autosaveDirectory)
    }

    private func recoveryJSON(in dir: URL) throws -> Data {
        try Data(contentsOf: dir.appendingPathComponent("recovery.moviecut"))
    }

    @Test("a burst of edits settles into the latest snapshot")
    func burstSettlesIntoLatestSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-coalesce-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel(autosaveDirectory: dir)
        // Three rapid timeline mutations, no waiting between them — the
        // debounce must coalesce them; the recovery file must end up with
        // the final name, not an intermediate one.
        for name in ["first", "second", "third"] {
            var renamed = vm.currentProject
            renamed.name = name
            await vm.apply(ReplaceProjectCommand(project: renamed))
        }
        // Settle past the 0.75 s debounce.
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let json = try String(decoding: recoveryJSON(in: dir), as: UTF8.self)
        #expect(json.contains("\"name\" : \"third\""),
                "latest snapshot must win after a coalesced burst")
        #expect(vm.autosaveFailureMessage == nil)
    }

    @Test("flushAutosave persists immediately without waiting for the debounce")
    func flushPersistsImmediately() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cc-flush-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vm = makeViewModel(autosaveDirectory: dir)
        var flushed = vm.currentProject
        flushed.name = "flushed"
        await vm.apply(ReplaceProjectCommand(project: flushed))
        // Flush right away — no debounce wait.
        await vm.flushAutosave()
        let json = try String(decoding: recoveryJSON(in: dir), as: UTF8.self)
        #expect(json.contains("\"name\" : \"flushed\""),
                "flush must write the latest snapshot synchronously")
    }
}
