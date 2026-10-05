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

    /// Any user-facing or diagnostic warnings produced during compilation.
    public let warnings: [String]

    /// Creates a prepared edit plan.
    public init(
        planId: UUID = UUID(),
        baseRevision: SessionRevision,
        batchCommand: EditingActionBatchCommand,
        expectedDuration: TimeInterval,
        warnings: [String] = []
    ) {
        self.planId = planId
        self.baseRevision = baseRevision
        self.batchCommand = batchCommand
        self.expectedDuration = expectedDuration
        self.warnings = warnings
    }

    public static func == (lhs: PreparedEditPlan, rhs: PreparedEditPlan) -> Bool {
        lhs.planId == rhs.planId &&
        lhs.baseRevision == rhs.baseRevision &&
        lhs.expectedDuration == rhs.expectedDuration &&
        lhs.warnings == rhs.warnings
    }
}
