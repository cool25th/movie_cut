import Foundation

/// An actor that serializes project edits and owns undo/redo history.
public actor EditorSession {
    /// The current project state.
    public private(set) var project: Project

    /// The current monotonically increasing session revision.
    public private(set) var revision: SessionRevision

    private var undoStack: [Project] = []
    private var redoStack: [Project] = []
    /// Cap on retained undo snapshots — the stack previously grew without
    /// bound (every dispatch retained a full `Project` copy for the whole
    /// session). When the cap trims old snapshots, `commandCount` keeps its
    /// cumulative semantics via `dispatchedCommandCount` below.
    public static let maxUndoHistory = 200
    /// Cumulative dispatch/undo/redo tally mirroring the uncapped
    /// `undoStack.count` semantics exactly: +1 per dispatch, −1 per undo,
    /// +1 per redo.
    private var dispatchedCommandCount = 0

    /// Plan ids that have already been applied successfully. Dispatching the
    /// same prepared plan twice (a lost-response retry or a double click)
    /// must not duplicate its clips — re-running the intent creates a NEW
    /// plan id, so rejecting a known id is always correct.
    private var appliedPlanIds: Set<UUID> = []

    /// Whether a plan with this id has already been applied in this session.
    public func hasApplied(planId: UUID) -> Bool {
        appliedPlanIds.contains(planId)
    }

    /// Creates an editor session for a project.
    public init(project: Project, epoch: UUID = UUID(), initialRevision: UInt64 = 0) {
        self.project = project
        self.revision = SessionRevision(epoch: epoch, value: initialRevision)
    }

    /// Applies a command and records an undo snapshot.
    ///
    /// If `expectedRevision` is provided and does not match the session's current revision,
    /// the dispatch is aborted with `EditorCommandError.staleRevision` without mutating state.
    /// If `planId` is provided and that plan was already applied, the dispatch
    /// is aborted with `EditorCommandError.duplicatePlanApplication`.
    @discardableResult
    public func dispatch(
        _ command: any EditorCommand,
        planId: UUID? = nil,
        expectedRevision: SessionRevision? = nil
    ) async throws -> SessionRevision {
        if let expected = expectedRevision, expected != revision {
            throw EditorCommandError.staleRevision(expected: expected, current: revision)
        }
        if let planId, appliedPlanIds.contains(planId) {
            throw EditorCommandError.duplicatePlanApplication(planId)
        }

        let previousProject = project
        try command.apply(to: &project)
        project.updatedAt = Date()
        undoStack.append(previousProject)
        dispatchedCommandCount += 1
        if undoStack.count > Self.maxUndoHistory {
            undoStack.removeFirst(undoStack.count - Self.maxUndoHistory)
        }
        redoStack.removeAll()
        revision = revision.advanced()
        if let planId {
            appliedPlanIds.insert(planId)
        }
        return revision
    }

    /// U-08 AC③: the number of commands dispatched this session — each
    /// user-facing action (button click, menu item, drag-commit) routes
    /// through `dispatch`, so this count approximates the interaction step
    /// count for UX metrics (see docs/UI_METRICS.md). Served from the
    /// cumulative tally, not the capped stack length, so trimming history
    /// cannot rewind the metric.
    public var commandCount: Int {
        dispatchedCommandCount
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
        dispatchedCommandCount = max(0, dispatchedCommandCount - 1)
        redoStack.append(project)
        project = previousProject
        revision = revision.advanced()
    }

    /// Restores the next project snapshot after an undo.
    public func redo() async throws {
        guard let nextProject = redoStack.popLast() else {
            throw EditorCommandError.nothingToRedo
        }
        dispatchedCommandCount += 1
        undoStack.append(project)
        project = nextProject
        revision = revision.advanced()
    }
}
