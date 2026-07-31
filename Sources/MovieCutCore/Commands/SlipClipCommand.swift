import Foundation

/// Slip moves only a clip's `sourceRange`: the same on-timeline span now plays a
/// different window of source media. The clip's `timelineRange` and the
/// timeline's total length are preserved. (Task 5.6, requirement 8.)
///
/// This command is the single undo unit for a slip. It reuses the locked-track
/// guard from `CommandSupport` (`Project.ensureTrackIsEditable`) exactly like
/// `TrimClipCommand`, and applies the pre-computed result of the pure
/// `ClipTrimMath.slip` function (task 5.5) so the command and the preview/export
/// paths can never disagree on the resulting source range.
///
/// The caller (the view-model / drag path) is responsible for running
/// `ClipTrimMath.slip(clip:sourceDelta:assetDuration:minimumSourceDuration:)`
/// — it is the one place that has the live `assetDuration` context — and handing
/// the resulting `source` range to this command. This mirrors how
/// `TrimClipCommand` takes ranges computed by `ClipTrimMath.compute`.
public struct SlipClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip being slipped.
    public var clipId: UUID

    /// The track expected to contain the clip.
    public var trackId: UUID?

    /// The new (already clamped) source range produced by `ClipTrimMath.slip`.
    /// Its duration equals the clip's current source duration; only `start`
    /// differs.
    public var newSourceRange: TimeRange

    /// Optional prior source range used when constructing an inverse command.
    public var previousSourceRange: TimeRange?

    /// Creates a slip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        trackId: UUID? = nil,
        newSourceRange: TimeRange,
        previousSourceRange: TimeRange? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.trackId = trackId
        self.newSourceRange = newSourceRange
        self.previousSourceRange = previousSourceRange
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = if let trackId {
            try project.clipLocation(for: clipId, in: trackId)
        } else {
            try project.clipLocation(for: clipId)
        }
        // Locked-track guard reused from CommandSupport, identical to the trim
        // path: a slip onto a locked track is rejected before any mutation.
        try project.ensureTrackIsEditable(at: location.trackIndex)

        guard newSourceRange.duration >= 0 else {
            throw EditorCommandError.invalidCommand("Slip source range cannot have a negative duration.")
        }

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].sourceRange = newSourceRange

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Slipped clip \(clipId)",
            undoValues: [
                "trackId": .uuid(project.timeline.tracks[location.trackIndex].id),
                "sourceRange": .timeRange(previousClip.sourceRange)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .uuid(let trackId)? = result.undoValues["trackId"],
            case .timeRange(let sourceRange)? = result.undoValues["sourceRange"]
        {
            return SlipClipCommand(
                clipId: clipId,
                trackId: trackId,
                newSourceRange: sourceRange
            )
        }

        guard let previousSourceRange else {
            return NoOpCommand(description: "Missing previous slip source range for inverse")
        }
        return SlipClipCommand(
            clipId: clipId,
            trackId: trackId,
            newSourceRange: previousSourceRange
        )
    }
}
