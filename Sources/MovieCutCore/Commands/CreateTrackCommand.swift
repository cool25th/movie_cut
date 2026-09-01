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
        // CODEX-19: callers assign `zIndex: tracks.count`, which collides
        // after a deletion (0/1/2, remove 0 → next add is 2, duplicating the
        // survivor). Rendering sorts by zIndex alone, so a duplicate makes
        // the overlap order nondeterministic. The command is the single
        // choke point every surface funnels through — normalize here:
        // clamp any colliding explicit z-index to max+1, leaving already
        // unique z-indexes untouched (deliberate layer placement survives).
        var normalized = track
        let occupied = Set(project.timeline.tracks.map(\.zIndex))
        if occupied.contains(normalized.zIndex) {
            normalized.zIndex = (occupied.max() ?? -1) + 1
        }
        project.timeline.tracks.append(normalized)
    }
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
