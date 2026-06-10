import Foundation

/// Typed values captured while applying a command and used to build inverses.
public enum CommandResultValue: Sendable, Equatable {
    /// A UUID value.
    case uuid(UUID)

    /// An array index.
    case int(Int)

    /// A timeline time range.
    case timeRange(TimeRange)

    /// A full clip snapshot.
    case clip(Clip)

    /// A full marker snapshot.
    case marker(Marker)

    /// A full media asset snapshot.
    case mediaAsset(MediaAsset)

    /// A clip property snapshot.
    case clipProperty(ClipProperty)

    /// A track property snapshot.
    case trackProperty(TrackProperty)

    /// A canvas preset snapshot.
    case canvasPreset(CanvasPreset)

    /// A project export settings snapshot.
    case exportSettings(ExportSettings)
}

/// The observable result of applying an editor command.
public struct CommandResult: Sendable, Equatable {
    /// Clip identifiers touched by the command.
    public let affectedClipIds: Set<UUID>

    /// A human-readable summary for diagnostics and undo labels.
    public let description: String

    /// Values captured by apply for constructing inverse commands.
    public let undoValues: [String: CommandResultValue]

    /// Creates a command result.
    public init(
        affectedClipIds: Set<UUID> = [],
        description: String,
        undoValues: [String: CommandResultValue] = [:]
    ) {
        self.affectedClipIds = affectedClipIds
        self.description = description
        self.undoValues = undoValues
    }
}
