import Foundation

/// Adds a clip to an existing track.
public struct AddClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The destination track identifier.
    public var trackId: UUID

    /// The clip to add.
    public var clip: Clip

    /// Creates an add-clip command.
    public init(id: UUID = UUID(), trackId: UUID, clip: Clip) {
        self.id = id
        self.trackId = trackId
        self.clip = clip
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)
        project.timeline.tracks[trackIndex].clips.append(clip)
        return CommandResult(affectedClipIds: [clip.id], description: "Added clip \(clip.id)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        DeleteClipCommand(clipId: clip.id, deletedTrackId: trackId, deletedClip: clip)
    }
}
