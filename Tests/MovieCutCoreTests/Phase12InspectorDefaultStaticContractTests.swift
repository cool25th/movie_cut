import Foundation
import Testing

/// Phase 1-2 keeps export in the top-right toolbar and makes the no-selection
/// inspector a compact, read-only project overview.
@Suite("Phase 1-2 Inspector Default StaticContract")
struct Phase12InspectorDefaultStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase12InspectorDefaultStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase12InspectorDefaultStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Inspector no-selection branch uses project overview instead of export form")
    func inspectorNoSelectionBranchUsesProjectOverviewInsteadOfExportForm() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let body = try section(
            in: inspector,
            from: "var body: some View",
            to: "    /// R4-01"
        )

        #expect(body.contains("ProjectOverviewInspectorView(viewModel: viewModel)"))
        #expect(body.contains("DisclosureGroup(isExpanded: $projectToolsExpanded)"))
        #expect(body.contains("projectToolsSections(carded: false)"))
        #expect(body.contains(".movieCutInspectorOverviewGroup("))
        #expect(!body.contains("EmptyInspectorSelectionView()"))
        #expect(!body.contains("InspectorExportSection(viewModel: viewModel)"))
        #expect(!body.contains(".movieCutCard(padding: 0, background: MovieCutTheme.cardBackground)"))
    }

    @Test("Project overview contains compact groups and accessibility markers")
    func projectOverviewContainsCompactGroupsAndAccessibilityMarkers() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let overview = try section(
            in: inspector,
            from: "private struct ProjectOverviewInspectorView",
            to: "private struct MarkerManagementSection"
        )

        for marker in [
            "P1 inspector polish contract",
            "ProjectOverviewHeader(",
            "ProjectOverviewSummaryStrip(items:",
            "@State private var isExportSummaryExpanded = false",
            "DisclosureGroup(isExpanded: $isExportSummaryExpanded)",
            #"title: "Project""#,
            #"title: "Canvas""#,
            #"title: "Timeline""#,
            #"title: "Export Summary""#,
            #"Text("Select a clip")"#,
            "movieCutInspectorOverviewGroup",
            #"accessibilityLabel: "Project information""#,
            #"accessibilityLabel: "Canvas information""#,
            #"accessibilityLabel: "Timeline information""#,
            #".accessibilityLabel("Export summary")"#,
            #".accessibilityLabel("Select a clip")"#,
            #".accessibilityHint("Select a timeline clip to show clip-specific inspector controls.")"#,
            #"Use the top-right export control to export or choose formats."#
        ] {
            #expect(overview.contains(marker))
        }

        #expect(overview.contains("viewModel.projectDisplayName"))
        #expect(overview.contains("viewModel.projectSaveStatusLabel"))
        #expect(overview.contains("viewModel.currentProject.canvas.aspectRatio.displayName"))
        #expect(overview.contains("viewModel.currentProject.timeline.duration"))
        #expect(overview.contains("viewModel.canvasResolutionBadgeText"))
        #expect(overview.contains("viewModel.currentProject.exportSettings"))
    }

    @Test("Selected clip inspector and collapsed project tools are preserved")
    func selectedClipInspectorAndCollapsedProjectToolsArePreserved() throws {
        let inspector = try source("App/MovieCutMac/InspectorPanel.swift")
        let body = try section(
            in: inspector,
            from: "if let clip = viewModel.selectedClip",
            to: "} else {"
        )

        #expect(body.contains("SelectedClipHeaderView(clip: clip)"))
        #expect(body.contains(".movieCutInspectorSelectedHeader()"))
        #expect(body.contains("selectedClipInspectorSections(for: clip)"))
        #expect(body.contains("DisclosureGroup(isExpanded: $projectToolsExpanded)"))
        #expect(body.contains("projectToolsSections(carded: false)"))
        #expect(body.contains(#"title: "Project Tools""#))
    }

    @Test("Top-right toolbar remains the export surface")
    func topRightToolbarRemainsTheExportSurface() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let exportControl = try section(
            in: content,
            from: "private var exportToolbarControl: some View",
            to: "    private var toolbarCanvasPresets"
        )

        #expect(content.contains("exportToolbarControl"))
        #expect(exportControl.contains("ControlGroup"))
        #expect(exportControl.contains("Button(action: { Task { await viewModel.exportProject() } })"))
        #expect(exportControl.contains("Menu {"))
        #expect(exportControl.contains(#".accessibilityLabel("Export project")"#))
        #expect(exportControl.contains(".accessibilityHint(exportButtonHelpText)"))
        #expect(exportControl.contains(#".accessibilityLabel("Export formats")"#))
        #expect(exportControl.contains(#".accessibilityHint("Choose explicit-bitrate video, ProRes, audio-only, animated GIF, still frame, or share the latest export.")"#))
    }

    @Test("InspectorExportSection remains available for future reuse")
    func inspectorExportSectionRemainsAvailableForFutureReuse() throws {
        let export = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        for marker in [
            "struct InspectorExportSection: View",
            #"Section("Export Settings")"#,
            #"Picker("Format", selection: exportContainerFormatBinding)"#,
            #"Picker("Resolution", selection: exportResolutionBinding)"#,
            #"Picker("Frame Rate", selection: exportFrameRateBinding)"#,
            #"Picker("Video Codec", selection: exportCodecBinding)"#,
            #"Picker("Audio Codec", selection: exportAudioCodecBinding)"#,
            #"Picker("Quality", selection: exportQualityBinding)"#,
            "exportEstimateView",
            #"Text("Export Summary")"#,
            #".accessibilityLabel("Export summary")"#
        ] {
            #expect(export.contains(marker))
        }
    }

    @Test("Phase 1-2 docs remain marked implemented after later Phase 1 polish")
    func phase12DocsRemainMarkedImplementedAfterLaterPhaseOnePolish() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 1-2 implemented with a compact ProjectOverviewInspectorView"))
        #expect(handoff.contains("verified by `Phase12InspectorDefaultStaticContractTests`"))
        #expect(handoff.contains("Phase 1 complete."))
        #expect(!handoff.contains("Phase 1-2/1-3/1-4 remain pending"))
    }
}

private enum Phase12InspectorDefaultStaticContractError: Error {
    case missingMarker(String)
}
