import Foundation

/// Duplicates a clip immediately after itself on the same track.
public struct DuplicateClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to duplicate.
    public var clipId: UUID

    /// Creates a duplicate-clip command.
    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let trackId = project.timeline.tracks[location.trackIndex].id
        let previousClips = project.timeline.tracks[location.trackIndex].clips
        let originalClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        var duplicateClip = originalClip
        duplicateClip.id = UUID()
        duplicateClip.timelineRange = TimeRange(
            start: originalClip.timelineRange.end,
            duration: originalClip.timelineRange.duration
        )

        project.timeline.tracks[location.trackIndex].clips.insert(
            duplicateClip,
            at: location.clipIndex + 1
        )
        // Magnetic compaction applies only to the main video track. Step 2 of
        // the core-editing repair handoff.
        if project.isMagneticTrack(trackId) {
            try project.compactTrackMagnetically(trackId)
        }
        try project.normalizeClipZIndexes(in: trackId)

        return CommandResult(
            affectedClipIds: Set(previousClips.map(\.id)).union([duplicateClip.id]),
            description: "Duplicated clip \(clipId)",
            undoValues: [
                "duplicateClipId": .uuid(duplicateClip.id),
                RestoreTrackClipsCommand.snapshotKey(for: trackId): .clips(previousClips)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = RestoreTrackClipsCommand.snapshots(from: result.undoValues)
        if !snapshots.isEmpty {
            return RestoreTrackClipsCommand(
                snapshots: snapshots,
                description: "Removed duplicated clip \(clipId)"
            )
        }

        if case .uuid(let duplicateClipId)? = result.undoValues["duplicateClipId"] {
            return DeleteClipCommand(clipId: duplicateClipId)
        }

        return NoOpCommand(description: "Missing duplicate clip identifier for inverse")
    }
}
