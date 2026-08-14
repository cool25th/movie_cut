import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for `FileOperationError.classify`.
///
/// These are NOT static-contract tests — they construct real `NSError` /
/// `CocoaError` values for each failure mode and assert the classification
/// maps them to the right user-facing category. The gap this pins: before this
/// type, save and export surfaced raw `error.localizedDescription` for every
/// failure (disk-full included), giving the user an opaque Foundation string
/// with no remediation. If a future change reverts to raw strings or breaks the
/// disk-full mapping, these tests fail.
@Suite("File Operation Error Classification")
struct FileOperationErrorTests {
    @Test("disk-full CocoaError classifies to .diskFull")
    func diskFullCocoaError() {
        let error = CocoaError(.fileWriteOutOfSpace)
        #expect(FileOperationError.classify(error) == .diskFull)
        #expect(FileOperationError.diskFull.userMessage.lowercased().contains("space"))
    }

    @Test("disk-full raw NSCocoaErrorDomain code maps to .diskFull")
    func diskFullRawNSError() {
        // Some write paths raise a plain NSError in NSCocoaErrorDomain rather
        // than a typed CocoaError; the classifier must still catch the code.
        let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(FileOperationError.classify(error) == .diskFull)
    }

    @Test("disk-full POSIX ENOSPC maps to .diskFull")
    func diskFullPOSIX() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.ENOSPC.rawValue))
        #expect(FileOperationError.classify(error) == .diskFull)
    }

    @Test("permission-denied classifies to .permissionDenied")
    func permissionDenied() {
        let error = CocoaError(.fileWriteNoPermission)
        #expect(FileOperationError.classify(error) == .permissionDenied)
        #expect(FileOperationError.permissionDenied.userMessage.lowercased().contains("permission"))
    }

    @Test("missing file classifies to .fileNotFound")
    func fileNotFound() {
        let error = CocoaError(.fileNoSuchFile)
        #expect(FileOperationError.classify(error) == .fileNotFound)
    }

    @Test("decoding failure classifies to .corrupt")
    func corruptDecode() {
        struct Bomb: Decodable {}
        let decoder = JSONDecoder()
        do {
            _ = try decoder.decode(Bomb.self, from: Data("not json".utf8))
            Issue.record("expected decode to throw")
        } catch {
            #expect(FileOperationError.classify(error) == .corrupt)
        }
    }

    @Test("cancellation classifies to .cancelled")
    func cancellation() {
        let error = CancellationError()
        #expect(FileOperationError.classify(error) == .cancelled)
    }

    @Test("unknown error falls back to .other with the underlying message")
    func unknownFallback() {
        let error = NSError(domain: "MovieCut", code: 42, userInfo: [NSLocalizedDescriptionKey: "something broke"])
        let classified = FileOperationError.classify(error)
        if case .other(let message) = classified {
            #expect(message == "something broke")
        } else {
            Issue.record("expected .other, got \(classified)")
        }
    }

    @Test("userMessage is non-empty for every category")
    func userMessageNonEmpty() {
        for category in [FileOperationError.diskFull, .permissionDenied, .writeFailed,
                         .fileNotFound, .corrupt, .cancelled, .other("boom")] {
            #expect(!category.userMessage.isEmpty, "\(category) has an empty userMessage")
        }
    }
}
