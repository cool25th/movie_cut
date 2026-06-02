import Foundation

public struct ExtractAudioCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID

    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let sourceClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        guard sourceClip.kind == .video else {
            throw EditorCommandError.invalidCommand("Audio can only be extracted from video clips.")
        }

        let audioClip = Clip(
            assetId: sourceClip.assetId,
            kind: .audio,
            sourceRange: sourceClip.sourceRange,
            timelineRange: sourceClip.timelineRange,
            volume: 1.0
        )

        project.timeline.tracks[location.trackIndex].clips.insert(audioClip, at: location.clipIndex + 1)

        return CommandResult(
            affectedClipIds: [clipId, audioClip.id],
            description: "Extracted audio from clip \(clipId)",
            undoValues: ["audioClipId": .uuid(audioClip.id)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .uuid(let audioClipId)? = result.undoValues["audioClipId"] {
            return DeleteClipCommand(clipId: audioClipId)
        }

        return NoOpCommand(description: "Missing extracted audio clip identifier for inverse")
    }
}
