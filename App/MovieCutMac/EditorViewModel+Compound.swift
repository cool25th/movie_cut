import Foundation
import MovieCutCore

// MARK: - Compound clip view-model entry points (task 5.9, requirement 7)
//
// These are the App-layer entry points for Inc 1 compound clips (no internal
// editing — this is not "compound clip complete"; that is Inc 2). They gather
// the selection, validate the same-track / ≥2-clip precondition at the
// view-model layer for a friendly error, and dispatch the Core commands
// `CreateCompoundClipCommand` / `ReleaseCompoundClipCommand`, each a single
// undo unit via the existing `dispatchCommand` seam (one `EditorSession`
// snapshot per dispatch).
//
// Per the task's collision-avoidance rule this lives in a NEW extension file:
// `EditorViewModel.swift` itself is not modified, and no other agent's file is
// touched. The user-facing UI affordances (a "Create Compound" context-menu
// item / toolbar button in `TimelineView.swift`, and a "Release Compound" item)
// live in shared views edited by other agents, so per the task instructions
// they are NOT wired here; the orchestrator wires the controls to these
// methods at the next integration pass (see "UI wiring" below). The Core
// behavior is fully exercised by `CompoundClipCommandTests` regardless of UI.
//
// Inc 1 render path: once a container exists, the timeline is flattened once
// per project change by `CompoundFlattener.flatten` (task 5.8) into a
// `FlattenedTimeline` snapshot that both the `PlaybackEngine` and
// `ExportEngine` receive, so preview and export agree by construction
// (requirement 7.5). That cache wiring also lives with the orchestrator; this
// file only adds the create/release entry points.

extension EditorViewModel {
    // MARK: - Create

    /// Bundles the current multi-clip selection into a single compound clip
    /// container on the timeline (Requirement 7.1). Requires two or more
    /// selected clips all on the same editable track; otherwise sets a
    /// user-facing `lastErrorMessage` and returns.
    ///
    /// Single undo unit: the command is committed through `dispatchCommand`,
    /// which pushes one project snapshot. The container's children are stored
    /// with relative timeline ranges (see `CreateCompoundClipCommand`), so
    /// subsequent move/trim/copy of the container preserves the internal
    /// composition relatively (Requirement 7.2) — verified by the flatten pass.
    func createCompoundFromSelection() async {
        guard !selectedClipIds.isEmpty else {
            lastErrorMessage = "Select two or more clips to create a compound clip."
            return
        }

        // All selected clips must live on the same track; gather them and
        // confirm the track is editable.
        let selection = selectedClipIds
        var owningTrack: Track?
        var sameTrack = true
        for track in currentProject.timeline.tracks {
            let onTrack = track.clips.filter { selection.contains($0.id) }
            if !onTrack.isEmpty {
                if owningTrack == nil {
                    owningTrack = track
                } else if owningTrack?.id != track.id {
                    sameTrack = false
                    break
                }
            }
        }
        guard sameTrack, let track = owningTrack else {
            lastErrorMessage = "Compound clips can only be created from clips on the same track."
            return
        }
        if track.isLocked {
            lastErrorMessage = "Unlock the track to create a compound clip."
            return
        }

        // Resolve selection to clips on that track, in timeline order, and keep
        // only those actually present (the selection may include ids no longer
        // on the track after a concurrent edit). Order by timeline start so the
        // container's relative children are deterministic.
        let selected = track.clips
            .filter { selection.contains($0.id) }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
            .map(\.id)
        guard selected.count >= 2 else {
            lastErrorMessage = "Select two or more clips to create a compound clip."
            return
        }
        // Inc 1 forbids nesting; refuse if any selected clip is already a
        // container (the Core command also rejects this, but the message here
        // is friendlier and avoids a throw round-trip).
        if track.clips.contains(where: { selection.contains($0.id) && $0.compoundId != nil }) {
            lastErrorMessage = "A compound clip cannot contain another compound clip."
            return
        }

        do {
            let containerClipId = UUID()
            try await dispatchCommand(
                CreateCompoundClipCommand(
                    trackId: track.id,
                    clipIds: selected,
                    containerClipId: containerClipId
                )
            )
            selectedClipId = containerClipId
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Release

    /// Releases the selected compound clip back into its original constituent
    /// clips (Requirement 7.4). No-op (with a friendly message) when the
    /// selection is not a compound container. Single undo unit via
    /// `dispatchCommand`.
    func releaseSelectedCompound() async {
        guard let clip = selectedClip,
              let trackId = selectedClipTrackId,
              let compoundId = clip.compoundId
        else {
            lastErrorMessage = "Select a compound clip to release it."
            return
        }
        if let track = selectedClipTrack, track.isLocked {
            lastErrorMessage = "Unlock the track to release this compound clip."
            return
        }

        do {
            try await dispatchCommand(
                ReleaseCompoundClipCommand(
                    trackId: trackId,
                    containerClipId: clip.id,
                    compoundId: compoundId
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - UI wiring (orchestrator integration note)
    //
    // The user-facing affordances intentionally do NOT live here. Recommended
    // wiring for the orchestrator at the next xcodegen / integration pass,
    // mirroring the existing context-menu construction in `TimelineView.swift`:
    //
    //   - "Create Compound" item: enabled when `selectedClipIds.count >= 2` and
    //     all selected clips share one editable track; action calls
    //     `createCompoundFromSelection()`.
    //   - "Release Compound" item: enabled when `selectedClip?.compoundId !=
    //     nil`; action calls `releaseSelectedCompound()`.
    //
    // That shared view is edited by other agents and is not modified here per
    // the collision-avoidance rule. The Core behavior (single undo unit,
    // relative preservation, release restore) is verified by
    // `CompoundClipCommandTests` independent of the UI wiring.
    //
    // Render wiring (task 5.8): on the same project-change signal that already
    // drives preview/export refresh, the orchestrator should call
    // `FlattenedTimelineCache.update(for:)` and then `distribute(to:project:)`
    // with the playback and export engines (both conforming to
    // `FlattenedTimelineConsumer`). That is the single place the cache is
    // computed and the single source both engines read, fulfilling requirement
    // 7.5. The frame loop must NOT call flatten.
}
