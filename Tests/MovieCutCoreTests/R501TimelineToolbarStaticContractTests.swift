import Foundation
import Testing

/// R5-01 keeps CapCut-style edit actions in one timeline header row while
/// leaving timeline commands and rendering semantics owned by the ViewModel.
@Suite("R5-01 Timeline Toolbar StaticContract")
struct R501TimelineToolbarStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R501TimelineToolbarStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R501TimelineToolbarStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Timeline header keeps edit marker and zoom controls in one row")
    func timelineHeaderKeepsSingleToolbarRow() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let header = try section(
            in: timeline,
            from: "HStack(spacing: MovieCutSpacing.small) {",
            to: "            }\n            .padding(.horizontal, MovieCutSpacing.medium)"
        )

        #expect(header.contains(#"title: NSLocalizedString("Timeline", comment: "")"#))
        #expect(header.contains("selectedClipToolbar"))
        #expect(header.contains("timelineMarkerControls"))
        #expect(header.contains("zoomControls"))
        #expect(header.contains("Spacer(minLength: MovieCutSpacing.small)"))
        #expect(!header.contains("QuickToolsPanel(viewModel: viewModel)"))
    }

    @Test("Selected clip toolbar promotes split delete ripple duplicate snap freeze reverse")
    func selectedClipToolbarPromotesPrimaryClipActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )

        for marker in [
            #"Split at Playhead"#,
            #"Delete Selected Clips"#,
            #"Ripple Delete Selected Clip"#,
            #"Duplicate Selected Clips"#,
            #"Snap Playhead to Clip Start"#,
            #"Snap Playhead to Clip End"#,
            #"Freeze Selected Frame"#,
            #"Reverse Selected Clip"#,
        ] {
            #expect(toolbar.contains(marker))
        }

        let split = try #require(toolbar.range(of: #"Split at Playhead"#))
        let delete = try #require(toolbar.range(of: #"Delete Selected Clips"#))
        let ripple = try #require(toolbar.range(of: #"Ripple Delete Selected Clip"#))
        let duplicate = try #require(toolbar.range(of: #"Duplicate Selected Clips"#))
        let snapStart = try #require(toolbar.range(of: #"Snap Playhead to Clip Start"#))
        let snapEnd = try #require(toolbar.range(of: #"Snap Playhead to Clip End"#))
        let freeze = try #require(toolbar.range(of: #"Freeze Selected Frame"#))
        let reverse = try #require(toolbar.range(of: #"Reverse Selected Clip"#))

        #expect(split.lowerBound < delete.lowerBound)
        #expect(delete.lowerBound < ripple.lowerBound)
        #expect(ripple.lowerBound < duplicate.lowerBound)
        #expect(duplicate.lowerBound < snapStart.lowerBound)
        #expect(snapStart.lowerBound < snapEnd.lowerBound)
        #expect(snapEnd.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < reverse.lowerBound)
        #expect(!toolbar.contains("sendSelectedClipLayerToBack()"))
        #expect(!toolbar.contains("bringSelectedClipLayerToFront()"))
        #expect(!toolbar.contains(#"Text(NSLocalizedString("Edit", comment: ""))"#))
    }

    @Test("Reverse and freeze buttons call existing ViewModel presentation hooks")
    func reverseAndFreezeButtonsUseExistingViewModelCalls() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )

        #expect(toolbar.contains("guard let selectedClip = viewModel.selectedClip else { return }"))
        #expect(toolbar.contains("await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)"))
        #expect(toolbar.contains("Task { await viewModel.freezeSelectedFrame() }"))
        #expect(toolbar.contains(".disabled(!selectedClipSupportsVisualTimelineEffect)"))
        #expect(toolbar.contains(#".help("Reverse Selected Clip")"#))
        #expect(toolbar.contains(#".accessibilityLabel(NSLocalizedString("Reverse Selected Clip", comment: ""))"#))
        #expect(toolbar.contains(#".accessibilityHint(NSLocalizedString("Reverse Selected Clip toggles reverse playback for the selected visual clip.", comment: ""))"#))
        #expect(toolbar.contains(#".help("Freeze Selected Frame")"#))
        #expect(toolbar.contains(#".accessibilityLabel(NSLocalizedString("Freeze Selected Frame", comment: ""))"#))
        #expect(toolbar.contains(#".accessibilityHint(NSLocalizedString("Freeze Selected Frame inserts a still frame at the playhead for the selected visual clip.", comment: ""))"#))
    }

    @Test("Reverse and freeze toolbar enablement remains presentation scoped")
    func reverseAndFreezeEnablementRemainsPresentationScoped() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let helper = try section(
            in: timeline,
            from: "private var selectedClipSupportsVisualTimelineEffect: Bool",
            to: "    private var zoomControls"
        )

        #expect(helper.contains("guard let selectedClip = viewModel.selectedClip else { return false }"))
        #expect(helper.contains("selectedClip.kind == .video || selectedClip.kind == .image"))
        #expect(!helper.contains("ReverseClipCommand"))
        #expect(!helper.contains("FreezeFrameCommand"))
    }
}

private enum R501TimelineToolbarStaticContractError: Error {
    case missingMarker(String)
}
