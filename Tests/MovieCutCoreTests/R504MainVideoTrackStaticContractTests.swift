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
            #"accessibilityLabel(NSLocalizedString("재생 헤드", comment: ""))"#,
            "onDrop(of: [.fileURL, .movie, .image, .movieCutMediaAssetID], isTargeted: nil)",
            "handleTrackDrop(providers: providers, location: location, trackId: track.id)",
            #"accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", comment: ""), trackHeaderAccessibilityLabel(for: track)))"#,
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
        #expect(accessibility.contains(#"return NSLocalizedString("비디오 트랙 헤더", comment: "")"#))
        #expect(timeline.contains("accessibilityLabel(trackHeaderAccessibilityLabel(for: track))"))
        #expect(timeline.contains(#"accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", comment: ""), trackHeaderAccessibilityLabel(for: track)))"#))
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

    @Test("R5-04 docs are implemented while speed curve is complete")
    func r504DocsAreImplementedWhileSpeedCurveIsComplete() throws {
        let parity = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")
        let r504Row = try section(
            in: parity,
            from: "| R5-04 | 메인 비디오 트랙 개념 |",
            to: "\n\n### R6."
        )

        #expect(r504Row.contains("✅ 구현(2026-06-17, Codex R5-04):"))
        #expect(r504Row.contains("첫 `.video` 트랙"))
        #expect(r504Row.contains("`mainVideoTrackId`/`isMainVideoTrack(_:)`"))
        #expect(r504Row.contains("compact `Main` 배지"))
        #expect(r504Row.contains("`.allowsHitTesting(false)`"))
        #expect(r504Row.contains("track ordering/model/import/export/playback/session semantics 변경 없음"))
        #expect(parity.contains("| R4-05 | **서브탭 깊이: Speed 곡선 에디터** | ✅ 구현(2026-06-18, Codex Phase 3-3):"))
        #expect(parity.contains("- **P3 완료** — R5-04, R4 서브탭 깊이(Speed 곡선 에디터)."))
        #expect(parity.contains("- **P3 심층 잔여** — 없음(이번 UI 로드맵 기준; optical-flow smooth slow motion은 별도 기능 backlog)."))
        #expect(!parity.contains("| R5-04 | 메인 비디오 트랙 개념 | 🟡 |"))
        #expect(handoff.contains("Phase 3-2/R5-04 implemented"))
        #expect(handoff.contains("Phase 3-3/R4 subtab depth implemented"))
        #expect(!handoff.contains("Speed 곡선 에디터 remains pending"))
        #expect(!handoff.contains("R5-04 메인 트랙 시각 구분 and Speed 곡선 에디터 remain pending"))
    }
}

private enum R504MainVideoTrackStaticContractError: Error {
    case missingMarker(String)
}
