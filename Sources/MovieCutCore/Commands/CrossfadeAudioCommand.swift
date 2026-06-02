import Foundation

public struct CrossfadeAudioCommand: EditorCommand, Sendable, Codable {
    public let id: UUID
    public var clipAId: UUID
    public var clipBId: UUID
    public var duration: TimeInterval
    public var oldClipAFadeOut: TimeInterval?
    public var oldClipBFadeIn: TimeInterval?

    public init(
        id: UUID = UUID(),
        clipAId: UUID,
        clipBId: UUID,
        duration: TimeInterval,
        oldClipAFadeOut: TimeInterval? = nil,
        oldClipBFadeIn: TimeInterval? = nil
    ) {
        self.id = id
        self.clipAId = clipAId
        self.clipBId = clipBId
        self.duration = duration
        self.oldClipAFadeOut = oldClipAFadeOut
        self.oldClipBFadeIn = oldClipBFadeIn
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        guard duration >= 0, duration.isFinite else {
            throw EditorCommandError.invalidCommand("Crossfade duration cannot be negative or infinite.")
        }

        let clipALocation = try project.clipLocation(for: clipAId)
        let clipBLocation = try project.clipLocation(for: clipBId)
        try project.ensureTrackIsEditable(at: clipALocation.trackIndex)
        try project.ensureTrackIsEditable(at: clipBLocation.trackIndex)

        let previousClipA = project.timeline.tracks[clipALocation.trackIndex].clips[clipALocation.clipIndex]
        let previousClipB = project.timeline.tracks[clipBLocation.trackIndex].clips[clipBLocation.clipIndex]

        project.timeline.tracks[clipALocation.trackIndex].clips[clipALocation.clipIndex].fadeOutDuration = duration
        project.timeline.tracks[clipBLocation.trackIndex].clips[clipBLocation.clipIndex].fadeInDuration = duration

        return CommandResult(
            affectedClipIds: [clipAId, clipBId],
            description: "Crossfaded audio clips \(clipAId) and \(clipBId)",
            undoValues: [
                "clipA": .clip(previousClipA),
                "clipB": .clip(previousClipB)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .clip(let clipA)? = result.undoValues["clipA"],
            case .clip(let clipB)? = result.undoValues["clipB"]
        {
            return RestoreAudioCrossfadeCommand(
                clipAId: clipAId,
                clipBId: clipBId,
                clipAFadeOutDuration: clipA.fadeOutDuration,
                clipBFadeInDuration: clipB.fadeInDuration
            )
        }

        guard let oldClipAFadeOut, let oldClipBFadeIn else {
            return NoOpCommand(description: "Missing previous audio crossfade values for inverse")
        }
        return RestoreAudioCrossfadeCommand(
            clipAId: clipAId,
            clipBId: clipBId,
            clipAFadeOutDuration: oldClipAFadeOut,
            clipBFadeInDuration: oldClipBFadeIn
        )
    }
}

private struct RestoreAudioCrossfadeCommand: EditorCommand, Sendable, Codable {
    let id: UUID
    var clipAId: UUID
    var clipBId: UUID
    var clipAFadeOutDuration: TimeInterval
    var clipBFadeInDuration: TimeInterval

    init(
        id: UUID = UUID(),
        clipAId: UUID,
        clipBId: UUID,
        clipAFadeOutDuration: TimeInterval,
        clipBFadeInDuration: TimeInterval
    ) {
        self.id = id
        self.clipAId = clipAId
        self.clipBId = clipBId
        self.clipAFadeOutDuration = clipAFadeOutDuration
        self.clipBFadeInDuration = clipBFadeInDuration
    }

    func apply(to project: inout Project) throws -> CommandResult {
        guard
            clipAFadeOutDuration >= 0,
            clipAFadeOutDuration.isFinite,
            clipBFadeInDuration >= 0,
            clipBFadeInDuration.isFinite
        else {
            throw EditorCommandError.invalidCommand("Audio fade durations cannot be negative or infinite.")
        }

        let clipALocation = try project.clipLocation(for: clipAId)
        let clipBLocation = try project.clipLocation(for: clipBId)
        try project.ensureTrackIsEditable(at: clipALocation.trackIndex)
        try project.ensureTrackIsEditable(at: clipBLocation.trackIndex)

        let previousClipA = project.timeline.tracks[clipALocation.trackIndex].clips[clipALocation.clipIndex]
        let previousClipB = project.timeline.tracks[clipBLocation.trackIndex].clips[clipBLocation.clipIndex]

        project.timeline.tracks[clipALocation.trackIndex].clips[clipALocation.clipIndex].fadeOutDuration = clipAFadeOutDuration
        project.timeline.tracks[clipBLocation.trackIndex].clips[clipBLocation.clipIndex].fadeInDuration = clipBFadeInDuration

        return CommandResult(
            affectedClipIds: [clipAId, clipBId],
            description: "Restored audio crossfade values for \(clipAId) and \(clipBId)",
            undoValues: [
                "clipA": .clip(previousClipA),
                "clipB": .clip(previousClipB)
            ]
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .clip(let clipA)? = result.undoValues["clipA"],
            case .clip(let clipB)? = result.undoValues["clipB"]
        {
            return RestoreAudioCrossfadeCommand(
                clipAId: clipAId,
                clipBId: clipBId,
                clipAFadeOutDuration: clipA.fadeOutDuration,
                clipBFadeInDuration: clipB.fadeInDuration
            )
        }

        return NoOpCommand(description: "Missing previous audio crossfade values for inverse")
    }
}
