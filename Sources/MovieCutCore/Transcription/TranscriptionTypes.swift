import Foundation

/// A word-level timing emitted by a speech provider.
public struct WordTiming: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var text: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var confidence: Double

    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double
    ) {
        self.id = id
        self.text = text
        self.startTime = max(0, startTime)
        self.endTime = max(self.startTime, endTime)
        self.confidence = min(max(confidence, 0.0), 1.0)
    }

    public func clamped(to range: TimeRange) -> WordTiming {
        let lower = range.start
        let upper = range.end
        let clampedStart = min(max(startTime, lower), upper)
        let clampedEnd = min(max(endTime, clampedStart), upper)
        return WordTiming(
            id: id,
            text: text,
            startTime: clampedStart,
            endTime: clampedEnd,
            confidence: confidence
        )
    }

    public func shifted(by offset: TimeInterval) -> WordTiming {
        WordTiming(
            id: id,
            text: text,
            startTime: startTime + offset,
            endTime: endTime + offset,
            confidence: confidence
        )
    }
}

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

    /// Optional word timings in source-audio absolute seconds.
    public var words: [WordTiming]?

    /// Creates a transcription segment.
    public init(
        id: UUID = UUID(),
        text: String,
        startTime: TimeInterval,
        endTime: TimeInterval,
        confidence: Double,
        words: [WordTiming]? = nil
    ) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.words = words
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
public enum TranscriptionError: Error, LocalizedError, Sendable, Equatable {
    /// The source asset cannot be transcribed yet.
    case assetNotReady

    /// The provider failed with a message.
    case transcriptionFailed(String)

    /// Transcription is unavailable on the current system or provider.
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .assetNotReady:
            return "Select an audio or video asset that is ready for transcription."
        case .transcriptionFailed(let message):
            return message
        case .notSupported:
            return "Transcription is unavailable on this system or provider."
        }
    }
}
