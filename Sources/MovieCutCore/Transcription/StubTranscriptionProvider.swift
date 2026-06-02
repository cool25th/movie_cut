import Foundation

/// Placeholder transcription provider used before a real ASR backend is wired in.
public struct StubTranscriptionProvider: TranscriptionProvider {
    /// Creates a stub provider.
    public init() {}

    public func transcribe(audioURL: URL, language: String?) async throws -> TranscriptionResult {
        TranscriptionResult(segments: [], language: language)
    }

    public var isAvailable: Bool {
        get async { false }
    }

    public var providerName: String {
        "Stub"
    }
}
