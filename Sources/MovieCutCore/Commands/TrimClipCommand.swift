import Foundation

/// Replaces a clip's source and timeline ranges.
public struct TrimClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to trim.
    public var clipId: UUID

    /// The track expected to contain the clip.
    public var trackId: UUID?

    /// The new source range.
    public var newSourceRange: TimeRange

    /// The new timeline range.
    public var newTimelineRange: TimeRange

    /// Optional prior source range used when constructing an inverse command.
    public var previousSourceRange: TimeRange?

    /// Optional prior timeline range used when constructing an inverse command.
    public var previousTimelineRange: TimeRange?

    /// Phase 0 compatibility alias for the new source range.
    public var sourceRange: TimeRange {
        get { newSourceRange }
        set { newSourceRange = newValue }
    }

    /// Phase 0 compatibility alias for the new timeline range.
    public var timelineRange: TimeRange {
        get { newTimelineRange }
        set { newTimelineRange = newValue }
    }

    /// Creates a trim command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        trackId: UUID? = nil,
        newSourceRange: TimeRange,
        newTimelineRange: TimeRange,
        previousSourceRange: TimeRange? = nil,
        previousTimelineRange: TimeRange? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.trackId = trackId
        self.newSourceRange = newSourceRange
        self.newTimelineRange = newTimelineRange
        self.previousSourceRange = previousSourceRange
        self.previousTimelineRange = previousTimelineRange
    }

    /// Creates a trim command using Phase 0 argument labels.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        previousSourceRange: TimeRange? = nil,
        previousTimelineRange: TimeRange? = nil
    ) {
        self.init(
            id: id,
            clipId: clipId,
            trackId: nil,
            newSourceRange: sourceRange,
            newTimelineRange: timelineRange,
            previousSourceRange: previousSourceRange,
            previousTimelineRange: previousTimelineRange
        )
    }

    public func apply(to project: inout Project) throws {
        let location = if let trackId {
            try project.clipLocation(for: clipId, in: trackId)
        } else {
            try project.clipLocation(for: clipId)
        }
        try project.ensureTrackIsEditable(at: location.trackIndex)

        guard newSourceRange.duration >= 0, newTimelineRange.duration >= 0 else {
            throw EditorCommandError.invalidCommand("Trim ranges cannot have negative durations.")
        }

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].sourceRange = newSourceRange
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].timelineRange = newTimelineRange
    }

    }
