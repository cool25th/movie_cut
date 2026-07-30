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
}
