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
}
