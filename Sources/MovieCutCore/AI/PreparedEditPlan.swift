import Foundation

/// The verified, executable output of an AI editing plan ready to be committed
/// to an `EditorSession`.
public struct PreparedEditPlan: Sendable, Equatable {
    /// Unique identifier for this prepared plan execution.
    public let planId: UUID

    /// The base session revision against which this plan was compiled and validated.
    public let baseRevision: SessionRevision

    /// The single atomic batch command wrapping all compiled mutations.
    public let batchCommand: EditingActionBatchCommand

    /// Expected timeline duration after applying this plan.
    public let expectedDuration: TimeInterval

    /// Net timeline duration change (`expectedDuration - beforeDuration`).
    public let durationDeltaSeconds: TimeInterval

    /// Number of high-level DSL actions compiled into this plan.
    public let actionCount: Int

    /// Distinct clip IDs directly targeted by the plan's actions.
    public let affectedClipCount: Int

    /// CA-35: true when at least one action in the plan is classified as destructive.
    public let containsDestructiveActions: Bool

    /// Human-readable summary lines describing what the plan will change.
    public let summaryLines: [String]

    /// Any user-facing or diagnostic warnings produced during compilation.
    public let warnings: [String]

    /// Creates a prepared edit plan.
    public init(
        planId: UUID = UUID(),
        baseRevision: SessionRevision,
        batchCommand: EditingActionBatchCommand,
        expectedDuration: TimeInterval,
        durationDeltaSeconds: TimeInterval = 0,
        actionCount: Int = 0,
        affectedClipCount: Int = 0,
        containsDestructiveActions: Bool = false,
        summaryLines: [String] = [],
        warnings: [String] = []
    ) {
        self.planId = planId
        self.baseRevision = baseRevision
        self.batchCommand = batchCommand
        self.expectedDuration = expectedDuration
        self.durationDeltaSeconds = durationDeltaSeconds
        self.actionCount = actionCount
        self.affectedClipCount = affectedClipCount
        self.containsDestructiveActions = containsDestructiveActions
        self.summaryLines = summaryLines
        self.warnings = warnings
    }

    public static func == (lhs: PreparedEditPlan, rhs: PreparedEditPlan) -> Bool {
        lhs.planId == rhs.planId &&
        lhs.baseRevision == rhs.baseRevision &&
        lhs.expectedDuration == rhs.expectedDuration &&
        lhs.durationDeltaSeconds == rhs.durationDeltaSeconds &&
        lhs.actionCount == rhs.actionCount &&
        lhs.affectedClipCount == rhs.affectedClipCount &&
        lhs.containsDestructiveActions == rhs.containsDestructiveActions &&
        lhs.summaryLines == rhs.summaryLines &&
        lhs.warnings == rhs.warnings
    }
}
