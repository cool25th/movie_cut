import Foundation
import Testing

/// Phase 1-4 lowers timeline track, grid, ruler, and unselected clip brightness
/// while preserving selection contrast and command-backed track header controls.
@Suite("Phase 1-4 Timeline Dark Fill StaticContract")
struct Phase14TimelineDarkFillStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase14TimelineDarkFillStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase14TimelineDarkFillStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Timeline theme tokens lower track ruler and grid brightness")
    func timelineThemeTokensLowerTrackRulerAndGridBrightness() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")

        for marker in [
            #"static let timelineBackground: Color = rgb(0x10, 0x11, 0x14)"#,
            #"static let rulerBackground: Color = rgb(0x17, 0x18, 0x1B)"#,
            #"static let trackBackground: Color = rgb(0x0E, 0x0F, 0x12)"#,
            #"static let trackHeaderBackground: Color = rgb(0x18, 0x19, 0x1C)"#,
            #"static let timelineGrid: Color = rgb(0x30, 0x32, 0x37, opacity: 0.24)"#,
        ] {
            #expect(shared.contains(marker))
        }

        #expect(!shared.contains(#"static let rulerBackground: Color = rgb(0x1C, 0x1D, 0x20)"#))
        #expect(!shared.contains(#"static let trackBackground: Color = rgb(0x14, 0x15, 0x18)"#))
        #expect(!shared.contains(#"static let trackHeaderBackground: Color = rgb(0x1B, 0x1C, 0x1F)"#))
        #expect(!shared.contains(#"static let timelineGrid: Color = rgb(0x38, 0x3A, 0x3F, opacity: 0.34)"#))
    }

    @Test("Ruler and grid lines use subtler timeline grid colors")
    func rulerAndGridLinesUseSubtlerTimelineGridColors() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let ruler = try section(
            in: timeline,
            from: "private var timeRuler: some View",
            to: "    private func timelineGridLines(height: CGFloat) -> some View"
        )
        let grid = try section(
            in: timeline,
            from: "private func timelineGridLines(height: CGFloat) -> some View",
            to: "    private func trackLane(_ track: Track) -> some View"
        )

        #expect(ruler.contains(#"with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.82) : MovieCutTheme.timelineGrid.opacity(0.48))"#))
        #expect(ruler.contains("lineWidth: isMajor ? 0.8 : 0.4"))
        #expect(!ruler.contains("isMajor ? MovieCutTheme.divider"))
        #expect(!ruler.contains("MovieCutTheme.divider : MovieCutTheme.timelineGrid"))

        #expect(grid.contains(#"with: .color(isMajor ? MovieCutTheme.timelineGrid.opacity(0.64) : MovieCutTheme.timelineGrid.opacity(0.36))"#))
        #expect(grid.contains("lineWidth: isMajor ? 0.5 : 0.35"))
        #expect(!grid.contains("MovieCutTheme.divider.opacity(0.44)"))
        #expect(!grid.contains("isMajor ? MovieCutTheme.divider"))
    }

    @Test("Unselected clips are dimmed while selected colors remain unchanged")
    func unselectedClipsAreDimmedWhileSelectedColorsRemainUnchanged() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let colors = try section(
            in: timeline,
            from: "private func colorForClip(clip: Clip, trackKind: TrackKind, selected: Bool) -> Color",
            to: "    private func clipLabel(_ clip: Clip) -> String"
        )

        #expect(colors.contains("return selected ? .pink : .pink.opacity(0.46)"))
        #expect(colors.contains("case .video: return selected ? .blue : .blue.opacity(0.42)"))
        #expect(colors.contains("case .audio: return selected ? .green : .green.opacity(0.42)"))
        #expect(colors.contains("case .text: return selected ? .orange : .orange.opacity(0.42)"))

        #expect(!colors.contains(".blue.opacity(0.6)"))
        #expect(!colors.contains(".green.opacity(0.6)"))
        #expect(!colors.contains(".orange.opacity(0.6)"))
        #expect(!colors.contains(".pink.opacity(0.68)"))
    }

    @Test("Selected clip stroke and track header commands remain visible")
    func selectedClipStrokeAndTrackHeaderCommandsRemainVisible() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let clip = try section(
            in: timeline,
            from: "private func clipView(_ clip: Clip, trackKind: TrackKind) -> some View",
            to: "    @ViewBuilder"
        )
        let lane = try section(
            in: timeline,
            from: "private func trackLane(_ track: Track) -> some View",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )
        let controls = try section(
            in: timeline,
            from: "private func trackHeaderControls(for track: Track) -> some View",
            to: "    @MainActor"
        )

        #expect(clip.contains(".stroke(Color.white.opacity(0.9), lineWidth: 1)"))
        #expect(lane.contains(".background(MovieCutTheme.trackHeaderBackground)"))
        #expect(lane.contains("trackHeaderControls(for: track)"))
        #expect(lane.contains(".accessibilityElement(children: .contain)"))
        #expect(controls.contains("Task { await viewModel.toggleTrackMute(track) }"))
        #expect(controls.contains("Task { await viewModel.toggleTrackHidden(track) }"))
        #expect(controls.contains("Task { await viewModel.toggleTrackLock(track) }"))
    }

    @Test("Phase 1-4 docs mark Phase 1 complete")
    func phase14DocsMarkPhase1Complete() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 1-4 implemented with darker timeline track/ruler tokens"))
        #expect(handoff.contains("subtler ruler/grid line drawing"))
        #expect(handoff.contains("lower unselected clip opacity"))
        #expect(handoff.contains("verified by `Phase14TimelineDarkFillStaticContractTests`"))
        #expect(handoff.contains("Phase 1 complete."))
        #expect(!handoff.contains("Phase 1-4 remains pending"))
    }
}

private enum Phase14TimelineDarkFillStaticContractError: Error {
    case missingMarker(String)
}
