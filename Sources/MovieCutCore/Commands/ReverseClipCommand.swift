import Foundation

/// Toggles reverse playback for a clip.
public struct ReverseClipCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID

    public init(id: UUID = UUID(), clipId: UUID) {
        self.id = id
        self.clipId = clipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].isReversed.toggle()

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Toggled reverse playback for clip \(clipId)"
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        ReverseClipCommand(clipId: clipId)
    }
}
