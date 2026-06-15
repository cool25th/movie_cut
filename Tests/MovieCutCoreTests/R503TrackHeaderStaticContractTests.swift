import Foundation
import Testing

/// R5-03 makes the timeline track header status icons command-backed controls
/// while preserving the timeline lane/drop surface.
@Suite("R5-03 Track Header StaticContract")
struct R503TrackHeaderStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R503TrackHeaderStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R503TrackHeaderStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Track lane header exposes mute hide and lock controls")
    func trackLaneHeaderExposesMuteHideAndLockControls() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let lane = try section(
            in: timeline,
            from: "private func trackLane(_ track: Track) -> some View",
            to: "    private func trackHeaderControls(for track: Track) -> some View"
        )
        let controls = try section(
            in: timeline,
            from: "private func trackHeaderControls(for track: Track) -> some View",
            to: "    @MainActor"
        )

        #expect(lane.contains("trackHeaderControls(for: track)"))
        #expect(lane.contains(".accessibilityElement(children: .contain)"))
        #expect(lane.contains(#"accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", comment: ""), trackHeaderAccessibilityLabel(for: track)))"#))
        #expect(lane.contains("handleTrackDrop(providers: providers, location: location, trackId: track.id)"))

        #expect(controls.components(separatedBy: "Button {").count - 1 == 3)
        #expect(controls.contains(#"Image(systemName: track.isMuted ? "speaker.slash" : "speaker.wave.2")"#))
        #expect(controls.contains(#"Image(systemName: track.isHidden ? "eye.slash" : "eye")"#))
        #expect(controls.contains(#"Image(systemName: track.isLocked ? "lock" : "lock.open")"#))
        #expect(controls.components(separatedBy: ".buttonStyle(.borderless)").count - 1 == 3)
        #expect(controls.contains(#"accessibilityLabel(NSLocalizedString("Mute track", comment: ""))"#))
        #expect(controls.contains(#"accessibilityLabel(NSLocalizedString("Hide track", comment: ""))"#))
        #expect(controls.contains(#"accessibilityLabel(NSLocalizedString("Lock track", comment: ""))"#))
        #expect(controls.contains("accessibilityValue(track.isMuted ?"))
        #expect(controls.contains("accessibilityValue(track.isHidden ?"))
        #expect(controls.contains("accessibilityValue(track.isLocked ?"))
        #expect(controls.contains("accessibilityHint(NSLocalizedString"))
    }

    @Test("Track header buttons call ViewModel toggle methods")
    func trackHeaderButtonsCallViewModelToggleMethods() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let controls = try section(
            in: timeline,
            from: "private func trackHeaderControls(for track: Track) -> some View",
            to: "    @MainActor"
        )

        #expect(controls.contains("Task { await viewModel.toggleTrackMute(track) }"))
        #expect(controls.contains("Task { await viewModel.toggleTrackHidden(track) }"))
        #expect(controls.contains("Task { await viewModel.toggleTrackLock(track) }"))
        #expect(!controls.contains("SetTrackPropertyCommand"))
    }

    @Test("Track toggle ViewModel methods remain command backed")
    func trackToggleViewModelMethodsRemainCommandBacked() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let methods = try section(
            in: viewModel,
            from: "func toggleTrackMute(_ track: Track) async",
            to: "    func rippleDeleteClip(clipId: UUID) async"
        )

        #expect(methods.contains("await apply(SetTrackPropertyCommand(trackId: track.id, property: .isMuted(!track.isMuted)))"))
        #expect(methods.contains("await apply(SetTrackPropertyCommand(trackId: track.id, property: .isLocked(!track.isLocked)))"))
        #expect(methods.contains("await apply(SetTrackPropertyCommand(trackId: track.id, property: .isHidden(!track.isHidden)))"))
        #expect(!methods.contains("session.dispatch"))
    }

    @Test("R5-03 docs are implemented without overclaiming R5-04")
    func r503DocsAreImplementedWithoutOverclaimingR504() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")

        #expect(docs.contains("| R5-03 | 트랙 헤더(잠금/숨김/음소거) | ✅ 구현(2026-06-16, Codex R5-03):"))
        #expect(docs.contains("`toggleTrackMute(_:)`/`toggleTrackHidden(_:)`/`toggleTrackLock(_:)`"))
        #expect(docs.contains("`SetTrackPropertyCommand`"))
        #expect(docs.contains("| R5-04 | 메인 비디오 트랙 개념 | 🟡 |"))
        #expect(docs.contains("- **P1 완료** — R1-02, R4-02, R5-02, R5-03."))
        #expect(!docs.contains("R5-03, R1-02"))
        #expect(!docs.contains("| R5-03 | 트랙 헤더(잠금/숨김/음소거) | 🟡 `isMuted` |"))
    }
}

private enum R503TrackHeaderStaticContractError: Error {
    case missingMarker(String)
}
