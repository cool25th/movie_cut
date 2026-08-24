import Foundation
import Testing
@testable import MovieCutiOS

/// G-27 result isolation (P1 review fix). The device E2E driver used to
/// wait/assert on the WHOLE `g27-result.txt`, so rows left by earlier
/// executions (or a pre-planted file containing `g27_done`/`g27_reopen`)
/// satisfied a new run's waits instantly and its `error=none` count. The
/// harness now tags every emitted row with a per-execution run ID that both
/// phases share; these tests pin that tagging contract as real behavior of
/// the production harness entry points.
@Suite("G-27 harness result run scoping")
@MainActor
struct IOSUITestHarnessRunScopingTests {
    @Test("the driver-passed run ID is honored verbatim")
    func driverRunIDIsHonored() {
        let env = ["MOVIECUT_UITEST": "1", "MOVIECUT_G27_RUN_ID": "g27-20260824-abc123"]
        #expect(IOSUITestHarness.resolvedRunID(environment: env) == "g27-20260824-abc123")
    }

    @Test("a missing run ID falls back to a unique per-launch ID")
    func missingRunIDGeneratesUniqueIDs() {
        let first = IOSUITestHarness.resolvedRunID(environment: [:])
        let second = IOSUITestHarness.resolvedRunID(environment: [:])
        #expect(!first.isEmpty)
        #expect(!second.isEmpty)
        #expect(first != second, "two launches must never share a generated run ID")
        #expect(first.hasPrefix("g27-"), "generated IDs stay greppable in the g27 namespace")
    }

    @Test("every emitted row is prefixed with the space-terminated run tag")
    func rowsAreRunTagged() {
        let tag = IOSUITestHarness.taggedLine(runID: "g27-20260824-abc123", line: "g27_done error=none")
        #expect(tag == "run=g27-20260824-abc123 g27_done error=none")
        #expect(tag.hasPrefix("run=g27-20260824-abc123 "), "driver-side `grep \"run=$RUN_ID \"` must match exactly this row and never a longer ID sharing the prefix")
    }

    @Test("driver-side run-scoped filtering ignores rows from other executions")
    func runScopedRowsExcludeOtherRuns() {
        // The exact filter the device runner applies, exercised against a
        // result file containing stale rows from an older execution plus
        // the current run's rows — the stale `g27_done` must not satisfy
        // the current run's wait, and `error=none` must be counted only
        // within the current run's rows.
        let runID = "g27-20260824-abc123"
        let file = """
        run=g27-20200101-old-old g27_start
        run=g27-20200101-old-old g27_done error=none
        run=\(runID) g27_start
        run=\(runID) g27_done error=none
        run=\(runID) g27_start
        run=\(runID) g27_reopen reopened_clips=2
        run=\(runID) g27_done error=none
        """
        let rows = file
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.contains("run=\(runID) ") }

        #expect(rows.count == 5, "stale rows are excluded from the run-scoped view")
        #expect(rows.filter { $0.contains("g27_reopen") }.count == 1)
        #expect(rows.filter { $0.contains("error=none") }.count == 2, "the older execution's clean finish must not inflate this run's count")
    }
}
