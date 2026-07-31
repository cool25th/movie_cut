import Foundation

/// The two top-level application surfaces (requirement 3 / design §4.2).
///
/// `home` lists recent projects; `editor` is the existing `ContentView`. The
/// `WindowGroup` branches on this. Staying a plain value type keeps the branch
/// decision testable without SwiftUI/AppKit.
public enum AppStage: Sendable, Equatable {
    case home
    case editor
}

/// Whether a request to transition between ``AppStage`` values should proceed,
/// be blocked, or first prompt the user to save unsaved work.
///
/// The editor → home transition reuses the same Save / Don't Save / Cancel
/// policy as `applicationShouldTerminate` (design §4.2), so the two situations
/// never present different UX for the same condition.
public enum AppStageTransitionOutcome: Sendable, Equatable {
    /// The transition may proceed immediately (the project is clean, or the user
    /// chose to discard, or a requested save succeeded).
    case proceed
    /// The transition is cancelled; the editor stays on screen and the session
    /// is preserved. This is what a Cancel choice, or a failed save, yields.
    case cancel
    /// The user chose Save and a save URL is already known: the caller should
    /// save to that URL, then resolve via ``AppStagePolicy.resolveAfterSave(_:)``.
    case needsSave
    /// The user chose Save and there is no save URL yet: the caller should
    /// present a Save As panel, save, then resolve via
    /// ``AppStagePolicy.resolveAfterSave(_:)``.
    case needsSaveAs
}

/// Pure transition/gate/dirty logic for ``AppStage`` (task 4.3).
///
/// Extracted from the view so the three branches that the home feature adds —
/// *whether to show home at all*, *whether a transition is blocked by unsaved
/// changes*, and *the harness gate that bypasses home* — are unit-testable
/// without SwiftUI/AppKit. The UI-test harness bypasses home entirely
/// (`MOVIECUT_UITEST` / `MOVIECUT_BOOTSTRAP_PROJECT`), so this type is the only
/// coverage for those decisions (design §4.2 coverage-gap note).
///
/// This type owns **decisions only**: no AppKit, no I/O, no env reads baked into
/// the decision functions. The App layer reads `ProcessInfo` and hands the
/// resulting values in, exactly mirroring how `UnsavedChangesPolicy` relates to
/// `EditorViewModel.confirmDiscardUnsavedChanges`.
public enum AppStagePolicy {
    /// Whether the harness gate is active.
    ///
    /// Two env vars bypass home and go straight to the editor (design §4.2
    /// "E2E 무회귀 게이트"):
    /// - `MOVIECUT_UITEST=1` — the DEBUG UI-test harness drives the editor
    ///   directly and must never be sent to home.
    /// - `MOVIECUT_BOOTSTRAP_PROJECT=<path>` — a bootstrap project is loaded
    ///   straight into the editor on launch (used by parity/golden harnesses).
    ///
    /// Returning the matched keys (rather than just a bool) lets tests and the
    /// App layer record *why* home was skipped, which keeps the coverage gap
    /// visible instead of silent.
    public static func harnessGateKeys(
        uiTestEnv: String?,
        bootstrapProjectEnv: String?
    ) -> Set<String> {
        var keys: Set<String> = []
        if uiTestEnv == "1" { keys.insert("MOVIECUT_UITEST") }
        if let path = bootstrapProjectEnv, !path.isEmpty { keys.insert("MOVIECUT_BOOTSTRAP_PROJECT") }
        return keys
    }

    /// The initial stage an app launch should land on.
    ///
    /// - When the harness gate is active the app starts in `.editor` (home is
    ///   bypassed — this is what keeps existing E2E / parity harnesses
    ///   regression-free, requirement 3.6).
    /// - Otherwise the app starts in `.home` (requirement 3.1).
    public static func initialStage(
        uiTestEnv: String?,
        bootstrapProjectEnv: String?
    ) -> AppStage {
        harnessGateKeys(uiTestEnv: uiTestEnv, bootstrapProjectEnv: bootstrapProjectEnv).isEmpty
            ? .home
            : .editor
    }

    /// Stage 1 of the editor → home transition: given the dirty state, the
    /// user's Save/Don't Save/Cancel choice, and whether a save URL is already
    /// known, decide what the caller should do.
    ///
    /// This is the **same** Save/Don't Save/Cancel policy as
    /// `applicationShouldTerminate` (design §4.2), expressed through the shared
    /// `UnsavedChangesUserChoice` type so the two call sites cannot drift:
    /// - A clean project proceeds immediately regardless of the choice.
    /// - Cancel always cancels.
    /// - Discard always proceeds.
    /// - Save routes through `.needsSave` (existing URL) or `.needsSaveAs`.
    public static func decideEditorToHome(
        isDirty: Bool,
        userChoice: UnsavedChangesUserChoice,
        hasSaveURL: Bool
    ) -> AppStageTransitionOutcome {
        if !isDirty { return .proceed }

        switch userChoice {
        case .save:
            return hasSaveURL ? .needsSave : .needsSaveAs
        case .discard:
            return .proceed
        case .cancel:
            return .cancel
        }
    }

    /// Stage 2: after the caller has attempted the save that `.needsSave` /
    /// `.needsSaveAs` requested, resolve the final outcome. A failed save
    /// returns `.cancel` so a transition never discards work — the same rule
    /// `UnsavedChangesPolicy.resolveAfterSave` enforces for new/open/import.
    ///
    /// Passing `.proceed` or `.cancel` here is a no-op (returns the input),
    /// which keeps the resolve step uniform even on non-save paths.
    public static func resolveAfterSave(
        _ outcome: AppStageTransitionOutcome,
        didSaveSucceed: Bool
    ) -> AppStageTransitionOutcome {
        switch outcome {
        case .needsSave, .needsSaveAs:
            return didSaveSucceed ? .proceed : .cancel
        case .proceed, .cancel:
            return outcome
        }
    }

    /// Whether the editor → home transition is currently blocked by unsaved
    /// changes. The view uses this to decide whether a plain "go home" tap needs
    /// to present the Save/Don't Save/Cancel prompt first. Equivalent to the
    /// guard `applicationShouldTerminate` runs before showing its alert.
    public static func editorToHomeRequiresPrompt(isDirty: Bool) -> Bool {
        isDirty
    }
}
