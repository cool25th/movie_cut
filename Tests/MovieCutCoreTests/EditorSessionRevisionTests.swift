import Foundation
import Testing
@testable import MovieCutCore

@Suite("EditorSession Revision Tests")
struct EditorSessionRevisionTests {

    private func makeProject() -> Project {
        Project(name: "TestProject")
    }

    private struct DummyCommand: EditorCommand {
        let id: UUID = UUID()
        let note: String

        func apply(to project: inout Project) throws {
            project.name = note
        }
    }

    @Test("Dispatching commands advances the session revision monotonically")
    func dispatchAdvancesRevision() async throws {
        let session = EditorSession(project: makeProject())
        let initialRevision = await session.revision
        #expect(initialRevision.value == 0)

        let rev1 = try await session.dispatch(DummyCommand(note: "Step 1"))
        #expect(rev1.value == 1)
        #expect(await session.revision.value == 1)

        let rev2 = try await session.dispatch(DummyCommand(note: "Step 2"))
        #expect(rev2.value == 2)
        #expect(await session.revision.value == 2)
    }

    @Test("Dispatching with matching expectedRevision succeeds")
    func dispatchWithExpectedRevisionSucceeds() async throws {
        let session = EditorSession(project: makeProject())
        let snapshot = await session.snapshotWithRevision()

        let rev = try await session.dispatch(
            DummyCommand(note: "Valid"),
            expectedRevision: snapshot.revision
        )
        #expect(rev.value == 1)
    }

    @Test("Dispatching with stale expectedRevision is rejected without mutating state")
    func dispatchWithStaleRevisionFails() async throws {
        let session = EditorSession(project: makeProject())
        let staleSnapshot = await session.snapshotWithRevision()

        // User or background edit happens in the meantime
        _ = try await session.dispatch(DummyCommand(note: "Intervening Edit"))

        // Now dispatch with the old snapshot revision
        await #expect(throws: EditorCommandError.self) {
            try await session.dispatch(
                DummyCommand(note: "Stale Plan"),
                expectedRevision: staleSnapshot.revision
            )
        }

        // Project name remains the intervening edit
        let current = await session.snapshot()
        #expect(current.name == "Intervening Edit")
    }

    @Test("Undo and Redo advance the revision monotonically")
    func undoAndRedoAdvanceRevision() async throws {
        let session = EditorSession(project: makeProject())
        _ = try await session.dispatch(DummyCommand(note: "Edit 1"))
        let revAfterEdit = await session.revision.value
        #expect(revAfterEdit == 1)

        try await session.undo()
        let revAfterUndo = await session.revision.value
        #expect(revAfterUndo == 2)

        try await session.redo()
        let revAfterRedo = await session.revision.value
        #expect(revAfterRedo == 3)
    }
}
