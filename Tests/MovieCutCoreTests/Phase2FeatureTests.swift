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
}
