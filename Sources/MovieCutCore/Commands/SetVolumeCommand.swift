import Foundation

/// Sets the audio volume multiplier for a clip.
public struct SetVolumeCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to modify.
    public var clipId: UUID

    /// The new volume multiplier.
    public var volume: Double

    /// Optional prior volume used when constructing an inverse command.
    public var previousVolume: Double?

    /// Creates a set-volume command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        volume: Double,
        previousVolume: Double? = nil
    ) {
        self.id = id
        self.clipId = clipId
        self.volume = volume
        self.previousVolume = previousVolume
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        try SetClipPropertyCommand(
            id: id,
            clipId: clipId,
            property: .volume(volume),
            previousProperty: previousVolume.map(ClipProperty.volume)
        )
        .apply(to: &project)
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .clipProperty(.volume(let volume))? = result.undoValues["property"] {
            return SetVolumeCommand(clipId: clipId, volume: volume)
        }

        guard let previousVolume else {
            return NoOpCommand(description: "Missing previous clip volume for inverse")
        }
        return SetVolumeCommand(clipId: clipId, volume: previousVolume)
    }
}
