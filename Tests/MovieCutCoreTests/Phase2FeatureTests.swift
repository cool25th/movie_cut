import Foundation
import Testing
@testable import MovieCutCore

@Suite("Phase 2 feature models")
struct Phase2FeatureTests {
    @Test("Chroma key defaults provide green and blue screen presets")
    func testChromaKeySettingsDefaults() {
        let green = ChromaKeySettings.greenScreen()
        let blue = ChromaKeySettings.blueScreen()

        #expect(green.keyColor == "#00FF00")
        #expect(blue.keyColor == "#0000FF")
        #expect(green.tolerance >= 0)
        #expect(green.tolerance <= 1)
        #expect(green.softness >= 0)
        #expect(green.softness <= 1)
        #expect(green.spillSuppression >= 0)
        #expect(green.spillSuppression <= 1)
    }

    @Test("Subtitle generator creates text clips from segments")
    func testSubtitleGeneratorCreatesClips() {
        let result = TranscriptionResult(
            segments: [
                TranscriptionSegment(text: "Hello", startTime: 1.0, endTime: 2.5, confidence: 0.92),
                TranscriptionSegment(text: "world", startTime: 2.5, endTime: 4.0, confidence: 0.88)
            ],
            language: "en"
        )

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())

        #expect(clips.count == 2)
        #expect(clips[0].kind == .text)
        #expect(clips[0].textContent?.text == "Hello")
        #expect(clips[0].timelineRange == TimeRange(start: 1.0, duration: 1.5))
        #expect(clips[0].sourceRange == clips[0].timelineRange)
        #expect(clips[1].textContent?.text == "world")
        #expect(clips[1].timelineRange == TimeRange(start: 2.5, duration: 1.5))
    }

    @Test("Transcription result joins segment text")
    func testTranscriptionResultFullText() {
        let result = TranscriptionResult(segments: [
            TranscriptionSegment(text: "Hello world", startTime: 0, endTime: 1, confidence: 0.95),
            TranscriptionSegment(text: "from MovieCut", startTime: 1, endTime: 2, confidence: 0.91)
        ])

        #expect(result.fullText == "Hello world from MovieCut")
    }

    // MARK: - Subtitle/Transcription data integrity (이서 data QA, 2026-06-08)

    @Test("SubtitleGenerator handles negative startTime gracefully")
    func subtitleGeneratorHandlesNegativeStartTime() {
        let result = TranscriptionResult(
            segments: [
                TranscriptionSegment(text: "Negative", startTime: -0.5, endTime: 1.0, confidence: 0.9),
            ],
            language: "en"
        )

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())

        #expect(clips.count == 1)
        // Recording: negative startTime flows through to clip timelineRange
        // SubtitleGenerator does NOT clamp — duration is max(0, 1.0 - (-0.5)) = 1.5
        #expect(clips[0].timelineRange.start == -0.5)
        #expect(clips[0].timelineRange.duration == 1.5)
    }

    @Test("SubtitleGenerator handles inverted segment (end < start)")
    func subtitleGeneratorHandlesInvertedSegment() {
        let result = TranscriptionResult(
            segments: [
                TranscriptionSegment(text: "Inverted", startTime: 5.0, endTime: 2.0, confidence: 0.9),
            ],
            language: "en"
        )

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())

        #expect(clips.count == 1)
        // Recording: duration = max(0, 2.0 - 5.0) = max(0, -3.0) = 0
        // SubtitleGenerator prevents negative duration via max(0, ...)
        // Risk: zero-duration clip created, timeline may have unexpected behavior
        #expect(clips[0].timelineRange.duration == 0)
    }

    @Test("SubtitleGenerator handles zero-duration segment")
    func subtitleGeneratorHandlesZeroDuration() {
        let result = TranscriptionResult(
            segments: [
                TranscriptionSegment(text: "Instant", startTime: 3.0, endTime: 3.0, confidence: 0.9),
            ],
            language: "en"
        )

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())

        #expect(clips.count == 1)
        #expect(clips[0].timelineRange.duration == 0)
        #expect(clips[0].textContent?.text == "Instant")
    }

    @Test("SubtitleGenerator handles empty segments list")
    func subtitleGeneratorHandlesEmptySegments() {
        let result = TranscriptionResult(segments: [], language: "en")

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())

        #expect(clips.isEmpty)
    }

    @Test("TranscriptionSegment clamps confidence to 0-1 range")
    func transcriptionSegmentClampsConfidence() {
        let over = TranscriptionSegment(text: "Over", startTime: 0, endTime: 1, confidence: 1.5)
        let under = TranscriptionSegment(text: "Under", startTime: 0, endTime: 1, confidence: -0.5)
        let normal = TranscriptionSegment(text: "Normal", startTime: 0, endTime: 1, confidence: 0.85)

        // Recording: confidence IS clamped in init
        #expect(over.confidence == 1.0)
        #expect(under.confidence == 0.0)
        #expect(normal.confidence == 0.85)
    }

    @Test("TranscriptionSegment does NOT clamp timestamps")
    func transcriptionSegmentDoesNotClampTimestamps() {
        let seg = TranscriptionSegment(text: "Test", startTime: -10, endTime: 100, confidence: 0.5)

        // Recording: startTime/endTime are raw — only confidence is clamped
        #expect(seg.startTime == -10)
        #expect(seg.endTime == 100)
    }
}
