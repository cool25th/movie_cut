import Foundation

/// P3 increment 2: applies a compiled agent script as ONE command. The whole
/// sequence applies to a draft project and is committed only if every inner
/// command succeeds, so a mid-sequence throw leaves the session's project
/// untouched (all-or-nothing), and one `dispatch` means one undo unit.
public struct EditingActionBatchCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The inner commands, applied in order.
    public let commands: [any EditorCommand]

    /// A human/agent-readable label for diagnostics (e.g. "agent plan (3 actions)").
    public let label: String

    /// Creates a batch command.
    public init(
        id: UUID = UUID(),
        label: String = "EditingActionBatch",
        commands: [any EditorCommand]
    ) {
        self.id = id
        self.label = label
        self.commands = commands
    }

    public func apply(to project: inout Project) throws {
        var draft = project
        for command in commands {
            try command.apply(to: &draft)
        }
        project = draft
    }
}
