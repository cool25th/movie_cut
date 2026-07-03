import Foundation

/// Converts transcription segments into timeline text clips.
public struct SubtitleGenerator: Sendable {
    /// Creates text clips for each transcription segment.
    public static func generateClips(from result: TranscriptionResult, trackId: UUID) -> [Clip] {
        _ = trackId

        return result.segments.map { segment in
            let duration = max(0, segment.endTime - segment.startTime)
            let range = TimeRange(start: segment.startTime, duration: duration)
            let relativeWords = relativeWordTimings(for: segment, duration: duration)
            return Clip(
                assetId: nil,
                kind: .text,
                sourceRange: range,
                timelineRange: range,
                textContent: TextClipContent(text: segment.text, wordTimings: relativeWords)
            )
        }
    }

    private static func relativeWordTimings(for segment: TranscriptionSegment, duration: TimeInterval) -> [WordTiming]? {
        guard let words = segment.words else { return nil }
        let segmentRange = TimeRange(start: segment.startTime, duration: duration)
        return words.map { word in
            word
                .clamped(to: segmentRange)
                .shifted(by: -segment.startTime)
        }
    }
}
