import Foundation
import Testing

@Suite("R6-01 Visual Parity Dark Shell StaticContract")
struct R601VisualParityDarkShellStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("R6-01 theme uses explicit CapCut dark semantic tokens")
    func themeUsesExplicitCapCutDarkSemanticTokens() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            #"static let editorBackground: Color = rgb(0x0F, 0x0F, 0x10)"#,
            #"static let panelBackground: Color = rgb(0x17, 0x18, 0x1A)"#,
            #"static let panelBackgroundRaised: Color = rgb(0x1B, 0x1C, 0x1F)"#,
            #"static let cardBackground: Color = rgb(0x18, 0x19, 0x1B)"#,
            #"static let elevatedCardBackground: Color = rgb(0x1B, 0x1C, 0x1E)"#,
            #"static let controlSurface: Color = rgb(0x1A, 0x1B, 0x1D)"#,
            #"static let libraryWellBackground: Color = rgb(0x22, 0x23, 0x26)"#,
            #"static let libraryRailButtonBackground: Color = rgb(0x2D, 0x2E, 0x32)"#,
            #"static let libraryCardBackground: Color = rgb(0x32, 0x33, 0x36)"#,
            #"static let libraryRaisedCardBackground: Color = rgb(0x38, 0x39, 0x3D)"#,
            #"static let libraryThumbnailBackground: Color = rgb(0x36, 0x38, 0x3C)"#,
            #"static let inspectorSelectedCardBackground: Color = rgb(0x13, 0x14, 0x16)"#,
            #"static let inspectorSelectedControlSurface: Color = rgb(0x17, 0x18, 0x1A)"#,
            #"static let previewBackground: Color = rgb(0x03, 0x03, 0x04)"#,
            #"static let previewWellBackground: Color = rgb(0x0F, 0x10, 0x12)"#,
            #"static let previewControlBackground: Color = rgb(0x13, 0x14, 0x16, opacity: 0.82)"#,
            #"static let previewEmptyStateBackground: Color = rgb(0x12, 0x13, 0x15, opacity: 0.94)"#,
            #"static let timelineBackground: Color = rgb(0x10, 0x11, 0x14)"#,
            #"static let trackBackground: Color = rgb(0x0E, 0x0F, 0x12)"#,
            #"static let timelineVideoClip: Color = rgb(0x1D, 0x30, 0x38)"#,
            #"static let accentCyan: Color = rgb(0x36, 0xD7, 0xFF)"#,
            #"static let selectedFill: Color = accentCyan.opacity(0.22)"#,
            #"func movieCutScrollBackground(_ background: Color = MovieCutTheme.panelBackground) -> some View"#,
            #"scrollContentBackground(.hidden)"#,
            #"func movieCutInputField() -> some View"#,
            #"func movieCutInspectorSelectedCard() -> some View"#,
        ] {
            #expect(shared.contains(marker))
        }

        #expect(!shared.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(!shared.contains("Color(nsColor: .textBackgroundColor)"))
        #expect(!shared.contains("Color(nsColor: .separatorColor)"))
    }

    @Test("R6-01 content view forces dark editor shell")
    func contentViewForcesDarkEditorShell() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")

        #expect(content.contains(".background(MovieCutTheme.editorBackground.ignoresSafeArea())"))
        #expect(content.contains(".preferredColorScheme(.dark)"))
        #expect(content.contains(".tint(MovieCutTheme.accentCyan)"))
        #expect(content.contains(".background(MovieCutTheme.editorBackground)"))
        #expect(content.contains(".movieCutScrollBackground(MovieCutTheme.panelBackgroundRaised)"))
    }

    @Test("R6-01 left library uses compact dark tab cards and hidden scroll backgrounds")
    func leftLibraryUsesCompactDarkSurfaces() throws {
        let library = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        for marker in [
            #"GridItem(.flexible(minimum: 112), spacing: MovieCutSpacing.small)"#,
            #".fill(selectedLibraryTab == tab ? MovieCutTheme.selectedFill : MovieCutTheme.libraryRailButtonBackground)"#,
            #"selectedLibraryTab == tab ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText"#,
            #".fill(MovieCutTheme.libraryRailButtonBackground)"#,
            #"private var libraryContentWell: some View"#,
            #".fill(MovieCutTheme.libraryWellBackground)"#,
            #".movieCutScrollBackground(MovieCutTheme.libraryWellBackground)"#,
            #"private func libraryStaticThumbnailWell(systemImage: String, disabledReason: String?) -> some View"#,
            #"MovieCutTheme.libraryThumbnailBackground"#,
            #"MovieCutTheme.libraryCardBackground"#,
            #".frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)"#,
        ] {
            #expect(library.contains(marker))
        }
    }

    @Test("R6-01 right inspector uses dark compact cards and inputs")
    func rightInspectorUsesDarkCompactCardsAndInputs() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let basic = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let effects = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")
        let export = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(inspector.contains(".movieCutScrollBackground(viewModel.selectedClip == nil ? MovieCutTheme.panelBackground : MovieCutTheme.inspectorSelectedPanelBackground)"))
        #expect(inspector.contains("ProjectOverviewInspectorView(viewModel: viewModel)"))
        #expect(inspector.contains(".movieCutCard(background: MovieCutTheme.controlSurface)"))
        #expect(inspector.contains(".movieCutInspectorSelectedCard()"))
        #expect(inspector.contains("MovieCutTheme.inspectorSelectedControlSurface"))
        #expect(inspector.contains("MovieCutTheme.inspectorSelectedBorder"))
        #expect(inspector.contains(".tint(MovieCutTheme.accentCyan)"))
        #expect(inspector.contains(".movieCutInputField()"))
        #expect(basic.contains("VStack(alignment: .leading, spacing: MovieCutSpacing.small)"))
        #expect(basic.contains(".movieCutInputField()"))
        #expect(effects.contains("VStack(alignment: .leading, spacing: MovieCutSpacing.small)"))
        #expect(export.contains(".movieCutInputField()"))
    }

    @Test("R6-01 timeline uses dark ruler track rows and subtle grid")
    func timelineUsesDarkTrackRowsAndRuler() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for marker in [
            #".movieCutScrollBackground(MovieCutTheme.timelineBackground)"#,
            #".background(MovieCutTheme.timelineBackground)"#,
            #".fill(MovieCutTheme.rulerBackground)"#,
            #"private func timelineGridLines(height: CGFloat) -> some View"#,
            #"with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.64) : MovieCutTheme.timelineGrid.opacity(0.36))"#,
            #".background(MovieCutTheme.trackHeaderBackground)"#,
            #".fill(MovieCutTheme.trackBackground)"#,
            #"MovieCutTheme.timelineVideoClip"#,
            #"MovieCutTheme.timelineAudioClip"#,
            #"MovieCutTheme.timelineTextClip"#,
            #".fill(clipAccent.opacity(isSelected ? 0.86 : 0.52))"#,
            #"timelineGridLines(height: trackHeight)"#,
        ] {
            #expect(timeline.contains(marker))
        }
    }

    @Test("R6-01 preview stays black with compact import empty state")
    func previewStaysBlackWithCompactImportEmptyState() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")

        for marker in [
            #"MovieCutTheme.previewBackground"#,
            #"MovieCutTheme.previewWellBackground"#,
            #"MovieCutTheme.previewControlBackground"#,
            #"private func previewCanvasWell<Content: View>(@ViewBuilder content: () -> Content) -> some View"#,
            #".fill(MovieCutTheme.previewBackground)"#,
            #".padding(MovieCutSpacing.large + MovieCutSpacing.medium)"#,
            #"MovieCutTheme.inspectorSelectedControlSurface"#,
            #"MovieCutTheme.previewEmptyStateBackground"#,
            #"NSLocalizedString("Import media", comment: "")"#,
            #"NSLocalizedString("Import media, then drag it to the timeline.", comment: "")"#,
            #"openImportPanel()"#,
            #"Label(NSLocalizedString("Import Media", comment: ""), systemImage: "square.and.arrow.down")"#,
            #".controlSize(.regular)"#,
            #".frame(maxWidth: 300)"#,
            #"await viewModel.importMedia(urls)"#,
        ] {
            #expect(preview.contains(marker))
        }
    }

    @Test("R6-01 docs record loop three visual polish targets")
    func docsRecordLoopThreeVisualPolishTargets() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(docs.contains("Loop 3 targets measured populated-state gaps"))
        #expect(docs.contains("mean subregion similarity 0.6302"))
        #expect(docs.contains("left_browser sim 0.619"))
        #expect(docs.contains("right_inspector sim 0.561"))
        #expect(handoff.contains("Loop 3 note (2026-06-19)"))
        #expect(handoff.contains("medium-dark library card and thumbnail wells"))
        #expect(handoff.contains("near-black selected inspector cards"))
        #expect(!docs.contains("CapCut 98% visual parity loop 잔여"))
    }
}
