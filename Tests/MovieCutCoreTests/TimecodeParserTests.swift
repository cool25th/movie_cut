import Foundation
import Testing
@testable import MovieCutCore

/// CA-27 — Timecode 직접 입력. Exact 등급(수치 동일 판정): 파서는 UI가 아닌
/// 순수 함수이므로 아래 기대값은 프레임 정확도로 검증한다.
@Suite("Timecode Parser (CA-27)")
struct TimecodeParserTests {
    @Test("seconds-only and fractional seconds")
    func secondsOnly() {
        #expect(TimecodeParser.seconds(from: "0", frameRate: 30) == 0)
        #expect(TimecodeParser.seconds(from: "5", frameRate: 30) == 5)
        #expect(TimecodeParser.seconds(from: "5.5", frameRate: 30) == 5.5)
    }

    @Test("MM:SS and MM:SS.f")
    func minutesSeconds() {
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: 30) == 90)
        #expect(TimecodeParser.seconds(from: "01:30.5", frameRate: 30) == 90.5)
        #expect(TimecodeParser.seconds(from: "0:00", frameRate: 24) == 0)
    }

    @Test("MM:SS:FF uses the project frame rate")
    func minutesSecondsFrames() {
        #expect(TimecodeParser.seconds(from: "00:00:10:15", frameRate: 30) ?? -1 == 10.0 + 15.0 / 30.0)
        #expect(TimecodeParser.seconds(from: "1:00", frameRate: 24) == 60)
        #expect(TimecodeParser.seconds(from: "00:00:00:29", frameRate: 30) ?? -1 == 29.0 / 30.0)
        #expect(TimecodeParser.seconds(from: "00:00:00:23", frameRate: 24) ?? -1 == 23.0 / 24.0)
    }

    @Test("3 fields are MM:SS:FF (badge format); hours need the 4-field form")
    func hoursForm() {
        // The on-screen badge shows MM:SS:FF, so 3 fields stay minutes-based.
        #expect(TimecodeParser.seconds(from: "01:02:03", frameRate: 30) ?? -1 == 62.0 + 3.0 / 30.0)
        #expect(TimecodeParser.seconds(from: "02:00:00", frameRate: 30) == 120)
        // Hours only exist in the 4-field HH:MM:SS:FF form.
        #expect(TimecodeParser.seconds(from: "01:02:03:12", frameRate: 30) ?? -1 == 3723.0 + 12.0 / 30.0)
    }

    @Test("whitespace is trimmed")
    func trimsWhitespace() {
        #expect(TimecodeParser.seconds(from: "  1:30  ", frameRate: 30) == 90)
    }

    @Test("non-finite frame rates are rejected, not just non-positive")
    func nonFiniteFrameRate() {
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: 0) == nil)
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: .infinity) == nil)
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: -.infinity) == nil)
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: .nan) == nil)
    }

    @Test("inf, infinity, nan, and 1e309 inputs are rejected explicitly")
    func nonFiniteInput() {
        #expect(TimecodeParser.seconds(from: "inf", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "infinity", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "nan", frameRate: 30) == nil)
        // 1e309 parses as +inf — it must not slip through the numeric check.
        #expect(TimecodeParser.seconds(from: "1e309", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "-inf", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "0:00:inf", frameRate: 30) == nil)
    }

    @Test("arithmetic that overflows to a non-finite result is rejected")
    func overflowInput() {
        // Each field parses finite, but scaling overflows the final seconds.
        #expect(TimecodeParser.seconds(from: "1e308:00:00:00", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "1e308:00", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "1e308", frameRate: 30)?.isFinite == true)
    }

    @Test("frames fields accept whole frame numbers only")
    func fractionalFramesRejected() {
        // FF must be an integer in both the 3- and 4-field forms.
        #expect(TimecodeParser.seconds(from: "0:00:10.5", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "00:00:10:15.5", frameRate: 30) == nil)
        // Fractional SECONDS stay legal in the 1- and 2-field forms.
        #expect(TimecodeParser.seconds(from: "10.5", frameRate: 30) == 10.5)
        #expect(TimecodeParser.seconds(from: "1:30.25", frameRate: 30) == 90.25)
        // Integer frames fields still parse (MM:SS:FF → 0 min 10 s 0 f).
        #expect(TimecodeParser.seconds(from: "0:10:00", frameRate: 30) == 10)
    }

    @Test("NTSC rates keep their true last displayable frame (29 at 29.97, 23 at 23.976)")
    func ntscLastFrameBoundary() {
        // 29 < 29.97 — frame 29 is displayable and must parse.
        #expect(TimecodeParser.seconds(from: "0:00:29", frameRate: 29.97) ?? -1 == 29.0 / 29.97)
        // 30 is beyond a 29.97fps second — rejected, not wrapped.
        #expect(TimecodeParser.seconds(from: "0:00:30", frameRate: 29.97) == nil)
        #expect(TimecodeParser.seconds(from: "00:00:00:23", frameRate: 23.976) ?? -1 == 23.0 / 23.976)
        #expect(TimecodeParser.seconds(from: "00:00:00:24", frameRate: 23.976) == nil)
        // Exact rates keep their boundary too.
        #expect(TimecodeParser.seconds(from: "0:00:29", frameRate: 30) ?? -1 == 29.0 / 30.0)
        #expect(TimecodeParser.seconds(from: "0:00:30", frameRate: 30) == nil)
    }

    @Test("invalid input fails explicitly — never a silent 0 seek")
    func invalidInput() {
        #expect(TimecodeParser.seconds(from: "", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "   ", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "abc", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "-5", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "1:2:3:4:5", frameRate: 30) == nil)
        // Frames field beyond the frame rate is rejected, not wrapped.
        #expect(TimecodeParser.seconds(from: "0:00:99", frameRate: 30) == nil)
        #expect(TimecodeParser.seconds(from: "00:00:00:30", frameRate: 30) == nil)
        // Fractional minutes/frames-adjacent fields are rejected.
        #expect(TimecodeParser.seconds(from: "1.5:30", frameRate: 30) == nil)
        // Empty segments rejected.
        #expect(TimecodeParser.seconds(from: "1::30", frameRate: 30) == nil)
        // Zero frame rate cannot interpret frame fields at all.
        #expect(TimecodeParser.seconds(from: "1:30", frameRate: 0) == nil)
    }

    @Test("ruler labels adapt to long-form scales (CA-19)")
    func rulerLabelScales() {
        // Tick-style seconds under a minute.
        #expect(TimecodeParser.rulerLabel(forSeconds: 0) == "0s")
        #expect(TimecodeParser.rulerLabel(forSeconds: 10) == "10s")
        #expect(TimecodeParser.rulerLabel(forSeconds: 59) == "59s")
        // Minute scale zero-pads seconds.
        #expect(TimecodeParser.rulerLabel(forSeconds: 60) == "1:00")
        #expect(TimecodeParser.rulerLabel(forSeconds: 95) == "1:35")
        #expect(TimecodeParser.rulerLabel(forSeconds: 600) == "10:00")
        #expect(TimecodeParser.rulerLabel(forSeconds: 3599) == "59:59")
        // Hour scale.
        #expect(TimecodeParser.rulerLabel(forSeconds: 3600) == "1:00:00")
        #expect(TimecodeParser.rulerLabel(forSeconds: 7325) == "2:02:05")
    }
}
