import CoreGraphics
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

/// CA-20 stage 2-B: the timeline index's view-model surface — entry
/// build/filter correctness and the reveal path. The 30-minute p95 number
/// in the DoD is measured here as an automated proxy (filter latency over
/// a 30-minute synthetic timeline); the human walkthrough (VoiceOver
/// navigation, W4-editor task timing) stays the DoD's manual (U) axis.
@MainActor
@Suite("Timeline index behavior (CA-20 2-B)")
struct TimelineIndexBehaviorTests {
    private func makeViewModel(clipCount: Int = 3, markers: [Marker] = []) -> EditorViewModel {
        var assets: [UUID: MediaAsset] = [:]
        var clips: [Clip] = []
        for i in 0..<clipCount {
            let assetId = UUID()
            assets[assetId] = MediaAsset(
                originalURL: URL(fileURLWithPath: "/scratch/scene_\(i).mp4"),
                kind: .video, duration: 5
            )
            clips.append(Clip(
                assetId: assetId, kind: .video,
                sourceRange: TimeRange(start: 0, duration: 5),
                timelineRange: TimeRange(start: TimeInterval(i) * 5, duration: 5)
            ))
        }
        var project = Project(
            name: "index",
            mediaLibrary: MediaLibrary(assets: assets),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .video, name: "V", zIndex: 0, clips: clips)
            ])
        )
        project.markers = markers
        return EditorViewModel(project: project)
    }

    @Test("index panel is opt-in (off by default)")
    func toggleDefaultsOff() {
        #expect(makeViewModel().showTimelineIndex == false)
    }

    @Test("entries list clips and markers in timeline order; beat markers are excluded")
    func entryBuild() {
        let marker = Marker(time: 2, name: "Intro")
        let beat = Marker(time: 3, name: "b1", kind: .beat)
        let vm = makeViewModel(clipCount: 3, markers: [marker, beat])

        let entries = vm.timelineIndexEntries()
        #expect(entries.count == 4, "3 clips + 1 user marker (beat excluded)")
        #expect(entries.map(\.title).contains("scene_0"))
        #expect(entries.map(\.title).contains("Intro"))
        #expect(!entries.map(\.title).contains("b1"))
        #expect(entries.map(\.time) == entries.map(\.time).sorted(),
                "entries are in timeline order")
    }

    @Test("filter matches title, track name, and role name case-insensitively")
    func filtering() async throws {
        let vm = makeViewModel(clipCount: 3)
        try await vm.assignRole(TimelineRole.presets[1], to: [vm.currentProject.timeline.tracks[0].clips[1].id])

        #expect(vm.timelineIndexEntries(filter: "SCENE_1").count == 1,
                "title match is case-insensitive")
        #expect(vm.timelineIndexEntries(filter: "music").map(\.title) == ["scene_1"],
                "role name matches only the tagged clip")
        #expect(vm.timelineIndexEntries(filter: "v").map(\.title).count == 3,
                "track name matches every clip on that track")
        #expect(vm.timelineIndexEntries(filter: "zzz").isEmpty)

        let markerVM = makeViewModel(markers: [Marker(time: 9, name: "Outro")])
        #expect(markerVM.timelineIndexEntries(filter: "outro").count == 1)
    }

    @Test("reveal selects and jumps clips; markers jump via the marker path")
    func reveal() {
        let marker = Marker(time: 12, name: "Intro")
        let vm = makeViewModel(clipCount: 4, markers: [marker])

        let clipEntry = vm.timelineIndexEntries().first { $0.clipId != nil }!
        vm.revealTimelineIndexEntry(clipEntry)
        #expect(vm.selectedClipIds == [clipEntry.clipId!])
        #expect(vm.playheadTime == clipEntry.time)

        let markerEntry = vm.timelineIndexEntries().first { $0.kind == .marker }!
        vm.revealTimelineIndexEntry(markerEntry)
        #expect(vm.playheadTime == 12)
        #expect(vm.selectedClipIds == [clipEntry.clipId!],
                "marker reveal moves the playhead without disturbing the selection")
    }

    @Test("30-minute timeline: filter latency p95 stays far below budget (automated proxy)")
    func thirtyMinuteP95() {
        // 360 clips x 5s = 30 minutes, plus 30 user markers — the DoD's
        // long-form scale. Pre-registered budget: p95 <= 50ms per search
        // (pure in-memory filtering; the human walkthrough timing is U).
        var markers: [Marker] = []
        for i in 0..<30 {
            markers.append(Marker(time: TimeInterval(i) * 60, name: "marker_\(i)"))
        }
        let vm = makeViewModel(clipCount: 360, markers: markers)
        #expect(vm.timelineIndexEntries().count == 390)

        let queries = (0..<200).map { i in
            if i.isMultiple(of: 3) { return "scene_\(i % 360)" }
            if i.isMultiple(of: 5) { return "marker" }
            return "s"
        }
        var samples: [Double] = []
        let clock = ContinuousClock()
        for q in queries {
            let start = clock.now
            _ = vm.timelineIndexEntries(filter: q)
            let c = start.duration(to: clock.now).components
            samples.append(Double(c.seconds) + Double(c.attoseconds) / 1e18)
        }
        samples.sort()
        let p95 = samples[Int((Double(samples.count - 1) * 0.95).rounded(.down))]
        print(String(format: "INDEXP95 entries=390 queries=%d p95=%.3fms", samples.count, p95 * 1000))
        #expect(p95 <= 0.050, "p95 exceeds the 50ms budget — measured value on the INDEXP95 line above")
    }
}
