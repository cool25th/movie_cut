import Foundation
import Testing

/// Phase 2-3 keeps the timeline toolbar compact and icon-only while preserving
/// the edit, marker, zoom, tooltip, and accessibility contracts.
@Suite("Phase 2-3 Timeline Toolbar Icon Only StaticContract")
struct Phase23TimelineToolbarIconOnlyStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase23TimelineToolbarIconOnlyStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase23TimelineToolbarIconOnlyStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    @Test("Timeline toolbar helper defines compact localized icon button treatment")
    func timelineToolbarHelperDefinesCompactLocalizedIconButtons() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let helper = try section(
            in: timeline,
            from: "private func timelineToolbarIconButton(",
            to: "    private var selectedClipToolbar"
        )

        for marker in [
            "systemImage: String",
            "title: String",
            "accessibilityLabel: String? = nil",
            "hint: String",
            "accessibilityValue: String? = nil",
            "isDisabled: Bool = false",
            "NSLocalizedString(title, comment: \"\")",
            "Image(systemName: systemImage)",
            ".frame(width: 24, height: 24)",
            ".buttonStyle(.borderless)",
            ".controlSize(.small)",
            ".disabled(isDisabled)",
            ".foregroundStyle(isDisabled ? MovieCutTheme.mutedText.opacity(0.56) : Color.primary)",
            ".contentShape(Rectangle())",
            ".help(localizedTitle)",
            ".accessibilityLabel(localizedAccessibilityLabel)",
            ".accessibilityHint(localizedHint)"
        ] {
            #expect(helper.contains(marker))
        }
    }

    @Test("Selected clip toolbar uses icon helper for all eight edit actions")
    func selectedClipToolbarUsesIconHelperForAllEightEditActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )

        #expect(occurrenceCount(of: "timelineToolbarIconButton(", in: toolbar) == 8)

        for marker in [
            #"systemImage: "scissors""#,
            #"title: "Split at Playhead""#,
            #"hint: "Splits the selected clip at the playhead.""#,
            "Task { await viewModel.splitClip() }",
            "isDisabled: !viewModel.canSplitSelectedClip",
            #"systemImage: "trash""#,
            #"title: "Delete Selected Clips""#,
            #"hint: "Deletes the selected clips from the timeline.""#,
            "Task { await viewModel.deleteClip() }",
            "isDisabled: !viewModel.hasSelectedClips",
            #"systemImage: "delete.left""#,
            #"title: "Ripple Delete Selected Clip""#,
            #"hint: "Deletes the selected clip and closes the resulting gap.""#,
            "Task { await viewModel.rippleDeleteSelectedClip() }",
            "isDisabled: viewModel.selectedClip == nil",
            #"systemImage: "square.on.square""#,
            #"title: "Duplicate Selected Clips""#,
            #"hint: "Duplicates the selected clips on the timeline.""#,
            "Task { await viewModel.duplicateSelectedClips() }",
            #"systemImage: "arrow.left.to.line.compact""#,
            #"title: "Snap Playhead to Clip Start""#,
            #"hint: "Moves the playhead to the selected clip start.""#,
            "viewModel.snapPlayheadToSelectedClipStart()",
            #"systemImage: "arrow.right.to.line.compact""#,
            #"title: "Snap Playhead to Clip End""#,
            #"hint: "Moves the playhead to the selected clip end.""#,
            "viewModel.snapPlayheadToSelectedClipEnd()",
            #"systemImage: "snowflake""#,
            #"title: "Freeze Selected Frame""#,
            #"hint: "Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.""#,
            "Task { await viewModel.freezeSelectedFrame() }",
            "isDisabled: !selectedClipSupportsVisualTimelineEffect",
            #"systemImage: "backward.fill""#,
            #"title: "Reverse Selected Clip""#,
            #"hint: "Reverse Selected Clip toggles reverse playback for the selected visual clip.""#,
            "guard let selectedClip = viewModel.selectedClip else { return }",
            "await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)",
            #"accessibilityLabel(NSLocalizedString("Timeline edit tools", comment: ""))"#
        ] {
            #expect(toolbar.contains(marker))
        }
    }

    @Test("Marker controls use icon helper and preserve marker commands")
    func markerControlsUseIconHelperAndPreserveCommands() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let controls = try section(
            in: timeline,
            from: "private var timelineMarkerControls: some View",
            to: "    private var selectedClipSupportsVisualTimelineEffect"
        )

        #expect(occurrenceCount(of: "timelineToolbarIconButton(", in: controls) == 3)

        for marker in [
            #"systemImage: "backward.end.fill""#,
            #"title: "Previous Marker""#,
            #"hint: "Moves the playhead to the previous marker.""#,
            "isDisabled: viewModel.previousMarker == nil",
            "viewModel.goToPreviousMarker()",
            #"systemImage: "flag.fill""#,
            #"title: "Add Marker at Playhead""#,
            #"hint: "Adds a marker at the current playhead time.""#,
            #"accessibilityValue: String(format: NSLocalizedString("%d markers", comment: ""), sortedMarkers.count)"#,
            "viewModel.addMarkerAtPlayhead()",
            #"systemImage: "forward.end.fill""#,
            #"title: "Next Marker""#,
            #"hint: "Moves the playhead to the next marker.""#,
            "isDisabled: viewModel.nextMarker == nil",
            "viewModel.goToNextMarker()",
            #"accessibilityLabel(NSLocalizedString("Timeline marker controls", comment: ""))"#
        ] {
            #expect(controls.contains(marker))
        }
    }

    @Test("Zoom controls use icon helper while keeping slider and readout")
    func zoomControlsUseIconHelperWhileKeepingSliderAndReadout() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let controls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        #expect(occurrenceCount(of: "timelineToolbarIconButton(", in: controls) == 3)

        for marker in [
            #"systemImage: "minus.magnifyingglass""#,
            #"title: "Zoom Timeline Out""#,
            #"accessibilityLabel: "타임라인 축소""#,
            #"hint: "Zooms the timeline out.""#,
            "viewModel.zoomTimelineOut()",
            "Slider(value:",
            "Text(timelineZoomDisplay)",
            #"systemImage: "plus.magnifyingglass""#,
            #"title: "Zoom Timeline In""#,
            #"accessibilityLabel: "타임라인 확대""#,
            #"hint: "Zooms the timeline in.""#,
            "viewModel.zoomTimelineIn()",
            #"systemImage: "arrow.left.and.right""#,
            #"title: "Fit Timeline""#,
            #"hint: "Fits the visible timeline duration in the available timeline width.""#,
            "fitTimelineToAvailableWidth(timelineViewportWidth)",
            #"accessibilityLabel(NSLocalizedString("Timeline zoom controls", comment: ""))"#
        ] {
            #expect(controls.contains(marker))
        }
    }

    @Test("Toolbar action buttons do not expose visible text labels")
    func toolbarActionButtonsDoNotExposeVisibleTextLabels() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineZoomDisplay"
        )

        #expect(toolbar.contains("Text(timelineZoomDisplay)"))
        #expect(toolbar.range(of: #"(?:^|[^A-Za-z0-9_])Label\s*\("#, options: .regularExpression) == nil)

        for forbidden in [
            #"Text(NSLocalizedString("Split at Playhead", comment: ""))"#,
            #"Text(NSLocalizedString("Delete Selected Clips", comment: ""))"#,
            #"Text(NSLocalizedString("Ripple Delete Selected Clip", comment: ""))"#,
            #"Text(NSLocalizedString("Duplicate Selected Clips", comment: ""))"#,
            #"Text(NSLocalizedString("Snap Playhead to Clip Start", comment: ""))"#,
            #"Text(NSLocalizedString("Snap Playhead to Clip End", comment: ""))"#,
            #"Text(NSLocalizedString("Freeze Selected Frame", comment: ""))"#,
            #"Text(NSLocalizedString("Reverse Selected Clip", comment: ""))"#,
            #"Text(NSLocalizedString("Previous Marker", comment: ""))"#,
            #"Text(NSLocalizedString("Add Marker at Playhead", comment: ""))"#,
            #"Text(NSLocalizedString("Next Marker", comment: ""))"#,
            #"Text(NSLocalizedString("Zoom Timeline Out", comment: ""))"#,
            #"Text(NSLocalizedString("Zoom Timeline In", comment: ""))"#,
            #"Text(NSLocalizedString("Fit Timeline", comment: ""))"#
        ] {
            #expect(!toolbar.contains(forbidden))
        }
    }

    @Test("TimelineView remains edit only without Smart or QuickTools actions")
    func timelineViewRemainsEditOnlyWithoutSmartOrQuickToolsActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")

        for forbidden in [
            "QuickToolsPanel",
            "runAutoCutOnSelection",
            "detectSceneChangesForSelection",
            "detectBeats",
            "autoReframeSelection",
            "applyNoiseReductionToSelection",
            "extractAudioFromSelection"
        ] {
            #expect(!timeline.contains(forbidden))
        }
    }

    @Test("Handoff marks Phase 2-3 implemented and leaves Phase 2-4 pending")
    func handoffMarksPhase23ImplementedAndLeavesPhase24Pending() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 2-1 implemented"))
        #expect(handoff.contains("Phase 2-2 implemented"))
        #expect(handoff.contains("Phase 2-3 implemented"))
        #expect(handoff.contains("Phase23TimelineToolbarIconOnlyStaticContractTests"))
        #expect(handoff.contains("Phase 2-4 remains pending"))
        #expect(!handoff.contains("Phase 2-3 and Phase 2-4 remain pending"))
        #expect(!handoff.contains("Phase 2 complete"))
    }
}

private enum Phase23TimelineToolbarIconOnlyStaticContractError: Error {
    case missingMarker(String)
}
