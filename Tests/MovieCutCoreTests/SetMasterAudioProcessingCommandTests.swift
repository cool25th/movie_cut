import Foundation
import Testing
@testable import MovieCutCore

@Suite("Set Master Audio Processing Command")
struct SetMasterAudioProcessingCommandTests {
    @Test("command changes only the project master processing preset")
    func commandChangesOnlyMasterProcessingPreset() throws {
        var project = Project(name: "Master Audio")
        let original = project

        try SetMasterAudioProcessingCommand(processing: .sns).apply(to: &project)

        var expected = original
        expected.masterAudioProcessing = .sns
        #expect(project == expected)
    }

    @Test("session undo and redo round-trip on and off states")
    func sessionUndoRedoRoundTripsPreset() async throws {
        let session = EditorSession(project: Project(name: "Master Audio"))

        try await session.dispatch(SetMasterAudioProcessingCommand(processing: .sns))
        #expect(await session.snapshot().masterAudioProcessing == .sns)

        try await session.undo()
        #expect(await session.snapshot().masterAudioProcessing == nil)

        try await session.redo()
        #expect(await session.snapshot().masterAudioProcessing == .sns)

        try await session.dispatch(SetMasterAudioProcessingCommand(processing: nil))
        #expect(await session.snapshot().masterAudioProcessing == nil)

        try await session.undo()
        #expect(await session.snapshot().masterAudioProcessing == .sns)
    }
}
