import Foundation

/// An actor that serializes project edits and owns undo/redo history.
public actor EditorSession {
    /// The current project state.
    public private(set) var project: Project

    /// The current monotonically increasing session revision.
    public private(set) var revision: SessionRevision

    private var undoStack: [Project] = []
    private var redoStack: [Project] = []

    /// Creates an editor session for a project.
    public init(project: Project, epoch: UUID = UUID(), initialRevision: UInt64 = 0) {
        self.project = project
        self.revision = SessionRevision(epoch: epoch, value: initialRevision)
    }

    /// Applies a command and records an undo snapshot.
    ///
    /// If `expectedRevision` is provided and does not match the session's current revision,
    /// the dispatch is aborted with `EditorCommandError.staleRevision` without mutating state.
    @discardableResult
    public func dispatch(
        _ command: any EditorCommand,
        expectedRevision: SessionRevision? = nil
    ) async throws -> SessionRevision {
        if let expected = expectedRevision, expected != revision {
            throw EditorCommandError.staleRevision(expected: expected, current: revision)
        }

        let previousProject = project
        try command.apply(to: &project)
        project.updatedAt = Date()
        undoStack.append(previousProject)
        redoStack.removeAll()
        revision = revision.advanced()
        return revision
    }

    /// U-08 AC③: the number of commands dispatched this session — each
    /// user-facing action (button click, menu item, drag-commit) routes
    /// through `dispatch`, so this count approximates the interaction step
    /// count for UX metrics (see docs/UI_METRICS.md).
    public var commandCount: Int {
        undoStack.count
    }

    /// Returns a value snapshot of the current project.
    public func snapshot() async -> Project {
        project
    }

    /// Returns a snapshot of the current project along with its exact session revision.
    public func snapshotWithRevision() async -> (project: Project, revision: SessionRevision) {
        (project, revision)
    }

    /// Restores the previous project snapshot.
    public func undo() async throws {
        guard let previousProject = undoStack.popLast() else {
            throw EditorCommandError.nothingToUndo
        }
        redoStack.append(project)
        project = previousProject
        revision = revision.advanced()
    }

    /// Restores the next project snapshot after an undo.
    public func redo() async throws {
        guard let nextProject = redoStack.popLast() else {
            throw EditorCommandError.nothingToRedo
        }
        undoStack.append(project)
        project = nextProject
        revision = revision.advanced()
    }
}
