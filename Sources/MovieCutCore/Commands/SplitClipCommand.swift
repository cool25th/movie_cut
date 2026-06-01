import Foundation

/// Splits a clip into two clips at a timeline time.
public struct SplitClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to split.
    public var clipId: UUID

    /// The timeline split time in seconds.
    public var splitTime: TimeInterval

    /// The identifier assigned to the new trailing clip.
    public var newClipId: UUID

    /// Creates a split command.
    public init(id: UUID = UUID(), clipId: UUID, splitTime: TimeInterval, newClipId: UUID = UUID()) {
        self.id = id
        self.clipId = clipId
        self.splitTime = splitTime
        self.newClipId = newClipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let clip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        guard splitTime > clip.timelineRange.start, splitTime < clip.timelineRange.end else {
            throw EditorCommandError.invalidCommand("Split time must be inside the clip range.")
        }

        let firstDuration = splitTime - clip.timelineRange.start
        let secondDuration = clip.timelineRange.end - splitTime
        var firstClip = clip
        firstClip.timelineRange.duration = firstDuration
        firstClip.sourceRange.duration = firstDuration

        var secondClip = clip
        secondClip.id = newClipId
        secondClip.timelineRange = TimeRange(start: splitTime, duration: secondDuration)
        secondClip.sourceRange = TimeRange(
            start: clip.sourceRange.start + firstDuration,
            duration: secondDuration
        )

        project.timeline.tracks[location.trackIndex].clips[location.clipIndex] = firstClip
        project.timeline.tracks[location.trackIndex].clips.insert(secondClip, at: location.clipIndex + 1)

        return CommandResult(
            affectedClipIds: [clipId, newClipId],
            description: "Split clip \(clipId)"
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        MergeSplitClipCommand(originalClipId: clipId, splitClipId: newClipId)
    }
}

struct MergeSplitClipCommand: EditorCommand {
    let id: UUID
    let originalClipId: UUID
    let splitClipId: UUID

    init(id: UUID = UUID(), originalClipId: UUID, splitClipId: UUID) {
        self.id = id
        self.originalClipId = originalClipId
        self.splitClipId = splitClipId
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let originalLocation = try project.clipLocation(for: originalClipId)
        let splitLocation = try project.clipLocation(for: splitClipId)
        guard originalLocation.trackIndex == splitLocation.trackIndex else {
            throw EditorCommandError.invalidCommand("Split clips must be on the same track to merge.")
        }
        try project.ensureTrackIsEditable(at: originalLocation.trackIndex)

        let splitClip = project.timeline.tracks[splitLocation.trackIndex].clips.remove(at: splitLocation.clipIndex)
        project.timeline.tracks[originalLocation.trackIndex].clips[originalLocation.clipIndex].timelineRange.duration += splitClip.timelineRange.duration
        project.timeline.tracks[originalLocation.trackIndex].clips[originalLocation.clipIndex].sourceRange.duration += splitClip.sourceRange.duration

        return CommandResult(
            affectedClipIds: [originalClipId, splitClipId],
            description: "Merged split clip \(splitClipId)"
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Split merge inverse requires the original split time")
    }
}
