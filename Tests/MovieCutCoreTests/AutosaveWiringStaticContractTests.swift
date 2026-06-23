import Foundation
import Testing

/// Regression lock for the app-level autosave / crash-recovery wiring (Phase 0.6).
/// Behavioral evidence lives in `AutosaveRecoveryTests` and the headless harness;
/// this only guards the wiring from silent removal.
@Suite("Autosave Wiring Static Contract")
struct AutosaveWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("edits trigger autosave and the view model exposes recovery")
    func viewModelWiresAutosave() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        // Autosave fires from the shared post-edit refresh path.
        #expect(source.contains("scheduleAutosave()"))
        #expect(source.contains("func scheduleAutosave()"))
        #expect(source.contains("saveAutosave(snapshot)"))
        // Recovery + clean-quit clear are exposed.
        #expect(source.contains("func recoverableProject() async -> Project?"))
        #expect(source.contains("func adoptRecoveredProject("))
        #expect(source.contains("func clearRecoveryAutosave() async"))
    }

    @Test("app offers recovery on launch and clears autosave on clean quit")
    func contentViewWiresLifecycle() throws {
        let source = try source("App/MovieCutMac/ContentView.swift")
        #expect(source.contains("presentRecoveryIfNeeded()"))
        #expect(source.contains("NSApplication.willTerminateNotification"))
        #expect(source.contains("clearRecoveryAutosave()"))
        // The recovery modal is skipped in headless harness / bootstrap runs.
        #expect(source.contains("MOVIECUT_UITEST"))
        #expect(source.contains("MOVIECUT_BOOTSTRAP_PROJECT"))
    }
}
