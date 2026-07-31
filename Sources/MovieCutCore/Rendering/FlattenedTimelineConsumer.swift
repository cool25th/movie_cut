import Foundation

/// A rendering consumer that reads a `FlattenedTimeline` snapshot produced by
/// the single-source flattener (Task 5.8, Requirement 7.5).
///
/// This protocol is the **wiring contract** for the parity claim. Both
/// `PlaybackEngine` and `ExportEngine` adopt it (via the orchestrator's wiring,
/// since those types live in the App target). The contract is intentionally
/// minimal:
///
///   - The consumer accepts a snapshot via `attach(_:flattened:)` and stores it
///     verbatim. It does **not** call `CompoundFlattener.flatten` itself and
///     keeps **no own cache**; the snapshot it holds is exactly the one passed
///     in, so two consumers handed the same value hold identical state.
///   - The consumer exposes the snapshot it currently holds so a test can pin
///     that the playback and export engines received the byte-identical
///     `FlattenedTimeline` (the basis of the preview↔export parity claim).
///
/// The orchestrator computes the snapshot once on project change and calls
/// `attach` on both engines with the same value. The frame loops of both
/// engines then read from that stored snapshot rather than re-flattening.
public protocol FlattenedTimelineConsumer: AnyObject, Sendable {
    /// The project this consumer is currently bound to, or nil if detached.
    /// Async so that actor-backed consumers (the engines) can conform without
    /// crossing isolation boundaries.
    func boundProjectId() async -> UUID?

    /// Stores the single-source flattened snapshot. Called by the orchestrator
    /// (the only caller); never by the consumer itself. Implementations must
    /// store the value as-is without re-deriving it.
    func attach(_ project: Project, flattened: FlattenedTimeline) async

    /// Returns the snapshot this consumer currently holds, so a test can verify
    /// two consumers hold identical state. Returns nil before the first
    /// `attach`.
    func currentFlattenedTimeline() async -> FlattenedTimeline?
}

/// Diagnostic helper proving the parity invariant holds for two consumers:
/// they hold the **identical** `FlattenedTimeline`. Used by the task-5.8 pin
/// test and available to the orchestrator's integration tests.
public enum FlattenedTimelineParity {
    /// Returns true iff `a` and `b` are both attached to `projectId` and report
    /// the exact same snapshot (by `contentDigest` and structural equality).
    public static func bothHoldIdentical(
        for projectId: UUID,
        _ a: any FlattenedTimelineConsumer,
        _ b: any FlattenedTimelineConsumer
    ) async -> Bool {
        async let aBound = a.boundProjectId()
        async let bBound = b.boundProjectId()
        guard await aBound == projectId, await bBound == projectId else {
            return false
        }
        guard let snapshotA = await a.currentFlattenedTimeline(),
              let snapshotB = await b.currentFlattenedTimeline() else {
            return false
        }
        // Structural equality covers every field; the digest is a redundant
        // cross-check that a cheap comparison would agree.
        return snapshotA == snapshotB && snapshotA.contentDigest == snapshotB.contentDigest
    }
}
