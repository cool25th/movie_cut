import Foundation

/// The observable result of applying an editor command.
public struct CommandResult: Sendable, Equatable {
    /// Clip identifiers touched by the command.
    public let affectedClipIds: Set<UUID>

    /// A human-readable summary for diagnostics and undo labels.
    public let description: String

    /// Creates a command result.
    public init(affectedClipIds: Set<UUID> = [], description: String) {
        self.affectedClipIds = affectedClipIds
        self.description = description
    }
}
