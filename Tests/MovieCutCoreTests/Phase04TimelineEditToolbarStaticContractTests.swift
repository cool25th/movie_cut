import Foundation
import Testing

/// Phase 0-4 keeps the timeline toolbar edit-only after Smart/AI tools move
/// into the left library Smart tab.
@Suite("Phase 0-4 Timeline Edit Toolbar StaticContract")
struct Phase04TimelineEditToolbarStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase04TimelineEditToolbarStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase04TimelineEditToolbarStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Timeline header no longer uses QuickToolsPanel")
    func timelineHeaderNoLongerUsesQuickToolsPanel() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let header = try section(
            in: timeline,
            from: "HStack(spacing: MovieCutSpacing.small) {",
            to: "            }\n            .padding(.horizontal, MovieCutSpacing.medium)"
        )

        #expect(header.contains("selectedClipToolbar"))
        #expect(header.contains("timelineMarkerControls"))
        #expect(header.contains("zoomControls"))
        #expect(!header.contains("QuickToolsPanel(viewModel: viewModel)"))
        #expect(!timeline.contains("QuickToolsPanel(viewModel: viewModel)"))
    }

    @Test("TimelineView does not call AI Smart tool actions")
    func timelineViewDoesNotCallAISmartToolActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for forbidden in [
            "runAutoCutOnSelection",
            "detectSceneChangesForSelection",
            "detectBeats",
            "autoReframeSelection",
            "applyNoiseReductionToSelection",
            "extractAudioFromSelection",
            "Auto Cut",
            "Detect Scenes",
            "Detect Beats",
            "Clear Beats",
            "Auto Reframe",
            "Noise Reduce",
            "Extract Audio"
        ] {
            #expect(!timeline.contains(forbidden))
        }
    }

    @Test("Edit toolbar exposes only requested edit actions")
    func editToolbarExposesOnlyRequestedEditActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )

        for marker in [
            "await viewModel.splitClip()",
            "await viewModel.deleteClip()",
            "await viewModel.rippleDeleteSelectedClip()",
            "await viewModel.duplicateSelectedClips()",
            "viewModel.snapPlayheadToSelectedClipStart()",
            "viewModel.snapPlayheadToSelectedClipEnd()",
            "await viewModel.freezeSelectedFrame()",
            "await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)",
            #".help("Split at Playhead")"#,
            #".help("Delete Selected Clips")"#,
            #".help("Ripple Delete Selected Clip")"#,
            #".help("Duplicate Selected Clips")"#,
            #".help("Snap Playhead to Clip Start")"#,
            #".help("Snap Playhead to Clip End")"#,
            #".help("Freeze Selected Frame")"#,
            #".help("Reverse Selected Clip")"#,
            #"accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))"#
        ] {
            #expect(toolbar.contains(marker))
        }

        for forbidden in [
            "sendSelectedClipLayerToBack()",
            "bringSelectedClipLayerToFront()",
            #"Text(NSLocalizedString("Edit", comment: ""))"#,
            "QuickToolsPanel"
        ] {
            #expect(!toolbar.contains(forbidden))
        }
    }

    @Test("Marker controls live in TimelineView and call existing ViewModel methods")
    func markerControlsLiveInTimelineView() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let controls = try section(
            in: timeline,
            from: "private var timelineMarkerControls: some View",
            to: "    private var selectedClipSupportsVisualTimelineEffect"
        )

        for marker in [
            "viewModel.goToPreviousMarker()",
            "viewModel.addMarkerAtPlayhead()",
            "viewModel.goToNextMarker()",
            "viewModel.previousMarker == nil",
            "viewModel.nextMarker == nil",
            #".help("Previous Marker")"#,
            #".help("Add Marker at Playhead")"#,
            #".help("Next Marker")"#,
            #"accessibilityLabel(NSLocalizedString("Previous Marker", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Add Marker at Playhead", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Next Marker", comment: ""))"#,
            #"accessibilityLabel(NSLocalizedString("Timeline marker controls", comment: ""))"#
        ] {
            #expect(controls.contains(marker))
        }
    }

    @Test("Zoom controls remain in the toolbar with icon buttons and fit")
    func zoomControlsRemainInToolbar() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let zoom = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        for marker in [
            "viewModel.zoomTimelineOut()",
            "viewModel.zoomTimelineIn()",
            "Slider(value:",
            "Text(timelineZoomDisplay)",
            "fitTimelineToAvailableWidth(timelineViewportWidth)",
            #".help("Zoom Timeline Out")"#,
            #".help("Zoom Timeline In")"#,
            #".help("Fit Timeline")"#,
            #"accessibilityLabel(NSLocalizedString("Timeline zoom controls", comment: ""))"#
        ] {
            #expect(zoom.contains(marker))
        }

        #expect(!zoom.contains(#"Text(NSLocalizedString("Zoom", comment: ""))"#))
    }

    @Test("Smart library cards remain in MediaLibraryPanel")
    func smartLibraryCardsRemainInMediaLibraryPanel() throws {
        let mediaLibrary = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let smartTool = try section(
            in: mediaLibrary,
            from: "private enum SmartLibraryTool",
            to: "private enum LibraryHoverPreviewKind"
        )
        let performer = try section(
            in: mediaLibrary,
            from: "private func performSmartTool(_ tool: SmartLibraryTool) async",
            to: "    @ViewBuilder\n    private var transitionsTabContent"
        )

        for marker in [
            "case autoCut",
            "case sceneDetect",
            "case beatDetect",
            "case reframe",
            "case noiseReduction",
            "case extractAudio",
            #"NSLocalizedString("Auto Cut", comment: "")"#,
            #"NSLocalizedString("Detect Scenes", comment: "")"#,
            #"NSLocalizedString("Detect Beats", comment: "")"#,
            #"NSLocalizedString("Auto Reframe", comment: "")"#,
            #"NSLocalizedString("Noise Reduce", comment: "")"#,
            #"NSLocalizedString("Extract Audio", comment: "")"#
        ] {
            #expect(smartTool.contains(marker))
        }

        for marker in [
            "await viewModel.runAutoCutOnSelection()",
            "await viewModel.detectSceneChangesForSelection()",
            "await viewModel.detectBeats()",
            "await viewModel.autoReframeSelection()",
            "await viewModel.applyNoiseReductionToSelection()",
            "await viewModel.extractAudioFromSelection()"
        ] {
            #expect(performer.contains(marker))
        }
    }

    @Test("Handoff marks Phase 0-4 implemented and Phase 0 complete")
    func handoffMarksPhase04ImplementedAndPhase0Complete() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 0-4 implemented"))
        #expect(handoff.contains("edit-only timeline toolbar"))
        #expect(handoff.contains("Phase 0 complete"))
        #expect(handoff.contains("Phase04TimelineEditToolbarStaticContractTests"))
        #expect(!handoff.contains("Phase 0-4 remains pending"))
    }
}

private enum Phase04TimelineEditToolbarStaticContractError: Error {
    case missingMarker(String)
}
