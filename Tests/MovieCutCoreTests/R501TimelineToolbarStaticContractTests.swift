import Foundation
import Testing

/// R5-01 keeps CapCut-style clip actions in one timeline header row while
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

    @Test("Timeline header keeps edit quick tools marker and zoom in one row")
    func timelineHeaderKeepsSingleToolbarRow() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let content = try source("App/MovieCutMac/ContentView.swift")
        let header = try section(
            in: timeline,
            from: "HStack(spacing: MovieCutSpacing.small) {",
            to: "            }\n            .padding(.horizontal, MovieCutSpacing.medium)"
        )
        let quickTools = try section(
            in: content,
            from: "struct QuickToolsPanel: View",
            to: "struct ExportSheet: View"
        )

        #expect(header.contains(#"title: NSLocalizedString("Timeline", comment: "")"#))
        #expect(header.contains("selectedClipToolbar"))
        #expect(header.contains("QuickToolsPanel(viewModel: viewModel)"))
        #expect(header.contains("zoomControls"))
        #expect(quickTools.contains("markerControls"))
        #expect(quickTools.contains(#"Label("Marker (\(viewModel.currentProject.markers.count))", systemImage: "flag.fill")"#))
        #expect(quickTools.contains(#".help("Add Marker at Playhead")"#))
    }

    @Test("Selected clip toolbar promotes split duplicate reverse freeze delete ripple snap")
    func selectedClipToolbarPromotesPrimaryClipActions() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var zoomControls"
        )

        for marker in [
            #"Snap Playhead to Clip Start"#,
            #"Snap Playhead to Clip End"#,
            #"Split at Playhead"#,
            #"Duplicate Selected Clips"#,
            #"Reverse Selected Clip"#,
            #"Freeze Selected Frame"#,
            #"Delete Selected Clips"#,
            #"Ripple Delete Selected Clip"#,
        ] {
            #expect(toolbar.contains(marker))
        }

        let split = try #require(toolbar.range(of: #"Split at Playhead"#))
        let reverse = try #require(toolbar.range(of: #"Reverse Selected Clip"#))
        let freeze = try #require(toolbar.range(of: #"Freeze Selected Frame"#))
        let duplicate = try #require(toolbar.range(of: #"Duplicate Selected Clips"#))
        let delete = try #require(toolbar.range(of: #"Delete Selected Clips"#))
        let ripple = try #require(toolbar.range(of: #"Ripple Delete Selected Clip"#))

        #expect(split.lowerBound < reverse.lowerBound)
        #expect(reverse.lowerBound < freeze.lowerBound)
        #expect(freeze.lowerBound < duplicate.lowerBound)
        #expect(duplicate.lowerBound < delete.lowerBound)
        #expect(delete.lowerBound < ripple.lowerBound)
    }

    @Test("Reverse and freeze buttons call existing ViewModel presentation hooks")
    func reverseAndFreezeButtonsUseExistingViewModelCalls() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let toolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var zoomControls"
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
