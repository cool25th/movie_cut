import Foundation

/// G-26 (spec §6·§7) — sets the project's master audio processing preset.
/// The graph builder expands the preset into the master bus (the chain's
/// full parameters + the §6 preset algorithm version + the limiter's
/// latency declaration), and both render paths consume the serialized
/// chain — preview meter and export render it identically by construction.
public struct SetMasterAudioProcessingCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The preset to install; nil disables master processing.
    public var preset: MasterAudioProcessing?

    /// Optional prior preset used when constructing an inverse command.
    public var previousPreset: MasterAudioProcessing?

    public init(
        id: UUID = UUID(),
        preset: MasterAudioProcessing?,
        previousPreset: MasterAudioProcessing? = nil
    ) {
        self.id = id
        self.preset = preset
        self.previousPreset = previousPreset
    }

    public func apply(to project: inout Project) throws {
        project.masterAudioProcessing = preset
    }
}
