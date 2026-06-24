import Foundation
import Testing

/// Regression lock for the color-scope wiring (Phase 2A increment 6). The
/// ScopeAnalyzer reductions are unit-tested and `run_e2e_export.sh` confirms the
/// histogram is computed from a real graded thumbnail (luma sample count > 0);
/// this guards the view-model and inspector wiring.
@Suite("Color Scope Wiring Static Contract")
struct ColorScopeWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("the view model computes a grade-applied histogram from the thumbnail")
    func viewModelComputesScope() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("var scopeHistogram: ScopeAnalyzer.Histogram?"))
        #expect(source.contains("func refreshScopes()"))
        #expect(source.contains("ColorGradePixelProcessor.apply(colorGrade, to: image)"))
        #expect(source.contains("ScopeAnalyzer.histogram(rgba: bytes"))
        // Edits refresh the scope.
        #expect(source.contains("refreshScopes()"))
    }

    @Test("the grading panel shows the histogram and refreshes on clip change")
    func inspectorShowsScope() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        #expect(source.contains("HistogramView(histogram: histogram)"))
        #expect(source.contains("viewModel.scopeHistogram"))
        #expect(source.contains(".task(id: clip.id)"))
    }
}
