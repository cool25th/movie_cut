import Foundation

public struct AudioDuckingCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var duckLevel: Double
    public var originalVolumes: [UUID: Double]?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        duckLevel: Double,
        originalVolumes: [UUID: Double]? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.duckLevel = duckLevel
        self.originalVolumes = originalVolumes
    }

    public func apply(to project: inout Project) throws {
        guard duckLevel >= 0, duckLevel <= 1 else {
            throw EditorCommandError.invalidCommand("Duck level must be between 0.0 and 1.0.")
        }

        let speechLocation = try project.clipLocation(for: clipId)
        let speechClip = project.timeline.tracks[speechLocation.trackIndex].clips[speechLocation.clipIndex]
        let multiplier = 1.0 - duckLevel

        var targets: [(trackIndex: Int, clipIndex: Int)] = []
        for trackIndex in project.timeline.tracks.indices
            where project.timeline.tracks[trackIndex].kind == .audio
        {
            for clipIndex in project.timeline.tracks[trackIndex].clips.indices {
                let clip = project.timeline.tracks[trackIndex].clips[clipIndex]
                guard clip.id != clipId else {
                    continue
                }
                guard clip.timelineRange.overlaps(speechClip.timelineRange) else {
                    continue
                }
                targets.append((trackIndex, clipIndex))
            }
        }

        let editableTrackIndexes = Set(targets.map(\.trackIndex)).sorted()
        for trackIndex in editableTrackIndexes {
            try project.ensureTrackIsEditable(at: trackIndex)
        }
    }
}

private struct RestoreClipVolumesCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var volumes: [UUID: Double]

    init(id: UUID = UUID(), volumes: [UUID: Double]) {
        self.id = id
        self.volumes = volumes
    }

    func apply(to project: inout Project) throws {
        var targets: [(clipId: UUID, trackIndex: Int, clipIndex: Int, volume: Double)] = []
        for (clipId, volume) in volumes {
            let location = try project.clipLocation(for: clipId)
            targets.append((clipId, location.trackIndex, location.clipIndex, volume))
        }

        let editableTrackIndexes = Set(targets.map(\.trackIndex)).sorted()
        for trackIndex in editableTrackIndexes {
            try project.ensureTrackIsEditable(at: trackIndex)
        }

    }

    }

