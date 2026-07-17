import Foundation

/// Errors thrown by Phase 0 editor commands and sessions.
public enum EditorCommandError: Error, Sendable, Equatable {
    /// A requested track does not exist.
    case trackNotFound(UUID)

    /// A requested clip does not exist.
    case clipNotFound(UUID)

    /// A requested media asset does not exist.
    case assetNotFound(UUID)

    /// The project does not contain a card document.
    case cardDocumentMissing

    /// A requested card page does not exist.
    case cardPageNotFound(UUID)

    /// A requested card element does not exist.
    case cardElementNotFound(UUID)

    /// The operation attempted to edit a locked track.
    case trackLocked(UUID)

    /// The command arguments are invalid.
    case invalidCommand(String)

    /// There is no undo history.
    case nothingToUndo

    /// There is no redo history.
    case nothingToRedo
}
