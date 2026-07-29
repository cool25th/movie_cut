import Foundation

/// Updates the project's editing canvas preset.
public struct SetProjectCanvasCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new canvas preset.
    public var canvas: CanvasPreset

    /// Optional prior canvas used when constructing an inverse command.
    public var previousCanvas: CanvasPreset?

    /// Creates a canvas update command.
    public init(id: UUID = UUID(), canvas: CanvasPreset, previousCanvas: CanvasPreset? = nil) {
        self.id = id
        self.canvas = canvas
        self.previousCanvas = previousCanvas
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let previousCanvas = project.canvas
        project.canvas = canvas
        project.timeline.canvasSize = canvas.size
        project.timeline.aspectRatio = canvas.aspectRatio
        project.timeline.frameRate = canvas.frameRate.rational

        return CommandResult(
            description: "Set project canvas",
            undoValues: ["canvas": .canvasPreset(previousCanvas)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .canvasPreset(let canvas)? = result.undoValues["canvas"] {
            return SetProjectCanvasCommand(canvas: canvas)
        }

        guard let previousCanvas else {
            return NoOpCommand(description: "Missing canvas preset for inverse")
        }
        return SetProjectCanvasCommand(canvas: previousCanvas)
    }
}

/// Updates the project's default export preset settings.
public struct SetProjectExportSettingsCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new export settings.
    public var exportSettings: ExportSettings

    /// Optional prior settings used when constructing an inverse command.
    public var previousExportSettings: ExportSettings?

    /// Creates an export settings update command.
    public init(
        id: UUID = UUID(),
        exportSettings: ExportSettings,
        previousExportSettings: ExportSettings? = nil
    ) {
        self.id = id
        self.exportSettings = exportSettings
        self.previousExportSettings = previousExportSettings
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let previousSettings = project.exportSettings
        project.exportSettings = exportSettings

        return CommandResult(
            description: "Set project export settings",
            undoValues: ["exportSettings": .exportSettings(previousSettings)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .exportSettings(let settings)? = result.undoValues["exportSettings"] {
            return SetProjectExportSettingsCommand(exportSettings: settings)
        }

        guard let previousExportSettings else {
            return NoOpCommand(description: "Missing export settings for inverse")
        }
        return SetProjectExportSettingsCommand(exportSettings: previousExportSettings)
    }
}

/// Updates the project's playback (preview) settings.
public struct SetProjectPlaybackSettingsCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new playback settings.
    public var playbackSettings: PlaybackSettings

    /// Optional prior settings used when constructing an inverse command.
    public var previousPlaybackSettings: PlaybackSettings?

    /// Creates a playback settings update command.
    public init(
        id: UUID = UUID(),
        playbackSettings: PlaybackSettings,
        previousPlaybackSettings: PlaybackSettings? = nil
    ) {
        self.id = id
        self.playbackSettings = playbackSettings
        self.previousPlaybackSettings = previousPlaybackSettings
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let previousSettings = project.playbackSettings
        project.playbackSettings = playbackSettings

        return CommandResult(
            description: "Set project playback settings",
            undoValues: ["playbackSettings": .playbackSettings(previousSettings)]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if case .playbackSettings(let settings)? = result.undoValues["playbackSettings"] {
            return SetProjectPlaybackSettingsCommand(playbackSettings: settings)
        }

        guard let previousPlaybackSettings else {
            return NoOpCommand(description: "Missing playback settings for inverse")
        }
        return SetProjectPlaybackSettingsCommand(playbackSettings: previousPlaybackSettings)
    }
}

private extension ExportFrameRate {
    var rational: Rational {
        switch self {
        case .fps24:
            return Rational(numerator: 24, denominator: 1)
        case .fps30:
            return Rational(numerator: 30, denominator: 1)
        case .fps60:
            return Rational(numerator: 60, denominator: 1)
        }
    }
}
