import Foundation
import MovieCutCore
import Testing

/// Unit tests for the pure unsaved-changes guard policy. This is the regression
/// net for `EditorViewModel.confirmDiscardUnsavedChanges`: the policy owns every
/// branch decision (including the "a failed save never discards work" rule), so
/// pinning it here protects the guard even though the ViewModel itself is not an
/// SPM test target.
@Suite("UnsavedChangesPolicy")
struct UnsavedChangesPolicyTests {
    // MARK: - decide() — stage 1

    @Test("Clean project proceeds regardless of the user choice")
    func cleanProjectAlwaysProceeds() {
        for choice in UnsavedChangesUserChoice.allCases {
            #expect(
                UnsavedChangesPolicy.decide(isDirty: false, userChoice: choice, hasSaveURL: true) == .proceed,
                "clean project should proceed even for \(choice)"
            )
            #expect(
                UnsavedChangesPolicy.decide(isDirty: false, userChoice: choice, hasSaveURL: false) == .proceed
            )
        }
    }

    @Test("Cancel keeps the session intact")
    func cancelKeepsSession() {
        // Acceptance criterion: Cancel leaves the session as-is.
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .cancel, hasSaveURL: true) == .cancel)
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .cancel, hasSaveURL: false) == .cancel)
    }

    @Test("Discard proceeds without saving")
    func discardProceeds() {
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .discard, hasSaveURL: true) == .proceed)
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .discard, hasSaveURL: false) == .proceed)
    }

    @Test("Save routes to needsSave when a URL is known, needsSaveAs otherwise")
    func saveRouting() {
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .save, hasSaveURL: true) == .needsSave)
        #expect(UnsavedChangesPolicy.decide(isDirty: true, userChoice: .save, hasSaveURL: false) == .needsSaveAs)
    }

    // MARK: - resolveAfterSave() — stage 2

    @Test("A failed save cancels instead of discarding work")
    func failedSaveCancels() {
        // Acceptance criterion: a save failure must not discard work.
        #expect(UnsavedChangesPolicy.resolveAfterSave(.needsSave, didSaveSucceed: false) == .cancel)
        #expect(UnsavedChangesPolicy.resolveAfterSave(.needsSaveAs, didSaveSucceed: false) == .cancel)
    }

    @Test("A successful save proceeds")
    func successfulSaveProceeds() {
        #expect(UnsavedChangesPolicy.resolveAfterSave(.needsSave, didSaveSucceed: true) == .proceed)
        #expect(UnsavedChangesPolicy.resolveAfterSave(.needsSaveAs, didSaveSucceed: true) == .proceed)
    }

    @Test("resolveAfterSave is a no-op on already-terminal decisions")
    func resolveIsNoOpOnTerminal() {
        #expect(UnsavedChangesPolicy.resolveAfterSave(.proceed, didSaveSucceed: false) == .proceed)
        #expect(UnsavedChangesPolicy.resolveAfterSave(.cancel, didSaveSucceed: true) == .cancel)
        #expect(UnsavedChangesPolicy.resolveAfterSave(.proceed, didSaveSucceed: true) == .proceed)
        #expect(UnsavedChangesPolicy.resolveAfterSave(.cancel, didSaveSucceed: false) == .cancel)
    }

    // MARK: - End-to-end policy flow (save path, the data-loss regression)

    @Test("Save-then-failure leaves the work intact end to end")
    func saveFailureFlow() {
        // The exact sequence confirmDiscardUnsavedChanges runs when the user
        // picks Save but the save errors out.
        let stage1 = UnsavedChangesPolicy.decide(isDirty: true, userChoice: .save, hasSaveURL: true)
        #expect(stage1 == .needsSave)
        let resolved = UnsavedChangesPolicy.resolveAfterSave(stage1, didSaveSucceed: false)
        #expect(resolved == .cancel)
    }

    @Test("Save-then-success proceeds end to end")
    func saveSuccessFlow() {
        let stage1 = UnsavedChangesPolicy.decide(isDirty: true, userChoice: .save, hasSaveURL: false)
        #expect(stage1 == .needsSaveAs)
        let resolved = UnsavedChangesPolicy.resolveAfterSave(stage1, didSaveSucceed: true)
        #expect(resolved == .proceed)
    }

    @Test("Discard flow is a single stage")
    func discardFlow() {
        let stage1 = UnsavedChangesPolicy.decide(isDirty: true, userChoice: .discard, hasSaveURL: true)
        #expect(stage1 == .proceed)
    }
}
