import Foundation

/// Adds a track to the project's timeline.
public struct CreateTrackCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The track to append.
    public var track: Track

    /// Creates a track creation command.
    public init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        if project.timeline.tracks.contains(where: { $0.id == track.id }) {
            throw EditorCommandError.invalidCommand("Track already exists: \(track.id)")
        }
        project.timeline.tracks.append(track)
        return CommandResult(description: "Created track \(track.name)")
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        RemoveTrackCommand(track: track)
    }
}

struct RemoveTrackCommand: EditorCommand {
    let id: UUID
    let track: Track

    init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let index = try project.trackIndex(for: track.id)
        let removedTrack = project.timeline.tracks.remove(at: index)
        let affectedClipIds = Set(removedTrack.clips.map(\.id))
        return CommandResult(affectedClipIds: affectedClipIds, description: "Removed track \(removedTrack.name)")
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        CreateTrackCommand(track: track)
    }
}
