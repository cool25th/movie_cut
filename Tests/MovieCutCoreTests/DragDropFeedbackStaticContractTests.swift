import Foundation
import Testing

/// The macOS SwiftUI drop delegates are verified by xcodebuild. These checks
/// keep the user-visible drag/drop feedback wiring visible in the SwiftPM loop.
@Suite("Drag Drop Feedback Static Contract")
struct DragDropFeedbackStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model exposes drop success and error feedback helpers")
    func viewModelExposesDropFeedbackHelpers() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(source.contains("func setDropStatus"))
        #expect(source.contains("func setDropError"))
        #expect(source.contains("lastErrorMessage = nil"))
        #expect(source.contains("lastStatusMessage = message"))
        #expect(source.contains("lastStatusMessage = nil"))
        #expect(source.contains("lastErrorMessage = message"))
        #expect(source.contains("reportTimelineFileDropSuccess"))
        #expect(source.contains("reportTimelineLibraryAssetDropSuccess"))
        #expect(source.contains("reportMediaLibraryDropSuccess"))
    }

    @Test("timeline decoded-empty callbacks report drop failures")
    func timelineDecodedEmptyCallbacksReportFailures() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains("guard !assetIds.isEmpty else"))
        #expect(source.contains("viewModel.reportInvalidTimelineLibraryAssetDrop()"))
        #expect(source.contains("guard !urls.isEmpty else"))
        #expect(source.contains("viewModel.reportInvalidTimelineFileDrop()"))
        #expect(source.contains("viewModel.reportUnsupportedTimelineDrop()"))
    }

    @Test("media library invalid drops report feedback instead of silently returning")
    func mediaLibraryInvalidDropsReportFeedback() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        #expect(source.contains("MediaLibraryDropPayloadLoader.loadFileURLs"))
        #expect(source.contains("viewModel.reportInvalidMediaLibraryDrop()"))
        #expect(source.contains("DragDropHandler.isSupportedMediaURL"))
        #expect(source.contains("await viewModel.importMedia(urls)"))
    }
}
