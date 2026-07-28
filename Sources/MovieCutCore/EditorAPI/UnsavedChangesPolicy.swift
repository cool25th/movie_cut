import Foundation

/// The user's answer to a "save unsaved changes?" prompt. This is the presenter
/// input (from an `NSAlert`, a harness injection, or a script); the policy below
/// decides what to do with it.
public enum UnsavedChangesUserChoice: String, Sendable, CaseIterable {
    /// Save the project, then proceed only if the save succeeded.
    case save
    /// Discard the unsaved work and proceed.
    case discard
    /// Cancel the operation, leaving the current session untouched.
    case cancel
}

/// The policy decision for a session-replacing operation (new/open/import/
/// template/cloud) when unsaved changes may exist. Pure — no AppKit, no I/O.
public enum UnsavedChangesDecision: Sendable, Equatable {
    /// Proceed with the operation (the project is clean, or the user chose to
    /// discard, or a save succeeded).
    case proceed
    /// Cancel the operation; the current session is preserved.
    case cancel
    /// The user chose Save and a save URL already exists: the caller should save
    /// to that URL, then resolve the outcome via ``resolveAfterSave``.
    case needsSave
    /// The user chose Save and there is no save URL: the caller should present a
    /// Save As panel, save, then resolve the outcome via ``resolveAfterSave``.
    case needsSaveAs
}

/// Pure decision logic for the unsaved-changes guard. Extracted from
/// `EditorViewModel.confirmDiscardUnsavedChanges` so the policy (including the
/// "a failed save never discards work" rule) can be unit-tested without the app
/// target. The app layer keeps only the AppKit presentation (alert / save panel)
/// and the actual save call; this type owns every branch decision.
public enum UnsavedChangesPolicy {
    /// Stage 1: given the dirty state, the user's choice, and whether a save URL
    /// is already known, decide what the caller should do.
    ///
    /// - A clean project proceeds immediately regardless of the choice.
    /// - Cancel always cancels.
    /// - Discard always proceeds.
    /// - Save routes through `.needsSave` (existing URL) or `.needsSaveAs`.
    public static func decide(
        isDirty: Bool,
        userChoice: UnsavedChangesUserChoice,
        hasSaveURL: Bool
    ) -> UnsavedChangesDecision {
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
    /// returns `.cancel` so the caller never discards work — this is the rule
    /// the previous inline `lastErrorMessage == nil` check encoded.
    ///
    /// Passing `.proceed` or `.cancel` here is a no-op (returns the input),
    /// which keeps the resolve step uniform even on non-save paths.
    public static func resolveAfterSave(
        _ decision: UnsavedChangesDecision,
        didSaveSucceed: Bool
    ) -> UnsavedChangesDecision {
        switch decision {
        case .needsSave, .needsSaveAs:
            return didSaveSucceed ? .proceed : .cancel
        case .proceed, .cancel:
            return decision
        }
    }
}
