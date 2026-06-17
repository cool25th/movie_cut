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
            #"static let cardBackground: Color = rgb(0x24, 0x25, 0x28)"#,
            #"static let elevatedCardBackground: Color = rgb(0x2F, 0x30, 0x34)"#,
            #"static let controlSurface: Color = rgb(0x28, 0x2A, 0x2D)"#,
            #"static let previewBackground: Color = rgb(0x03, 0x03, 0x04)"#,
            #"static let timelineBackground: Color = rgb(0x10, 0x11, 0x14)"#,
            #"static let trackBackground: Color = rgb(0x14, 0x15, 0x18)"#,
            #"static let accentCyan: Color = rgb(0x36, 0xD7, 0xFF)"#,
            #"static let selectedFill: Color = accentCyan.opacity(0.22)"#,
            #"func movieCutScrollBackground(_ background: Color = MovieCutTheme.panelBackground) -> some View"#,
            #"scrollContentBackground(.hidden)"#,
            #"func movieCutInputField() -> some View"#,
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
            #".fill(selectedLibraryTab == tab ? MovieCutTheme.selectedFill : MovieCutTheme.controlSurface)"#,
            #"selectedLibraryTab == tab ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText"#,
            #".fill(MovieCutTheme.controlSurface)"#,
            #".movieCutScrollBackground(MovieCutTheme.panelBackground)"#,
            #".movieCutCard(background: MovieCutTheme.elevatedCardBackground)"#,
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

        #expect(inspector.contains(".movieCutScrollBackground(MovieCutTheme.panelBackground)"))
        #expect(inspector.contains(".movieCutCard(padding: 0, background: MovieCutTheme.cardBackground)"))
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
            #"with: .color(isMajor ? MovieCutTheme.divider.opacity(0.44) : MovieCutTheme.timelineGrid)"#,
            #".background(MovieCutTheme.trackHeaderBackground)"#,
            #".fill(MovieCutTheme.trackBackground)"#,
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
            #"MovieCutTheme.controlSurface.opacity(0.90)"#,
            #"MovieCutTheme.previewEmptyStateBackground"#,
            #"NSLocalizedString("Import media", comment: "")"#,
            #"NSLocalizedString("Import media, then drag it to the timeline.", comment: "")"#,
            #"openImportPanel()"#,
            #"Label(NSLocalizedString("Import Media", comment: ""), systemImage: "square.and.arrow.down")"#,
            #".controlSize(.regular)"#,
            #".frame(maxWidth: 280)"#,
            #"await viewModel.importMedia(urls)"#,
        ] {
            #expect(preview.contains(marker))
        }
    }

    @Test("R6-01 docs record loop one as partial visual polish")
    func docsRecordLoopOneAsPartialVisualPolish() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")

        #expect(docs.contains("Loop 1 dark-shell polish implemented; quantitative side-by-side still pending/looping."))
        #expect(docs.contains("partial visual-polish implementation"))
        #expect(!docs.contains("CapCut 98% visual parity loop 잔여"))
    }
}
