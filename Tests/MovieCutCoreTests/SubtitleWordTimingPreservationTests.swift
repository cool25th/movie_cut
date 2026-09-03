import Foundation
import MovieCutCore
import Testing

/// STEP 2 — word-timing preservation across the subtitle edit paths.
///
/// Karaoke captions carry per-word timings in `TranscriptionSegment.words`.
/// Three edit paths previously dropped them, silently demoting a karaoke
/// caption to plain text: split, merge, and timeline alignment. The
/// `SubtitleGenerator` word-timing helpers exist to keep karaoke working
/// through those edits, and these tests pin that behavior at the model level
/// (no render needed — the render path is covered by the parity sweep).
@Suite("Subtitle word-timing preservation (STEP 2)")
struct SubtitleWordTimingPreservationTests {

    // MARK: - splitWordTimings

    @Test("split partitions words by midTime and never returns nil for non-empty input")
    func splitPartitionsByMidTime() {
        let words = [
            WordTiming(text: "one", startTime: 1.0, endTime: 1.5, confidence: 1),
            WordTiming(text: "two", startTime: 2.0, endTime: 2.5, confidence: 1),
            WordTiming(text: "three", startTime: 3.0, endTime: 3.5, confidence: 1)
        ]

        let halves = SubtitleGenerator.splitWordTimings(words, at: 2.5)
        #expect(halves != nil)
        #expect(halves?.first.map(\.text) == ["one", "two"])
        #expect(halves?.second.map(\.text) == ["three"])
    }

    @Test("split at a word boundary puts the boundary word in the second half")
    func splitAtWordBoundary() {
        let words = [
            WordTiming(text: "one", startTime: 1.0, endTime: 1.5, confidence: 1),
            WordTiming(text: "two", startTime: 2.0, endTime: 2.5, confidence: 1)
        ]
        // midTime == a word's start: that word belongs to the second half.
        let halves = SubtitleGenerator.splitWordTimings(words, at: 2.0)
        #expect(halves?.first.map(\.text) == ["one"])
        #expect(halves?.second.map(\.text) == ["two"])
    }

    @Test("split returns nil only when there were no word timings")
    func splitNilOnlyWhenEmpty() {
        #expect(SubtitleGenerator.splitWordTimings(nil, at: 1.0) == nil)
        #expect(SubtitleGenerator.splitWordTimings([], at: 1.0) == nil)
    }

    // MARK: - mergedWordTimings

    @Test("merge concatenates, deduplicates by id, and sorts by start time")
    func mergeConcatenatesAndDeduplicates() {
        let first = [
            WordTiming(text: "a", startTime: 1.0, endTime: 1.4, confidence: 1),
            WordTiming(text: "c", startTime: 3.0, endTime: 3.4, confidence: 1)
        ]
        let second = [
            WordTiming(text: "b", startTime: 2.0, endTime: 2.4, confidence: 1),
            // Duplicate of a word already in `first` (same id) — must be dropped.
            WordTiming(id: first[0].id, text: "a", startTime: 1.0, endTime: 1.4, confidence: 1)
        ]

        let merged = SubtitleGenerator.mergedWordTimings(first, second)
        #expect(merged?.map(\.text) == ["a", "b", "c"])
    }

    @Test("merge with one nil side returns the other")
    func mergeOneNilSide() {
        let words = [WordTiming(text: "only", startTime: 1.0, endTime: 1.5, confidence: 1)]
        #expect(SubtitleGenerator.mergedWordTimings(words, nil)?.count == 1)
        #expect(SubtitleGenerator.mergedWordTimings(nil, words)?.count == 1)
    }

    @Test("merge of two nil/empty sides returns nil")
    func mergeTwoEmptyReturnsNil() {
        #expect(SubtitleGenerator.mergedWordTimings(nil, nil) == nil)
        #expect(SubtitleGenerator.mergedWordTimings([], []) == nil)
        #expect(SubtitleGenerator.mergedWordTimings(nil, []) == nil)
    }

    // MARK: - wordTimingsAlignedToClip

    @Test("alignment maps absolute source words to clip-relative timeline seconds")
    func alignmentMapsToClipRelativeTimeline() {
        // Segment words are absolute source seconds in [10, 12].
        let segment = TranscriptionSegment(
            text: "hello world",
            startTime: 10,
            endTime: 12,
            confidence: 1,
            words: [
                WordTiming(text: "hello", startTime: 10.1, endTime: 10.5, confidence: 1),
                WordTiming(text: "world", startTime: 10.6, endTime: 11.0, confidence: 1)
            ]
        )
        // A clip whose source covers [10, 12] and which sits on the timeline
        // at [100, 102] (1:1 rate). The render reads `time - timeRangeStart`,
        // so word timings must be expressed relative to timeline start 100.
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 10, duration: 2),
            timelineRange: TimeRange(start: 100, duration: 2)
        )

        let aligned = SubtitleGenerator.wordTimingsAlignedToClip(for: segment, clip: clip)
        #expect(aligned?.count == 2)
        // "hello" source [10.1, 10.5] -> timeline [100.1, 100.5] -> relative [0.1, 0.5]
        // (epsilon compare — the source->timeline mapping is floating-point.)
        #expect(abs((aligned?[0].startTime ?? 0) - 0.1) < 1e-6)
        #expect(abs((aligned?[0].endTime ?? 0) - 0.5) < 1e-6)
        // "world" source [10.6, 11.0] -> timeline [100.6, 101.0] -> relative [0.6, 1.0]
        #expect(abs((aligned?[1].startTime ?? 0) - 0.6) < 1e-6)
        #expect(abs((aligned?[1].endTime ?? 0) - 1.0) < 1e-6)
    }

    @Test("alignment returns nil when the segment has no words, never otherwise demoting")
    func alignmentNilOnlyWhenNoWords() {
        let noWords = TranscriptionSegment(text: "x", startTime: 0, endTime: 1, confidence: 1)
        let clip = Clip(kind: .video, sourceRange: TimeRange(start: 0, duration: 1),
                        timelineRange: TimeRange(start: 0, duration: 1))
        #expect(SubtitleGenerator.wordTimingsAlignedToClip(for: noWords, clip: clip) == nil)
    }

    @Test("alignment drops words that fall outside the clip's rendered span")
    func alignmentDropsOutOfSpanWords() {
        let segment = TranscriptionSegment(
            text: "kept dropped kept-after",
            startTime: 9,
            endTime: 13,
            confidence: 1,
            words: [
                WordTiming(text: "before", startTime: 9.0, endTime: 9.5, confidence: 1),  // outside
                WordTiming(text: "kept", startTime: 10.2, endTime: 10.8, confidence: 1), // inside
                WordTiming(text: "after", startTime: 12.5, endTime: 12.9, confidence: 1) // outside
            ]
        )
        // Clip renders source [10, 12] onto timeline [0, 2].
        let clip = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 10, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )

        let aligned = SubtitleGenerator.wordTimingsAlignedToClip(for: segment, clip: clip)
        #expect(aligned?.count == 1)
        #expect(aligned?[0].text == "kept")
    }

    // MARK: - End-to-end edit simulation

    @Test("split then merge round-trips the word set")
    func splitThenMergeRoundTrips() {
        let original = [
            WordTiming(text: "one", startTime: 1.0, endTime: 1.5, confidence: 1),
            WordTiming(text: "two", startTime: 2.0, endTime: 2.5, confidence: 1),
            WordTiming(text: "three", startTime: 3.0, endTime: 3.5, confidence: 1)
        ]
        let halves = SubtitleGenerator.splitWordTimings(original, at: 2.5)
        let rejoined = SubtitleGenerator.mergedWordTimings(halves?.first, halves?.second)

        // Same count, same texts, same order after a split+merge cycle.
        #expect(rejoined?.count == 3)
        #expect(rejoined?.map(\.text) == ["one", "two", "three"])
        #expect(rejoined?.map(\.startTime) == [1.0, 2.0, 3.0])
    }
}
