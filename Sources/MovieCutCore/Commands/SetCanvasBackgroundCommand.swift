import Foundation

/// Sets or clears the project canvas background fill.
public struct SetCanvasBackgroundCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The new background, or nil for the default black canvas.
    public var background: CanvasBackground?

    /// Optional prior background used when constructing an inverse command.
    public var previousBackground: CanvasBackground?

    /// Creates a set-canvas-background command.
    public init(
        id: UUID = UUID(),
        background: CanvasBackground?,
        previousBackground: CanvasBackground? = nil
    ) {
        self.id = id
        self.background = background
        self.previousBackground = previousBackground
    }

    public func apply(to project: inout Project) throws {
        let previous = project.canvasBackground
        project.canvasBackground = background

    }

    }
