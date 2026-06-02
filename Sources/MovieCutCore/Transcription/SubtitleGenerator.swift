import Foundation

/// Converts transcription segments into timeline text clips.
public struct SubtitleGenerator: Sendable {
    /// Creates text clips for each transcription segment.
    public static func generateClips(from result: TranscriptionResult, trackId: UUID) -> [Clip] {
        _ = trackId

        return result.segments.map { segment in
            let duration = max(0, segment.endTime - segment.startTime)
            let range = TimeRange(start: segment.startTime, duration: duration)
            return Clip(
                assetId: nil,
                kind: .text,
                sourceRange: range,
                timelineRange: range,
                textContent: TextClipContent(text: segment.text)
            )
        }
    }
}
