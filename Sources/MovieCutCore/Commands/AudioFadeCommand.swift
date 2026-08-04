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

    public func apply(to project: inout Project) throws {
        guard fadeInDuration >= 0, fadeOutDuration >= 0 else {
            throw EditorCommandError.invalidCommand("Audio fade durations cannot be negative.")
        }

        let location = try project.clipLocation(for: clipId)
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let previousClip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].fadeInDuration = fadeInDuration
        project.timeline.tracks[location.trackIndex].clips[location.clipIndex].fadeOutDuration = fadeOutDuration
    }
}
