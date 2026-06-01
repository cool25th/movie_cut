import Foundation

/// Removes a clip from its track.
public struct DeleteClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to delete.
    public var clipId: UUID

    /// Optional prior track identifier used when constructing an inverse command.
    public var deletedTrackId: UUID?

    /// Optional prior clip value used when constructing an inverse command.
    public var deletedClip: Clip?

    /// Optional prior clip index used when constructing an inverse command.
    public var deletedClipIndex: Int?

    /// Creates a delete-clip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        deletedTrackId: UUID? = nil,
        deletedClip: Clip? = nil,
        deletedClipIndex: Int? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.deletedTrackId = deletedTrackId
        self.deletedClip = deletedClip
        self.deletedClipIndex = deletedClipIndex
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let removed = try project.removeClip(id: clipId)
        return CommandResult(
            affectedClipIds: [removed.clip.id],
            description: "Deleted clip \(clipId)",
            undoValues: [
                "trackId": .uuid(removed.trackId),
                "clipIndex": .int(removed.clipIndex),
                "clip": .clip(removed.clip)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .uuid(let trackId)? = result.undoValues["trackId"],
            case .clip(let clip)? = result.undoValues["clip"],
            case .int(let clipIndex)? = result.undoValues["clipIndex"]
        {
            return AddClipCommand(trackId: trackId, clip: clip, insertionIndex: clipIndex)
        }

        guard let deletedTrackId, let deletedClip else {
            return NoOpCommand(description: "Missing deleted clip snapshot for inverse")
        }
        return AddClipCommand(trackId: deletedTrackId, clip: deletedClip, insertionIndex: deletedClipIndex)
    }
}
