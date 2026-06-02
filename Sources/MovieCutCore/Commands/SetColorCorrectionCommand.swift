import Foundation

/// Sets the color correction values for a clip.
public struct SetColorCorrectionCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var colorCorrection: ColorCorrection?
    public var previousColorCorrection: ColorCorrection?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        colorCorrection: ColorCorrection?,
        previousColorCorrection: ColorCorrection? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.colorCorrection = colorCorrection
        self.previousColorCorrection = previousColorCorrection
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)
        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].colorCorrection = colorCorrection

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set color correction for clip \(clipId)",
            undoValues: ["clip": .clip(previousClip)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clip(let clip)? = result.undoValues["clip"] {
            return SetColorCorrectionCommand(clipId: clipId, colorCorrection: clip.colorCorrection)
        }
        return SetColorCorrectionCommand(clipId: clipId, colorCorrection: previousColorCorrection)
    }
}
