import Foundation

/// A single timed speech segment produced by transcription.
public struct TranscriptionSegment: Codable, Sendable, Equatable, Identifiable {
    /// The segment identifier.
    public var id: UUID

    /// The recognized text.
    public var text: String

    /// Segment start time in seconds.
    public var startTime: TimeInterval

    /// Segment end time in seconds.
    public var endTime: TimeInterval

    /// Provider confidence from 0.0 to 1.0.
    public var confidence: Double

    /// Creates a transcription segment.
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = min(max(confidence, 0.0), 1.0)
    }
}

/// The complete output from an ASR provider.
public struct TranscriptionResult: Codable, Sendable, Equatable {
    /// Timed transcription segments.
    public var segments: [TranscriptionSegment]

    /// Optional BCP-47 language identifier.
    public var language: String?

    /// The full transcription text joined from all segments.
    public var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    /// Creates a transcription result.
    public init(segments: [TranscriptionSegment], language: String? = nil) {
        self.segments = segments
        self.language = language
    }
}

/// Errors surfaced by the transcription abstraction.
public enum TranscriptionError: Error, Sendable, Equatable {
    /// The source asset cannot be transcribed yet.
    case assetNotReady

    /// The provider failed with a message.
    case transcriptionFailed(String)

    /// Transcription is unavailable on the current system or provider.
    case notSupported
}
