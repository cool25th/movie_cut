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
            #"static let cardBackground: Color = rgb(0x1E, 0x1F, 0x22)"#,
            #"static let elevatedCardBackground: Color = rgb(0x22, 0x23, 0x26)"#,
            #"static let controlSurface: Color = rgb(0x24, 0x25, 0x28)"#,
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
        ] {
            #expect(shared.contains(marker))
        }
    }

    @Test("Phase 1-4 timeline track ruler and grid tokens remain unchanged")
    func phase14TimelineTrackRulerAndGridTokensRemainUnchanged() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for marker in [
            #"static let rulerBackground: Color = rgb(0x1C, 0x1D, 0x20)"#,
            #"static let trackBackground: Color = rgb(0x14, 0x15, 0x18)"#,
            #"static let timelineGrid: Color = rgb(0x38, 0x3A, 0x3F, opacity: 0.34)"#,
        ] {
            #expect(shared.contains(marker))
        }

        for marker in [
            #".fill(MovieCutTheme.rulerBackground)"#,
            #"with: .color(isMajor ? MovieCutTheme.divider.opacity(0.44) : MovieCutTheme.timelineGrid)"#,
            #".fill(MovieCutTheme.trackBackground)"#,
        ] {
            #expect(timeline.contains(marker))
        }
    }

    @Test("Phase 1-3 docs are marked implemented without advancing Phase 1-4")
    func phase13DocsAreMarkedImplementedWithoutAdvancingPhase14() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 1-3 implemented with darker near-flat shared card tokens"))
        #expect(handoff.contains("verified by `Phase13CardDensityStaticContractTests`"))
        #expect(handoff.contains("Phase 1-4 remains pending"))
        #expect(!handoff.contains("Phase 1-3/1-4 remain pending"))
    }
}
