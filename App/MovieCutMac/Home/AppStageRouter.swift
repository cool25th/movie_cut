import AppKit
import SwiftUI
import MovieCutCore

/// App-layer holder of the current ``AppStage`` and the editor ↔ home router
/// (task 4.3 / 4.4).
///
/// This is a thin SwiftUI/AppKit adapter: it owns the *current stage* and the
/// Save/Don't Save/Cancel **presentation**, but every branch decision is
/// delegated to the pure, unit-tested ``AppStagePolicy`` in Core (the harness
/// bypasses home, so the Core policy is the only coverage for those decisions).
///
/// The editor → home transition reuses the exact Save / Don't Save / Cancel
/// policy of `MovieCutAppDelegate.applicationShouldTerminate` (design §4.2),
/// routed through the shared ``UnsavedChangesUserChoice`` /
/// ``AppStageTransitionOutcome`` types so the two situations cannot drift. The
/// *Save* action reuses the VM's existing ``terminateAfterSaving()`` path
/// (which already handles the save-URL-or-Save-As + save + success cases), so
/// no save logic is duplicated.
///
/// The router records projects opened from Home, while successful saves are
/// recorded by `EditorViewModel.saveProject(to:)` through the shared
/// `RecentProjectsStore`. This keeps Cmd-S, the editor Save button, and
/// home-originated opens on the same persisted recent-project list.
///
/// The router calls the view model's project lifecycle entry points
/// (`currentProject`, `isDirty`, `terminateAfterSaving()`, `openProject(from:)`,
/// `newProject()`) and the home-routing extension's
/// `recordCurrentProjectToRecent(_:savedTo:)`.
@MainActor
@Observable
final class AppStageRouter {
    /// The surface the `WindowGroup` currently shows.
    private(set) var stage: AppStage

    private let viewModel: EditorViewModel
    private let store: RecentProjectsStore

    init(viewModel: EditorViewModel, store: RecentProjectsStore) {
        self.viewModel = viewModel
        self.store = store
        viewModel.recentProjectsStore = store
        // Read the harness gate once at construction (launch). The gate is
        // static for the process lifetime, so this is the only read.
        let env = ProcessInfo.processInfo.environment
        self.stage = AppStagePolicy.initialStage(
            uiTestEnv: env["MOVIECUT_UITEST"],
            bootstrapProjectEnv: env["MOVIECUT_BOOTSTRAP_PROJECT"]
        )
    }

    // MARK: - Transitions the views request

    /// User tapped "New Project" on the home screen. The VM's own
    /// `confirmDiscardUnsavedChanges` (shared policy) guards the session swap;
    /// on success the router flips to the editor.
    func requestNewProject() async {
        guard await viewModel.newProject() else { return }
        stage = .editor
    }

    /// Open a project file (from the home list's recent entry or an Open panel).
    /// Resolves the security-scoped bookmark, opens the project inside the
    /// scope, then flips to the editor. Records the opened project into the
    /// recent list (requirement 3.3) so it sorts to the top on the next home
    /// visit. Returns whether the open succeeded so the home list can refresh on
    /// failure.
    @discardableResult
    func requestOpenProject(at url: URL, bookmark: Data?) async -> Bool {
        // The single owner of the scope lifecycle opens the project file inside
        // a security scope so the sandbox re-reaches it (requirement 3.5). The
        // VM's own guard handles any unsaved session swap via the shared policy.
        // The single owner of the scope lifecycle opens the project file inside
        // a security scope so the sandbox re-reaches it (requirement 3.5). Use
        // the begin/end pair directly to avoid crossing a concurrency boundary
        // with the @MainActor view model inside a generic closure body.
        let scopedURL = SecurityScopedAccess.beginScope(for: url, bookmark: bookmark)
        defer { SecurityScopedAccess.endScope(for: scopedURL) }
        await viewModel.openProject(from: scopedURL)
        guard viewModel.lastErrorMessage == nil else { return false }
        // Record the opened project (refreshes recency + thumbnail at open time,
        // satisfying the recent-list-update intent of requirement 3.3 on the
        // home-routed flow).
        await viewModel.recordCurrentProjectToRecent(store, savedTo: url)
        stage = .editor
        return true
    }

    /// User requested to leave the editor and return home (requirement 3.7).
    ///
    /// If the project is clean this flips immediately. If it is dirty the
    /// router presents the Save / Don't Save / Cancel alert (the same three
    /// buttons and order as `applicationShouldTerminate`), then maps the choice
    /// through ``AppStagePolicy`` and performs any save it requests. A failed
    /// save cancels the transition so work is never discarded.
    func requestReturnToHome() async {
        // Fast path: the harness gate is active. The harness never expects a
        // modal and cannot be in the home stage (it bypasses home), so this is
        // purely defensive — but mirrors confirmDiscardUnsavedChanges' gate.
        let env = ProcessInfo.processInfo.environment
        if !AppStagePolicy.harnessGateKeys(
            uiTestEnv: env["MOVIECUT_UITEST"],
            bootstrapProjectEnv: env["MOVIECUT_BOOTSTRAP_PROJECT"]
        ).isEmpty {
            stage = .home
            return
        }

        guard AppStagePolicy.editorToHomeRequiresPrompt(isDirty: viewModel.isDirty) else {
            stage = .home
            return
        }

        let choice = presentUnsavedChangesAlert()
        await applyEditorToHomeChoice(choice)
    }

    // MARK: - Shared decision → action mapping

    /// Maps a Save/Don't Save/Cancel choice through the pure policy, performing
    /// any save it requests, and flips to home on `.proceed`.
    ///
    /// The *Save* action reuses `EditorViewModel.terminateAfterSaving()`, which
    /// already handles both the "has save URL" and "needs Save As" branches and
    /// returns whether the save succeeded. That is the exact save path
    /// `applicationShouldTerminate` runs, so the home transition and quit share
    /// one save implementation (design §4.2).
    private func applyEditorToHomeChoice(_ choice: UnsavedChangesUserChoice) async {
        switch choice {
        case .discard:
            // Policy: dirty + discard → proceed.
            stage = .home
        case .cancel:
            // Policy: dirty + cancel → cancel.
            return
        case .save:
            // Reuse the terminate save path verbatim. It presents Save As if
            // needed and returns success/failure; the policy maps that to the
            // final outcome.
            let saved = await viewModel.terminateAfterSaving()
            let outcome = AppStagePolicy.decideEditorToHome(
                isDirty: viewModel.isDirty,
                userChoice: .save,
                hasSaveURL: true // terminateAfterSaving resolved the URL itself
            )
            let resolved = AppStagePolicy.resolveAfterSave(outcome, didSaveSucceed: saved)
            if resolved == .proceed { stage = .home }
        }
    }

    /// Presents the Save / Don't Save / Cancel alert. Same three buttons, same
    /// order, same copy as `applicationShouldTerminate` and
    /// `EditorViewModel.presentUnsavedChangesAlert` — the home transition must
    /// not present a different UX for the same condition (design §4.2).
    private func presentUnsavedChangesAlert() -> UnsavedChangesUserChoice {
        let alert = NSAlert()
        alert.messageText = "Save changes to \"\(viewModel.currentProject.name)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}
