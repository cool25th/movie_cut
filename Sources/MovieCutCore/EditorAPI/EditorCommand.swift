import Foundation

/// A serializable edit operation that can mutate a project through the editor session.
public protocol EditorCommand: Sendable {
    /// The command identifier.
    var id: UUID { get }

    /// Applies the command to a project.
    func apply(to project: inout Project) throws -> CommandResult

    /// Builds an inverse command from the apply result when enough information is available.
    func invert(from result: CommandResult) throws -> any EditorCommand
}
