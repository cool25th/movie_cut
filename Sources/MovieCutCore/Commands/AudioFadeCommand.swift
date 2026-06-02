import Foundation

public struct AudioFadeCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipId: UUID
    public var fadeInDuration: TimeInterval
    public var fadeOutDuration: TimeInterval
    public var oldFadeIn: TimeInterval?
    public var oldFadeOut: TimeInterval?

    public init(
        id: UUID = UUID(),
        clipId: UUID,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        oldFadeIn: TimeInterval? = nil,
        oldFadeOut: TimeInterval? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.fadeInDuration = fadeInDuration
        self.fadeOutDuration = fadeOutDuration
        self.oldFadeIn = oldFadeIn
        self.oldFadeOut = oldFadeOut
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard fadeInDuration >= 0, fadeOutDuration >= 0 else {
            throw EditorCommandError.invalidCommand("Audio fade durations cannot be negative.")
        }

        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].fadeInDuration = fadeInDuration
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].fadeOutDuration = fadeOutDuration

        return CommandResult(
            affectedClipIds: [clipId],
            description: "Set audio fade for \(clipId)",
            undoValues: ["clip": .clip(previousClip)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clip(let clip)? = result.undoValues["clip"] {
            return AudioFadeCommand(
                clipId: clipId,
                fadeInDuration: clip.fadeInDuration,
                fadeOutDuration: clip.fadeOutDuration
            )
        }

        guard let oldFadeIn, let oldFadeOut else {
            return NoOpCommand(description: "Missing previous audio fade values for inverse")
        }
        return AudioFadeCommand(clipId: clipId, fadeInDuration: oldFadeIn, fadeOutDuration: oldFadeOut)
    }

    public func invert() -> any EditorCommand {
        guard let oldFadeIn, let oldFadeOut else {
            return NoOpCommand(description: "Missing previous audio fade values for inverse")
        }
        return AudioFadeCommand(clipId: clipId, fadeInDuration: oldFadeIn, fadeOutDuration: oldFadeOut)
    }
}
