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

    public func apply(to project: inout Project) throws {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].mask = mask
    }

        public func invert() -> any EditorCommand {
        SetClipMaskCommand(clipId: clipId, mask: oldMask)
    }
}
