import Foundation

/// Moves a clip to a new timeline start and optionally to another track.
public struct MoveClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to move.
    public var clipId: UUID

    /// The expected source track, or the current clip track when nil.
    public var sourceTrackId: UUID?

    /// The destination track, or the source track when nil.
    public var targetTrackId: UUID?

    /// The new timeline range in seconds.
    public var newTimelineRange: TimeRange

    /// Optional prior track identifier used when constructing an inverse command.
    public var previousTrackId: UUID?

    /// Optional prior timeline range used when constructing an inverse command.
    public var previousTimelineRange: TimeRange?

    /// Optional destination clip index used when restoring a move.
    public var destinationClipIndex: Int?

    /// Phase 0 compatibility alias for the new timeline range start.
    public var newTimelineStart: TimeInterval {
        get { newTimelineRange.start }
        set { newTimelineRange.start = newValue }
    }

    /// Phase 0 compatibility alias for the previous timeline range start.
    public var previousTimelineStart: TimeInterval? {
        get { previousTimelineRange?.start }
        set {
            if let newValue {
                if previousTimelineRange == nil {
                    previousTimelineRange = TimeRange(start: newValue, duration: 0)
                } else {
                    previousTimelineRange?.start = newValue
                }
            } else {
                previousTimelineRange = nil
            }
        }
    }

    /// Creates a move-clip command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        sourceTrackId: UUID? = nil,
        targetTrackId: UUID? = nil,
        newTimelineRange: TimeRange,
        previousTrackId: UUID? = nil,
        previousTimelineRange: TimeRange? = nil,
        destinationClipIndex: Int? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.sourceTrackId = sourceTrackId
        self.targetTrackId = targetTrackId
        self.newTimelineRange = newTimelineRange
        self.previousTrackId = previousTrackId
        self.previousTimelineRange = previousTimelineRange
        self.destinationClipIndex = destinationClipIndex
    }

    /// Creates a move-clip command from a new start time while preserving duration.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        targetTrackId: UUID? = nil,
        newTimelineStart: TimeInterval,
        previousTrackId: UUID? = nil,
        previousTimelineStart: TimeInterval? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.sourceTrackId = nil
        self.targetTrackId = targetTrackId
        self.newTimelineRange = TimeRange(start: newTimelineStart, duration: 0)
        self.previousTrackId = previousTrackId
        self.previousTimelineRange = previousTimelineStart.map { TimeRange(start: $0, duration: 0) }
        self.destinationClipIndex = nil
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = if let sourceTrackId {
            try project.clipLocation(for: clipId, in: sourceTrackId)
        } else {
            try project.clipLocation(for: clipId)
        }
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let currentTrackId = project.timeline.tracks[location.trackIndex].id
        let destinationTrackId = targetTrackId ?? currentTrackId
        let destinationTrackIndex = try project.trackIndex(for: destinationTrackId)
        try project.ensureTrackIsEditable(at: destinationTrackIndex)
        let sourceTrackClipsBefore = project.timeline.tracks[location.trackIndex].clips
        let destinationTrackClipsBefore = project.timeline.tracks[destinationTrackIndex].clips

        var updatedRange = newTimelineRange
        let originalClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        if updatedRange.duration == 0 {
            updatedRange.duration = originalClip.timelineRange.duration
        }
        guard updatedRange.duration >= 0 else {
            throw EditorCommandError.invalidCommand("Timeline range duration cannot be negative.")
        }

        if location.trackIndex == destinationTrackIndex {
            project.timeline.tracks[location.trackIndex].clips[location.clipIndex].timelineRange = updatedRange
        } else {
            var clip = project.timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
            clip.timelineRange = updatedRange
            let adjustedDestinationIndex: Int?
            if let destinationClipIndex, destinationTrackIndex == location.trackIndex, destinationClipIndex > location.clipIndex {
                adjustedDestinationIndex = destinationClipIndex - 1
            } else {
                adjustedDestinationIndex = destinationClipIndex
            }
            if let adjustedDestinationIndex {
                guard adjustedDestinationIndex >= 0,
                      adjustedDestinationIndex <= project.timeline.tracks[destinationTrackIndex].clips.count
                else {
                    throw EditorCommandError.invalidCommand("Clip insertion index is out of bounds.")
                }
                project.timeline.tracks[destinationTrackIndex].clips.insert(clip, at: adjustedDestinationIndex)
            } else {
                project.timeline.tracks[destinationTrackIndex].clips.append(clip)
            }
        }

        // Magnetic compaction applies only to the main video track. Free tracks
        // preserve the requested clip position (same-track drag, cross-track
        // drop). Step 2 of the core-editing repair handoff.
        if project.isMagneticTrack(currentTrackId) {
            try project.compactTrackMagnetically(currentTrackId)
        }
        try project.normalizeClipZIndexes(in: currentTrackId)
        if destinationTrackId != currentTrackId {
            if project.isMagneticTrack(destinationTrackId) {
                try project.compactTrackMagnetically(destinationTrackId)
            }
            try project.normalizeClipZIndexes(in: destinationTrackId)
        }

        var undoValues: [String: CommandResultValue] = [
            "sourceTrackId": .uuid(currentTrackId),
            "sourceClipIndex": .int(location.clipIndex),
            "timelineRange": .timeRange(originalClip.timelineRange),
            RestoreTrackClipsCommand.snapshotKey(for: currentTrackId): .clips(sourceTrackClipsBefore)
        ]
        if destinationTrackId != currentTrackId {
            undoValues[RestoreTrackClipsCommand.snapshotKey(for: destinationTrackId)] = .clips(destinationTrackClipsBefore)
        }

        var affectedClipIds = Set(sourceTrackClipsBefore.map(\.id))
        if destinationTrackId != currentTrackId {
            affectedClipIds.formUnion(destinationTrackClipsBefore.map(\.id))
        }
        affectedClipIds.insert(clipId)

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Moved clip \(clipId)",
            undoValues: undoValues
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = RestoreTrackClipsCommand.snapshots(from: result.undoValues)
        if !snapshots.isEmpty {
            return RestoreTrackClipsCommand(
                snapshots: snapshots,
                description: "Restored moved clip \(clipId)"
            )
        }

        if
            case .uuid(let originalTrackId)? = result.undoValues["sourceTrackId"],
            case .int(let originalClipIndex)? = result.undoValues["sourceClipIndex"],
            case .timeRange(let originalRange)? = result.undoValues["timelineRange"]
        {
            return MoveClipCommand(
                clipId: clipId,
                sourceTrackId: targetTrackId,
                targetTrackId: originalTrackId,
                newTimelineRange: originalRange,
                destinationClipIndex: originalClipIndex
            )
        }

        guard let previousTimelineRange else {
            return NoOpCommand(description: "Missing previous clip position for inverse")
        }

        return MoveClipCommand(
            clipId: clipId,
            sourceTrackId: targetTrackId,
            targetTrackId: previousTrackId,
            newTimelineRange: previousTimelineRange
        )
    }
}
