import Foundation

/// Applies a canvas change AND an export-settings change in ONE command so a
/// single undo restores both (CODEX-18).
///
/// The fps preset surfaces previously dispatched `SetProjectCanvasCommand`
/// and `SetProjectExportSettingsCommand` back to back — the session is
/// snapshot-based, so that produced TWO undo steps, and one undo restored
/// only the export frame rate while the canvas/timeline kept the new fps:
/// the very drift the lockstep was meant to prevent. This command composes
/// both mutations atomically: canvas (with its timeline size/aspect/frame
/// rate rebind, matching `SetProjectCanvasCommand`) plus the export
/// settings, landing as a single undo entry.
public struct SetProjectCanvasAndExportSettingsCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new canvas preset.
    public var canvas: CanvasPreset

    /// The new export settings.
    public var exportSettings: ExportSettings

    /// Optional prior values used when constructing an inverse command.
    public var previousCanvas: CanvasPreset?
    public var previousExportSettings: ExportSettings?

    /// Creates an atomic canvas + export-settings update.
    public init(
        id: UUID = UUID(),
        canvas: CanvasPreset,
        exportSettings: ExportSettings,
        previousCanvas: CanvasPreset? = nil,
        previousExportSettings: ExportSettings? = nil
    ) {
        self.id = id
        self.canvas = canvas
        self.exportSettings = exportSettings
        self.previousCanvas = previousCanvas
        self.previousExportSettings = previousExportSettings
    }

    public func apply(to project: inout Project) throws {
        // Canvas half — identical rebind to SetProjectCanvasCommand.
        project.canvas = canvas
        project.timeline.canvasSize = canvas.size
        project.timeline.aspectRatio = canvas.aspectRatio
        project.timeline.frameRate = canvas.frameRate.rational
        // Export half.
        project.exportSettings = exportSettings
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
