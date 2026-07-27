import Foundation

/// Atomically changes a clip's playback speed AND reconciles its rendered
/// timeline duration, ripples the main video track, and clamps stale
/// clip-local time fields — all in one undo step (the editor session snapshots
/// the whole project).
///
/// Before this command existed, `SetClipPropertyCommand` mutated only
/// `playbackRate` / `speedRampPoints` and left `timelineRange.duration` stale,
/// so the timeline width, snap points, marker positions, transition/fade
/// durations, ducking ranges, and the start of the next clip on the magnetic
/// main track all drifted out of sync with what Playback/Export actually
/// rendered. Step 4 of the core-editing repair handoff.
public struct SetClipSpeedCommand: EditorCommand {
    /// The speed change to apply.
    public enum SpeedChange: Sendable, Equatable {
        /// A constant playback rate (clamped to 0.25x...4.0x).
        case constantRate(Double)
        /// Speed-ramp control points (replaces any existing ramp; an empty or
        /// single-point array clears the ramp and falls back to constant rate).
        case rampPoints([SpeedRampPoint])
    }

    /// The command identifier.
    public let id: UUID

    /// The clip whose speed is changing.
    public var clipId: UUID

    /// The track expected to contain the clip (nil = search all tracks).
    public var trackId: UUID?

    /// The speed change to apply.
    public var change: SpeedChange

    /// Creates a speed-change command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        trackId: UUID? = nil,
        change: SpeedChange
    ) {
        self.id = id
        self.clipId = clipId
        self.trackId = trackId
        self.change = change
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = if let trackId {
            try project.clipLocation(for: clipId, in: trackId)
        } else {
            try project.clipLocation(for: clipId)
        }
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let oldClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        let trackIdValue = project.timeline.tracks[location.trackIndex].id

        var newClip = oldClip
        switch change {
        case .constantRate(let rate):
            newClip.playbackRate = min(max(rate, 0.25), 4.0)
            // A constant-rate change clears any existing ramp so the two don't
            // disagree (the mapping prefers ramp points when count >= 2).
            newClip.speedRampPoints = []
        case .rampPoints(let points):
            newClip.speedRampPoints = points
            // Keep playbackRate as the identity baseline / fallback for paths
            // that read it before consulting the mapping; it is not used when
            // ramp points are present (>= 2).
        }

        // Derive the new rendered timeline duration from the canonical mapping.
        // For freeze-frames and image clips the stored timelineRange.duration
        // is the authority (the mapping returns it as-is), so the speed change
        // leaves the duration unchanged — only the rate field moves.
        let newDuration: TimeInterval
        if let mapping = newClip.makeTimeMapping() {
            newDuration = mapping.renderedTimelineDuration
        } else {
            newDuration = oldClip.timelineRange.duration
        }

        newClip.timelineRange = TimeRange(
            start: oldClip.timelineRange.start,
            duration: newDuration
        )

        // Reconcile stale clip-local time fields to the new duration.
        newClip.clampTimeFields(to: newDuration)

        project.timeline.tracks[location.trackIndex].clips[location.clipIndex] = newClip

        // Ripple the magnetic main video track so subsequent clips close the gap
        // (or open space) left by the duration change. Free tracks keep their
        // offsets (Step 2 contract).
        if project.isMagneticTrack(trackIdValue) {
            try project.compactTrackMagnetically(trackIdValue)
            try project.normalizeClipZIndexes(in: trackIdValue)
        }

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set clip speed for \(clipId)",
            undoValues: [
                "trackId": .uuid(trackIdValue),
                "clip": .clip(oldClip)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        // The editor session restores the whole-project snapshot on undo, so
        // this invert is a best-effort restore of the original clip for any
        // composed-command path that uses it directly.
        if
            case .uuid(let trackId)? = result.undoValues["trackId"],
            case .clip(let oldClip)? = result.undoValues["clip"]
        {
            // Restore the prior speed fields by inferring the change kind.
            let restoreChange: SpeedChange
            if oldClip.speedRampPoints.count >= 2 {
                restoreChange = .rampPoints(oldClip.speedRampPoints)
            } else {
                restoreChange = .constantRate(oldClip.playbackRate)
            }
            return SetClipSpeedCommand(clipId: clipId, trackId: trackId, change: restoreChange)
        }
        return SetClipSpeedCommand(clipId: clipId, trackId: trackId, change: change)
    }
}
