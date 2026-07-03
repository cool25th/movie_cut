import Foundation
import MovieCutCore
import Testing

@Suite("Styled Caption Word Timing")
struct StyledCaptionWordTimingTests {
    @Test("legacy transcription segment decodes without words")
    func legacyTranscriptionSegmentDecodesWithoutWords() throws {
        let json = """
        {
          "id": "11111111-1111-4111-8111-111111111111",
          "text": "Hello world",
          "startTime": 1.0,
          "endTime": 2.0,
          "confidence": 0.75
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: json)

        #expect(decoded.text == "Hello world")
        #expect(decoded.words == nil)
    }

    @Test("transcription segment round trips word timings and clamps confidence")
    func transcriptionSegmentRoundTripsWordTimings() throws {
        let segment = TranscriptionSegment(
            text: "Hello world",
            startTime: 10,
            endTime: 12,
            confidence: 1.4,
            words: [
                WordTiming(text: "Hello", startTime: 10.1, endTime: 10.5, confidence: -0.2),
                WordTiming(text: "world", startTime: 10.6, endTime: 11.0, confidence: 0.9)
            ]
        )

        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(TranscriptionSegment.self, from: data)

        #expect(decoded.confidence == 1.0)
        #expect(decoded.words?.count == 2)
        #expect(decoded.words?[0].text == "Hello")
        #expect(decoded.words?[0].confidence == 0.0)
        #expect(decoded.words?[1].confidence == 0.9)
    }

    @Test("legacy text clip content decodes with nil word timings")
    func legacyTextClipContentDecodesWithNilWordTimings() throws {
        let json = """
        {
          "text": "Subtitle",
          "fontFamily": "System",
          "fontSize": 48,
          "fontColor": "#FFFFFF",
          "alignment": "center",
          "position": { "x": 0, "y": 0 },
          "contentKind": "text"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TextClipContent.self, from: json)

        #expect(decoded.text == "Subtitle")
        #expect(decoded.wordTimings == nil)
    }

    @Test("subtitle generator stores word timings relative to clip start")
    func subtitleGeneratorStoresRelativeWordTimings() {
        let result = TranscriptionResult(segments: [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 10,
                endTime: 12,
                confidence: 0.8,
                words: [
                    WordTiming(text: "Hello", startTime: 10.5, endTime: 10.9, confidence: 0.7),
                    WordTiming(text: "world", startTime: 11.0, endTime: 11.4, confidence: 0.8)
                ]
            )
        ])

        let clips = SubtitleGenerator.generateClips(from: result, trackId: UUID())
        let words = clips.first?.textContent?.wordTimings

        #expect(words?.count == 2)
        #expect(words?[0].text == "Hello")
        #expect(abs((words?[0].startTime ?? -1) - 0.5) < 0.0001)
        #expect(abs((words?[0].endTime ?? -1) - 0.9) < 0.0001)
        #expect(abs((words?[1].startTime ?? -1) - 1.0) < 0.0001)
        #expect(abs((words?[1].endTime ?? -1) - 1.4) < 0.0001)
    }

    @Test("subtitle generator clamps out of range words within segment duration")
    func subtitleGeneratorClampsOutOfRangeWords() {
        let result = TranscriptionResult(segments: [
            TranscriptionSegment(
                text: "Clamped",
                startTime: 10,
                endTime: 12,
                confidence: 0.8,
                words: [
                    WordTiming(text: "before", startTime: 9.5, endTime: 10.25, confidence: 0.7),
                    WordTiming(text: "after", startTime: 11.75, endTime: 13.0, confidence: 0.8)
                ]
            )
        ])

        let words = SubtitleGenerator.generateClips(from: result, trackId: UUID()).first?.textContent?.wordTimings

        #expect(words?.count == 2)
        #expect(words?[0].startTime == 0)
        #expect(abs((words?[0].endTime ?? -1) - 0.25) < 0.0001)
        #expect(abs((words?[1].startTime ?? -1) - 1.75) < 0.0001)
        #expect(words?[1].endTime == 2.0)
    }

    @Test("SRT serialization remains sentence compatible and omits word timing data")
    func srtSerializationOmitsWordTimingData() {
        let segments = [
            TranscriptionSegment(
                text: "Hello world",
                startTime: 0,
                endTime: 2,
                confidence: 1,
                words: [WordTiming(text: "Hello", startTime: 0, endTime: 0.5, confidence: 1)]
            )
        ]

        let srt = SubtitleDocument.srtString(from: segments)

        #expect(srt.contains("Hello world"))
        #expect(!srt.contains("WordTiming"))
        #expect(!srt.contains("wordTimings"))
        #expect(!srt.contains("Hello\nworld"))
    }
}
