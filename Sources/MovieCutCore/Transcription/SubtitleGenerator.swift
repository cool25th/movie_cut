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

// MARK: - Word-timing preservation across segment edits
// (capcut-surpass 10af50b re-port: split/merge edit paths keep karaoke
// captions karaoke-capable instead of silently dropping segment.words.)

public extension SubtitleGenerator {
    /// Splits a segment's word timings at `midTime` into the two halves a
    /// split produces. Words are partitioned by their start time relative to
    /// `midTime`; timings stay in the same absolute-source-second frame as
    /// the input so the result drops straight into the two new segments'
    /// `words`. Returns `nil` only when there were no word timings to begin
    /// with — a split must never *demote* a karaoke-capable segment.
    ///
    /// Words whose start exactly equals `midTime` go to the second half, so a
    /// split at a word boundary is clean.
    static func splitWordTimings(
        _ words: [WordTiming]?,
        at midTime: TimeInterval
    ) -> (first: [WordTiming], second: [WordTiming])? {
        guard let words, !words.isEmpty else { return nil }
        let first = words.filter { $0.startTime < midTime }
        let second = words.filter { $0.startTime >= midTime }
        return (first, second)
    }

    /// Merges two word-timing arrays (both in absolute source seconds) into
    /// one, preserving order and dropping duplicates by word id.
    static func mergedWordTimings(
        _ first: [WordTiming]?,
        _ second: [WordTiming]?
    ) -> [WordTiming]? {
        switch (first?.isEmpty ?? true, second?.isEmpty ?? true) {
        case (true, true):
            return nil
        case (true, false):
            return second
        case (false, true):
            return first
        case (false, false):
            let seen = Set(first!.map(\.id))
            let merged = first! + second!.filter { !seen.contains($0.id) }
            return merged.sorted(by: { lhs, rhs in lhs.startTime < rhs.startTime })
        }
    }
}

public extension SubtitleGenerator {
    /// Maps a segment's absolute-source-second word timings into the
    /// timeline-relative frame a karaoke render expects for a clip aligned to
    /// `clip`. Words map source→timeline through the clip's canonical
    /// `ClipTimeMapping`, then shift by `-timelineRange.start`; words outside
    /// the mapped span are dropped. Returns `nil` when the segment carries no
    /// word timings, so an aligned clip never silently demotes karaoke.
    static func wordTimingsAlignedToClip(
        for segment: TranscriptionSegment,
        clip: Clip
    ) -> [WordTiming]? {
        guard let words = segment.words, !words.isEmpty else { return nil }
        guard let mapping = clip.makeTimeMapping() else { return nil }

        let timelineStart = clip.timelineRange.start
        let timelineEnd = clip.timelineRange.end
        return words.compactMap { word -> WordTiming? in
            let wordTimelineStart = mapping.timelineTime(forSourceTime: word.startTime)
            let wordTimelineEnd = mapping.timelineTime(forSourceTime: word.endTime)
            guard wordTimelineStart.isFinite, wordTimelineEnd.isFinite else { return nil }
            guard wordTimelineEnd > timelineStart, wordTimelineStart < timelineEnd else { return nil }
            let clampedStart = min(max(wordTimelineStart, timelineStart), timelineEnd)
            let clampedEnd = min(max(wordTimelineEnd, clampedStart), timelineEnd)
            return WordTiming(
                id: word.id,
                text: word.text,
                startTime: clampedStart - timelineStart,
                endTime: clampedEnd - timelineStart,
                confidence: word.confidence
            )
        }
    }
}
