import Foundation
import CoreGraphics
import Testing
@testable import MovieCutCore

/// Task 5.8 — Compound Inc 1b flatten render (single-source cache).
///
/// These pin the parity claim's foundation: that the timeline is flattened
/// **once**, in **one place**, and that **both** render consumers receive the
/// **identical** `FlattenedTimeline` snapshot. `PlaybackEngine` and
/// `ExportEngine` live in the App target and adopt the
/// `FlattenedTimelineConsumer` contract via the orchestrator's wiring; here we
/// prove the contract with stand-in consumers and the real `CompoundFlattener`
/// + `FlattenedTimelineCache` from Core.
@Suite("Compound flatten render (Task 5.8)")
struct CompoundFlattenTests {

    // MARK: - Flatten is single-level and non-recursive

    @Test("flatten replaces a container with its shifted children, one level only")
    func flattenExpandsOneLevel() throws {
        let projectId = UUID()
        // Two plain clips plus one container clip on the same track.
        let plain1 = Clip(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000001")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let plain2 = Clip(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000002")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 3),
            timelineRange: TimeRange(start: 12, duration: 3)
        )

        // Children stored RELATIVE to the compound's zero. The container sits
        // at timeline start 4, so children must land at 4+0 and 4+2.
        let childA = Clip(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000010")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let childB = Clip(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000011")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 2, duration: 2)
        )
        let compound = CompoundDefinition(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000099")!,
            name: "Intro",
            childClips: [childA, childB]
        )
        let container = Clip(
            id: UUID(uuidString: "aaaa0000-0000-4000-8000-000000000003")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 4, duration: 4),
            compoundId: compound.id
        )

        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: [plain1, container, plain2])
        track.isLocked = false
        let project = Project(
            id: projectId,
            name: "Flatten",
            timeline: Timeline(tracks: [track]),
            compounds: [compound]
        )

        let flattened = CompoundFlattener.flatten(project)

        // 3 in, but container expands to 2 -> 4 clips out.
        let clips = flattened.tracks[0].clips
        #expect(clips.count == 4)

        // Plain clips pass through unchanged (byte-identical).
        #expect(clips[0] == plain1)
        #expect(clips[3] == plain2)

        // Children shifted by the container's timeline start (4).
        let movedA = clips[1]
        let movedB = clips[2]
        #expect(movedA.id == childA.id)
        #expect(abs(movedA.timelineRange.start - 4.0) < 1e-9)
        #expect(abs(movedA.timelineRange.duration - 2.0) < 1e-9)
        #expect(movedB.id == childB.id)
        #expect(abs(movedB.timelineRange.start - 6.0) < 1e-9)
        #expect(abs(movedB.timelineRange.duration - 2.0) < 1e-9)

        // No container survives flattening.
        #expect(clips.allSatisfy { $0.compoundId == nil })
        // Snapshot carries project identity and render-time params.
        #expect(flattened.projectId == projectId)
        #expect(flattened.schemaVersion == project.schemaVersion)
    }

    @Test("a project with no compounds flattens to itself clip-for-clip")
    func flattenNoCompoundsIsIdentity() throws {
        let a = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let b = Clip(
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 0, duration: 5)
        )
        let vTrack = Track(kind: .video, name: "V", zIndex: 0, clips: [a])
        let aTrack = Track(kind: .audio, name: "A", zIndex: 1, clips: [b])
        let project = Project(name: "Plain", timeline: Timeline(tracks: [vTrack, aTrack]))

        let flattened = CompoundFlattener.flatten(project)

        #expect(flattened.tracks.count == 2)
        #expect(flattened.tracks[0].clips == [a])
        #expect(flattened.tracks[1].clips == [b])
    }

    @Test("flatten is pure: the source project is not mutated")
    func flattenIsPure() throws {
        let child = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let compound = CompoundDefinition(name: "C", childClips: [child])
        let container = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 1, duration: 2),
            compoundId: compound.id
        )
        var track = Track(kind: .video, name: "V", zIndex: 0, clips: [container])
        track.isLocked = false
        let project = Project(name: "P", timeline: Timeline(tracks: [track]), compounds: [compound])

        let before = project
        _ = CompoundFlattener.flatten(project)
        // The pure flattener must leave the input untouched.
        #expect(project == before)
        #expect(project.timeline.tracks[0].clips[0].compoundId == compound.id)
    }

    // MARK: - Single-source cache: both consumers get the IDENTICAL snapshot

    @Test("the cache computes once and hands the identical snapshot to both engines")
    func cacheHandsIdenticalSnapshotToBothConsumers() async throws {
        // Stand-in consumers standing in for PlaybackEngine / ExportEngine.
        // They conform to the same contract the App engines adopt, so proving
        // they hold identical state is the parity claim itself.
        let playback = TestConsumer()
        let export = TestConsumer()

        let child = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let compound = CompoundDefinition(name: "C", childClips: [child])
        let container = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 5, duration: 2),
            compoundId: compound.id
        )
        var track = Track(kind: .video, name: "V", zIndex: 0, clips: [container])
        track.isLocked = false
        let project = Project(
            id: UUID(uuidString: "bbbb0000-0000-4000-8000-000000000001")!,
            name: "P",
            timeline: Timeline(tracks: [track]),
            compounds: [compound]
        )

        // The orchestrator's single step: compute once, then distribute.
        let cache = FlattenedTimelineCache()
        await cache.update(for: project)
        await cache.distribute(to: [playback, export], project: project)

        // Both engines received the identical snapshot — this is the parity
        // claim's basis. Structural equality AND the content digest agree.
        let same = await FlattenedTimelineParity.bothHoldIdentical(
            for: project.id, playback, export
        )
        #expect(same)

        let a = await playback.currentFlattenedTimeline()!
        let b = await export.currentFlattenedTimeline()!
        #expect(a == b)
        #expect(a.contentDigest == b.contentDigest)
        // The expanded child is present in the snapshot both hold.
        #expect(a.tracks[0].clips.count == 1)
        #expect(abs(a.tracks[0].clips[0].timelineRange.start - 5.0) < 1e-9)
    }

    @Test("two distinct project states produce distinct snapshots (cache updates on change)")
    func cacheUpdatesOnProjectChange() async throws {
        let playback = TestConsumer()
        let export = TestConsumer()
        let cache = FlattenedTimelineCache()

        // State 1: single plain clip at timeline 0.
        let clip1 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let track1 = Track(kind: .video, name: "V", zIndex: 0, clips: [clip1])
        let projectId = UUID(uuidString: "cccc0000-0000-4000-8000-000000000001")!
        let project1 = Project(id: projectId, name: "P1", timeline: Timeline(tracks: [track1]))
        await cache.update(for: project1)
        await cache.distribute(to: [playback, export], project: project1)
        let digest1 = await playback.currentFlattenedTimeline()!.contentDigest
        #expect(await FlattenedTimelineParity.bothHoldIdentical(for: projectId, playback, export))

        // State 2: same project id, clip moved to timeline 10.
        let clip2 = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 10, duration: 2)
        )
        let track2 = Track(kind: .video, name: "V", zIndex: 0, clips: [clip2])
        let project2 = Project(id: projectId, name: "P2", timeline: Timeline(tracks: [track2]))
        await cache.update(for: project2)
        await cache.distribute(to: [playback, export], project: project2)
        let digest2 = await playback.currentFlattenedTimeline()!.contentDigest

        // The snapshot changed and both engines still agree on the new one.
        #expect(digest1 != digest2)
        #expect(await FlattenedTimelineParity.bothHoldIdentical(for: projectId, playback, export))
    }
}

// MARK: - Stand-in consumer

/// A test double for `PlaybackEngine` / `ExportEngine` that adopts the same
/// `FlattenedTimelineConsumer` contract the App engines adopt via the
/// orchestrator. It stores the snapshot verbatim with no own flatten call and
/// no own cache beyond the single value, exactly as the contract requires.
private actor TestConsumer: FlattenedTimelineConsumer {
    private var snapshot: FlattenedTimeline?
    private var bound: UUID?

    func boundProjectId() async -> UUID? { bound }

    func attach(_ project: Project, flattened: FlattenedTimeline) async {
        bound = project.id
        snapshot = flattened
    }

    func currentFlattenedTimeline() async -> FlattenedTimeline? {
        snapshot
    }
}
