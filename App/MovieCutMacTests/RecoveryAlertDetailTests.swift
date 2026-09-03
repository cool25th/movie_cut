import Foundation
import Testing
@testable import MovieCutMac

/// External review follow-up: the crash-recovery alert must identify WHAT the
/// user would recover (project name) and HOW OLD it is (last autosave time),
/// instead of a bare "found a project" line that could be anyone's session.
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
    }

    @Test("blank name falls back to Untitled; missing date omits the time line")
    func fallbackAndOmission() {
        let blank = ContentView.recoveryAlertDetail(projectName: "   ", autosaveDate: nil)
        #expect(blank.contains("Untitled"))
        #expect(!blank.contains("Last autosave"), "no date → no stale time line")

        let named = ContentView.recoveryAlertDetail(projectName: "Named", autosaveDate: nil)
        #expect(named.contains("Named"))
        #expect(!named.contains("Last autosave"))
    }
}
