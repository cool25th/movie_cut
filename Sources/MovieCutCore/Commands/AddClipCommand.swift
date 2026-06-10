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

        let previousClips = try project.trackClipSnapshot(for: trackId)
        try project.insertClip(clip, into: trackId, at: insertionIndex)
        try project.compactTrackMagnetically(trackId)
        try project.normalizeClipZIndexes(in: trackId)
        project.normalizeTrackZIndexes()

        return CommandResult(
            affectedClipIds: Set(previousClips.map(\.id)).union([clip.id]),
            description: "Added clip \(clip.id)",
            undoValues: [
                "trackId": .uuid(trackId),
                "clip": .clip(clip),
                RestoreTrackClipsCommand.snapshotKey(for: trackId): .clips(previousClips)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = RestoreTrackClipsCommand.snapshots(from: result.undoValues)
        if !snapshots.isEmpty {
            return RestoreTrackClipsCommand(
                snapshots: snapshots,
                description: "Removed added clip \(clip.id)"
            )
        }

        return DeleteClipCommand(clipId: clip.id, deletedTrackId: trackId, deletedClip: clip, deletedClipIndex: insertionIndex)
    }
}
