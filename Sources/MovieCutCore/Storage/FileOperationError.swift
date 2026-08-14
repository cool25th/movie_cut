import Foundation

/// User-facing classification of file-operation errors (save, export, autosave).
///
/// Foundation throws opaque `NSError`/`CocoaError` strings for disk-full,
/// permission, and quota failures. Surfacing `error.localizedDescription`
/// gives the user a raw Foundation message with no remediation guidance. This
/// type maps the common, actionable failure modes to a short, plain-language
/// category and message so the UI can tell the user what to do — and so tests
/// can assert the mapping rather than a fragile string.
///
/// The v1 render-reliability plan calls out disk-full handling as a gap (zero
/// `ENOSPC` handling existed). This is the single source of truth for that
/// classification across save and export paths.
public enum FileOperationError: Error, Sendable, Equatable {
    /// The destination disk is out of space (or hit a per-volume quota).
    case diskFull
    /// The app lacks permission to write at the destination (sandbox, readonly).
    case permissionDenied
    /// The destination file could not be created or replaced.
    case writeFailed
    /// The file being read is missing.
    case fileNotFound
    /// The file being read is corrupt or unreadable (decode failed).
    case corrupt
    /// The operation was cancelled by the user.
    case cancelled
    /// Anything else; carries the underlying message for diagnostics.
    case other(String)

    /// A short, user-actionable message for this category.
    public var userMessage: String {
        switch self {
        case .diskFull:
            return "The disk is out of space. Free up storage and try again."
        case .permissionDenied:
            return "MovieCut doesn't have permission to write there. Pick a different location."
        case .writeFailed:
            return "The file couldn't be saved. Try a different folder or filename."
        case .fileNotFound:
            return "The file can't be found. It may have been moved or deleted."
        case .corrupt:
            return "The file appears to be damaged and can't be read."
        case .cancelled:
            return "The operation was cancelled."
        case .other(let message):
            return message
        }
    }

    /// Classifies a thrown error into a `FileOperationError` category.
    ///
    /// Inspects `NSError` codes (`NSFileWriteOutOfSpaceError`,
    /// `NSFileWriteNoPermissionError`, `NSFileNoSuchFileError`, etc.) and the
    /// `POSIXError` `ENOSPC` fallback. Unknown errors become `.other`.
    public static func classify(_ error: Error) -> FileOperationError {
        let nsError = error as NSError

        // Cancellation: cooperative `CancellationError` or a POSIX EINTR/ECANCELED.
        if error is CancellationError {
            return .cancelled
        }

        // CocoaError write-side codes.
        if let cocoa = nsError as? CocoaError {
            switch cocoa.code {
            case .fileWriteOutOfSpace:
                return .diskFull
            case .fileWriteNoPermission, .fileWriteVolumeReadOnly:
                return .permissionDenied
            case .fileNoSuchFile, .fileReadNoSuchFile:
                return .fileNotFound
            default:
                break
            }
        }

        // Raw NSError code fallbacks (some paths don't wrap in CocoaError).
        let domain = nsError.domain
        let code = nsError.code
        if domain == NSCocoaErrorDomain {
            if code == NSFileWriteOutOfSpaceError { return .diskFull }
            if code == NSFileWriteNoPermissionError { return .permissionDenied }
            if code == NSFileNoSuchFileError { return .fileNotFound }
        }

        // POSIX ENOSPC — raised directly by some lower-level writes.
        if domain == NSPOSIXErrorDomain, code == Int(POSIXError.ENOSPC.rawValue) {
            return .diskFull
        }

        // DecodingError / corruption.
        if error is DecodingError {
            return .corrupt
        }

        return .other(nsError.localizedDescription)
    }
}
