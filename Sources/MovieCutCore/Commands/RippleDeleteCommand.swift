import Foundation

/// Deletes a clip and shifts subsequent clips left to close the gap.
public struct RippleDeleteCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to ripple-delete.
    public var clipId: UUID

    /// Creates a ripple-delete command.
    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let trackId = project.timeline.tracks[location.trackIndex].id
        let deletedClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        let duration = deletedClip.timelineRange.duration
        guard duration >= 0 else {
            throw EditorCommandError.invalidCommand("Clip duration cannot be negative.")
        }

        project.timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)

        var affectedClipIds: Set<UUID> = [deletedClip.id]
        let clipCount = project.timeline.tracks[location.trackIndex].clips.count
        for index in location.clipIndex..<clipCount {
            project.timeline.tracks[location.trackIndex].clips[index].timelineRange.start -= duration
            affectedClipIds.insert(project.timeline.tracks[location.trackIndex].clips[index].id)
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Ripple deleted clip \(clipId)",
            undoValues: [
                "trackId": .uuid(trackId),
                "clipIndex": .int(location.clipIndex),
                "clip": .clip(deletedClip)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .uuid(let trackId)? = result.undoValues["trackId"],
            case .int(let clipIndex)? = result.undoValues["clipIndex"],
            case .clip(let clip)? = result.undoValues["clip"]
        {
            return RestoreRippleDeleteCommand(trackId: trackId, clip: clip, insertionIndex: clipIndex)
        }

        return NoOpCommand(description: "Missing ripple delete snapshot for inverse")
    }
}

struct RestoreRippleDeleteCommand: EditorCommand {
    let id: UUID
    var trackId: UUID
    var clip: Clip
    var insertionIndex: Int

    init(id: UUID = UUID(), trackId: UUID, clip: Clip, insertionIndex: Int) {
        self.id = id
        self.trackId = trackId
        self.clip = clip
        self.insertionIndex = insertionIndex
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)
        guard insertionIndex >= 0, insertionIndex <= project.timeline.tracks[trackIndex].clips.count else {
            throw EditorCommandError.invalidCommand("Clip insertion index is out of bounds.")
        }

        let duration = clip.timelineRange.duration
        var affectedClipIds: Set<UUID> = [clip.id]
        for index in insertionIndex..<project.timeline.tracks[trackIndex].clips.count {
            project.timeline.tracks[trackIndex].clips[index].timelineRange.start += duration
            affectedClipIds.insert(project.timeline.tracks[trackIndex].clips[index].id)
        }
        project.timeline.tracks[trackIndex].clips.insert(clip, at: insertionIndex)

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Restored ripple deleted clip \(clip.id)"
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        RippleDeleteCommand(clipId: clip.id)
    }
}
