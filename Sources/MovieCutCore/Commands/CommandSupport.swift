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

    mutating func clipLocation(for clipId: UUID, in trackId: UUID) throws -> (trackIndex: Int, clipIndex: Int) {
        let trackIndex = try trackIndex(for: trackId)
        guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
            throw EditorCommandError.clipNotFound(clipId)
        }
        return (trackIndex, clipIndex)
    }

    func ensureTrackIsEditable(at index: Int) throws {
        let track = timeline.tracks[index]
        if track.isLocked {
            throw EditorCommandError.trackLocked(track.id)
        }
    }

    mutating func removeClip(id clipId: UUID) throws -> (trackId: UUID, clipIndex: Int, clip: Clip) {
        let location = try clipLocation(for: clipId)
        try ensureTrackIsEditable(at: location.trackIndex)
        let trackId = timeline.tracks[location.trackIndex].id
        let clip = timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
        return (trackId, location.clipIndex, clip)
    }

    mutating func insertClip(_ clip: Clip, into trackId: UUID, at insertionIndex: Int?) throws {
        let trackIndex = try trackIndex(for: trackId)
        try ensureTrackIsEditable(at: trackIndex)

        if let insertionIndex {
            guard insertionIndex >= 0, insertionIndex <= timeline.tracks[trackIndex].clips.count else {
                throw EditorCommandError.invalidCommand("Clip insertion index is out of bounds.")
            }
            timeline.tracks[trackIndex].clips.insert(clip, at: insertionIndex)
        } else {
            timeline.tracks[trackIndex].clips.append(clip)
        }
    }

    mutating func normalizeTrackZIndexes() {
        for index in timeline.tracks.indices {
            timeline.tracks[index].zIndex = index
        }
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
