import Foundation
import Testing

@Suite("Export Format Static Contract")
struct ExportFormatStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("ExportEngine applies target bitrate through an AVFoundation export constraint")
    func exportEngineAppliesFileLengthLimit() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("exportSession.fileLengthLimit"))
        #expect(source.contains("AVAssetExportSession preset exports do not expose a direct averageVideoBitRate knob"))
        #expect(source.contains("bitrateForQuality(project.exportSettings)"))
    }

    @Test("ExportEngine output file type is driven by persisted container format")
    func exportEngineUsesContainerFormatForOutputType() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("settings.containerFormat"))
        #expect(source.contains("fallbackFileTypes(for: settings)"))
        #expect(source.contains("case .mp4"))
        #expect(source.contains("case .mov"))
        #expect(source.contains("case .m4v"))
    }

    @Test("Inspector binds format and quality to typed export settings")
    func inspectorUsesTypedExportSettingsBindings() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(source.contains("Picker(\"Format\", selection: exportContainerFormatBinding)"))
        #expect(source.contains("Picker(\"Quality\", selection: exportQualityBinding)"))
        #expect(source.contains("Binding<ExportContainerFormat>"))
        #expect(source.contains("Binding<ExportQuality>"))
        #expect(!source.contains("Picker(\"Format\", selection: $viewModel.exportFormat)"))
        #expect(!source.contains("Picker(\"Quality\", selection: $viewModel.exportQuality)"))
    }

    @Test("Backlog marks format codec bitrate export item complete with AVAssetExportSession caveat")
    func backlogMarksExportFormatItemComplete() throws {
        let source = try source("docs/CAPCUT_FEATURE_BACKLOG.md")

        #expect(source.contains("- [x] ✅ 포맷별 export(mp4/mov, 코덱/비트레이트 실제 반영) (P1)"))
        #expect(source.contains("AVAssetExportSession"))
        #expect(source.contains("fileLengthLimit"))
        #expect(source.contains("averageVideoBitRate"))
    }
}
