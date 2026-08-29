import Foundation

/// G-26 (spec §6·§7) — updates the project-level master audio processing
/// preset. The graph builder expands the preset into the master bus (the
/// chain's full parameters + the §6 preset algorithm version + the limiter's
/// latency declaration), and both render paths consume the serialized chain —
/// preview meter and export render it identically by construction.
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
