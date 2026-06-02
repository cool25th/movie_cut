import Foundation

/// A provider capable of turning an audio source into timed speech segments.
public protocol TranscriptionProvider: Sendable {
    /// Transcribes an audio file URL, optionally constrained to a language.
    func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult

    /// Whether this provider can be used in the current environment.
    var isAvailable: Bool { get async }

    /// User-visible provider name.
    var providerName: String { get }
}
