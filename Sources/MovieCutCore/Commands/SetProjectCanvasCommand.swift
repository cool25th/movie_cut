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

    public func apply(to project: inout Project) throws {
        let previousCanvas = project.canvas
        project.canvas = canvas
        project.timeline.canvasSize = canvas.size
        project.timeline.aspectRatio = canvas.aspectRatio
        project.timeline.frameRate = canvas.frameRate.rational
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

    public func apply(to project: inout Project) throws {
        let previousSettings = project.exportSettings
        project.exportSettings = exportSettings
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

    public func apply(to project: inout Project) throws {
        let previousSettings = project.playbackSettings
        project.playbackSettings = playbackSettings
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
