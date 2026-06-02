import Foundation

/// Duplicates a clip immediately after itself on the same track.
public struct DuplicateClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to duplicate.
    public var clipId: UUID

    /// Creates a duplicate-clip command.
    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let originalClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        var duplicateClip = originalClip
        duplicateClip.id = UUID()
        duplicateClip.timelineRange = TimeRange(
            start: originalClip.timelineRange.end,
            duration: originalClip.timelineRange.duration
        )

        project.timeline.tracks[location.trackIndex].clips.insert(
            duplicateClip,
            at: location.clipIndex + 1
        )

        return CommandResult(
            affectedClipIds: [duplicateClip.id],
            description: "Duplicated clip \(clipId)",
            undoValues: ["duplicateClipId": .uuid(duplicateClip.id)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .uuid(let duplicateClipId)? = result.undoValues["duplicateClipId"] {
            return DeleteClipCommand(clipId: duplicateClipId)
        }

        return NoOpCommand(description: "Missing duplicate clip identifier for inverse")
    }
}
