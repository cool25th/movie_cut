import Foundation

/// Bundles a set of same-track clips into a single compound clip container
/// (Task 5.9, Requirement 7.1 / 7.7). Inc 1 — no internal editing, no nesting.
///
/// What this single undo unit does, atomically:
///   1. Validates the inputs (≥2 clips, all on `trackId`, none already a
///      container — nesting is forbidden by `validateCompounds` at load, and we
///      refuse to create it here too).
///   2. Captures the **previous track clips** and the **previous compounds
///      list** so the inverse can restore exactly.
///   3. Removes the selected clips from the track and inserts one container
///      clip in their place, positioned at the earliest selected clip's
///      timeline start and spanning the union of their timeline spans.
///   4. Adds a new `CompoundDefinition` whose `childClips` are the selected
///      clips with their `timelineRange` re-expressed **relative to the
///      container's start** and with `compoundId == nil` (no nesting). The
///      children otherwise retain their source ranges, kinds, transforms, etc.
///
/// The container's `compoundId` references the new definition. The flatten pass
/// (task 5.8) re-expands the container on render, so moving/trimming/copying
/// the container preserves the internal composition relatively (Requirement 7.2)
/// and the timeline displays a single clip (Requirement 7.1).
public struct CreateCompoundClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The track holding the clips to bundle.
    public var trackId: UUID

    /// The ids of the clips to bundle, in source order. At least two required.
    public var clipIds: [UUID]

    /// The id to assign the new compound definition (and the container's
    /// `compoundId`). Defaults to a fresh UUID.
    public var compoundId: UUID

    /// Optional explicit container clip id / name; defaults are generated.
    public var containerClipId: UUID
    public var compoundName: String

    public init(
        id: UUID = UUID(),
        trackId: UUID,
        clipIds: [UUID],
        compoundId: UUID = UUID(),
        containerClipId: UUID = UUID(),
        compoundName: String = "Compound"
    ) {
        self.id = id
        self.trackId = trackId
        self.clipIds = clipIds
        self.compoundId = compoundId
        self.containerClipId = containerClipId
        self.compoundName = compoundName
    }

    public func apply(to project: inout Project) throws {
        guard clipIds.count >= 2 else {
            throw EditorCommandError.invalidCommand(
                "A compound clip requires at least two clips."
            )
        }
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)

        // Resolve each requested id to a clip on this track, preserving the
        // caller's order. An unknown id, or an id that lives on another track,
        // is rejected before any mutation (atomic).
        let idSet = Set(clipIds)
        guard idSet.count == clipIds.count else {
            throw EditorCommandError.invalidCommand("Duplicate clip ids in compound request.")
        }
        var selected: [Clip] = []
        selected.reserveCapacity(clipIds.count)
        for clipId in clipIds {
            guard let clip = project.timeline.tracks[trackIndex].clips
                .first(where: { $0.id == clipId }) else {
                throw EditorCommandError.clipNotFound(clipId)
            }
            if clip.compoundId != nil {
                // Refuse to nest: a container cannot itself become a child.
                throw EditorCommandError.invalidCommand(
                    "A compound clip cannot contain another compound clip."
                )
            }
            selected.append(clip)
        }

        let previousTrackClips = project.timeline.tracks[trackIndex].clips
        let previousCompounds = project.compounds

        // Container placement: earliest start, union span.
        let earliestStart = selected.map(\.timelineRange.start).min() ?? 0
        let latestEnd = selected.map(\.timelineRange.end).max() ?? earliestStart
        let unionSpan = max(0, latestEnd - earliestStart)

        // Children with timelineRange made relative to the container start.
        // compoundId is left nil (no nesting); everything else is preserved.
        let children = selected.map { clip -> Clip in
            var child = clip
            child.timelineRange = TimeRange(
                start: clip.timelineRange.start - earliestStart,
                duration: clip.timelineRange.duration
            )
            child.compoundId = nil
            return child
        }

        // The container is a minimal placeholder clip: its timelineRange is the
        // union span, sourceRange matches it (the flatten pass ignores the
        // container's own source in favor of the children). kind matches the
        // common case among the selected clips.
        let containerKind = selected.first?.kind ?? .video
        let container = Clip(
            id: containerClipId,
            kind: containerKind,
            sourceRange: TimeRange(start: 0, duration: unionSpan),
            timelineRange: TimeRange(start: earliestStart, duration: unionSpan),
            compoundId: compoundId
        )

        // Replace the selected clips in-place: remove all of them, then insert
        // the container where the earliest one began (preserve relative order
        // of any non-selected clips).
        var remaining = previousTrackClips.filter { !idSet.contains($0.id) }
        let insertIndex = remaining.firstIndex(where: { $0.timelineRange.start >= earliestStart }) ?? remaining.count
        remaining.insert(container, at: insertIndex)
        project.timeline.tracks[trackIndex].clips = remaining

        // Register the definition.
        let definition = CompoundDefinition(
            id: compoundId,
            name: compoundName,
            childClips: children
        )
        project.compounds.append(definition)

    }
}

/// Releases a compound clip back into its original constituent clips (Task 5.9,
/// Requirement 7.4 / 7.7). Single undo unit.
///
/// Used both as a user-facing command (release a compound) and as the inverse
/// of `CreateCompoundClipCommand`. It removes the container clip from its
/// track, restores the prior track clips (the originals, with their absolute
/// timeline ranges), and removes (or, when constructed with explicit restore
/// data, restores the prior list of) the compound definition.
public struct ReleaseCompoundClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The track holding the container clip to release.
    public var trackId: UUID

    /// The container clip to dissolve.
    public var containerClipId: UUID

    /// The compound definition this container references.
    public var compoundId: UUID

    /// When nil, release expands the definition's children onto the track at
    /// the container's timeline start (the user-facing release). When non-nil
    /// (set by the create-command inverse), this is the exact prior state to
    /// restore, so undo of create is byte-exact.
    public var restoreTrackClips: [Clip]?

    /// Prior compounds list to restore on release; when nil, the definition is
    /// simply removed. Set by the create-command inverse.
    public var restoreCompounds: [CompoundDefinition]?

    public init(
        id: UUID = UUID(),
        trackId: UUID,
        containerClipId: UUID,
        compoundId: UUID,
        restoreTrackClips: [Clip]? = nil,
        restoreCompounds: [CompoundDefinition]? = nil
    ) {
        self.id = id
        self.trackId = trackId
        self.containerClipId = containerClipId
        self.compoundId = compoundId
        self.restoreTrackClips = restoreTrackClips
        self.restoreCompounds = restoreCompounds
    }

    public func apply(to project: inout Project) throws {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)

        guard let containerIndex = project.timeline.tracks[trackIndex].clips
            .firstIndex(where: { $0.id == containerClipId }) else {
            throw EditorCommandError.clipNotFound(containerClipId)
        }
        let container = project.timeline.tracks[trackIndex].clips[containerIndex]
        guard container.compoundId == compoundId else {
            throw EditorCommandError.invalidCommand(
                "Clip \(containerClipId) does not reference compound \(compoundId)."
            )
        }

        let previousTrackClips = project.timeline.tracks[trackIndex].clips
        let previousCompounds = project.compounds

        if let restoreTrackClips {
            // Byte-exact restore path (create-command inverse).
            project.timeline.tracks[trackIndex].clips = restoreTrackClips
        } else {
            // User-facing release: expand the children at the container's start.
            guard let definition = project.compounds.first(where: { $0.id == compoundId }) else {
                throw EditorCommandError.invalidCommand(
                    "Compound definition \(compoundId) not found."
                )
            }
            var rebuilt = previousTrackClips
            rebuilt.remove(at: containerIndex)
            // Expand exactly the same visible child window used by playback
            // and export flattening. This preserves container move/trim edits
            // when the user releases the compound instead of resurrecting
            // trimmed-away child ranges.
            let expanded = CompoundFlattener.visibleChildren(
                of: definition,
                in: container
            )
            // Insert expanded clips where the container was, in definition order.
            for (offset, child) in expanded.enumerated() {
                rebuilt.insert(child, at: containerIndex + offset)
            }
            project.timeline.tracks[trackIndex].clips = rebuilt
        }

        // Remove (or restore) the definition.
        if let restoreCompounds {
            project.compounds = restoreCompounds
        } else {
            project.compounds.removeAll { $0.id == compoundId }
        }
    }
}

/// Internal byte-exact restore used as the inverse of `ReleaseCompoundClipCommand`.
/// Replays the captured pre-release track clips and compounds list verbatim,
/// which restores the container. Not directly invertible (the inverse-of-inverse
/// rebuilds via the public commands).
struct RestoreCompoundContainerCommand: EditorCommand {
    let id = UUID()
    let trackId: UUID
    let restoreTrackClips: [Clip]
    let restoreCompounds: [CompoundDefinition]

    func apply(to project: inout Project) throws {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)
        project.timeline.tracks[trackIndex].clips = restoreTrackClips
        project.compounds = restoreCompounds
    }
}
