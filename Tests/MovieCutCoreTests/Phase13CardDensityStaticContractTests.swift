import Foundation
import Testing

/// Phase 1-3 raises dark_fill around the inspector and timeline chrome by
/// flattening elevated cards and making borders/dividers less visually dense.
@Suite("Phase 1-3 Card Density StaticContract")
struct Phase13CardDensityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("Shared inspector tokens flatten cards and reduce border density")
    func sharedInspectorTokensFlattenCardsAndReduceBorderDensity() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            #"static let panelBackgroundRaised: Color = rgb(0x1B, 0x1C, 0x1F)"#,
            #"static let cardBackground: Color = rgb(0x18, 0x19, 0x1B)"#,
            #"static let elevatedCardBackground: Color = rgb(0x1B, 0x1C, 0x1E)"#,
            #"static let controlSurface: Color = rgb(0x1A, 0x1B, 0x1D)"#,
            #"static let inspectorSelectedPanelBackground: Color = rgb(0x21, 0x22, 0x25)"#,
            #"static let inspectorSelectedCardBackground: Color = rgb(0x22, 0x23, 0x26)"#,
            #"static let inspectorSelectedRowBackground: Color = rgb(0x26, 0x27, 0x2A)"#,
            #"static let inspectorSelectedControlSurface: Color = rgb(0x2A, 0x2C, 0x30)"#,
            #"static let inspectorSelectedBorder: Color = rgb(0x46, 0x49, 0x50, opacity: 0.10)"#,
            #"static let divider: Color = rgb(0x35, 0x36, 0x3A, opacity: 0.46)"#,
            #"static let border: Color = rgb(0x3D, 0x40, 0x46, opacity: 0.34)"#,
        ] {
            #expect(shared.contains(marker))
        }

        #expect(!shared.contains(#"static let cardBackground: Color = rgb(0x24, 0x25, 0x28)"#))
        #expect(!shared.contains(#"static let elevatedCardBackground: Color = rgb(0x2F, 0x30, 0x34)"#))
        #expect(!shared.contains(#"static let divider: Color = rgb(0x3A, 0x3B, 0x3F, opacity: 0.72)"#))
        #expect(!shared.contains(#"static let border: Color = rgb(0x48, 0x4B, 0x52, opacity: 0.62)"#))
    }

    @Test("MovieCut card modifier keeps semantic defaults with subtler border")
    func movieCutCardModifierKeepsSemanticDefaultsWithSubtlerBorder() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            #"func movieCutCard("#,
            #"background: Color = MovieCutTheme.cardBackground"#,
            #"border: Color = MovieCutTheme.border"#,
            #".stroke(border, lineWidth: 0.5)"#,
            #"func movieCutInspectorSelectedCard() -> some View"#,
            #"background: MovieCutTheme.inspectorSelectedCardBackground"#,
            #"border: MovieCutTheme.inspectorSelectedBorder"#,
            #"func movieCutInspectorSelectedFlatRow() -> some View"#,
            #"background: MovieCutTheme.inspectorSelectedRowBackground"#,
            #"border: MovieCutTheme.inspectorSelectedBorder.opacity(0.35)"#,
        ] {
            #expect(shared.contains(marker))
        }
    }

    @Test("Phase 1-4 darkens timeline tokens after Phase 1-3 card density")
    func phase14DarkensTimelineTokensAfterPhase13CardDensity() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for marker in [
            #"static let rulerBackground: Color = rgb(0x24, 0x26, 0x2B)"#,
            #"static let trackBackground: Color = rgb(0x1A, 0x1C, 0x20)"#,
            #"static let trackHeaderBackground: Color = rgb(0x2A, 0x2D, 0x32)"#,
            #"static let timelineGrid: Color = rgb(0x30, 0x32, 0x37, opacity: 0.24)"#,
        ] {
            #expect(shared.contains(marker))
        }

        for marker in [
            #".fill(MovieCutTheme.rulerBackground)"#,
            #"with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.64) : MovieCutTheme.timelineGrid.opacity(0.36))"#,
            #".fill(MovieCutTheme.trackBackground)"#,
        ] {
            #expect(timeline.contains(marker))
        }
    }

    @Test("Phase 1-3 docs remain marked implemented after Phase 1-4")
    func phase13DocsRemainMarkedImplementedAfterPhase14() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 1-3 implemented with darker near-flat shared card tokens"))
        #expect(handoff.contains("verified by `Phase13CardDensityStaticContractTests`"))
        #expect(handoff.contains("Phase 1-4 implemented with darker timeline track/ruler tokens"))
        #expect(handoff.contains("Phase 1 complete."))
        #expect(!handoff.contains("Phase 1-3/1-4 remain pending"))
    }
}
