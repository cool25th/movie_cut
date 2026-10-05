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

    /// The session revision shifted while an asynchronous command/plan was preparing.
    case staleRevision(expected: SessionRevision, current: SessionRevision)

    /// A prepared plan was dispatched twice with the same `planId`. The
    /// first successful dispatch records the id; a re-dispatch of the SAME
    /// prepared batch is an accident or a lost-response retry — never a
    /// second edit. Re-running the intent produces a NEW plan id.
    case duplicatePlanApplication(UUID)
}
