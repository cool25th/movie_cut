import Foundation
import Testing
@testable import MovieCutCore

/// Stability coverage (Phase 0.6): crash-recovery autosave round-trips and the
/// recovery file's presence correctly distinguishes a crash from a clean quit.
@Suite("Autosave Recovery")
struct AutosaveRecoveryTests {
    private func tempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-autosave-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeProject(name: String) -> Project {
        Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            name: name,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            appVersion: "0.1.0",
            mediaLibrary: MediaLibrary(),
            timeline: Timeline(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: [],
                markers: []
            ),
            markers: [],
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    @Test("autosave round-trips and clear removes it")
    func autosaveRoundTripAndClear() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(autosaveDirectory: dir)
        let project = makeProject(name: "Recovery Me")

        #expect(await store.hasAutosave() == false)
        #expect(await store.loadAutosaveIfAvailable() == nil)

        try await store.saveAutosave(project)
        #expect(await store.hasAutosave() == true)
        #expect(await store.loadAutosaveIfAvailable() == project)

        await store.clearAutosave()
        #expect(await store.hasAutosave() == false)
        #expect(await store.loadAutosaveIfAvailable() == nil)
    }

    @Test("a crash (no clear) leaves recovery for the next launch")
    func crashLeavesRecovery() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = makeProject(name: "Crashed Session")

        // Session 1 autosaves but never clears (simulating a crash).
        let session1 = ProjectStore(autosaveDirectory: dir)
        try await session1.saveAutosave(project)

        // Session 2 (fresh store, same directory) finds the recovery.
        let session2 = ProjectStore(autosaveDirectory: dir)
        #expect(await session2.hasAutosave() == true)
        #expect(await session2.loadAutosaveIfAvailable() == project)
    }

    @Test("a clean quit (clear) leaves nothing to recover")
    func cleanQuitLeavesNothing() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = makeProject(name: "Clean Session")

        let session1 = ProjectStore(autosaveDirectory: dir)
        try await session1.saveAutosave(project)
        await session1.clearAutosave()  // clean quit

        let session2 = ProjectStore(autosaveDirectory: dir)
        #expect(await session2.hasAutosave() == false)
        #expect(await session2.loadAutosaveIfAvailable() == nil)
    }

    @Test("a corrupt recovery file is reported and removed, not silently swallowed")
    func corruptRecoveryIsReportedAndRemoved() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(autosaveDirectory: dir)

        // Hand-write a malformed recovery file at the exact autosave path.
        let autosaveURL = dir.appendingPathComponent("recovery.moviecut")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("this is not valid moviecut JSON {{{{".utf8).write(to: autosaveURL)

        #expect(await store.hasAutosave() == true)
        // Previously this returned nil via `try?` with NO record of the failure
        // and left the corrupt file on disk forever. Now it records the failure
        // and removes the file.
        #expect(await store.loadAutosaveIfAvailable() == nil)
        let failure = await store.lastAutosaveLoadFailure
        #expect(failure != nil, "a corrupt autosave must record a failure, not return nil silently")
        #expect(failure == .corrupt, "expected .corrupt classification, got \(String(describing: failure))")
        // The corrupt file is gone so it can't trap the user every launch.
        #expect(FileManager.default.fileExists(atPath: autosaveURL.path) == false)
    }

    @Test("a successful load after a corrupt file clears the recorded failure")
    func successfulLoadClearsFailure() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(autosaveDirectory: dir)

        // First: corrupt file → records failure.
        let autosaveURL = dir.appendingPathComponent("recovery.moviecut")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: autosaveURL)
        _ = await store.loadAutosaveIfAvailable()
        #expect(await store.lastAutosaveLoadFailure != nil)

        // Then: a valid autosave is written (simulating the next edit session).
        try await store.saveAutosave(makeProject(name: "Good"))
        let recovered = await store.loadAutosaveIfAvailable()
        #expect(recovered != nil)
        #expect(await store.lastAutosaveLoadFailure == nil, "a successful load must clear the recorded failure")
    }

    @Test("autosave modification date is exposed for the recovery prompt")
    func autosaveModificationDateExposed() async throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProjectStore(autosaveDirectory: dir)

        #expect(await store.autosaveModificationDate() == nil, "no autosave on disk → no date")

        let before = Date()
        try await store.saveAutosave(makeProject(name: "Stamped"))
        let date = await store.autosaveModificationDate()
        #expect(date != nil, "an existing autosave must expose its last-write time")
        #expect(date!.timeIntervalSince(before) > -5, "exposed date should reflect the write just performed")

        await store.clearAutosave()
        #expect(await store.autosaveModificationDate() == nil, "cleared autosave → no date")
    }
}
