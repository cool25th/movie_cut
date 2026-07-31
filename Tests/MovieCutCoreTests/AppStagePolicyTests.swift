import Foundation
import Testing
@testable import MovieCutCore

/// Task 4.3 — coverage for the AppStage transition/gate/dirty logic.
///
/// The UI-test harness bypasses home (`MOVIECUT_UITEST` /
/// `MOVIECUT_BOOTSTRAP_PROJECT`), so these unit tests are the **only** coverage
/// for: whether home shows at all, whether a transition is blocked by unsaved
/// changes, and the harness gate decision (design §4.2 coverage-gap note).
///
/// These are pure decision tests — no AppKit, no I/O — mirroring
/// `UnsavedChangesPolicyTests`. The App-layer wrapper is exercised by the home
/// XCUITest added in task 4.5.
@Suite("AppStagePolicy")
struct AppStagePolicyTests {

    // MARK: - Harness gate (requirement 3.6 — E2E regression-free)

    @Test("initialStage is .home with no gate env vars")
    func initialStageIsHomeWhenUngated() {
        #expect(AppStagePolicy.initialStage(uiTestEnv: nil, bootstrapProjectEnv: nil) == .home)
    }

    @Test("MOVIECUT_UITEST=1 gates straight to editor")
    func uitestGateBypassesHome() {
        #expect(AppStagePolicy.initialStage(uiTestEnv: "1", bootstrapProjectEnv: nil) == .editor)
    }

    @Test("MOVIECUT_UITEST other than 1 does NOT gate")
    func uitestGateRequiresExactOne() {
        // Only the literal "1" is the harness handshake; any other value is not.
        #expect(AppStagePolicy.initialStage(uiTestEnv: "0", bootstrapProjectEnv: nil) == .home)
        #expect(AppStagePolicy.initialStage(uiTestEnv: "true", bootstrapProjectEnv: nil) == .home)
        #expect(AppStagePolicy.initialStage(uiTestEnv: "", bootstrapProjectEnv: nil) == .home)
    }

    @Test("MOVIECUT_BOOTSTRAP_PROJECT non-empty gates straight to editor")
    func bootstrapGateBypassesHome() {
        #expect(
            AppStagePolicy.initialStage(uiTestEnv: nil, bootstrapProjectEnv: "/tmp/x.moviecut") == .editor
        )
    }

    @Test("MOVIECUT_BOOTSTRAP_PROJECT empty does NOT gate")
    func bootstrapGateRequiresNonEmpty() {
        #expect(AppStagePolicy.initialStage(uiTestEnv: nil, bootstrapProjectEnv: "") == .home)
    }

    @Test("both gates active → editor, and the keys report which matched")
    func bothGatesReportMatchedKeys() {
        let keys = AppStagePolicy.harnessGateKeys(
            uiTestEnv: "1",
            bootstrapProjectEnv: "/tmp/x.moviecut"
        )
        #expect(keys == Set(["MOVIECUT_UITEST", "MOVIECUT_BOOTSTRAP_PROJECT"]))
        #expect(
            AppStagePolicy.initialStage(uiTestEnv: "1", bootstrapProjectEnv: "/tmp/x.moviecut") == .editor
        )
    }

    @Test("no gate active → empty matched-keys set")
    func noGateYieldsEmptyKeys() {
        #expect(AppStagePolicy.harnessGateKeys(uiTestEnv: nil, bootstrapProjectEnv: nil).isEmpty)
        #expect(AppStagePolicy.harnessGateKeys(uiTestEnv: "0", bootstrapProjectEnv: "").isEmpty)
    }

    // MARK: - Dirty transition (requirement 3.7 — Save/Don't Save/Cancel)

    @Test("clean editor → home proceeds without prompting, regardless of choice")
    func cleanTransitionAlwaysProceeds() {
        for choice in UnsavedChangesUserChoice.allCases {
            #expect(
                AppStagePolicy.decideEditorToHome(isDirty: false, userChoice: choice, hasSaveURL: true)
                    == .proceed,
                "clean project should proceed for choice \(choice)"
            )
            #expect(
                AppStagePolicy.decideEditorToHome(isDirty: false, userChoice: choice, hasSaveURL: false)
                    == .proceed
            )
        }
    }

    @Test("dirty + Cancel cancels the transition")
    func dirtyCancelBlocks() {
        #expect(
            AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .cancel, hasSaveURL: true) == .cancel
        )
    }

    @Test("dirty + Discard proceeds (discards unsaved work)")
    func dirtyDiscardProceeds() {
        #expect(
            AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .discard, hasSaveURL: true) == .proceed
        )
    }

    @Test("dirty + Save with an existing URL → needsSave")
    func dirtySaveWithURLNeedsSave() {
        #expect(
            AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .save, hasSaveURL: true) == .needsSave
        )
    }

    @Test("dirty + Save with no URL → needsSaveAs")
    func dirtySaveWithoutURLNeedsSaveAs() {
        #expect(
            AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .save, hasSaveURL: false) == .needsSaveAs
        )
    }

    @Test("editorToHomeRequiresPrompt mirrors isDirty")
    func promptRequiredExactlyWhenDirty() {
        #expect(AppStagePolicy.editorToHomeRequiresPrompt(isDirty: true) == true)
        #expect(AppStagePolicy.editorToHomeRequiresPrompt(isDirty: false) == false)
    }

    // MARK: - resolveAfterSave (a failed save never discards work)

    @Test("needsSave resolved to proceed on success")
    func saveSuccessProceeds() {
        #expect(AppStagePolicy.resolveAfterSave(.needsSave, didSaveSucceed: true) == .proceed)
        #expect(AppStagePolicy.resolveAfterSave(.needsSaveAs, didSaveSucceed: true) == .proceed)
    }

    @Test("needsSave resolved to cancel on failure — a failed save never discards work")
    func saveFailureCancels() {
        #expect(AppStagePolicy.resolveAfterSave(.needsSave, didSaveSucceed: false) == .cancel)
        #expect(AppStagePolicy.resolveAfterSave(.needsSaveAs, didSaveSucceed: false) == .cancel)
    }

    @Test("resolveAfterSave is a no-op for proceed/cancel")
    func resolveNoOpsForTerminalOutcomes() {
        #expect(AppStagePolicy.resolveAfterSave(.proceed, didSaveSucceed: true) == .proceed)
        #expect(AppStagePolicy.resolveAfterSave(.proceed, didSaveSucceed: false) == .proceed)
        #expect(AppStagePolicy.resolveAfterSave(.cancel, didSaveSucceed: true) == .cancel)
        #expect(AppStagePolicy.resolveAfterSave(.cancel, didSaveSucceed: false) == .cancel)
    }

    // MARK: - End-to-end transition matrix (the matrix the App layer maps to UI)

    @Test("full dirty → save → succeed path lands on proceed")
    func fullSavePathLandsOnProceed() {
        let outcome = AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .save, hasSaveURL: true)
        #expect(outcome == .needsSave)
        #expect(AppStagePolicy.resolveAfterSave(outcome, didSaveSucceed: true) == .proceed)
    }

    @Test("full dirty → save → fail path lands on cancel (work preserved)")
    func fullSaveFailPathLandsOnCancel() {
        let outcome = AppStagePolicy.decideEditorToHome(isDirty: true, userChoice: .save, hasSaveURL: true)
        #expect(AppStagePolicy.resolveAfterSave(outcome, didSaveSucceed: false) == .cancel)
    }
}
