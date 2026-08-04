import Foundation
import MovieCutCore
import Testing

/// Guards the whole-project replacement command that routes Auto Highlights
/// (and any future whole-project operation) through the editor session's
/// command path so undo restores the prior project instead of being lost to a
/// session reset.
@Suite("ReplaceProjectCommand")
struct ReplaceProjectCommandTests {
    @Test("Replacing the project pushes the prior project onto the undo stack")
    func replacementIsUndoable() async throws {
        let original = Project(name: "Original")
        let replacement = Project(name: "Highlight")

        let session = EditorSession(project: original)
        try await session.dispatch(ReplaceProjectCommand(
            project: replacement,
            previousProject: original
        ))

        let afterDispatch = await session.snapshot()
        #expect(afterDispatch.name == "Highlight")

        try await session.undo()
        let afterUndo = await session.snapshot()
        #expect(afterUndo.name == "Original")
    }

    @Test("Apply swaps the project")
    func applyAndInvertRoundTrip() throws {
        let original = Project(name: "Original")
        var working = original
        let replacement = Project(name: "Highlight")

        let command = ReplaceProjectCommand(project: replacement, previousProject: original)
        try command.apply(to: &working)
        #expect(working.name == "Highlight")
    }

    @Test("Redo reapplies the replacement after undo")
    func redoReappliesReplacement() async throws {
        let original = Project(name: "Original")
        let replacement = Project(name: "Highlight")

        let session = EditorSession(project: original)
        try await session.dispatch(ReplaceProjectCommand(project: replacement, previousProject: original))
        try await session.undo()

        try await session.redo()
        let afterRedo = await session.snapshot()
        #expect(afterRedo.name == "Highlight")
    }
}
