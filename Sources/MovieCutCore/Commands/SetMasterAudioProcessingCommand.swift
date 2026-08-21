import Foundation

/// Updates the project-level master audio processing preset.
///
/// `EditorSession` captures whole-project snapshots around every command, so
/// switching the preset remains undo/redo-safe without teaching the UI about
/// persistence or graph internals. `nil` is the explicit bypass/off state.
public struct SetMasterAudioProcessingCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new master processing preset, or nil to bypass the master chain.
    public var processing: MasterAudioProcessing?

    /// Creates a project-level master processing update command.
    public init(id: UUID = UUID(), processing: MasterAudioProcessing?) {
        self.id = id
        self.processing = processing
    }

    public func apply(to project: inout Project) throws {
        project.masterAudioProcessing = processing
    }
}
