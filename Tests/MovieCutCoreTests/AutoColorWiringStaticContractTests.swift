import Foundation
import Testing

/// Regression lock for the on-device auto-white-balance wiring (Phase 3). The
/// gray-world math is unit-tested (AutoColorAnalyzerTests) and run_e2e_export.sh
/// confirms it produces a corrective gain; this guards the view-model and UI.
@Suite("Auto Color Wiring Static Contract")
struct AutoColorWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("the view model runs auto white balance from the thumbnail and sets a grade")
    func viewModelWiresAutoColor() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("func autoColorSelectedClip()"))
        #expect(source.contains("AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: bytes)"))
        #expect(source.contains("await updateSelectedColorGrade(grade)"))
    }

    @Test("the grading panel exposes an auto white balance button")
    func inspectorExposesAutoColor() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        #expect(source.contains("Auto WB"))
        #expect(source.contains("viewModel.autoColorSelectedClip()"))
    }
}
