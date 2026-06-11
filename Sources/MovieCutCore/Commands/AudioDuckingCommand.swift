import Foundation

public struct AudioDuckingCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var duckLevel: Double
    public var originalVolumes: [UUID: Double]?

    private static let undoKeyPrefix = "volume:"

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

    public func apply(to project: inout Project) throws -> CommandResult {
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

        var affectedClipIds = Set<UUID>()
        var undoValues: [String: CommandResultValue] = [:]
        for target in targets {
            let clip = project.timeline.tracks[target.trackIndex].clips[target.clipIndex]
            affectedClipIds.insert(clip.id)
            undoValues[Self.undoKey(for: clip.id)] = .clipProperty(.volume(clip.volume))
            project.timeline.tracks[target.trackIndex].clips[target.clipIndex].volume = clip.volume * multiplier
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Ducked overlapping audio for speech clip \(clipId)",
            undoValues: undoValues
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let volumes = Self.volumes(from: result.undoValues)
        if !volumes.isEmpty {
            return RestoreClipVolumesCommand(volumes: volumes)
        }

        if let originalVolumes, !originalVolumes.isEmpty {
            return RestoreClipVolumesCommand(volumes: originalVolumes)
        }

        return NoOpCommand(description: "Missing ducked audio volume values for inverse")
    }

    private static func undoKey(for clipId: UUID) -> String {
        "\(undoKeyPrefix)\(clipId.uuidString)"
    }

    private static func volumes(from undoValues: [String: CommandResultValue]) -> [UUID: Double] {
        var volumes: [UUID: Double] = [:]
        for (key, value) in undoValues {
            guard key.hasPrefix(undoKeyPrefix) else {
                continue
            }

            let uuidString = String(key.dropFirst(undoKeyPrefix.count))
            guard
                let clipId = UUID(uuidString: uuidString),
                case .clipProperty(.volume(let volume)) = value
            else {
                continue
            }
            volumes[clipId] = volume
        }
        return volumes
    }
}

private struct RestoreClipVolumesCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var volumes: [UUID: Double]

    init(id: UUID = UUID(), volumes: [UUID: Double]) {
        self.id = id
        self.volumes = volumes
    }

    func apply(to project: inout Project) throws -> CommandResult {
        var targets: [(clipId: UUID, trackIndex: Int, clipIndex: Int, volume: Double)] = []
        for (clipId, volume) in volumes {
            let location = try project.clipLocation(for: clipId)
            targets.append((clipId, location.trackIndex, location.clipIndex, volume))
        }

        let editableTrackIndexes = Set(targets.map(\.trackIndex)).sorted()
        for trackIndex in editableTrackIndexes {
            try project.ensureTrackIsEditable(at: trackIndex)
        }

        var affectedClipIds = Set<UUID>()
        var undoValues: [String: CommandResultValue] = [:]
        for target in targets {
            let previousVolume = project.timeline.tracks[target.trackIndex].clips[target.clipIndex].volume
            affectedClipIds.insert(target.clipId)
            undoValues["volume:\(target.clipId.uuidString)"] = .clipProperty(.volume(previousVolume))
            project.timeline.tracks[target.trackIndex].clips[target.clipIndex].volume = target.volume
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Restored audio clip volumes",
            undoValues: undoValues
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        var volumes: [UUID: Double] = [:]
        for (key, value) in result.undoValues {
            guard key.hasPrefix("volume:") else {
                continue
            }

            let uuidString = String(key.dropFirst("volume:".count))
            guard
                let clipId = UUID(uuidString: uuidString),
                case .clipProperty(.volume(let volume)) = value
            else {
                continue
            }
            volumes[clipId] = volume
        }

        guard !volumes.isEmpty else {
            return NoOpCommand(description: "Missing previous audio volume values for inverse")
        }
        return RestoreClipVolumesCommand(volumes: volumes)
    }
}

