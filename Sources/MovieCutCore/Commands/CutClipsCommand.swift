import Foundation

/// Removes selected clips across tracks without magnetic compaction.
public struct CutClipsCommand: EditorCommand {
    public let id: UUID
    public let clipIds: Set<UUID>

    public init(id: UUID = UUID(), clipIds: Set<UUID>) {
        self.id = id
        self.clipIds = clipIds
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard !clipIds.isEmpty else {
            throw EditorCommandError.invalidCommand("Cut selection cannot be empty.")
        }

        let previousTracks = project.timeline.tracks
        var locations: [UUID: Int] = [:]
        for trackIndex in previousTracks.indices {
            for clip in previousTracks[trackIndex].clips where clipIds.contains(clip.id) {
                locations[clip.id] = trackIndex
            }
        }

        if let missingId = clipIds.subtracting(locations.keys).sorted(by: { $0.uuidString < $1.uuidString }).first {
            throw EditorCommandError.clipNotFound(missingId)
        }
        if let lockedIndex = Set(locations.values).sorted().first(where: { previousTracks[$0].isLocked }) {
            throw EditorCommandError.trackLocked(previousTracks[lockedIndex].id)
        }

        var tracks = previousTracks
        for trackIndex in Set(locations.values).sorted() {
            tracks[trackIndex].clips.removeAll { clipIds.contains($0.id) }
            tracks[trackIndex].normalizeClipZIndexes()
        }
        for index in tracks.indices {
            tracks[index].zIndex = index
        }
        project.timeline.tracks = tracks

        return CommandResult(
            affectedClipIds: clipIds,
            description: "Cut \(clipIds.count) clips",
            undoValues: ["timelineTracks": .tracks(previousTracks)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        guard case .tracks(let tracks)? = result.undoValues["timelineTracks"] else {
            return NoOpCommand(description: "Missing pre-cut timeline snapshot for inverse")
        }
        return RestoreTimelineTracksCommand(tracks: tracks, description: "Restored cut clips")
    }
}
