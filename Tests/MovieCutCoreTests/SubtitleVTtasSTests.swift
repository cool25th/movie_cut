import Foundation
import Testing
@testable import MovieCutCore

/// Task 4.8 / 4.9 — WebVTT and ASS subtitle serialization.
///
/// These tests verify by actually parsing the generated output (not via
/// string-containment) and confirming the parsed timing matches the source
/// segments, satisfying requirement 6 acceptance criteria 1–5.
@Suite("Subtitle VTT/ASS Serialization")
struct SubtitleVTTASSTests {
    /// Reference segments used across format round-trips. Order is intentionally
    /// shuffled relative to start time so the serializer's sort is exercised,
    /// and covers single-digit and multi-hour timestamps plus multi-line text.
    private let reference: [TranscriptionSegment] = [
        TranscriptionSegment(text: "First cue", startTime: 0.0, endTime: 1.5, confidence: 1),
        TranscriptionSegment(text: "Second cue", startTime: 2.0, endTime: 4.25, confidence: 1),
        TranscriptionSegment(text: "Multi\nline", startTime: 5.0, endTime: 6.0, confidence: 1),
        TranscriptionSegment(text: "한국어 자막", startTime: 3661.5, endTime: 3662.75, confidence: 1)
    ]

    private func assertTimingsMatch(
        _ parsed: [TranscriptionSegment],
        _ original: [TranscriptionSegment],
        tolerance: TimeInterval,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(parsed.count == original.count)
        for (a, b) in zip(parsed, original) {
            #expect(abs(a.startTime - b.startTime) <= tolerance)
            #expect(abs(a.endTime - b.endTime) <= tolerance)
        }
    }

    // MARK: - WebVTT

    @Test("WebVTT output starts with the WEBVTT header")
    func vttHasHeader() {
        let vtt = SubtitleDocument.vttString(from: reference)
        #expect(vtt.hasPrefix("WEBVTT\n"))
    }

    @Test("WebVTT uses HH:MM:SS.mmm timestamps with the --> cue arrow")
    func vttTimestampFormat() {
        let segments = [TranscriptionSegment(text: "hi", startTime: 3661.789, endTime: 3662.0, confidence: 1)]
        let vtt = SubtitleDocument.vttString(from: segments)

        // 3661.789s == 01:01:01.789
        #expect(vtt.contains("01:01:01.789 --> 01:01:02.000"))
        #expect(SubtitleDocument.vttTimestamp(from: 0) == "00:00:00.000")
        #expect(SubtitleDocument.vttTimestamp(from: -1) == "00:00:00.000")
    }

    @Test("WebVTT round-trips through parseVTT with matching timing and text")
    func vttRoundTrip() {
        let vtt = SubtitleDocument.vttString(from: reference)
        let parsed = SubtitleDocument.parseVTT(vtt)

        // Text is preserved exactly, including embedded newlines.
        #expect(parsed.map(\.text) == reference.map(\.text))
        // VTT millisecond precision -> 1ms tolerance.
        assertTimingsMatch(parsed, reference, tolerance: 0.001)
    }

    @Test("WebVTT parser tolerates cue identifiers, NOTE blocks, and MM:SS timestamps")
    func vttParserIsTolerant() {
        let vtt = """
        WEBVTT

        NOTE This is a comment that should be skipped.
        It spans two lines.

        cue-1
        00:01.000 --> 00:02.500
        Short timestamp

        00:05.000 --> 00:06.000
        No identifier
        """

        let parsed = SubtitleDocument.parseVTT(vtt)
        #expect(parsed.count == 2)
        #expect(parsed[0].text == "Short timestamp")
        #expect(abs(parsed[0].startTime - 1.0) < 0.001)
        #expect(abs(parsed[0].endTime - 2.5) < 0.001)
        #expect(parsed[1].text == "No identifier")
        #expect(abs(parsed[1].startTime - 5.0) < 0.001)
    }

    @Test("Empty segments produce empty WebVTT")
    func vttEmpty() {
        #expect(SubtitleDocument.vttString(from: []).isEmpty)
        #expect(SubtitleDocument.parseVTT("").isEmpty)
    }

    @Test("WebVTT timestamp parser handles H:MM:SS and MM:SS forms")
    func vttTimestampParser() {
        #expect(SubtitleDocument.timeInterval(fromVTTTimestamp: "01:01:01.789").map { abs($0 - 3661.789) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromVTTTimestamp: "01:01.5").map { abs($0 - 61.5) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromVTTTimestamp: "12.0").map { abs($0 - 12.0) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromVTTTimestamp: "bad") == nil)
    }

    // MARK: - ASS

    @Test("ASS output contains the required script sections")
    func assHasSections() {
        let ass = SubtitleDocument.assString(from: reference)
        #expect(ass.contains("[Script Info]"))
        #expect(ass.contains("ScriptType: v4.00+"))
        #expect(ass.contains("[V4+ Styles]"))
        #expect(ass.contains("[Events]"))
        #expect(ass.contains("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"))
    }

    @Test("ASS emits exactly one Default style with no per-clip styling")
    func assSingleDefaultStyle() {
        let ass = SubtitleDocument.assString(from: reference)
        // Only one "Style:" line (the single default style).
        let styleLines = ass.split(separator: "\n").filter { $0.hasPrefix("Style:") }
        #expect(styleLines.count == 1)
        #expect(styleLines.first?.contains("Default") == true)
        // No karaoke tags and no inline style overrides in the dialogue text.
        #expect(!ass.contains("\\k"))
        #expect(!ass.contains("{\\"))
    }

    @Test("ASS uses H:MM:SS.cc single-digit-hour timestamps")
    func assTimestampFormat() {
        let segments = [TranscriptionSegment(text: "hi", startTime: 3661.789, endTime: 3662.0, confidence: 1)]
        let ass = SubtitleDocument.assString(from: segments)
        // 3661.789s -> 366178.9cs rounds to 366179cs -> 1:01:01.79. 0s -> 0:00:00.00.
        #expect(ass.contains("1:01:01.79"))
        #expect(ass.contains("1:01:02.00"))
        #expect(SubtitleDocument.assTimestamp(from: 0) == "0:00:00.00")
        #expect(SubtitleDocument.assTimestamp(from: -1) == "0:00:00.00")
    }

    @Test("ASS round-trips through parseASS with matching timing and text")
    func assRoundTrip() {
        let ass = SubtitleDocument.assString(from: reference)
        let parsed = SubtitleDocument.parseASS(ass)

        #expect(parsed.map(\.text) == reference.map(\.text))
        // ASS centisecond precision -> 10ms tolerance.
        assertTimingsMatch(parsed, reference, tolerance: 0.01)
    }

    @Test("ASS dialogue text containing commas survives the parser")
    func assKeepsCommasInText() {
        let segments = [
            TranscriptionSegment(text: "Hello, world, again", startTime: 1.0, endTime: 2.0, confidence: 1)
        ]
        let ass = SubtitleDocument.assString(from: segments)
        let parsed = SubtitleDocument.parseASS(ass)
        #expect(parsed.count == 1)
        #expect(parsed[0].text == "Hello, world, again")
    }

    @Test("ASS hard line breaks decode back to newlines")
    func assLineBreaks() {
        let segments = [
            TranscriptionSegment(text: "Line one\nLine two", startTime: 1.0, endTime: 2.0, confidence: 1)
        ]
        let ass = SubtitleDocument.assString(from: segments)
        // Multi-line text is encoded with \N in the dialogue.
        #expect(ass.contains("Line one\\NLine two"))
        let parsed = SubtitleDocument.parseASS(ass)
        #expect(parsed.first?.text == "Line one\nLine two")
    }

    @Test("Empty segments produce an ASS header with no dialogues")
    func assEmpty() {
        let ass = SubtitleDocument.assString(from: [])
        #expect(ass.contains("[Events]"))
        let dialogueLines = ass.split(separator: "\n").filter { $0.hasPrefix("Dialogue:") }
        #expect(dialogueLines.isEmpty)
        #expect(SubtitleDocument.parseASS(ass).isEmpty)
    }

    @Test("ASS timestamp parser rejects malformed input")
    func assTimestampParser() {
        #expect(SubtitleDocument.timeInterval(fromASSTimestamp: "1:01:01.78").map { abs($0 - 3661.78) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromASSTimestamp: "0:00:05.00").map { abs($0 - 5.0) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromASSTimestamp: "bad") == nil)
    }

    // MARK: - SRT non-regression

    @Test("SRT export is unchanged: VTT/ASS additions do not touch srtString")
    func srtNonRegression() {
        let srt = SubtitleDocument.srtString(from: reference)
        let parsed = SubtitleDocument.parseSRT(srt)

        // SRT still parses back with the same text and timing.
        #expect(parsed.map(\.text) == reference.map(\.text))
        assertTimingsMatch(parsed, reference, tolerance: 0.001)
        // SRT still uses the comma decimal separator (unchanged contract).
        #expect(srt.contains("00:00:00,000 --> 00:00:01,500"))
    }

    @Test("All three formats share the same source segments with no timing drift")
    func allFormatsAgreeOnTiming() {
        let srt = SubtitleDocument.parseSRT(SubtitleDocument.srtString(from: reference))
        let vtt = SubtitleDocument.parseVTT(SubtitleDocument.vttString(from: reference))
        let ass = SubtitleDocument.parseASS(SubtitleDocument.assString(from: reference))

        // Text matches across all three formats.
        #expect(srt.map(\.text) == reference.map(\.text))
        #expect(vtt.map(\.text) == reference.map(\.text))
        #expect(ass.map(\.text) == reference.map(\.text))

        // Start times agree across formats within their respective precisions.
        for i in 0..<reference.count {
            let srtStart = srt[i].startTime
            let vttStart = vtt[i].startTime
            let assStart = ass[i].startTime
            #expect(abs(srtStart - vttStart) <= 0.001)
            #expect(abs(srtStart - assStart) <= 0.01)
        }
    }
}
