import Foundation

/// The single owner of the flattened-timeline cache (Task 5.8).
///
/// This is the **one place** the cache lives. On a project change the
/// orchestrator (App layer) calls `update(for:)`, which computes the snapshot
/// once via the pure `CompoundFlattener.flatten` and stores it. The same
/// snapshot value is then handed to both `PlaybackEngine` and `ExportEngine`
/// through their `FlattenedTimelineConsumer` contract, so preview and export
/// render from byte-identical state.
///
/// Discipline enforced by design here:
///   - Flatten is called from `update(for:)`, never from a frame loop and never
///     from inside an engine.
///   - The cache holds exactly one snapshot per project identity; the value is
///     a `Sendable` struct handed out by reference-free copies.
///   - The engines do not recompute or self-cache; they receive the value.
public actor FlattenedTimelineCache {
    /// The cached snapshot, or nil if no project is bound.
    private var snapshot: FlattenedTimeline?

    /// The project identity the snapshot was computed for, or nil if unbound.
    private var boundProjectId: UUID?

    public init() {}

    /// Recomputes and stores the flattened snapshot for `project`. Call this
    /// once per project change (the orchestrator's responsibility), not per
    /// frame.
    public func update(for project: Project) {
        snapshot = CompoundFlattener.flatten(project)
        boundProjectId = project.id
    }

    /// Returns the current snapshot without recomputing. The orchestrator hands
    /// this same value to both engines.
    public func current() -> FlattenedTimeline? {
        snapshot
    }

    /// Returns the project identity the cache is bound to, or nil.
    public func projectId() -> UUID? {
        boundProjectId
    }

    /// Detaches the cache (e.g. on project close).
    public func clear() {
        snapshot = nil
        boundProjectId = nil
    }

    /// Hands the current snapshot to two consumers (the playback and export
    /// engines), proving they receive the identical value. This is the seam the
    /// orchestrator uses on a project change; it is exercised by the task-5.8
    /// parity test with stand-in consumers and by the orchestrator's
    /// integration with the real engines.
    public func distribute(
        to consumers: [any FlattenedTimelineConsumer],
        project: Project
    ) async {
        guard let snapshot, boundProjectId == project.id else { return }
        for consumer in consumers {
            await consumer.attach(project, flattened: snapshot)
        }
    }
}
