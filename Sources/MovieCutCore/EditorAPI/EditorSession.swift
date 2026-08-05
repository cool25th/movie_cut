import Foundation

/// An actor that serializes project edits and owns undo/redo history.
public actor EditorSession {
    /// The current project state.
    public private(set) var project: Project

    private var undoStack: [Project] = []
    private var redoStack: [Project] = []

    /// Creates an editor session for a project.
    public init(project: Project) {
        self.project = project
    }

    /// Applies a command and records an undo snapshot.
    public func dispatch(_ command: any EditorCommand) async throws {
        let previousProject = project
        try command.apply(to: &project)
        project.updatedAt = Date()
        undoStack.append(previousProject)
        redoStack.removeAll()
    }

    /// Returns a value snapshot of the current project.
    public func snapshot() async -> Project {
        project
    }

    /// Restores the previous project snapshot.
    public func undo() async throws {
        guard let previousProject = undoStack.popLast() else {
            throw EditorCommandError.nothingToUndo
        }
        redoStack.append(project)
        project = previousProject
    }

    /// Restores the next project snapshot after an undo.
    public func redo() async throws {
        guard let nextProject = redoStack.popLast() else {
            throw EditorCommandError.nothingToRedo
        }
        undoStack.append(project)
        project = nextProject
    }
}
