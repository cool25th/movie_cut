import Foundation

/// Adds a clip to an existing track.
public struct AddClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The destination track identifier.
    public var trackId: UUID

    /// The clip to add.
    public var clip: Clip

    /// Optional insertion index used when restoring a deleted clip.
    public var insertionIndex: Int?

    /// Creates an add-clip command.
    public init(id: UUID = UUID(), trackId: UUID, clip: Clip, insertionIndex: Int? = nil) {
        self.id = id
        self.trackId = trackId
        self.clip = clip
        self.insertionIndex = insertionIndex
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        if (try? project.clipLocation(for: clip.id)) != nil {
            throw EditorCommandError.invalidCommand("Clip already exists: \(clip.id)")
        }

        try project.insertClip(clip, into: trackId, at: insertionIndex)
        project.normalizeTrackZIndexes()

        return CommandResult(
            affectedClipIds: [clip.id],
            description: "Added clip \(clip.id)",
            undoValues: [
                "trackId": .uuid(trackId),
                "clip": .clip(clip)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        DeleteClipCommand(clipId: clip.id, deletedTrackId: trackId, deletedClip: clip, deletedClipIndex: insertionIndex)
    }
}
