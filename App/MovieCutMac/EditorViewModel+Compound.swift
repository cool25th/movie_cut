import Foundation
import MovieCutCore

// MARK: - Compound clip view-model entry points (Inc 1 & Inc 2)
//
// Extends EditorViewModel with compound creation, release, and Phase 2 nested
// timeline navigation (enter/exit, breadcrumbs, virtual timeline display, and
// internal constituent edits).

extension EditorViewModel {
    // MARK: - Navigation & Breadcrumbs (Inc 2)

    /// Current navigation breadcrumbs for the timeline header.
    var timelineBreadcrumbs: [TimelineBreadcrumb] {
        var items: [TimelineBreadcrumb] = [
            .root(projectName: currentProject.name)
        ]

        if case let .compound(id, name) = timelineContext {
            items.append(.compound(id: id, name: name))
        }

        return items
    }

    /// The timeline structure currently visible and editable in the timeline view.
    /// Returns the root project timeline when at the root level, or a virtual
    /// track structure derived from the active compound's constituent child clips.
    var displayedTimeline: Timeline {
        switch timelineContext {
        case .root:
            return currentProject.timeline
        case let .compound(id, _):
            if let compound = currentProject.compounds.first(where: { $0.id == id }) {
                return CompoundTimelineConverter.makeVirtualTimeline(
                    from: compound,
                    frameRate: currentProject.timeline.frameRate
                )
            }
            return currentProject.timeline
        }
    }

    /// Enters into a compound clip's internal sequence for nested editing (Inc 2).
    func enterCompound(id: UUID) {
        guard let compound = currentProject.compounds.first(where: { $0.id == id }) else {
            lastErrorMessage = "Compound definition not found."
            return
        }

        timelineContext = .compound(id: id, name: compound.name)
        selectedClipId = nil
        selectedClipIds = []
        lastStatusMessage = "Editing compound clip: \(compound.name)"
    }

    /// Exits the nested compound timeline and returns to the parent root timeline (Inc 2).
    func exitToParentTimeline() {
        timelineContext = .root
        selectedClipId = nil
        selectedClipIds = []
        lastStatusMessage = nil
    }

    /// Navigates to a specific breadcrumb in the timeline trail.
    func navigateToBreadcrumb(_ breadcrumb: TimelineBreadcrumb) {
        switch breadcrumb.context {
        case .root:
            exitToParentTimeline()
        case let .compound(id, _):
            enterCompound(id: id)
        }
    }

    /// Updates the constituent child clips of the currently active compound definition (Inc 2).
    func updateCurrentCompoundChildren(_ newChildren: [Clip]) async {
        guard case let .compound(id, _) = timelineContext,
              let compound = currentProject.compounds.first(where: { $0.id == id })
        else {
            return
        }

        do {
            try await dispatchCommand(
                UpdateCompoundChildrenCommand(
                    compoundId: id,
                    newChildClips: newChildren,
                    oldChildClips: compound.childClips
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Create (Inc 1)

    /// Bundles the current multi-clip selection into a single compound clip
    /// container on the timeline (Requirement 7.1). Requires two or more
    /// selected clips all on the same editable track; otherwise sets a
    /// user-facing `lastErrorMessage` and returns.
    func createCompoundFromSelection() async {
        guard !selectedClipIds.isEmpty else {
            lastErrorMessage = "Select two or more clips to create a compound clip."
            return
        }

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

        let selected = track.clips
            .filter { selection.contains($0.id) }
            .sorted { $0.timelineRange.start < $1.timelineRange.start }
            .map(\.id)
        guard selected.count >= 2 else {
            lastErrorMessage = "Select two or more clips to create a compound clip."
            return
        }

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

    // MARK: - Release (Inc 1)

    /// Releases the selected compound clip back into its original constituent
    /// clips (Requirement 7.4). No-op when the selection is not a compound container.
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
}
