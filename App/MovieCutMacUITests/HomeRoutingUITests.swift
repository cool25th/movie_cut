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
/// Three tests:
/// 1. `testReachesEditorViaHomeWithoutGate` — the home-routed path. Launches
///    ungated, asserts the home surface is shown, taps the home "New Project"
///    button, and asserts the editor surface appears. This is the single
///    XCUITest the spec asks for ("홈을 거쳐 편집기에 도달하는 XCUITest 1건").
/// 2. `testHarnessGateStillBypassesHome` — the no-regression guard. Launches
///    with `MOVIECUT_UITEST=1` and asserts home is NOT shown (the editor is
///    reached directly), so existing gated E2E keeps bypassing home.
/// 3. `testSaveTerminateUngatedRelaunchOpensRecentProject` — saves through the
///    real editor UI, terminates, relaunches with no gate environment, and opens
///    the persisted recent card back into the editor.
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

    private func appContainerDocumentsDirectory() throws -> URL {
        // The UI-test runner and tested app have different sandbox HOME values.
        // Resolve the physical user home before addressing the app container.
        let runnerHomePath = FileManager.default.homeDirectoryForCurrentUser.path
        let userHomePath = runnerHomePath.components(separatedBy: "/Library/Containers/").first
            ?? runnerHomePath
        let directory = URL(filePath: userHomePath, directoryHint: .isDirectory)
            .appending(path: "Library/Containers/com.moviecut.mac/Data/Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeIsolatedAutosaveDirectory() throws -> URL {
        // Do not create this from the UI-test runner: it cannot create new
        // children in the tested app's container. ProjectStore creates the
        // directory from inside the tested app sandbox on first autosave.
        try appContainerDocumentsDirectory()
            .appending(path: "HomeRoutingAutosave-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    /// The home-routed path: launch ungated → home → New Project → editor.
    ///
    /// This is the only coverage for the AppStage branch that the harness gate
    /// hides. If home were accidentally skipped (e.g. the gate widened), the
    /// home surface would not appear and this fails.
    @MainActor
    func testReachesEditorViaHomeWithoutGate() throws {
        let app = XCUIApplication()
        let autosaveDirectory = try makeIsolatedAutosaveDirectory()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: autosaveDirectory)
        }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        // Recovery state is isolated because the tested app's default
        // Application Support directory is shared across UI test processes.
        app.launchEnvironment["MOVIECUT_AUTOSAVE_DIR"] = autosaveDirectory.path
        // CA-25: keep the first-run welcome card out of home-routing assertions.
        app.launchEnvironment["MOVIECUT_DISABLE_ONBOARDING"] = "1"
        // Deliberately NOT setting MOVIECUT_UITEST / MOVIECUT_BOOTSTRAP_PROJECT:
        // the app must start on home.
        app.launch()

        let homeSurface = app.descendants(matching: .any)["home.surface"]
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

        let editorSurface = app.descendants(matching: .any)["editor.surface"]
        XCTAssertTrue(
            editorSurface.waitForExistence(timeout: 30),
            "tapping New Project on home did not reach the editor — AppStageRouter transition regressed"
        )
    }

    /// No-regression guard for the harness gate (requirement 3.6). With the gate
    /// active the app must bypass home and go straight to the editor, exactly as
    /// existing E2E / parity / bootstrap harnesses expect.
    @MainActor
    func testHarnessGateStillBypassesHome() throws {
        let app = XCUIApplication()
        let autosaveDirectory = try makeIsolatedAutosaveDirectory()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: autosaveDirectory)
        }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["MOVIECUT_AUTOSAVE_DIR"] = autosaveDirectory.path
        // CA-25: keep the first-run welcome card out of home-routing assertions.
        app.launchEnvironment["MOVIECUT_DISABLE_ONBOARDING"] = "1"
        app.launchEnvironment["MOVIECUT_UITEST"] = "1"
        app.launch()

        let homeSurface = app.descendants(matching: .any)["home.surface"]
        // Home must NOT appear under the gate. Poll briefly: if it ever shows,
        // the gate was bypassed and existing E2E would regress.
        let homeAppeared = homeSurface.waitForExistence(timeout: 5)
        XCTAssertFalse(
            homeAppeared,
            "home surface appeared under MOVIECUT_UITEST=1 — the harness gate no longer bypasses home, E2E will regress"
        )

        // And the editor should be reachable directly. Under the harness the
        // parity surface or the editor surface takes over; accept either.
        let editorSurface = app.descendants(matching: .any)["editor.surface"]
        let paritySurface = app.descendants(matching: .any)["parity.harness.surface"]
        let reachedEditor = editorSurface.waitForExistence(timeout: 30)
            || paritySurface.waitForExistence(timeout: 5)
        XCTAssertTrue(
            reachedEditor,
            "under the harness gate the app did not reach the editor/parity surface directly"
        )
    }

    /// Full sandbox persistence proof: save through the real ViewModel/store,
    /// terminate the process, relaunch without the home-bypass gate, and open
    /// the newest recent card back into the editor. Termination is controlled
    /// exclusively by XCUIApplication; MOVIECUT_UITEST_QUIT is never set.
    @MainActor
    func testSaveTerminateUngatedRelaunchOpensRecentProject() throws {
        let documentsDirectory = try appContainerDocumentsDirectory()
        let autosaveDirectory = try makeIsolatedAutosaveDirectory()
        let projectURL = documentsDirectory
            .appending(path: "HomeRouting-\(UUID().uuidString).moviecut")

        let app = XCUIApplication()
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: projectURL)
            try? FileManager.default.removeItem(at: autosaveDirectory)
        }
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment = [
            "MOVIECUT_AUTOSAVE_DIR": autosaveDirectory.path,
            "MOVIECUT_UITEST_HOME_SAVE_PATH": projectURL.path
        ]
        XCTAssertNil(app.launchEnvironment["MOVIECUT_UITEST"])
        XCTAssertNil(app.launchEnvironment["MOVIECUT_BOOTSTRAP_PROJECT"])
        XCTAssertNil(app.launchEnvironment["MOVIECUT_UITEST_QUIT"])
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.surface"].waitForExistence(timeout: 30),
            "first ungated launch did not show Home"
        )
        let newProjectButton = app.buttons["home.newProject"]
        XCTAssertTrue(newProjectButton.waitForExistence(timeout: 10))
        newProjectButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["editor.surface"].waitForExistence(timeout: 30),
            "New Project did not enter the editor"
        )

        let saveButton = app.buttons["editor.saveProject"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 10),
            "editor Save button was not exposed to UI automation"
        )
        saveButton.click()
        let saveDeadline = Date().addingTimeInterval(30)
        while Date() < saveDeadline,
              !FileManager.default.fileExists(atPath: projectURL.path) {
            usleep(200_000)
        }
        let saveStatus = app.descendants(matching: .any)["moviecut.status"]
        let saveStatusText: String
        if saveStatus.exists {
            saveStatusText = (saveStatus.value as? String) ?? saveStatus.label
        } else {
            saveStatusText = "unavailable"
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: projectURL.path),
            "Save command did not persist the injected sandbox project path; status=\(saveStatusText)"
        )
        // saveProject records RecentProjects after writing project bytes.
        usleep(1_000_000)

        app.terminate()
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 30),
            "the first app process did not terminate fully"
        )

        // Genuine ungated relaunch: the recovery directory remains isolated,
        // while no harness, bootstrap, save-path, or quit gate survives.
        app.launchEnvironment = [
            "MOVIECUT_AUTOSAVE_DIR": autosaveDirectory.path
        ]
        XCTAssertNil(app.launchEnvironment["MOVIECUT_UITEST"])
        XCTAssertNil(app.launchEnvironment["MOVIECUT_BOOTSTRAP_PROJECT"])
        XCTAssertNil(app.launchEnvironment["MOVIECUT_UITEST_HOME_SAVE_PATH"])
        XCTAssertNil(app.launchEnvironment["MOVIECUT_UITEST_QUIT"])
        app.launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["home.surface"].waitForExistence(timeout: 30),
            "ungated relaunch did not return to Home"
        )

        let recentCards = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "home.card.")
        )
        let newestCard = recentCards.firstMatch
        XCTAssertTrue(
            newestCard.waitForExistence(timeout: 30),
            "saved project did not appear in the recent-project grid"
        )
        newestCard.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["editor.surface"].waitForExistence(timeout: 30),
            "opening the saved recent card did not return to editor.surface"
        )
    }
}
