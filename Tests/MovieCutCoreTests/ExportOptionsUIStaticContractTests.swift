import Foundation
import Testing
@testable import MovieCutCore

/// Locks the macOS UI wiring that surfaces the planner-backed export kinds:
/// the `EditorViewModel` action methods and the single toolbar export control.
@Suite("Export Options UI Static Contract")
struct ExportOptionsUIStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func slice(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw ExportOptionsUIStaticContractError.missingMarker(start)
        }
        guard let endRange = source[startRange.upperBound...].range(of: end) else {
            throw ExportOptionsUIStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("EditorViewModel exposes an action per planner-backed export kind")
    func viewModelExposesExportKindActions() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("func exportWithExplicitBitrate() async"))
        #expect(source.contains("func exportProResMaster() async"))
        #expect(source.contains("func exportAudioOnly() async"))
        #expect(source.contains("func exportAnimatedGIF() async"))
        #expect(source.contains("func exportStillFrame() async"))
    }

    @Test("Export-kind actions route through the dedicated ExportEngine methods")
    func viewModelRoutesToEngineMethods() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(source.contains("exportEngine.exportVideoWithExplicitBitrate("))
        #expect(source.contains("profileOverride: .proRes422"))
        #expect(source.contains("exportEngine.exportAudioOnly("))
        #expect(source.contains("exportEngine.exportAnimatedGIF("))
        #expect(source.contains("exportEngine.exportStillFrame("))
        #expect(source.contains("at: playheadTime"))
    }

    @Test("Toolbar uses one export control with a dropdown for formats and latest-share")
    func toolbarUsesOneExportControlWithDropdownFormats() throws {
        let source = try source("App/MovieCutMac/ContentView.swift")
        let exportControl = try slice(
            in: source,
            from: "private var exportToolbarControl: some View",
            to: "private var toolbarCanvasPresets"
        )

        #expect(!source.contains("Label(\"Export As\""))
        #expect(source.contains("exportToolbarControl"))
        #expect(exportControl.contains("ControlGroup"))
        #expect(exportControl.contains("Button(action: { Task { await viewModel.exportProject() } })"))
        #expect(exportControl.contains("Menu {"))
        #expect(exportControl.contains(".disabled(viewModel.exportEngine.isExporting)"))
        #expect(exportControl.contains("viewModel.exportWithExplicitBitrate()"))
        #expect(exportControl.contains("viewModel.exportProResMaster()"))
        #expect(exportControl.contains("viewModel.exportAudioOnly()"))
        #expect(exportControl.contains("viewModel.exportAnimatedGIF()"))
        #expect(exportControl.contains("viewModel.exportStillFrame()"))
        #expect(exportControl.contains("if let exportURL = viewModel.lastExportURL"))
        #expect(exportControl.contains("ShareLink(item: exportURL)"))
        #expect(exportControl.contains(".accessibilityLabel(\"Share latest export\")"))
    }
}

private enum ExportOptionsUIStaticContractError: Error {
    case missingMarker(String)
}
