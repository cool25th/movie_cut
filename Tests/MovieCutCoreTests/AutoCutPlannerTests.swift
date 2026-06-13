import Foundation
import Testing
@testable import MovieCutCore

/// F-18 auto cut: padding planner math and the single-undo AutoCutCommand.
@Suite("Auto Cut Planner")
struct AutoCutPlannerTests {
    // MARK: - Planner

    @Test("padding trims each side of silence and preserves speech edges")
    func paddingTrimsSilence() {
        let bounds = TimeRange(start: 0, duration: 20)
        let silence = [TimeRange(start: 5, duration: 4)]   // 5...9

        let removable = AutoCutPlanner.removableRanges(
            fromSilence: silence,
            within: bounds,
            padding: 0.5
        )

        #expect(removable.count == 1)
        #expect(abs(removable[0].start - 5.5) < 0.001)
        #expect(abs(removable[0].end - 8.5) < 0.001)
    }

    @Test("silence shorter than twice the padding is dropped")
    func shortSilenceDropped() {
        let bounds = TimeRange(start: 0, duration: 10)
        let silence = [TimeRange(start: 4, duration: 0.6)]  // padding 0.4 each side → 0.6-0.8 < min

        let removable = AutoCutPlanner.removableRanges(
            fromSilence: silence,
            within: bounds,
            padding: 0.4
        )
        #expect(removable.isEmpty)
    }

    @Test("ranges are clamped to the clip bounds")
    func clampedToBounds() {
        let bounds = TimeRange(start: 2, duration: 6)   // 2...8
        let silence = [
            TimeRange(start: 0, duration: 4),           // overlaps 2...4
            TimeRange(start: 7, duration: 5)            // overlaps 7...8
        ]

        let removable = AutoCutPlanner.removableRanges(
            fromSilence: silence,
            within: bounds,
            padding: 0
        )

        #expect(removable.count == 2)
        #expect(removable.first!.start >= 2)
        #expect(removable.last!.end <= 8)
    }

    @Test("adjacent padded ranges merge")
    func adjacentRangesMerge() {
        let bounds = TimeRange(start: 0, duration: 20)
        let silence = [
            TimeRange(start: 3, duration: 2),    // 3...5
            TimeRange(start: 5, duration: 2)     // 5...7  (touch → merge)
        ]

        let removable = AutoCutPlanner.removableRanges(
            fromSilence: silence,
            within: bounds,
            padding: 0
        )
        #expect(removable.count == 1)
        #expect(abs(removable[0].start - 3) < 0.001)
        #expect(abs(removable[0].end - 7) < 0.001)
    }

    @Test("total duration sums removable ranges")
    func totalDuration() {
        let ranges = [
            TimeRange(start: 0, duration: 1.5),
            TimeRange(start: 3, duration: 2.5)
        ]
        #expect(abs(AutoCutPlanner.totalDuration(of: ranges) - 4.0) < 0.001)
    }

    @Test("empty bounds produce no ranges")
    func emptyBounds() {
        let removable = AutoCutPlanner.removableRanges(
            fromSilence: [TimeRange(start: 0, duration: 5)],
            within: TimeRange(start: 0, duration: 0),
            padding: 0
        )
        #expect(removable.isEmpty)
    }

    // MARK: - Command

    private func projectWithSingleAudioClip() -> (Project, UUID) {
        var project = Project(name: "AutoCut")
        let clip = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 20),
            timelineRange: TimeRange(start: 0, duration: 20)
        )
        var track = Track(kind: .audio, name: "Audio 1")
        track.clips = [clip]
        project.timeline.tracks = [track]
        return (project, clip.id)
    }

    @Test("auto cut command removes the middle range and shortens the timeline")
    func commandRemovesRange() async throws {
        let (project, _) = projectWithSingleAudioClip()
        let originalDuration = project.timeline.duration

        let session = EditorSession(project: project)
        try await session.dispatch(AutoCutCommand(removableRanges: [TimeRange(start: 8, duration: 4)]))

        let snapshot = await session.snapshot()
        // Splitting at 8 and 12 then removing the middle clip leaves clips that
        // together cover less than the original timeline.
        let totalClipDuration = snapshot.timeline.tracks
            .flatMap(\.clips)
            .reduce(0) { $0 + $1.timelineRange.duration }
        #expect(totalClipDuration < originalDuration)
        #expect(totalClipDuration <= 16.001)
    }

    @Test("auto cut is a single undo unit (AC③)")
    func singleUndo() async throws {
        let (project, _) = projectWithSingleAudioClip()
        let session = EditorSession(project: project)

        try await session.dispatch(AutoCutCommand(removableRanges: [
            TimeRange(start: 3, duration: 2),
            TimeRange(start: 10, duration: 3)
        ]))

        var snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks[0].clips.count > 1)

        // A single undo fully restores the original single clip.
        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.timeline.tracks[0].clips.count == 1)
        #expect(abs(snapshot.timeline.tracks[0].clips[0].timelineRange.duration - 20) < 0.001)
    }

    @Test("empty removable ranges throw")
    func emptyRangesThrow() {
        var project = Project(name: "Empty")
        #expect(throws: (any Error).self) {
            _ = try AutoCutCommand(removableRanges: []).apply(to: &project)
        }
    }
}

/// Wiring visibility for the auto-cut preview UI (not a completion criterion by
/// itself — see spec DoD §1.3).
@Suite("Auto Cut Preview Static Contract")
struct AutoCutPreviewStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("view model exposes preview, apply, cancel, and parameters")
    func viewModelExposesPreview() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        #expect(viewModel.contains("func previewAutoCutOnSelection"))
        #expect(viewModel.contains("func applyAutoCutPreview"))
        #expect(viewModel.contains("func cancelAutoCutPreview"))
        #expect(viewModel.contains("AutoCutPlanner.removableRanges"))
        #expect(viewModel.contains("AutoCutCommand(removableRanges:"))
        #expect(viewModel.contains("var autoCutThresholdDB"))
        #expect(viewModel.contains("var autoCutPadding"))
    }

    @Test("inspector exposes parameter sliders and preview controls")
    func inspectorExposesControls() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        #expect(inspector.contains("autoCutSection"))
        #expect(inspector.contains("autoCutThresholdDB"))
        #expect(inspector.contains("previewAutoCutOnSelection"))
        #expect(inspector.contains("applyAutoCutPreview"))
    }

    @Test("timeline renders removal preview highlights")
    func timelineRendersHighlights() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        #expect(timeline.contains("autoCutPreviewRanges"))
    }
}
