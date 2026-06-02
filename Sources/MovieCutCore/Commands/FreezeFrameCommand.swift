import Foundation

/// Splits a clip and inserts a still-frame hold at a clip-relative time.
public struct FreezeFrameCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var freezeTime: TimeInterval
    public var freezeDuration: TimeInterval

    public init(id: UUID = UUID(), clipId: UUID, freezeTime: TimeInterval, freezeDuration: TimeInterval = 2.0) {
        self.id = id
        self.clipId = clipId
        self.freezeTime = freezeTime
        self.freezeDuration = freezeDuration
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        let clip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        guard freezeDuration > 0 else { throw EditorCommandError.invalidCommand("Freeze duration must be positive.") }
        guard freezeTime > 0, freezeTime < clip.timelineRange.duration else {
            throw EditorCommandError.invalidCommand("Freeze time must be inside the clip range.")
        }
        let trailingSourceDuration = clip.sourceRange.duration - freezeTime
        guard trailingSourceDuration >= 0 else {
            throw EditorCommandError.invalidCommand("Freeze time exceeds the clip source range.")
        }

        let trackId = project.timeline.tracks[location.trackIndex].id
        let freezeStart = clip.timelineRange.start + freezeTime
        var leadingClip = clip
        leadingClip.timelineRange.duration = freezeTime
        leadingClip.sourceRange.duration = freezeTime

        var freezeClip = clip
        freezeClip.id = UUID()
        freezeClip.kind = .image
        freezeClip.sourceRange = TimeRange(start: clip.sourceRange.start + freezeTime, duration: 0)
        freezeClip.timelineRange = TimeRange(start: freezeStart, duration: freezeDuration)

        var trailingClip = clip
        trailingClip.id = UUID()
        trailingClip.sourceRange = TimeRange(start: clip.sourceRange.start + freezeTime, duration: trailingSourceDuration)
        trailingClip.timelineRange = TimeRange(start: freezeStart + freezeDuration, duration: clip.timelineRange.duration - freezeTime)

        var affectedClipIds: Set<UUID> = [clipId, freezeClip.id, trailingClip.id]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex] = leadingClip
        project.timeline.tracks[location.trackIndex].clips.insert(freezeClip, at: location.clipIndex + 1)
        project.timeline.tracks[location.trackIndex].clips.insert(trailingClip, at: location.clipIndex + 2)
        for index in (location.clipIndex + 3)..<project.timeline.tracks[location.trackIndex].clips.count {
            project.timeline.tracks[location.trackIndex].clips[index].timelineRange.start += freezeDuration
            affectedClipIds.insert(project.timeline.tracks[location.trackIndex].clips[index].id)
        }

        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Inserted freeze frame for clip \(clipId)",
            undoValues: [
                "trackId": .uuid(trackId),
                "clipIndex": .int(location.clipIndex),
                "clip": .clip(clip),
                "freezeClipId": .uuid(freezeClip.id),
                "trailingClipId": .uuid(trailingClip.id)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .uuid(let trackId)? = result.undoValues["trackId"],
           case .int(let clipIndex)? = result.undoValues["clipIndex"],
           case .clip(let clip)? = result.undoValues["clip"],
           case .uuid(let freezeClipId)? = result.undoValues["freezeClipId"],
           case .uuid(let trailingClipId)? = result.undoValues["trailingClipId"] {
            return RemoveFreezeFrameCommand(
                originalClipId: clipId,
                freezeClipId: freezeClipId,
                trailingClipId: trailingClipId,
                trackId: trackId,
                originalClipIndex: clipIndex,
                originalClip: clip,
                freezeTime: freezeTime,
                freezeDuration: freezeDuration
            )
        }
        return NoOpCommand(description: "Missing freeze-frame snapshot for inverse")
    }
}

private struct RemoveFreezeFrameCommand: EditorCommand {
    let id = UUID()
    var originalClipId: UUID
    var freezeClipId: UUID
    var trailingClipId: UUID
    var trackId: UUID
    var originalClipIndex: Int
    var originalClip: Clip
    var freezeTime: TimeInterval
    var freezeDuration: TimeInterval

    func apply(to project: inout Project) throws -> CommandResult {
        let trackIndex = try project.trackIndex(for: trackId)
        try project.ensureTrackIsEditable(at: trackIndex)
        var clips = project.timeline.tracks[trackIndex].clips
        guard originalClipIndex + 2 < clips.count,
              clips[originalClipIndex].id == originalClipId,
              clips[originalClipIndex + 1].id == freezeClipId,
              clips[originalClipIndex + 2].id == trailingClipId else {
            throw EditorCommandError.invalidCommand("Freeze-frame clips are not adjacent.")
        }
        clips.remove(at: originalClipIndex + 2)
        clips.remove(at: originalClipIndex + 1)
        clips[originalClipIndex] = originalClip
        var affectedClipIds: Set<UUID> = [originalClipId, freezeClipId, trailingClipId]
        for index in (originalClipIndex + 1)..<clips.count {
            clips[index].timelineRange.start -= freezeDuration
            affectedClipIds.insert(clips[index].id)
        }
        project.timeline.tracks[trackIndex].clips = clips
        return CommandResult(affectedClipIds: affectedClipIds, description: "Removed freeze frame for clip \(originalClipId)")
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        FreezeFrameCommand(clipId: originalClipId, freezeTime: freezeTime, freezeDuration: freezeDuration)
    }
}
