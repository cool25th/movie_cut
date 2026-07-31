import Foundation
import MovieCutCore

// MARK: - Slip / slide view-model entry points (task 5.6, requirement 8)
//
// These are the App-layer entry points that connect a timeline drag (with a
// keyboard modifier) to the slip / slide Core commands. They run the pure
// `ClipTrimMath.slip` / `ClipTrimMath.slide` math (task 5.5) — the single
// time-calculation authority already used by the trim path — and hand the
// resulting ranges to `SlipClipCommand` / `SlideClipCommand`, each dispatched
// as one undo unit via the existing `dispatchCommand` seam.
//
// Per the task's collision-avoidance rule this lives in a NEW extension file:
// `EditorViewModel.swift` itself is not modified, and no other agent's file is
// touched. The timeline gesture wiring (the SwiftUI `DragGesture` + modifier
// that calls `slipSelectedClip(sourceDelta:)` / `slideSelectedClip(timelineDelta:)`)
// lives in `TimelineView.swift`, a shared view. Per the task instructions, that
// shared view is NOT edited here; the orchestrator wires the gesture to these
// methods at the next integration pass (see "Gesture wiring" below).

extension EditorViewModel {
    // MARK: - Slip

    /// Slips the selected clip's source window by `sourceDelta` source seconds
    /// while keeping its timeline position and the timeline's total length
    /// fixed. No-op when nothing temporal is selected (image/text have no slip
    /// meaning) or when the clip's track is locked.
    ///
    /// Slip routes through `ClipTrimMath.slip` (the shared authority) and
    /// commits through `SlipClipCommand`, a single undo unit that reuses the
    /// locked-track guard. The resulting source range is the one the preview
    /// composition already reads, so preview and export agree by construction
    /// (requirement 8.4 / the task-2 parity gate).
    func slipSelectedClip(sourceDelta: TimeInterval) async {
        guard let clip = selectedClip,
              let trackId = selectedClipTrackId
        else { return }

        let minimum = Self.minimumTimelineClipDuration
        guard let result = ClipTrimMath.slip(
            clip: clip,
            sourceDelta: sourceDelta,
            assetDuration: assetDuration(forClipID: clip.id),
            minimumSourceDuration: minimum
        ) else {
            lastErrorMessage = "This clip has no source media to slip."
            return
        }

        do {
            try await dispatchCommand(
                SlipClipCommand(
                    clipId: clip.id,
                    trackId: trackId,
                    newSourceRange: result.source,
                    previousSourceRange: clip.sourceRange
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Slide

    /// Slides the selected clip by `timelineDelta` timeline seconds, trimming
    /// its adjacent neighbors' boundaries to keep the total timeline length
    /// constant. The clip's own source range and rendered span are preserved.
    /// No-op when the clip has no same-track neighbors to absorb the move, when
    /// the slide is not feasible, or when the track is locked.
    ///
    /// Slide routes through `ClipTrimMath.slide` (the shared authority, which
    /// consults `Clip.makeTimeMapping()` exactly like the trim path) and
    /// commits through `SlideClipCommand`, a single undo unit that reuses the
    /// locked-track guard. Target and neighbors are mutated together in one
    /// `apply`, so the project snapshot the session pushes for this command
    /// covers all of them at once.
    func slideSelectedClip(timelineDelta: TimeInterval) async {
        guard let clip = selectedClip,
              let trackId = selectedClipTrackId,
              let track = selectedClipTrack,
              let targetIndex = track.clips.firstIndex(where: { $0.id == clip.id })
        else { return }

        let minimum = Self.minimumTimelineClipDuration
        guard let result = ClipTrimMath.slide(
            clips: track.clips,
            targetIndex: targetIndex,
            timelineDelta: timelineDelta,
            minimumDuration: minimum
        ) else {
            lastErrorMessage = "Not enough room to slide this clip."
            return
        }

        // Each placement carries only a timeline range; the command keeps every
        // affected clip's own source range. The target's source is unchanged by
        // definition of slide; neighbors keep their source and just play a
        // longer/shorter span.
        let targetPlacement = SlideClipCommand.Placement(
            clipId: result.target.clipId,
            timeline: result.target.timeline
        )
        let neighborPlacements = result.neighbors.map {
            SlideClipCommand.Placement(clipId: $0.clipId, timeline: $0.timeline)
        }
        var previousClips: [UUID: Clip] = [clip.id: clip]
        for neighbor in result.neighbors {
            if let neighborClip = track.clips.first(where: { $0.id == neighbor.clipId }) {
                previousClips[neighbor.clipId] = neighborClip
            }
        }

        do {
            try await dispatchCommand(
                SlideClipCommand(
                    trackId: trackId,
                    target: targetPlacement,
                    neighbors: neighborPlacements,
                    previousClips: previousClips
                )
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Gesture wiring (orchestrator integration note)
    //
    // The actual SwiftUI gesture wiring intentionally does NOT live here. The
    // slip / slide modifiers are timeline interactions whose gesture state
    // (drag translation, snap points, `pixelsPerSecond`) is owned by
    // `TimelineView.swift`. That file is a shared view edited by other agents,
    // so per the task's collision-avoidance rule it is not modified here.
    //
    // Recommended wiring for the orchestrator at the next xcodegen/integration
    // pass (mirrors the existing `leftTrimGesture`/`rightTrimGesture` in
    // TimelineView.swift):
    //
    //   - Slip: option-drag on a clip body. In `moveGesture` (or a dedicated
    //     gesture), detect `.option` via the gesture's modifier phase and call
    //     `viewModel.slipSelectedClip(sourceDelta: dragDelta.width /
    //     pixelsPerSecond)` on `.onEnded`. Slip maps a timeline drag distance
    //     1:1 to source seconds (the clip's speed is already baked into the
    //     mapping the slip math consults), so no extra scaling is needed.
    //   - Slide: command-drag (or a dedicated slide cursor) on a clip body.
    //     Call `viewModel.slideSelectedClip(timelineDelta: dragDelta.width /
    //     pixelsPerSecond)` on `.onEnded`.
    //   - Both should commit once on drag end (not per tick) so each is a
    //     single undo unit; live preview during the drag can reuse the existing
    //     `updateClip` / drag-state machinery if desired, but the authoritative
    //     commit must go through these two methods.
}
