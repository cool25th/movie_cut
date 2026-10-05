import Foundation

/// A structured editing production plan produced by a planning provider or montage generator.
public struct ProductionPlan: Sendable, Equatable, Codable {
    /// Unique identifier for this plan instance.
    public let planId: UUID

    /// Base session revision against which this plan was generated.
    public let baseRevision: SessionRevision

    /// Short human-readable summary of the user's intent.
    public let userIntent: String

    /// The target duration for the completed timeline in seconds.
    public let targetDuration: TimeInterval

    /// Desired canvas preset (e.g. 9:16 vertical), if requested.
    public let targetCanvas: CanvasPreset?

    /// Ordered list of typed editing actions to execute.
    public let actions: [EditingActionDSL.Action]

    /// Key assumptions made during planning (e.g. clip durations, transition styles).
    public let assumptions: [String]

    public init(
        planId: UUID = UUID(),
        baseRevision: SessionRevision,
        userIntent: String,
        targetDuration: TimeInterval,
        targetCanvas: CanvasPreset? = nil,
        actions: [EditingActionDSL.Action],
        assumptions: [String] = []
    ) {
        self.planId = planId
        self.baseRevision = baseRevision
        self.userIntent = userIntent
        self.targetDuration = targetDuration
        self.targetCanvas = targetCanvas
        self.actions = actions
        self.assumptions = assumptions
    }
}
