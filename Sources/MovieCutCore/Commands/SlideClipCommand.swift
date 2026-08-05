import Foundation

/// Slide moves a clip on the timeline and trims the adjacent neighbors'
/// boundaries to keep the total timeline length constant. The clip's own
/// `sourceRange` and rendered timeline duration are preserved. (Task 5.6,
/// requirement 8.)
///
/// This command is the single undo unit for a slide: the target clip and every
/// neighbor are mutated together in one `apply` call, so the project snapshot
/// the session pushes for this command covers all of them at once. It reuses
/// the locked-track guard from `CommandSupport`
/// (`Project.ensureTrackIsEditable`) exactly like the trim path, and applies
/// the pre-computed placements from the pure `ClipTrimMath.slide` function
/// (task 5.5) so the command and the preview/export paths can never disagree.
///
/// The caller (the view-model / drag path) runs
/// `ClipTrimMath.slide(clips:targetIndex:timelineDelta:minimumDuration:)` —
/// the one place with the full same-track clip set — and hands the resulting
/// `SlideResult` placements to this command. Only `timelineRange` updates are
/// written; each affected clip keeps its own `sourceRange` (the target's source
/// is unchanged by definition of slide; neighbors keep their source and just
/// play a longer/shorter span).
public struct SlideClipCommand: EditorCommand {
    /// One clip placement to write. Mirrors `ClipTrimMath.SlideClipPlacement`
    /// but carries only the data the command needs; placement order does not
    /// matter (each carries its own `clipId`).
    public struct Placement: Sendable, Equatable {
        /// The clip identifier this placement updates.
        public let clipId: UUID
        /// The new timeline range to write onto the clip.
        public let timeline: TimeRange

        public init(clipId: UUID, timeline: TimeRange) {
            self.clipId = clipId
            self.timeline = timeline
        }
    }

    /// The command identifier.
    public let id: UUID

    /// The track expected to contain the slid clip and its neighbors.
    public var trackId: UUID?

    /// The slid clip's new timeline placement.
    public var target: Placement

    /// Neighbor clips whose boundary was adjusted to absorb the move. May be
    /// empty (single clip / clamped to zero). Each must name a distinct clip id
    /// and none may equal `target.clipId`.
    public var neighbors: [Placement]

    /// Optional prior full-clip snapshots keyed by clip id, used when building
    /// an inverse command without an apply result (e.g. for cooperative undo).
    public var previousClips: [UUID: Clip]

    /// Creates a slide command.
    public init(
        id: UUID = UUID(),
        trackId: UUID?,
        target: Placement,
        neighbors: [Placement] = [],
        previousClips: [UUID: Clip] = [:]
    ) {
        self.id = id
        self.trackId = trackId
        self.target = target
        self.neighbors = neighbors
        self.previousClips = previousClips
    }

    public func apply(to project: inout Project) throws {
        // Resolve the track once via the target clip. clipLocation re-validates
        // that the clip still exists; the locked-track guard then runs on that
        // track, identical to the trim/slip path.
        let location = if let trackId {
            try project.clipLocation(for: target.clipId, in: trackId)
        } else {
            try project.clipLocation(for: target.clipId)
        }
        try project.ensureTrackIsEditable(at: location.trackIndex)
        let resolvedTrackId = project.timeline.tracks[location.trackIndex].id

        let placements = placementsById
        // Every named clip must be on the resolved track; a clip that moved
        // tracks (or vanished) between the caller's slide math and this apply
        // rejects rather than producing a half-applied state.
        var clipIndices: [UUID: Int] = [:]
        for (index, clip) in project.timeline.tracks[location.trackIndex].clips.enumerated() {
            if placements[clip.id] != nil {
                clipIndices[clip.id] = index
            }
        }
        guard clipIndices.count == placements.count else {
            throw EditorCommandError.invalidCommand(
                "Slide placements must all resolve to clips on the target track."
            )
        }

        // Apply every placement: only the timeline range is rewritten; each
        // clip keeps its own source range.
        for (clipId, clipIndex) in clipIndices {
            guard let placement = placements[clipId] else { continue }
            project.timeline.tracks[location.trackIndex].clips[clipIndex].timelineRange = placement.timeline
        }
    }

        // MARK: - Internals

    private var placementsById: [UUID: Placement] {
        var dictionary: [UUID: Placement] = [target.clipId: target]
        for neighbor in neighbors {
            // Defensive: a neighbor id colliding with the target is ignored so
            // the target's placement always wins. Duplicate neighbor ids collapse
            // to the last one (they should not occur — ClipTrimMath emits each
            // neighbor once).
            if neighbor.clipId == target.clipId { continue }
            dictionary[neighbor.clipId] = neighbor
        }
        return dictionary
    }

    private static let undoKeyPrefix = "clip:"
    private static func undoKey(for clipId: UUID) -> String {
        "\(undoKeyPrefix)\(clipId.uuidString)"
    }
}
