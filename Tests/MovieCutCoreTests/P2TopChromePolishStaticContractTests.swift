import Foundation
import Testing

/// P2 top chrome polish is presentation-layer only: compact secondary project
/// and canvas controls, quieter central project status, and primary Export.
@Suite("P2 Top Chrome Polish StaticContract")
struct P2TopChromePolishStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw P2TopChromePolishStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw P2TopChromePolishStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func assertContainsInOrder(_ source: String, _ markers: [String]) throws {
        var cursor = source.startIndex
        for marker in markers {
            guard let range = source.range(of: marker, range: cursor..<source.endIndex) else {
                throw P2TopChromePolishStaticContractError.missingMarker(marker)
            }
            cursor = range.upperBound
        }
    }

    @Test("Toolbar records P2 marker and groups secondary chrome")
    func toolbarRecordsP2MarkerAndGroupsSecondaryChrome() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let toolbar = try section(
            in: content,
            from: ".toolbar {",
            to: "        .toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)"
        )
        let compactHelper = try section(
            in: content,
            from: "private func topChromeCompactCluster<Content: View>",
            to: "    private var toolbarCanvasPresets"
        )
        let secondaryStyle = try section(
            in: content,
            from: "private extension View",
            to: "struct QuickToolsPanel"
        )

        #expect(toolbar.contains("P2 top chrome polish contract"))
        #expect(toolbar.components(separatedBy: "topChromeCompactCluster(accessibilityLabel:").count - 1 == 2)
        try assertContainsInOrder(toolbar, [
            #"topChromeCompactCluster(accessibilityLabel: "Canvas view controls")"#,
            #"Picker("Canvas", selection: $viewModel.canvasSelection)"#,
            "toolbarCanvasResolutionBadge",
            "Button(action: { isCanvasSettingsPresented.toggle() })",
            #"topChromeCompactCluster(accessibilityLabel: "Project helper controls")"#,
            "isTemplatePickerPresented.toggle()",
            #"Button("Export Package…")"#,
            #"Button("Import Package…")"#,
            "exportToolbarControl"
        ])
        #expect(compactHelper.contains("HStack(spacing: MovieCutSpacing.xxSmall)"))
        #expect(compactHelper.contains("MovieCutTheme.controlSurface.opacity(0.18)"))
        #expect(compactHelper.contains(".accessibilityElement(children: .contain)"))
        #expect(!compactHelper.contains(".stroke("))
        #expect(secondaryStyle.contains("func topChromeSecondaryToolbarStyle() -> some View"))
        #expect(secondaryStyle.contains("labelStyle(.iconOnly)"))
        #expect(secondaryStyle.contains(".buttonStyle(.borderless)"))
        #expect(secondaryStyle.contains(".controlSize(.small)"))
        #expect(secondaryStyle.contains(".foregroundStyle(.secondary)"))
        #expect(!toolbar.contains("Divider()"))
    }

    @Test("Project status and canvas badge are quieter context chrome")
    func projectStatusAndCanvasBadgeAreQuieterContextChrome() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let projectStatus = try section(
            in: content,
            from: "private var projectStatusToolbarItem: some View",
            to: "    private var toolbarCanvasResolutionBadge"
        )
        let badge = try section(
            in: content,
            from: "private var toolbarCanvasResolutionBadge: some View",
            to: "    private var exportToolbarControl"
        )

        #expect(projectStatus.contains("HStack(spacing: MovieCutSpacing.xSmall)"))
        #expect(projectStatus.contains(".font(.subheadline.weight(.semibold))"))
        #expect(projectStatus.contains(".font(.caption2.weight(.medium))"))
        #expect(projectStatus.contains(".foregroundStyle(MovieCutTheme.mutedText)"))
        #expect(badge.contains("Label {"))
        #expect(badge.contains("Text(viewModel.canvasResolutionBadgeText)"))
        #expect(badge.contains(#"Image(systemName: "rectangle.ratio")"#))
        #expect(badge.contains(".font(.caption2.weight(.medium))"))
        #expect(badge.contains("MovieCutTheme.controlSurface.opacity(0.32)"))
        #expect(!badge.contains(".stroke(MovieCutTheme.border, lineWidth: 0.5)"))
    }

    @Test("Export stays distinct and primary")
    func exportStaysDistinctAndPrimary() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let exportControl = try section(
            in: content,
            from: "private var exportToolbarControl: some View",
            to: "    private func topChromeCompactCluster"
        )

        #expect(exportControl.contains("ControlGroup"))
        #expect(exportControl.contains(#"Label("Export", systemImage: "square.and.arrow.up")"#))
        #expect(exportControl.contains(".buttonStyle(.borderedProminent)"))
        #expect(exportControl.contains(".tint(MovieCutTheme.accentCyan)"))
        #expect(exportControl.contains("Menu {"))
        #expect(exportControl.contains(".accessibilityLabel(\"Export project\")"))
        #expect(exportControl.contains(".accessibilityValue(exportButtonAccessibilityValue)"))
        #expect(exportControl.contains(".accessibilityHint(exportButtonHelpText)"))
        #expect(exportControl.contains(".accessibilityLabel(\"Export formats\")"))
        #expect(exportControl.contains(".disabled(viewModel.exportEngine.isExporting)"))
    }

    @Test("Top toolbar still excludes timeline edit commands")
    func topToolbarStillExcludesTimelineEditCommands() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let toolbar = try section(
            in: content,
            from: ".toolbar {",
            to: "        .toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)"
        )

        for forbiddenTopToolbarEdit in [
            "await viewModel.splitClip()",
            "viewModel.addMarkerAtPlayhead()",
            "await viewModel.deleteClip()",
            #"Label("Split", systemImage: "scissors")"#,
            #"Label("Add Marker", systemImage: "flag.fill")"#,
            #"Label("Delete", systemImage: "trash")"#
        ] {
            #expect(!toolbar.contains(forbiddenTopToolbarEdit))
        }
    }

    @Test("Toolbar accessibility labels and hints are preserved")
    func toolbarAccessibilityLabelsAndHintsArePreserved() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")

        for marker in [
            #"accessibilityLabel(NSLocalizedString("Project save status", comment: ""))"#,
            #"accessibilityValue("\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel)")"#,
            #"accessibilityHint(NSLocalizedString("Shows the current project name and save or autosave status.", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Canvas and export resolution", comment: ""))"#,
            "accessibilityValue(viewModel.canvasResolutionBadgeText)",
            #"accessibilityHint(NSLocalizedString("Shows the current canvas aspect ratio and computed export render size.", comment: ""))"#,
            #".accessibilityLabel("Export project")"#,
            ".accessibilityValue(exportButtonAccessibilityValue)",
            ".accessibilityHint(exportButtonHelpText)",
            #".accessibilityLabel("Export formats")"#,
            #".accessibilityHint("Choose explicit-bitrate video, ProRes, audio-only, animated GIF, still frame, or share the latest export.")"#,
            #".accessibilityLabel("Templates")"#,
            #".accessibilityHint("Open template picker.")"#,
            #".accessibilityLabel("Package")"#,
            #".accessibilityHint("Export or import a self-contained .mctemplate project package.")"#
        ] {
            #expect(content.contains(marker))
        }
    }
}

private enum P2TopChromePolishStaticContractError: Error {
    case missingMarker(String)
}
