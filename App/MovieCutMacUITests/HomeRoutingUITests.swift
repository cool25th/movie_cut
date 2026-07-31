import XCTest

/// Task 4.5 — home-routed path coverage (requirement 3.6 / design §4.2).
///
/// The DEBUG UI-test harness bypasses home (`MOVIECUT_UITEST` /
/// `MOVIECUT_BOOTSTRAP_PROJECT`), so the home surface and the editor ↔ home
/// routing have **zero** coverage from existing E2E. These tests launch the
/// real app *without* those gate env vars so the app lands on home, then drive
/// the home → editor transition through the live `AppStageRouter` (whose
/// decisions are unit-tested in Core via `AppStagePolicy`).
///
/// Two tests:
/// 1. `testReachesEditorViaHomeWithoutGate` — the home-routed path. Launches
///    ungated, asserts the home surface is shown, taps the home "New Project"
///    button, and asserts the editor surface appears. This is the single
///    XCUITest the spec asks for ("홈을 거쳐 편집기에 도달하는 XCUITest 1건").
/// 2. `testHarnessGateStillBypassesHome` — the no-regression guard. Launches
///    with `MOVIECUT_UITEST=1` and asserts home is NOT shown (the editor is
///    reached directly), so existing gated E2E keeps bypassing home.
///
/// Both rely on the `home.surface` / `editor.surface` accessibility identifiers
/// attached to the branched `WindowGroup` content, and `home.newProject` on the
/// home New Project button — no Accessibility-permission-dependent modal is
/// involved, so `MOVIECUT_UITEST_QUIT` is never set (the known handshake
/// constraint documented in `UnsavedChangesGuardUITests`).
final class HomeRoutingUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    /// The home-routed path: launch ungated → home → New Project → editor.
    ///
    /// This is the only coverage for the AppStage branch that the harness gate
    /// hides. If home were accidentally skipped (e.g. the gate widened), the
    /// home surface would not appear and this fails.
    func testReachesEditorViaHomeWithoutGate() throws {
        let app = XCUIApplication()
        // Deliberately NOT setting MOVIECUT_UITEST / MOVIECUT_BOOTSTRAP_PROJECT:
        // the app must start on home.
        app.launch()

        let homeSurface = app.otherElements["home.surface"]
        XCTAssertTrue(
            homeSurface.waitForExistence(timeout: 30),
            "app did not launch to the home surface — home routing regressed"
        )

        let newProjectButton = app.buttons["home.newProject"]
        XCTAssertTrue(
            newProjectButton.waitForExistence(timeout: 10),
            "home New Project button not found — home surface did not render its actions"
        )
        newProjectButton.tap()

        let editorSurface = app.otherElements["editor.surface"]
        XCTAssertTrue(
            editorSurface.waitForExistence(timeout: 30),
            "tapping New Project on home did not reach the editor — AppStageRouter transition regressed"
        )
    }

    /// No-regression guard for the harness gate (requirement 3.6). With the gate
    /// active the app must bypass home and go straight to the editor, exactly as
    /// existing E2E / parity / bootstrap harnesses expect.
    func testHarnessGateStillBypassesHome() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_UITEST"] = "1"
        app.launch()

        let homeSurface = app.otherElements["home.surface"]
        // Home must NOT appear under the gate. Poll briefly: if it ever shows,
        // the gate was bypassed and existing E2E would regress.
        let homeAppeared = homeSurface.waitForExistence(timeout: 5)
        XCTAssertFalse(
            homeAppeared,
            "home surface appeared under MOVIECUT_UITEST=1 — the harness gate no longer bypasses home, E2E will regress"
        )

        // And the editor should be reachable directly. Under the harness the
        // parity surface or the editor surface takes over; accept either.
        let editorSurface = app.otherElements["editor.surface"]
        let paritySurface = app.otherElements["parity.harness.surface"]
        let reachedEditor = editorSurface.waitForExistence(timeout: 30)
            || paritySurface.waitForExistence(timeout: 5)
        XCTAssertTrue(
            reachedEditor,
            "under the harness gate the app did not reach the editor/parity surface directly"
        )
    }

    // MARK: - Sandbox restart + recent-list open (requirement 3.5)
    //
    // The spec's third clause for 4.5 — "샌드박스에서 앱 완전 종료 후 재실행 →
    // 최근 목록에서 프로젝트 열기 성공을 실행 증거로 확인" — needs a full
    // sandboxed app build (the security-scoped bookmark round-trips only under
    // the real sandbox) and a genuine quit+relaunch. That build is produced by
    // the orchestrator via xcodebuild; this UITest target cannot produce it.
    //
    // The behaviour it exercises is:
    //   1. Launch ungated, open/save a project (records it to
    //      Application Support/MovieCut/RecentProjects.json with a security-
    //      scoped bookmark).
    //   2. Quit the app fully.
    //   3. Relaunch ungated → home shows the project card.
    //   4. Tap the card → `SecurityScopedAccess` resolves the bookmark under the
    //      sandbox and the editor opens (requirement 3.5).
    //
    // The unit-testable pieces are already covered: bookmark resolve/scope pair
    // (SecurityScopedAccessTests), recent-store upsert/partition/reachability
    // (RecentProjectsStoreTests), and the routing decision (AppStagePolicyTests).
    // This file covers the home-routed UI path (test above). The full
    // sandbox-relaunch evidence is deferred to the orchestrator's full-app run.
}
