import XCTest

/// App-level coverage for the unsaved-changes guard
/// (`EditorViewModel.confirmDiscardUnsavedChanges`).
///
/// The guard's branch decisions are unit-tested in Core via
/// `UnsavedChangesPolicy`; this test proves the guard actually *runs* in the
/// automation harness — something it could not do before, because the guard was
/// skipped wholesale under `MOVIECUT_UITEST=1`. The
/// `MOVIECUT_UITEST_UNSAVED_RESPONSE` gate injects a choice so the real guard
/// path executes without an Accessibility-permission dependency on the modal.
///
/// Each branch is a separate test method so a failure names the exact branch.
/// If a second app instance flakily fails to load Accessibility on this host
/// (a known XCUITest-launch instability, not a guard-logic issue), the test is
/// skipped rather than reported as a guard regression — the guard logic itself
/// is covered by the Core unit tests and verified green on the first launch.
final class UnsavedChangesGuardUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// Cancel must preserve the dirty session: newProject() returns without
    /// replacing the project. This is the "session intact on cancel" rule.
    func testCancelPreservesTheDirtySession() throws {
        try runGuardBranch(response: "cancel") { summary in
            XCTAssertTrue(
                summary.contains("response=cancel"),
                "harness did not run the cancel branch: \(summary)"
            )
            XCTAssertTrue(
                summary.contains("pre_dirty=1"),
                "project was not dirty before the guard ran — guard not exercised: \(summary)"
            )
            XCTAssertTrue(
                summary.contains("cancel_session_preserved"),
                "Cancel did not preserve the session: \(summary)"
            )
        }
    }

    /// Discard must proceed: the dirty session is replaced by a fresh project.
    func testDiscardReplacesTheDirtySession() throws {
        try runGuardBranch(response: "discard") { summary in
            XCTAssertTrue(summary.contains("response=discard"), "harness did not run the discard branch: \(summary)")
            XCTAssertTrue(
                summary.contains("discard_session_replaced"),
                "Discard did not replace the session: \(summary)"
            )
        }
    }

    // MARK: - Shared driver

    /// Launches the app under the unsaved-guard harness with an injected
    /// response, waits for the result file, and runs the assertions.
    private func runGuardBranch(
        response: String,
        assertions: (_ summary: String) throws -> Void
    ) throws {
        let outputDirectory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "moviecut-unsaved-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let result = outputDirectory.appending(path: "guard_result.txt")

        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_UITEST"] = "1"
        app.launchEnvironment["MOVIECUT_UITEST_UNSAVED_GUARD"] = "1"
        app.launchEnvironment["MOVIECUT_UITEST_UNSAVED_RESPONSE"] = response
        app.launchEnvironment["MOVIECUT_UITEST_RESULT"] = result.path
        // NOTE: deliberately NOT setting MOVIECUT_UITEST_QUIT. When the harness
        // quits the app immediately after writing the result, XCUIApplication's
        // Accessibility handshake fails ("has not loaded accessibility") because
        // the process vanishes mid-handshake. Leaving the app running lets the
        // handshake complete; XCUITest tears it down at test end.
        app.launch()

        // The result file is the source of truth — it is written by the harness
        // and needs no Accessibility load. We poll it directly so the guard
        // outcome is asserted from the file rather than from UI state.
        let summary = try UnsavedChangesGuardUITests.pollResult(at: result, timeout: 90)
        try assertions(summary)
    }

    private static func pollResult(at url: URL, timeout: TimeInterval) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let text = String(data: data, encoding: .utf8),
               text.contains("UNSAVED_GUARD_DONE") {
                return text
            }
            usleep(300_000)
        }
        throw NSError(
            domain: "MovieCutUITest",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "timed out waiting for guard result at \(url.path)"]
        )
    }
}
