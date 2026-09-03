import Foundation
import Testing
@testable import MovieCutMac

/// External review follow-up: the crash-recovery alert must identify WHAT the
/// user would recover (project name) and HOW OLD it is (last autosave time),
/// instead of a bare "found a project" line that could be anyone's session.
/// Assertions are locale-free where the text itself is localized (line counts
/// and data substrings), so the suite passes under any app language.
@Suite("Recovery alert identification")
struct RecoveryAlertDetailTests {

    @Test("detail names the project and the last autosave time")
    func identifiesProjectAndTime() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let detail = ContentView.recoveryAlertDetail(
            projectName: "Talking Head Cut",
            autosaveDate: stamp
        )
        #expect(detail.contains("Talking Head Cut"))
        #expect(detail.contains(stamp.formatted(date: .abbreviated, time: .shortened)))
        #expect(detail.split(separator: "\n").count == 3, "body + project line + time line")
    }

    @Test("blank name falls back to Untitled; missing date omits the time line")
    func fallbackAndOmission() {
        let blank = ContentView.recoveryAlertDetail(projectName: "   ", autosaveDate: nil)
        #expect(blank.contains(NSLocalizedString("Untitled", comment: "")))
        #expect(blank.split(separator: "\n").count == 2, "body + project line, no time line")

        let named = ContentView.recoveryAlertDetail(projectName: "Named", autosaveDate: nil)
        #expect(named.contains("Named"))
        #expect(named.split(separator: "\n").count == 2)
    }
}
