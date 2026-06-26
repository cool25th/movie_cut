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

    @Test("the view model runs auto white balance and auto levels from the thumbnail")
    func viewModelWiresAutoColor() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("func autoColorSelectedClip()"))
        #expect(source.contains("func autoLevelsSelectedClip()"))
        #expect(source.contains("AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: rgba)"))
        #expect(source.contains("AutoColorAnalyzer.autoLevelsGrade(rgba: rgba)"))
    }

    @Test("the grading panel exposes auto white balance and auto levels buttons")
    func inspectorExposesAutoColor() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        #expect(source.contains("Auto WB"))
        #expect(source.contains("viewModel.autoColorSelectedClip()"))
        #expect(source.contains("Auto Levels"))
        #expect(source.contains("viewModel.autoLevelsSelectedClip()"))
    }
}
