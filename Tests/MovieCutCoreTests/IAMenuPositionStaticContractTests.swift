import Foundation
import Testing

/// Locks the CapCut-like IA/menu-position pass: top chrome owns project/view/export
/// controls, preview transport is bottom-docked, and edit commands live by the timeline.
@Suite("IA Menu Position StaticContract")
struct IAMenuPositionStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw IAMenuPositionStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw IAMenuPositionStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func assertContainsInOrder(_ source: String, _ markers: [String]) throws {
        var cursor = source.startIndex
        for marker in markers {
            guard let range = source.range(of: marker, range: cursor..<source.endIndex) else {
                throw IAMenuPositionStaticContractError.missingMarker(marker)
            }
            cursor = range.upperBound
        }
    }

    @Test("Top toolbar keeps project view export chrome and excludes timeline edits")
    func topToolbarKeepsProjectViewExportChromeAndExcludesTimelineEdits() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let toolbar = try section(
            in: content,
            from: ".toolbar {",
            to: "        .toolbarBackground(MovieCutTheme.panelBackgroundRaised, for: .windowToolbar)"
        )
        let undoRedoCluster = try section(
            in: toolbar,
            from: "ToolbarItemGroup(placement: .navigation)",
            to: "ToolbarItemGroup(placement: .primaryAction)"
        )
        let primaryCluster = try section(
            in: toolbar,
            from: "ToolbarItemGroup(placement: .primaryAction)",
            to: "            }\n        }"
        )

        #expect(toolbar.contains("Clip editing actions are timeline-local"))
        #expect(undoRedoCluster.contains("await viewModel.undo()"))
        #expect(undoRedoCluster.contains("await viewModel.redo()"))

        try assertContainsInOrder(primaryCluster, [
            #"Picker("Canvas", selection: $viewModel.canvasSelection)"#,
            "toolbarCanvasResolutionBadge",
            "CanvasSettingsView(",
            "isTemplatePickerPresented.toggle()",
            #"Button("Export Package…")"#,
            #"Button("Import Package…")"#,
            "await viewModel.syncToCloud()",
            "exportToolbarControl"
        ])

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

    @Test("Timeline toolbar is the edit command center with labeled clusters")
    func timelineToolbarIsTheEditCommandCenterWithLabeledClusters() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let selectedToolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )
        let markerControls = try section(
            in: timeline,
            from: "private var timelineMarkerControls: some View",
            to: "    private var selectedClipSupportsVisualTimelineEffect"
        )
        let zoomControls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        for marker in [
            "private func timelineToolbarGroupLabel(title: String, systemImage: String) -> some View",
            "private func timelineToolbarCluster<Content: View>(",
            #"title: "Edit""#,
            #"title: "Quick Tools""#,
            #"title: "Markers""#,
            #"title: "Zoom""#,
            #"accessibilityLabel: "Timeline quick tools""#,
        ] {
            #expect(timeline.contains(marker))
        }

        for marker in [
            "Task { await viewModel.splitClip() }",
            "Task { await viewModel.deleteClip() }",
            "Task { await viewModel.rippleDeleteSelectedClip() }",
            "Task { await viewModel.duplicateSelectedClips() }",
            "viewModel.snapPlayheadToSelectedClipStart()",
            "viewModel.snapPlayheadToSelectedClipEnd()",
            "Task { await viewModel.freezeSelectedFrame() }",
            "await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)",
            #"accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))"#
        ] {
            #expect(selectedToolbar.contains(marker))
        }

        try assertContainsInOrder(markerControls, [
            #"title: "Previous Marker""#,
            "viewModel.goToPreviousMarker()",
            #"title: "Add Marker at Playhead""#,
            "viewModel.addMarkerAtPlayhead()",
            #"title: "Next Marker""#,
            "viewModel.goToNextMarker()"
        ])

        #expect(zoomControls.contains("Slider(value: Binding("))
        #expect(zoomControls.contains("Text(timelineZoomDisplay)"))
        #expect(zoomControls.contains("fitTimelineToAvailableWidth(timelineViewportWidth)"))
    }

    @Test("Preview transport is bottom docked and canvas reserves bottom space")
    func previewTransportIsBottomDockedAndCanvasReservesBottomSpace() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let body = try section(
            in: preview,
            from: "var body: some View",
            to: "    private func previewCanvasWell"
        )
        let canvasWell = try section(
            in: preview,
            from: "private func previewCanvasWell<Content: View>",
            to: "    private var previewTransportBar"
        )
        let transport = try section(
            in: preview,
            from: "private var previewTransportBar: some View",
            to: "    private var playbackTransportCapsule"
        )

        #expect(body.contains("preview transport is bottom-docked"))
        try assertContainsInOrder(body, [
            "VStack {",
            "Spacer(minLength: 0)",
            "previewTransportBar"
        ])
        #expect(canvasWell.contains(".padding(.top, 16)"))
        #expect(canvasWell.contains(".padding(.bottom, 64)"))
        #expect(transport.contains(".padding(.bottom, 8)"))
        #expect(!transport.contains(".padding(.top, 8)"))
    }

    @Test("Docs record the IA menu position pass")
    func docsRecordTheIAMenuPositionPass() throws {
        for path in [
            "docs/UIUX_HANDOFF.md",
            "docs/CAPCUT_UI_PARITY_REQUIREMENTS.md",
            "docs/CAPCUT_UI_SHOWCASE_HANDOFF.md"
        ] {
            let docs = try source(path)
            #expect(docs.contains("IA/menu-position pass (2026-06-19)"))
            #expect(docs.contains("top toolbar no longer owns clip editing"))
            #expect(docs.contains("preview transport is bottom-docked"))
            #expect(docs.contains("timeline is the edit command center"))
        }
    }
}

private enum IAMenuPositionStaticContractError: Error {
    case missingMarker(String)
}
