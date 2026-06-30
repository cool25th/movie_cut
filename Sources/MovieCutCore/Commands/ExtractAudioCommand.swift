import Foundation

public struct ExtractAudioCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var extractedClipId: UUID

    public init(id: UUID = UUID(), clipId: UUID, extractedClipId: UUID = UUID()) {
        self.id = id
        self.clipId = clipId
        self.extractedClipId = extractedClipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        let sourceClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        guard sourceClip.kind == .video else {
            throw EditorCommandError.invalidCommand("Audio can only be extracted from video clips.")
        }
        guard sourceClip.sourceRange.isPositiveFinite, sourceClip.timelineRange.isPositiveFinite else {
            throw EditorCommandError.invalidCommand("Audio extraction requires a positive clip range.")
        }
        guard let assetId = sourceClip.assetId else {
            throw EditorCommandError.invalidCommand("Selected clip does not reference a media asset.")
        }
        guard let sourceAsset = project.mediaLibrary.assets[assetId] else {
            throw EditorCommandError.assetNotFound(assetId)
        }
        guard sourceAsset.kind == .video else {
            throw EditorCommandError.invalidCommand("Audio can only be extracted from video assets.")
        }
        if (try? project.clipLocation(for: extractedClipId)) != nil {
            throw EditorCommandError.invalidCommand("Extracted audio clip already exists: \(extractedClipId)")
        }

        let audioClip = Clip(
            id: extractedClipId,
            assetId: sourceClip.assetId,
            kind: .audio,
            sourceRange: sourceClip.sourceRange,
            timelineRange: sourceClip.timelineRange,
            volume: sourceClip.volume,
            fadeInDuration: sourceClip.fadeInDuration,
            fadeOutDuration: sourceClip.fadeOutDuration,
            equalizer: sourceClip.equalizer,
            playbackRate: sourceClip.playbackRate,
            speedRampPoints: sourceClip.speedRampPoints
        )

        if let targetTrackIndex = firstAvailableAudioTrackIndex(for: sourceClip.timelineRange, in: project) {
            let targetTrackId = project.timeline.tracks[targetTrackIndex].id
            let previousClips = try project.trackClipSnapshot(for: targetTrackId)
            let insertionIndex = insertionIndex(for: audioClip, in: previousClips)
            try project.insertClip(audioClip, into: targetTrackId, at: insertionIndex)
            try project.normalizeClipZIndexes(in: targetTrackId)
            project.normalizeTrackZIndexes()

            return CommandResult(
                affectedClipIds: Set(previousClips.map(\.id)).union([clipId, audioClip.id]),
                description: "Extracted audio from clip \(clipId)",
                undoValues: [
                    "audioClipId": .uuid(audioClip.id),
                    "trackId": .uuid(targetTrackId),
                    RestoreTrackClipsCommand.snapshotKey(for: targetTrackId): .clips(previousClips)
                ]
            )
        }

        let audioTrack = Track(
            kind: .audio,
            name: nextAudioTrackName(in: project),
            zIndex: project.timeline.tracks.count,
            clips: [audioClip]
        )
        project.timeline.tracks.append(audioTrack)
        project.normalizeTrackZIndexes()

        return CommandResult(
            affectedClipIds: [clipId, audioClip.id],
            description: "Extracted audio from clip \(clipId)",
            undoValues: [
                "audioClipId": .uuid(audioClip.id),
                "trackId": .uuid(audioTrack.id),
                "createdTrackId": .uuid(audioTrack.id)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        let snapshots = RestoreTrackClipsCommand.snapshots(from: result.undoValues)
        if !snapshots.isEmpty {
            return RestoreTrackClipsCommand(
                snapshots: snapshots,
                description: "Removed extracted audio clip \(extractedClipId)"
            )
        }

        if case .uuid(let audioClipId)? = result.undoValues["audioClipId"] {
            let createdTrackId: UUID?
            if case .uuid(let trackId)? = result.undoValues["createdTrackId"] {
                createdTrackId = trackId
            } else {
                createdTrackId = nil
            }
            return RemoveExtractedAudioClipCommand(
                clipId: audioClipId,
                createdTrackId: createdTrackId
            )
        }

        return NoOpCommand(description: "Missing extracted audio clip identifier for inverse")
    }

    private func firstAvailableAudioTrackIndex(for range: TimeRange, in project: Project) -> Int? {
        for index in project.timeline.tracks.indices {
            let track = project.timeline.tracks[index]
            guard track.kind == .audio, !track.isLocked else { continue }
            if !track.clips.contains(where: { $0.timelineRange.overlaps(range) }) {
                return index
            }
        }
        return nil
    }

    private func insertionIndex(for clip: Clip, in clips: [Clip]) -> Int {
        clips.firstIndex { Track.clipTimelineOrder(clip, $0) } ?? clips.count
    }

    private func nextAudioTrackName(in project: Project) -> String {
        let nextIndex = project.timeline.tracks.filter { $0.kind == .audio }.count + 1
        return "Audio \(nextIndex)"
    }
}

private struct RemoveExtractedAudioClipCommand: EditorCommand {
    let id: UUID
    var clipId: UUID
    var createdTrackId: UUID?

    init(id: UUID = UUID(), clipId: UUID, createdTrackId: UUID?) {
        self.id = id
        self.clipId = clipId
        self.createdTrackId = createdTrackId
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let trackId = project.timeline.tracks[location.trackIndex].id
        let previousClips = project.timeline.tracks[location.trackIndex].clips
        let removedClip = project.timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
        var affectedClipIds = Set(previousClips.map(\.id))

        if createdTrackId == trackId, project.timeline.tracks[location.trackIndex].clips.isEmpty {
            project.timeline.tracks.remove(at: location.trackIndex)
            project.normalizeTrackZIndexes()
        } else {
            try project.normalizeClipZIndexes(in: trackId)
        }

        affectedClipIds.insert(removedClip.id)
        return CommandResult(
            affectedClipIds: affectedClipIds,
            description: "Removed extracted audio clip \(clipId)"
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        NoOpCommand(description: "Missing extracted audio clip snapshot for inverse")
    }
}

private extension TimeRange {
    var isPositiveFinite: Bool {
        start.isFinite && duration.isFinite && duration > 0 && end.isFinite
    }
}
