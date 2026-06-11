import Foundation
import Testing
@testable import MovieCutCore

/// F-13: SRT parsing/serialization that feeds the existing subtitle
/// pending-clip and burn-in pipeline.
@Suite("Subtitle Document")
struct SubtitleDocumentTests {
    @Test("parses a standard SRT document in order")
    func parsesStandardSRT() {
        let srt = """
        1
        00:00:01,000 --> 00:00:02,500
        Hello world

        2
        00:00:03,250 --> 00:00:05,000
        Second cue
        """

        let segments = SubtitleDocument.parseSRT(srt)
        #expect(segments.count == 2)
        #expect(segments[0].text == "Hello world")
        #expect(abs(segments[0].startTime - 1.0) < 0.001)
        #expect(abs(segments[0].endTime - 2.5) < 0.001)
        #expect(segments[1].text == "Second cue")
        #expect(abs(segments[1].startTime - 3.25) < 0.001)
    }

    @Test("joins multi-line cue text and tolerates CRLF and missing indexes")
    func toleratesRealWorldVariants() {
        let srt = "00:00:00,500 --> 00:00:01,500\r\nLine one\r\nLine two\r\n\r\nnot a timecode\r\n\r\n2\r\n00:01:00.000 --> 00:01:02.000\r\nDot millis"

        let segments = SubtitleDocument.parseSRT(srt)
        #expect(segments.count == 2)
        #expect(segments[0].text == "Line one\nLine two")
        #expect(abs(segments[1].startTime - 60.0) < 0.001)
        #expect(segments[1].text == "Dot millis")
    }

    @Test("skips blocks with invalid or reversed timecodes")
    func skipsInvalidBlocks() {
        let srt = """
        1
        00:00:05,000 --> 00:00:03,000
        Reversed

        2
        garbage --> 00:00:09,000
        Broken

        3
        00:00:10,000 --> 00:00:11,000
        Valid
        """

        let segments = SubtitleDocument.parseSRT(srt)
        #expect(segments.count == 1)
        #expect(segments[0].text == "Valid")
    }

    @Test("sorts out-of-order cues by start time")
    func sortsByStart() {
        let srt = """
        1
        00:00:10,000 --> 00:00:11,000
        Later

        2
        00:00:01,000 --> 00:00:02,000
        Earlier
        """

        let segments = SubtitleDocument.parseSRT(srt)
        #expect(segments.map(\.text) == ["Earlier", "Later"])
    }

    @Test("serialization round-trips through the parser")
    func roundTrips() {
        let original = [
            TranscriptionSegment(text: "First", startTime: 0.5, endTime: 2.0, confidence: 1),
            TranscriptionSegment(text: "Multi\nline", startTime: 3.0, endTime: 4.25, confidence: 1),
            TranscriptionSegment(text: "한국어 자막", startTime: 65.125, endTime: 70.0, confidence: 1)
        ]

        let srt = SubtitleDocument.srtString(from: original)
        let parsed = SubtitleDocument.parseSRT(srt)

        #expect(parsed.count == original.count)
        for (a, b) in zip(parsed, original) {
            #expect(a.text == b.text)
            #expect(abs(a.startTime - b.startTime) < 0.002)
            #expect(abs(a.endTime - b.endTime) < 0.002)
        }
    }

    @Test("timestamps format hours minutes seconds milliseconds")
    func timestampFormatting() {
        #expect(SubtitleDocument.srtTimestamp(from: 0) == "00:00:00,000")
        #expect(SubtitleDocument.srtTimestamp(from: 3661.789) == "01:01:01,789")
        #expect(SubtitleDocument.srtTimestamp(from: -5) == "00:00:00,000")
        #expect(SubtitleDocument.timeInterval(fromSRTTimestamp: "01:01:01,789").map { abs($0 - 3661.789) < 0.001 } == true)
        #expect(SubtitleDocument.timeInterval(fromSRTTimestamp: "bad") == nil)
    }

    @Test("empty input produces no segments and empty serialization")
    func emptyInput() {
        #expect(SubtitleDocument.parseSRT("").isEmpty)
        #expect(SubtitleDocument.srtString(from: []).isEmpty)
    }
}

/// Wiring visibility for the subtitle editing UI (not a completion criterion
/// by itself — see spec DoD §1.3).
@Suite("Subtitle Editing Static Contract")
struct SubtitleEditingStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model exposes segment editing and SRT import/export")
    func viewModelExposesEditing() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func updateGeneratedSubtitleSegment"))
        #expect(viewModel.contains("func splitGeneratedSubtitleSegment"))
        #expect(viewModel.contains("func mergeGeneratedSubtitleSegmentWithNext"))
        #expect(viewModel.contains("func deleteGeneratedSubtitleSegment"))
        #expect(viewModel.contains("func importSubtitles(from url: URL)"))
        #expect(viewModel.contains("func exportSubtitles(to url: URL)"))
        #expect(viewModel.contains("rebuildPendingSubtitleClips"))
        #expect(viewModel.contains("SubtitleDocument.parseSRT"))
        #expect(viewModel.contains("SubtitleDocument.srtString"))
    }

    @Test("auto subtitles view exposes row editing and SRT buttons")
    func viewExposesEditingControls() throws {
        let view = try source("App/MovieCutMac/Transcription/AutoSubtitlesView.swift")
        #expect(view.contains("SubtitleSegmentRow"))
        #expect(view.contains("updateGeneratedSubtitleSegment"))
        #expect(view.contains("splitGeneratedSubtitleSegment"))
        #expect(view.contains("mergeGeneratedSubtitleSegmentWithNext"))
        #expect(view.contains("deleteGeneratedSubtitleSegment"))
        #expect(view.contains("Import SRT"))
        #expect(view.contains("Export SRT"))
    }
}
