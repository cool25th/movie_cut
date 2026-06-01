import Foundation

extension Project {
    mutating func trackIndex(for trackId: UUID) throws -> Int {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            throw EditorCommandError.trackNotFound(trackId)
        }
        return index
    }

    mutating func clipLocation(for clipId: UUID) throws -> (trackIndex: Int, clipIndex: Int) {
        for trackIndex in timeline.tracks.indices {
            if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) {
                return (trackIndex, clipIndex)
            }
        }
        throw EditorCommandError.clipNotFound(clipId)
    }

    func ensureTrackIsEditable(at index: Int) throws {
        let track = timeline.tracks[index]
        if track.isLocked {
            throw EditorCommandError.trackLocked(track.id)
        }
    }

    mutating func removeClip(id clipId: UUID) throws -> (trackId: UUID, clip: Clip) {
        let location = try clipLocation(for: clipId)
        try ensureTrackIsEditable(at: location.trackIndex)
        let trackId = timeline.tracks[location.trackIndex].id
        let clip = timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
        return (trackId, clip)
    }
}

struct NoOpCommand: EditorCommand {
    let id: UUID
    let description: String

    init(id: UUID = UUID(), description: String = "No operation") {
        self.id = id
        self.description = description
    }

    func apply(to project: inout Project) throws -> CommandResult {
        CommandResult(description: description)
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        self
    }
}
