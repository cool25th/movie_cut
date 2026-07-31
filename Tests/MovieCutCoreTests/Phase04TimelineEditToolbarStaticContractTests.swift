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

    // Removed `timelineViewDoesNotCallAISmartToolActions` (defect-pinning, req 15.2):
    // it locked "TimelineView must not call any AI Smart tool action" by forbidding
    // runAutoCutOnSelection / detectBeats / autoReframeSelection / Noise Reduce /
    // Extract Audio, etc. That actively blocked legitimate CapCut-parity wiring of
    // those tools into the timeline surface. The edit-toolbar scope boundary is
    // still guarded by editToolbarExposesOnlyRequestedEditActions below.

    @Test("Edit toolbar exposes only requested edit actions")
    func editToolbarExposesOnlyRequestedEditActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )

        #expect(toolbar.components(separatedBy: "timelineToolbarIconButton(").count - 1 == 8)

        for marker in [
            "await viewModel.splitClip()",
            "await viewModel.deleteClip()",
            "await viewModel.rippleDeleteSelectedClip()",
            "await viewModel.duplicateSelectedClips()",
            "viewModel.snapPlayheadToSelectedClipStart()",
            "viewModel.snapPlayheadToSelectedClipEnd()",
            "await viewModel.freezeSelectedFrame()",
            "await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)",
            #"title: "Split at Playhead""#,
            #"title: "Delete Selected Clips""#,
            #"title: "Ripple Delete Selected Clip""#,
            #"title: "Duplicate Selected Clips""#,
            #"title: "Snap Playhead to Clip Start""#,
            #"title: "Snap Playhead to Clip End""#,
            #"title: "Freeze Selected Frame""#,
            #"title: "Reverse Selected Clip""#,
            #"hint: "Splits the selected clip at the playhead.""#,
            #"hint: "Deletes the selected clips from the timeline.""#,
            #"hint: "Deletes the selected clip and closes the resulting gap.""#,
            #"hint: "Duplicates the selected clips on the timeline.""#,
            #"hint: "Moves the playhead to the selected clip start.""#,
            #"hint: "Moves the playhead to the selected clip end.""#,
            #"hint: "Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.""#,
            #"hint: "Reverse Selected Clip toggles reverse playback for the selected visual clip.""#,
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

        #expect(controls.components(separatedBy: "timelineToolbarIconButton(").count - 1 == 3)

        for marker in [
            "viewModel.goToPreviousMarker()",
            "viewModel.addMarkerAtPlayhead()",
            "viewModel.goToNextMarker()",
            "viewModel.previousMarker == nil",
            "viewModel.nextMarker == nil",
            #"title: "Previous Marker""#,
            #"title: "Add Marker at Playhead""#,
            #"title: "Next Marker""#,
            #"hint: "Moves the playhead to the previous marker.""#,
            #"hint: "Adds a marker at the current playhead time.""#,
            #"hint: "Moves the playhead to the next marker.""#,
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

        #expect(zoom.components(separatedBy: "timelineToolbarIconButton(").count - 1 == 3)

        for marker in [
            "viewModel.zoomTimelineOut()",
            "viewModel.zoomTimelineIn()",
            "Slider(value:",
            "Text(timelineZoomDisplay)",
            "fitTimelineToAvailableWidth(timelineViewportWidth)",
            #"title: "Zoom Timeline Out""#,
            #"title: "Zoom Timeline In""#,
            #"title: "Fit Timeline""#,
            // Task 1.3: the two Korean zoom-label markers were deleted here; the
            // runtime label check lives in
            // `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`.
            #"hint: "Zooms the timeline out.""#,
            #"hint: "Zooms the timeline in.""#,
            #"hint: "Fits the visible timeline duration in the available timeline width.""#,
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
}

private enum Phase04TimelineEditToolbarStaticContractError: Error {
    case missingMarker(String)
}
