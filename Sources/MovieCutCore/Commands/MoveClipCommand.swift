import Foundation

/// Moves a clip to a new timeline start and optionally to another track.
public struct MoveClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to move.
    public var clipId: UUID

    /// The destination track, or the current track when nil.
    public var targetTrackId: UUID?

    /// The new timeline start in seconds.
    public var newTimelineStart: TimeInterval

    /// Optional prior track identifier used when constructing an inverse command.
    public var previousTrackId: UUID?

    /// Optional prior timeline start used when constructing an inverse command.
    public var previousTimelineStart: TimeInterval?

    /// Creates a move-clip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        targetTrackId: UUID? = nil,
        newTimelineStart: TimeInterval,
        previousTrackId: UUID? = nil,
        previousTimelineStart: TimeInterval? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.targetTrackId = targetTrackId
        self.newTimelineStart = newTimelineStart
        self.previousTrackId = previousTrackId
        self.previousTimelineStart = previousTimelineStart
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        let currentTrackId = project.timeline.tracks[location.trackIndex].id
        let destinationTrackId = targetTrackId ?? currentTrackId
        let destinationTrackIndex = try project.trackIndex(for: destinationTrackId)
        try project.ensureTrackIsEditable(at: destinationTrackIndex)

        if location.trackIndex == destinationTrackIndex {
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].timelineRange.start = newTimelineStart
        } else {
            var clip = project.timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
            clip.timelineRange.start = newTimelineStart
            project.timeline.tracks[destinationTrackIndex].clips.append(clip)
        }

        return CommandResult(affectedClipIds: [clipId], description: "Moved clip \(clipId)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        guard let previousTimelineStart else {
            return NoOpCommand(description: "Missing previous clip position for inverse")
        }
        return MoveClipCommand(
            clipId: clipId,
            targetTrackId: previousTrackId,
            newTimelineStart: previousTimelineStart
        )
    }
}
