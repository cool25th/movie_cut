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

    public func apply(to project: inout Project) throws {
        if project.timeline.tracks.contains(where: { $0.id == track.id }) {
            throw EditorCommandError.invalidCommand("Track already exists: \(track.id)")
        }
        project.timeline.tracks.append(track)    }

    }

public struct RemoveTrackCommand: EditorCommand {
    public let id: UUID
    public let track: Track

    public init(id: UUID = UUID(), track: Track) {
        self.id = id
        self.track = track
    }

    public func apply(to project: inout Project) throws {
        let index = try project.trackIndex(for: track.id)
        project.timeline.tracks.remove(at: index)
    }
}
