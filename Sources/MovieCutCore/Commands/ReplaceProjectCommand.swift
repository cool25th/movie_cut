import Foundation

/// Swaps the entire project for a prebuilt replacement, capturing the previous
/// project so the editor session's snapshot-based undo can restore it.
///
/// This routes whole-project operations (e.g. Auto Highlights, which builds a
/// fresh highlight sequence) through the command path instead of replacing the
/// `EditorSession` directly. Replacing the session discarded the undo stack and
/// silenced Cmd+Z; dispatching this command pushes the previous project onto
/// the undo stack, so undo restores the pre-highlight project.
///
/// `invert` is implemented for completeness but is not on the live undo path —
/// `EditorSession` rolls back via whole-project snapshots, not by replaying
/// inverse commands.
public struct ReplaceProjectCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The replacement project to install.
    public var project: Project

    /// Optional prior project used when constructing an inverse command.
    public var previousProject: Project?

    /// Creates a whole-project replacement command.
    public init(id: UUID = UUID(), project: Project, previousProject: Project? = nil) {
        self.id = id
        self.project = project
        self.previousProject = previousProject
    }

    public func apply(to project: inout Project) throws {
        let previous = project
        project = self.project    }

    }
