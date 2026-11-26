import Foundation

/// P3 increment 2 — the applier: the bridge from typed agent actions to real
/// `EditorCommand`s applied through the session's proven contracts.
///
/// Contract (the agent-editing safety layer, pre-registered in CAPCUT_FEATURE
/// BACKLOG P3-01):
///   1. **Fail-closed**: every action in a script is validated (kernel
///      `plan()`) against the project BEFORE anything compiles or applies.
///      One invalid action rejects the whole script.
///   2. **Atomic**: the script compiles into a single
///      `EditingActionBatchCommand` — one `dispatch`, one undo unit, and the
///      batch itself applies to a draft so a mid-sequence failure cannot
///      mutate the session.
///   3. **Offline**: analysis-backed actions (`duckBackground`,
///      `removeSilence`) run the on-device `SpeechDuckingService` /
///      `SilenceDetectionProvider` — no provider, no network, ever.
///
/// The wire boundary for agents is `EditingActionDSL.decode` → this applier;
/// UI (and the future MCP surface) never hands raw timeline mutations to an
/// agent.
public enum EditingActionApplier {

    /// Typed failures that only occur at compile/apply time (the kernel's
    /// `PlanningError` covers everything knowable from the project alone).
    public enum ApplierError: Error, Equatable, Sendable {
        /// The clip references an asset id that is not in the media library.
        case assetMissing(UUID)
        /// The speech clip has no detectable voiced intervals to duck around.
        case noVoicedIntervals
    }

    /// What an applied script reports back to the calling surface.
    public struct ApplyReport: Equatable, Sendable {
        /// Actions in the applied script.
        public let actionCount: Int
        /// Real commands the script compiled to.
        public let commandCount: Int
        /// Undo units consumed — always 1 (the atomicity contract).
        public let undoUnits: Int
    }

    /// Validates every action first (fail-closed), then compiles the whole
    /// script into one batch command. Analysis-backed actions resolve their
    /// audio here, on-device.
    public static func compile(
        _ actions: [EditingActionDSL.Action],
        for project: Project
    ) async throws -> EditingActionBatchCommand {
        let prepared = try await EditingPlanCompiler.compile(
            actions,
            for: project,
            baseRevision: SessionRevision(),
            label: "agent plan (\(actions.count) action\(actions.count == 1 ? "" : "s"))"
        )
        return prepared.batchCommand
    }

    /// Applies a script to a session as ONE undo unit. Throws before any
    /// mutation if any action is invalid or any analysis fails.
    @discardableResult
    public static func apply(
        _ actions: [EditingActionDSL.Action],
        to session: EditorSession
    ) async throws -> ApplyReport {
        let (project, revision) = await session.snapshotWithRevision()
        let prepared = try await EditingPlanCompiler.compile(
            actions,
            for: project,
            baseRevision: revision,
            label: "agent plan (\(actions.count) action\(actions.count == 1 ? "" : "s"))"
        )
        let commandCount = prepared.batchCommand.commands.count
        try await session.dispatch(prepared.batchCommand, expectedRevision: revision)
        return ApplyReport(
            actionCount: actions.count,
            commandCount: commandCount,
            undoUnits: 1
        )
    }
}
