import Foundation
import Testing

/// Phase 0-2 moves the Smart/AI automation entry points into the left library
/// as presentation-only cards.
@Suite("Phase 0-2 Smart Tools StaticContract")
struct Phase02SmartToolsStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase02SmartToolsStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase02SmartToolsStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Smart tab replaces placeholder with two column card grid")
    func smartTabReplacesPlaceholderWithTwoColumnCardGrid() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let smartTab = try section(
            in: source,
            from: "private var smartTabContent: some View",
            to: "    @ViewBuilder\n    private var transitionsTabContent"
        )

        #expect(!source.contains("Smart tools move here next."))
        #expect(source.contains("@State private var runningSmartTool: SmartLibraryTool?"))
        #expect(smartTab.contains("LazyVGrid(columns: libraryGridColumns"))
        #expect(smartTab.contains("ForEach(SmartLibraryTool.allCases) { tool in"))
        #expect(smartTab.contains("smartToolButton(tool)"))
        #expect(!smartTab.contains("ScrollView(.horizontal"))
        #expect(source.contains("private func smartToolCard("))
        #expect(source.contains("private func smartToolAffordance("))
        #expect(source.contains("ProgressView()"))
        #expect(source.contains("runningSmartTool == tool"))
        #expect(source.contains("viewModel.quickToolProgressMessage"))
        #expect(source.contains("viewModel.lastStatusMessage"))
        #expect(source.contains("viewModel.lastErrorMessage"))
    }

    @Test("SmartLibraryTool exposes exactly six requested cards")
    func smartLibraryToolExposesExactlySixRequestedCards() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let toolEnum = try section(
            in: source,
            from: "private enum SmartLibraryTool",
            to: "private enum LibraryHoverPreviewKind"
        )
        let enumCases = try section(
            in: toolEnum,
            from: "private enum SmartLibraryTool",
            to: "    var id: Self { self }"
        )

        let caseLines = enumCases
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("case ") }

        #expect(caseLines == [
            "case autoCut",
            "case sceneDetect",
            "case beatDetect",
            "case reframe",
            "case noiseReduction",
            "case extractAudio"
        ])

        for marker in [
            #"NSLocalizedString("Auto Cut", comment: "")"#,
            #"return "speaker.slash""#,
            #"NSLocalizedString("Detect Scenes", comment: "")"#,
            #"return "film.stack""#,
            #"NSLocalizedString("Detect Beats", comment: "")"#,
            #"return "metronome""#,
            #"NSLocalizedString("Auto Reframe", comment: "")"#,
            #"return "viewfinder""#,
            #"NSLocalizedString("Noise Reduce", comment: "")"#,
            #"return "waveform.badge.minus""#,
            #"NSLocalizedString("Extract Audio", comment: "")"#,
            #"return "waveform""#,
            #"Analyze silence and prepare automatic cuts for the selected clip."#,
            #"Select an audio or video clip."#,
            #"Select a video clip."#
        ] {
            #expect(toolEnum.contains(marker))
        }
    }

    @Test("Smart cards use existing ViewModel booleans and async actions")
    func smartCardsUseExistingViewModelBooleansAndAsyncActions() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let enabled = try section(
            in: source,
            from: "private func isSmartToolEnabled(_ tool: SmartLibraryTool) -> Bool",
            to: "    private func runSmartTool"
        )
        let performer = try section(
            in: source,
            from: "private func performSmartTool(_ tool: SmartLibraryTool) async",
            to: "    @ViewBuilder\n    private var transitionsTabContent"
        )

        for marker in [
            "return viewModel.canRunAutoCutOnSelection",
            "return viewModel.canDetectSceneChangesForSelection",
            "return viewModel.canDetectBeats",
            "return viewModel.canAutoReframeSelection",
            "return viewModel.canApplyNoiseReductionToSelection",
            "return viewModel.canExtractAudioFromSelection"
        ] {
            #expect(enabled.contains(marker))
        }

        for marker in [
            "await viewModel.runAutoCutOnSelection()",
            "await viewModel.detectSceneChangesForSelection()",
            "await viewModel.detectBeats()",
            "await viewModel.autoReframeSelection()",
            "await viewModel.applyNoiseReductionToSelection()",
            "await viewModel.extractAudioFromSelection()"
        ] {
            #expect(performer.contains(marker))
        }
    }

    @Test("Timeline no longer embeds QuickToolsPanel after Phase 0-4")
    func timelineNoLongerEmbedsQuickToolsPanelAfterPhase04() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        #expect(!timeline.contains("QuickToolsPanel(viewModel: viewModel)"))
    }
}

private enum Phase02SmartToolsStaticContractError: Error {
    case missingMarker(String)
}
