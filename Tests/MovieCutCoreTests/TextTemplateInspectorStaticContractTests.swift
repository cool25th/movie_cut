import Foundation
import Testing

@Suite("Text Template Inspector Static Contract")
struct TextTemplateInspectorStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("Selected text inspector exposes Core template browser thumbnails")
    func selectedTextInspectorExposesCoreTemplateBrowser() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")

        #expect(inspector.contains("textTemplateBrowser()"))
        #expect(inspector.contains("Text(\"Templates\")"))
        #expect(inspector.contains("ScrollView(.horizontal, showsIndicators: false)"))
        #expect(inspector.contains("LazyHGrid("))
        #expect(inspector.contains("MovieCutCore.TextTemplate.builtIn"))
        #expect(inspector.contains("InspectorTextTemplateThumbnail(template: template)"))
        #expect(inspector.contains("viewModel.addTextTemplateClip(template)"))
        #expect(inspector.contains("Creates a new text clip at the playhead with this template style."))
    }

    @Test("Inspector template entry points use the Core template library")
    func inspectorEntryPointsUseCoreTemplateLibrary() throws {
        let analysis = try source("App/MovieCutMac/Inspector/InspectorAnalysisSection.swift")

        #expect(analysis.contains("ForEach(MovieCutCore.TextTemplate.builtIn)"))
        #expect(analysis.contains("viewModel.addTextTemplateClip(template)"))
        #expect(!analysis.contains("EditorViewModel.textTemplates"))
        #expect(!analysis.contains("viewModel.addTextFromTemplate(template)"))
    }
}
