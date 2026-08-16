import Foundation
import Testing
@testable import MovieCutCore

/// S9 — J/K/L shuttle and edit tool modes.
///
/// Covers the pure Core pieces: the `EditTool` enum and the `ShuttleRate`
/// speed-step math.
@Suite("Edit tool and shuttle (S9)")
struct EditToolAndShuttleTests {

    @Test("EditTool has select, blade, slip, slide cases and valid properties")
    func editToolCases() {
        #expect(EditTool.allCases == [.select, .blade, .slip, .slide])
        #expect(EditTool.select.rawValue == "select")
        #expect(EditTool.blade.rawValue == "blade")
        #expect(EditTool.slip.rawValue == "slip")
        #expect(EditTool.slide.rawValue == "slide")

        #expect(EditTool.select.shortcutKey == "v")
        #expect(EditTool.blade.shortcutKey == "c")
        #expect(EditTool.slip.shortcutKey == "y")
        #expect(EditTool.slide.shortcutKey == "u")

        #expect(!EditTool.select.displayName.isEmpty)
        #expect(!EditTool.blade.systemImage.isEmpty)
        #expect(!EditTool.slip.systemImage.isEmpty)
        #expect(!EditTool.slide.systemImage.isEmpty)
    }

    @Test("Shuttle forward speed steps up 1→2→4 and caps at 4")
    func forwardSpeedSteps() {
        #expect(ShuttleRate.forwardStep(forTapCount: 0) == 1.0)
        #expect(ShuttleRate.forwardStep(forTapCount: 1) == 1.0)
        #expect(ShuttleRate.forwardStep(forTapCount: 2) == 2.0)
        #expect(ShuttleRate.forwardStep(forTapCount: 3) == 4.0)
        #expect(ShuttleRate.forwardStep(forTapCount: 5) == 4.0) // capped
    }

    @Test("Shuttle reverse speed mirrors forward with a negative sign")
    func reverseSpeedMirrorsForward() {
        #expect(ShuttleRate.reverseStep(forTapCount: 1) == -1.0)
        #expect(ShuttleRate.reverseStep(forTapCount: 2) == -2.0)
        #expect(ShuttleRate.reverseStep(forTapCount: 3) == -4.0)
    }
}
