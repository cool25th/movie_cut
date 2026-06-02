import Foundation

public struct SetClipMaskCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var mask: Mask?
    public var oldMask: Mask?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        mask: Mask?,
        oldMask: Mask? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.mask = mask
        self.oldMask = oldMask
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].mask = mask

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set mask for clip \(clipId)",
            undoValues: ["clip": .clip(previousClip)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clip(let clip)? = result.undoValues["clip"] {
            return SetClipMaskCommand(clipId: clipId, mask: clip.mask)
        }

        return SetClipMaskCommand(clipId: clipId, mask: oldMask)
    }

    public func invert() -> any EditorCommand {
        SetClipMaskCommand(clipId: clipId, mask: oldMask)
    }
}
