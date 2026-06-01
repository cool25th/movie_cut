import Foundation

/// Replaces a clip's source and timeline ranges.
public struct TrimClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to trim.
    public var clipId: UUID

    /// The new source range.
    public var sourceRange: TimeRange

    /// The new timeline range.
    public var timelineRange: TimeRange

    /// Optional prior source range used when constructing an inverse command.
    public var previousSourceRange: TimeRange?

    /// Optional prior timeline range used when constructing an inverse command.
    public var previousTimelineRange: TimeRange?

    /// Creates a trim command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        previousSourceRange: TimeRange? = nil,
        previousTimelineRange: TimeRange? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.sourceRange = sourceRange
        self.timelineRange = timelineRange
        self.previousSourceRange = previousSourceRange
        self.previousTimelineRange = previousTimelineRange
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].sourceRange = sourceRange
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].timelineRange = timelineRange
        return CommandResult(affectedClipIds: [clipId], description: "Trimmed clip \(clipId)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        guard let previousSourceRange, let previousTimelineRange else {
            return NoOpCommand(description: "Missing previous trim ranges for inverse")
        }
        return TrimClipCommand(
            clipId: clipId,
            sourceRange: previousSourceRange,
            timelineRange: previousTimelineRange
        )
    }
}
