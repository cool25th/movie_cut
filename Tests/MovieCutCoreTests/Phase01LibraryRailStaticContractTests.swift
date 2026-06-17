import Foundation
import Testing

/// Phase 0-1 replaces the left library's horizontal pill tabs with a fixed
/// vertical icon rail while keeping imports and tab actions presentation-only.
@Suite("Phase 0-1 Library Rail StaticContract")
struct Phase01LibraryRailStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase01LibraryRailStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase01LibraryRailStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Library rail replaces horizontal tab scroll with fixed vertical rail")
    func libraryRailReplacesHorizontalTabScroll() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let body = try section(
            in: source,
            from: "var body: some View",
            to: "    @ViewBuilder\n    private var headerActions"
        )
        let rail = try section(
            in: source,
            from: "private var libraryTabRail: some View",
            to: "    private func libraryRailButton"
        )

        #expect(source.contains("private let libraryRailWidth: CGFloat = 60"))
        #expect(source.contains("private let libraryRailItemHeight: CGFloat = 32"))
        #expect(source.contains("private let libraryRailTopInset: CGFloat = 112"))
        #expect(!source.contains("private var libraryTabBar"))
        #expect(!source.contains("ScrollView(.horizontal"))
        #expect(body.contains("HStack(spacing: 0)"))
        #expect(body.contains("libraryTabRail"))
        #expect(body.contains("Divider()"))
        #expect(body.contains("librarySearchField"))
        #expect(body.contains("selectedLibraryTabContent"))
        #expect(rail.contains("VStack(spacing: libraryRailItemSpacing)"))
        #expect(rail.contains("ForEach(LibraryTab.allCases) { tab in"))
        #expect(rail.contains(".padding(.top, libraryRailTopInset)"))
        #expect(rail.contains(".frame(width: libraryRailWidth)"))
        #expect(rail.contains(".frame(maxHeight: .infinity, alignment: .top)"))
        #expect(rail.contains(#"accessibilityLabel(NSLocalizedString("Library browser tabs", comment: ""))"#))
    }

    @Test("Rail items preserve accessibility and selected highlight")
    func railItemsPreserveAccessibilityAndSelectedHighlight() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let button = try section(
            in: source,
            from: "private func libraryRailButton(for tab: LibraryTab) -> some View",
            to: "    private func selectLibraryTab"
        )

        #expect(button.contains("Image(systemName: tab.systemImage)"))
        #expect(button.contains("Text(tab.railLabel)"))
        #expect(button.contains(".fill(selectedLibraryTab == tab ? MovieCutTheme.selectedFill : MovieCutTheme.controlSurface)"))
        #expect(button.contains("selectedLibraryTab == tab ? MovieCutTheme.accentCyan.opacity(0.62) : MovieCutTheme.border.opacity(0.46)"))
        #expect(button.contains(".foregroundStyle(selectedLibraryTab == tab ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText)"))
        #expect(button.contains(".accessibilityLabel(tab.displayName)"))
        #expect(button.contains(".accessibilityHint(tab.accessibilityHint)"))
        #expect(button.contains(#".accessibilityValue(selectedLibraryTab == tab ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))"#))
    }

    @Test("LibraryTab exposes exactly ten rail cases and requested metadata")
    func libraryTabExposesExactlyTenRailCases() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let enumCases = try section(
            in: source,
            from: "private enum LibraryTab: CaseIterable, Identifiable",
            to: "    var id: Self { self }"
        )

        let caseLines = enumCases
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.hasPrefix("case ") }

        #expect(caseLines == [
            "case media",
            "case audio",
            "case text",
            "case captions",
            "case stickers",
            "case effects",
            "case transitions",
            "case filters",
            "case adjustment",
            "case smart"
        ])

        for marker in [
            #"NSLocalizedString("Captions", comment: "")"#,
            #"NSLocalizedString("Auto subtitles and SRT", comment: "")"#,
            #"NSLocalizedString("Adjust", comment: "")"#,
            #"NSLocalizedString("Color and look controls", comment: "")"#,
            #"NSLocalizedString("Smart", comment: "")"#,
            #"NSLocalizedString("AI tools and automation", comment: "")"#,
            #"case .captions: return "captions.bubble""#,
            #"case .adjustment: return "slider.horizontal.3""#,
            #"case .smart: return "wand.and.stars""#,
            "var railLabel: String"
        ] {
            #expect(source.contains(marker))
        }
    }

    @Test("New tab bodies are presentation only and preserve drop import")
    func newTabBodiesArePresentationOnlyAndPreserveDropImport() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let selectedContent = try section(
            in: source,
            from: "private var selectedLibraryTabContent: some View",
            to: "    private var libraryTabRail"
        )

        for marker in [
            "case .captions:",
            "case .adjustment:",
            "case .smart:",
            "captionsTabContent",
            "adjustmentTabContent",
            "smartTabContent"
        ] {
            #expect(selectedContent.contains(marker))
        }

        #expect(source.contains(".onDrop(of: [.fileURL, .movie, .image], isTargeted: nil)"))
        #expect(source.contains("handleDrop(providers)"))
        #expect(source.contains("await viewModel.importMedia(urls)"))
        #expect(source.contains("AutoSubtitlesView(viewModel: viewModel)"))
        #expect(source.contains("private var adjustmentTabContent: some View"))
        #expect(source.contains("previewKind: .adjustment"))
        #expect(source.contains("types: adjustmentEffectTypes"))
        #expect(source.contains("private var adjustmentEffectTypes: [EffectType]"))
        #expect(source.contains("[.brightness, .contrast, .saturation, .temperature, .exposure]"))
        #expect(source.contains("private var smartTabContent: some View"))
        #expect(!source.contains("Smart tools move here next."))
        #expect(!source.contains("QuickToolsPanel(viewModel: viewModel)"))
    }

    @Test("ContentView gives left rail and content column enough width")
    func contentViewGivesLeftRailAndContentColumnEnoughWidth() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")

        #expect(content.contains(".frame(minWidth: 360, idealWidth: 380, maxWidth: 430)"))
    }

    @Test("Handoff keeps Phase 0-1 progress noted")
    func handoffKeepsPhase01ProgressNoted() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 0-1 implemented"))
        #expect(handoff.contains("Phase01LibraryRailStaticContractTests"))
        #expect(handoff.contains("Phase 0-2 implemented"))
        #expect(handoff.contains("Phase 0-3 implemented"))
        #expect(handoff.contains("Phase 0-4 implemented"))
        #expect(handoff.contains("Phase 0 complete"))
        #expect(!handoff.contains("Phase 0-4 remains pending"))
    }
}

private enum Phase01LibraryRailStaticContractError: Error {
    case missingMarker(String)
}
