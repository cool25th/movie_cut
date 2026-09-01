import Foundation
import Testing

/// Regression lock for the on-device auto-white-balance wiring (Phase 3,
/// restored for the capcut-surpass integration). The gray-world math is
/// unit-tested (AutoColorAnalyzerTests); this guards the view-model and UI so
/// the AI Assistant entry points can never silently fall back to hardcoded
/// color constants again (the e9f6703 disconnect).
@Suite("Auto Color Wiring Static Contract")
struct AutoColorWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("the view model runs auto white balance, levels, and enhance from the thumbnail")
    func viewModelWiresAutoColor() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("func autoColorSelectedClip()"))
        #expect(source.contains("func autoLevelsSelectedClip()"))
        #expect(source.contains("func autoEnhanceSelectedClip()"))
        #expect(source.contains("AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: rgba)"))
        #expect(source.contains("AutoColorAnalyzer.autoLevelsGrade(rgba: rgba)"))
        #expect(source.contains("AutoColorAnalyzer.autoEnhanceGrade(rgba: rgba)"))
    }

    @Test("the grading panel exposes auto enhance and an auto menu")
    func inspectorEffectsExposeAutoColor() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        #expect(source.contains("Auto Enhance"))
        #expect(source.contains("viewModel.autoEnhanceSelectedClip()"))
        #expect(source.contains("viewModel.autoColorSelectedClip()"))
        #expect(source.contains("viewModel.autoLevelsSelectedClip()"))
    }

    @Test("the AI Assistant buttons call the real analyzer path, not a stub")
    func assistantAutoColorCallsRealAnalyzer() throws {
        let inspector = try source("App/MovieCutMac/EditorViewModel+Inspector.swift")
        #expect(inspector.contains("func autoEnhance() async"))
        #expect(inspector.contains("await autoEnhanceSelectedClip()"))
        #expect(inspector.contains("func autoColorCorrect() async"))
        #expect(inspector.contains("await autoColorSelectedClip()"))
        // The hardcoded-constant stub is gone.
        #expect(!inspector.contains("func autoColorCorrect(for clipId: UUID)"))
        #expect(!inspector.contains("colorCorrection.brightness = 0.05"))

        let analysis = try source("App/MovieCutMac/Inspector/InspectorAnalysisSection.swift")
        #expect(analysis.contains("viewModel.autoEnhance()"))
        #expect(analysis.contains("viewModel.autoColorCorrect()"))
    }
}
