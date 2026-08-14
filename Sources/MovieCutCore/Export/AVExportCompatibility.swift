import AVFoundation
import Foundation

#if canImport(AVFoundation)
/// Cross-toolchain wrapper for `AVAssetExportSession` exports.
///
/// Two SDK-dependent traps this centralizes:
/// 1. **Availability.** The plain `try await session.export(to:as:)` resolves
///   DIFFERENTLY by SDK: on the macOS 15 SDK the compiler picks
///   `export(to:as:isolation:)` over the deprecated original, which is
///   macOS 15+/iOS 18+ — an availability error against this package's macOS 14
///   / iOS 17 minimums. Later SDKs backfilled the availability, so the same
///   code builds on Swift 6.3/Xcode 26 but fails on Xcode 16 — exactly what
///   the GitHub CI (pinned to Xcode 16) exposed.
/// 2. **Sendable.** `AVAssetExportSession` is not Sendable, so passing it from
///   a `@MainActor` engine into a nonisolated helper trips Swift 6.3's
///   region-isolation check. The box opts out explicitly: each session is
///   created, configured, and awaited within one sequential flow, so there is
///   no actual cross-task sharing. (`sending` parameters would express this
///   precisely but need Swift 6.2, which the pinned Xcode 16 lacks.)
public enum AVExportCompatibility {
    /// A `@unchecked Sendable` box for a single-flow export session.
    public struct SessionBox: @unchecked Sendable {
        public let session: AVAssetExportSession
        public init(_ session: AVAssetExportSession) {
            self.session = session
        }
    }

    /// Exports via the given session, handling the macOS 15 / iOS 18 API split.
    public static func export(
        _ box: SessionBox,
        to url: URL,
        as fileType: AVFileType
    ) async throws {
        let session = box.session
        if #available(macOS 15.0, iOS 18.0, *) {
            try await session.export(to: url, as: fileType)
        } else {
            // Legacy imperative path for macOS 14 / iOS 17. On newer SDKs this
            // branch compiles with a deprecation warning only; it is never
            // executed there because the availability gate takes the branch
            // above.
            session.outputURL = url
            session.outputFileType = fileType
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                session.exportAsynchronously {
                    continuation.resume()
                }
            }
            guard session.status == .completed else {
                throw session.error
                    ?? CocoaError(.fileWriteUnknown, userInfo: [
                        NSFilePathErrorKey: url.path
                    ])
            }
        }
    }
}
#endif
