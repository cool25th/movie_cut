import Foundation
import Testing
@testable import MovieCutCore

/// Locks the macOS UI wiring that surfaces the planner-backed export kinds:
/// the `EditorViewModel` action methods and the toolbar "Export As" menu.
@Suite("Export Options UI Static Contract")
struct ExportOptionsUIStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
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

    @Test("Toolbar exposes an Export As menu for the additional formats")
    func toolbarExposesExportAsMenu() throws {
        let source = try source("App/MovieCutMac/ContentView.swift")
        #expect(source.contains("Label(\"Export As\""))
        #expect(source.contains("viewModel.exportWithExplicitBitrate()"))
        #expect(source.contains("viewModel.exportProResMaster()"))
        #expect(source.contains("viewModel.exportAudioOnly()"))
        #expect(source.contains("viewModel.exportAnimatedGIF()"))
        #expect(source.contains("viewModel.exportStillFrame()"))
    }
}
