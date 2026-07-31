import Foundation
import Testing

/// R5-04 adds a presentation-only main video track treatment to the timeline
/// while keeping track ordering, commands, drops, clips, markers, and playback/export semantics unchanged.
@Suite("R5-04 Main Video Track StaticContract")
struct R504MainVideoTrackStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R504MainVideoTrackStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R504MainVideoTrackStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Main video track is selected as the first video track in TimelineView")
    func mainVideoTrackIsSelectedAsFirstVideoTrackInTimelineView() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let helper = try section(
            in: timeline,
            from: "private var mainVideoTrackId: Track.ID?",
            to: "    private var timelineContentWidth"
        )
        let lane = try section(
            in: timeline,
            from: "private func trackLane(_ track: Track) -> some View",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )

        #expect(helper.contains("viewModel.currentProject.timeline.tracks.first { $0.kind == .video }?.id"))
        #expect(helper.contains("private func isMainVideoTrack(_ track: Track) -> Bool"))
        #expect(helper.contains("track.id == mainVideoTrackId"))
        #expect(lane.contains("let isMainVideo = isMainVideoTrack(track)"))
        #expect(lane.contains("if isMainVideo {"))
        #expect(lane.contains("mainVideoTrackBadge"))
        #expect(lane.contains("mainVideoTrackHeaderAccent(isMainVideo: isMainVideo)"))
        #expect(lane.contains("mainVideoTrackLaneHighlight(isMainVideo: isMainVideo)"))
    }

    @Test("Main video track has compact badge and non-hit-testable header lane accents")
    func mainVideoTrackHasBadgeAndNonHitTestableAccents() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let badge = try section(
            in: timeline,
            from: "private var mainVideoTrackBadge: some View",
            to: "    @ViewBuilder\n    private func mainVideoTrackHeaderAccent"
        )
        let headerAccent = try section(
            in: timeline,
            from: "private func mainVideoTrackHeaderAccent(isMainVideo: Bool) -> some View",
            to: "    @ViewBuilder\n    private func mainVideoTrackLaneHighlight"
        )
        let laneHighlight = try section(
            in: timeline,
            from: "private func mainVideoTrackLaneHighlight(isMainVideo: Bool) -> some View",
            to: "    private func trackLane(_ track: Track) -> some View"
        )

        #expect(badge.contains(#"Text(NSLocalizedString("Main", comment: ""))"#))
        #expect(badge.contains("MovieCutTypography.micro"))
        #expect(badge.contains("Capsule()"))
        #expect(badge.contains("MovieCutTheme.accentCyan"))
        #expect(badge.contains(".accessibilityHidden(true)"))
        #expect(headerAccent.contains("RoundedRectangle(cornerRadius: MovieCutRadius.small)"))
        #expect(headerAccent.contains(".strokeBorder(MovieCutTheme.accentCyan.opacity(0.20), lineWidth: 1)"))
        #expect(headerAccent.contains(".allowsHitTesting(false)"))
        #expect(laneHighlight.contains(".fill(MovieCutTheme.accentCyan.opacity(0.035))"))
        #expect(laneHighlight.contains(".strokeBorder(MovieCutTheme.accentCyan.opacity(0.14), lineWidth: 1)"))
        #expect(laneHighlight.contains(".frame(width: timelineContentWidth, height: trackHeight, alignment: .leading)"))
        #expect(laneHighlight.contains(".allowsHitTesting(false)"))
    }

    @Test("Main video treatment preserves timeline lane drop clip marker grid and playhead surface")
    func mainVideoTreatmentPreservesTimelineLaneSurface() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let lane = try section(
            in: timeline,
            from: "private func trackLane(_ track: Track) -> some View",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )

        for marker in [
            ".background(MovieCutTheme.trackHeaderBackground.opacity(0.74))",
            "trackHeaderControls(for: track)",
            "Rectangle()\n                    .fill(MovieCutTheme.trackBackground)",
            "timelineGridLines(height: trackHeight)",
            "clipView(clip, trackKind: track.kind)",
            "TimelineMarkerLine(marker: marker, height: trackHeight)",
            "playheadOverlay",
            "onDrop(of: [.fileURL, .movie, .image, .movieCutMediaAssetID], isTargeted: nil)",
            "handleTrackDrop(providers: providers, location: location, trackId: track.id)",
            // Task 1.3: the `%@ 클립 추가 영역` marker was deleted here. The lane
            // drop region still needs an accessibility label, but that is now
            // verified at runtime by
            // `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`
            // instead of by pinning a source literal.
            #"accessibilityHint(NSLocalizedString("Drop media files or library assets here to add clips at the drop position.", comment: ""))"#
        ] {
            #expect(lane.contains(marker))
        }
    }

    @Test("Main video accessibility copy is routed through existing track label helper")
    func mainVideoAccessibilityCopyUsesTrackLabelHelper() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let accessibility = try section(
            in: timeline,
            from: "private func trackHeaderAccessibilityLabel(for track: Track) -> String",
            to: "    private func timelineSecondsString"
        )

        #expect(accessibility.contains("if isMainVideoTrack(track)"))
        #expect(accessibility.contains(#"NSLocalizedString("Main video track, %@", comment: "")"#))
        #expect(accessibility.contains("track.name"))
        // Task 1.3: the `비디오 트랙 헤더` fallback assertion and the
        // `%@ 클립 추가 영역` lane assertion were deleted. Both pinned the Korean
        // keys requirement 1 removed. The behaviour they guarded — a main video
        // track reads differently from a plain video track, and the lane drop
        // region derives its label from the header label — is verified at runtime
        // by `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`.
        #expect(timeline.contains("accessibilityLabel(trackHeaderAccessibilityLabel(for: track))"))
    }

    @Test("Main video visuals remain presentation only with no command service or model coupling")
    func mainVideoVisualsRemainPresentationOnly() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let visuals = try section(
            in: timeline,
            from: "private var mainVideoTrackId: Track.ID?",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )

        for forbidden in [
            "EditorSession",
            "dispatch(",
            "Command",
            "SetTrackPropertyCommand",
            "importMedia",
            "ExportPlanner",
            "PlaybackEngine",
            "addImportedAssetsToTimeline",
            "toggleTrackMute",
            "toggleTrackHidden",
            "toggleTrackLock"
        ] {
            #expect(!visuals.contains(forbidden))
        }

        for path in [
            "Sources/MovieCutCore/Models/Track.swift",
            "App/MovieCutMac/EditorViewModel.swift",
            "App/MovieCutMac/Export/ExportEngine.swift",
            "App/MovieCutMac/Playback/PlaybackEngine.swift"
        ] {
            let serviceSource = try source(path)
            for uiMarker in [
                "mainVideoTrackId",
                "isMainVideoTrack",
                "mainVideoTrackBadge",
                "mainVideoTrackLaneHighlight",
                "Main video track"
            ] {
                #expect(!serviceSource.contains(uiMarker))
            }
        }
    }
}

private enum R504MainVideoTrackStaticContractError: Error {
    case missingMarker(String)
}
