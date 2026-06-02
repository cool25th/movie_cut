import Foundation

/// Copies a clip to a target track at a target timeline start.
public struct CopyClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to copy.
    public var clipId: UUID

    /// The destination track identifier.
    public var targetTrackId: UUID

    /// The copied clip's timeline start in seconds.
    public var targetStartTime: TimeInterval

    /// Creates a copy-clip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        targetTrackId: UUID,
        targetStartTime: TimeInterval
    ) {
        self.id = id
        self.clipId = clipId
        self.targetTrackId = targetTrackId
        self.targetStartTime = targetStartTime
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard targetStartTime >= 0 else {
            throw EditorCommandError.invalidCommand("Target start time cannot be negative.")
        }

        let sourceLocation = try project.clipLocation(for: clipId)
        let originalClip = project.timeline.tracks[sourceLocation.trackIndex].clips[sourceLocation.clipIndex]

        var copiedClip = originalClip
        copiedClip.id = UUID()
        copiedClip.timelineRange = TimeRange(
            start: targetStartTime,
            duration: originalClip.timelineRange.duration
        )

        try project.insertClip(copiedClip, into: targetTrackId, at: nil)

        return CommandResult(
            affectedClipIds: [copiedClip.id],
            description: "Copied clip \(clipId)",
            undoValues: ["copiedClipId": .uuid(copiedClip.id)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .uuid(let copiedClipId)? = result.undoValues["copiedClipId"] {
            return DeleteClipCommand(clipId: copiedClipId)
        }

        return NoOpCommand(description: "Missing copied clip identifier for inverse")
    }
}
