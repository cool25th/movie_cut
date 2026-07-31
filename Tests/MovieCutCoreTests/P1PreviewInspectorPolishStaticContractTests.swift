import Foundation
import Testing

/// P1 preview + inspector hierarchy polish is presentation-layer only:
/// compact bottom transport, quieter preview empty state, compact no-selection
/// inspector, and clearer selected clip hierarchy.
@Suite("P1 Preview Inspector Polish StaticContract")
struct P1PreviewInspectorPolishStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw P1PreviewInspectorPolishStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw P1PreviewInspectorPolishStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Preview keeps bottom-docked transport while compacting chrome and empty CTA")
    func previewKeepsBottomDockedTransportWhileCompactingChromeAndEmptyCTA() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let body = try section(
            in: preview,
            from: "var body: some View",
            to: "    private func previewCanvasWell"
        )
        let transport = try section(
            in: preview,
            from: "private var previewTransportBar: some View",
            to: "    private var playbackTransportCapsule"
        )
        let emptyState = try section(
            in: preview,
            from: "private var previewEmptyState: some View",
            to: "    private func previewTimeBadge"
        )

        #expect(body.contains("preview transport is bottom-docked"))
        #expect(body.contains("P1 preview polish contract"))
        #expect(body.contains("previewTransportBar"))
        #expect(preview.contains("PreviewLoop4WellTexture(intensity: 0.28)"))
        #expect(preview.contains(".padding(.bottom, 64)"))
        #expect(transport.contains("ViewThatFits(in: .horizontal)"))
        #expect(transport.contains(".padding(.vertical, 4)"))
        #expect(transport.contains(".padding(.bottom, 8)"))
        #expect(transport.contains("previewCanvasResolutionBadge"))
        #expect(transport.contains("previewSafeZoneToggle"))
        #expect(transport.contains("previewZoomControls"))
        #expect(transport.contains("previewVolumeControl"))
        #expect(emptyState.contains(".buttonStyle(.bordered)"))
        #expect(emptyState.contains(".controlSize(.small)"))
        #expect(emptyState.contains(".frame(maxWidth: 250)"))
        #expect(emptyState.contains("openImportPanel()"))
        #expect(!emptyState.contains(".buttonStyle(.borderedProminent)"))
    }

    @Test("Inspector no-selection hierarchy is compact and export summary is collapsed")
    func inspectorNoSelectionHierarchyIsCompactAndExportSummaryIsCollapsed() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let overview = try section(
            in: inspector,
            from: "private struct ProjectOverviewInspectorView",
            to: "private struct MarkerManagementSection"
        )

        #expect(overview.contains("P1 inspector polish contract"))
        #expect(overview.contains("ProjectOverviewHeader("))
        #expect(overview.contains("ProjectOverviewSummaryStrip(items:"))
        #expect(overview.contains("@State private var isExportSummaryExpanded = false"))
        #expect(overview.contains("DisclosureGroup(isExpanded: $isExportSummaryExpanded)"))
        #expect(overview.contains(#"title: "Export Summary""#))
        #expect(overview.contains(#".accessibilityLabel("Export summary")"#))
        #expect(overview.contains("ProjectOverviewRow(title: \"Output\""))
        #expect(overview.contains("ProjectOverviewRow(title: \"Format\""))
        #expect(overview.contains("ProjectOverviewRow(title: \"Video\""))
        #expect(overview.contains("ProjectOverviewRow(title: \"Audio\""))
        #expect(inspector.contains("projectToolsSections(carded: false)"))
        #expect(!inspector.contains("projectToolsSections(carded: true)"))
    }

    @Test("Selected video text and audio inspector states keep clear hierarchy")
    func selectedVideoTextAndAudioInspectorStatesKeepClearHierarchy() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let basic = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let effects = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")

        #expect(inspector.contains("SelectedClipHeaderView(clip: clip)"))
        #expect(inspector.contains("private struct SelectedClipHeaderView: View"))
        #expect(inspector.contains(".movieCutInspectorSelectedHeader()"))
        #expect(inspector.contains("case .audio:"))
        #expect(inspector.contains("mode: InspectorBasicMode.audio"))
        #expect(inspector.contains("case .text:"))
        #expect(inspector.contains("mode: InspectorBasicMode.text"))
        #expect(inspector.contains("case .video, .image:"))
        #expect(inspector.contains("Picker(\"Inspector section\", selection: $selectedInspectorSubtab)"))
        #expect(inspector.contains(".pickerStyle(.segmented)"))
        #expect(inspector.contains(".tint(MovieCutTheme.accentCyan)"))
        #expect(shared.contains("func movieCutInspectorSelectedHeader() -> some View"))
        #expect(shared.contains("func movieCutInspectorOverviewGroup("))
        #expect(shared.contains("MovieCutTheme.inspectorSelectedRowBackground.opacity(0.74)"))
        #expect(shared.contains("MovieCutTheme.inspectorSelectedBorder.opacity(0.18)"))
        #expect(basic.contains("MovieCutTheme.inspectorSelectedControlSurface.opacity(0.58)"))
        #expect(effects.contains(".monospacedDigit()"))
    }
}

private enum P1PreviewInspectorPolishStaticContractError: Error {
    case missingMarker(String)
}
