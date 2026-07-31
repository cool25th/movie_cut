import Foundation
import CoreGraphics
import Testing
@testable import MovieCutCore

/// Task 5.9 — Compound Inc 1c create / release commands (Requirements 7.1, 7.2,
/// 7.4, 7.7).
///
/// These pin the command contracts for Inc 1 (no internal editing, so this is
/// not "compound clip complete"):
///   - create bundles N clips into a single displayed container and stores the
///     relative internal composition;
///   - release restores the original clips;
///   - both are a single undo unit (apply→invert→apply is byte-exact, and one
///     `EditorSession.dispatch` is one undo step);
///   - moving / copying the container preserves the internal composition
///     relatively (verified through the task-5.8 flatten pass);
///   - creating a compound that would nest a container is rejected at creation.
@Suite("CreateCompoundClip / ReleaseCompoundClip (Task 5.9)")
struct CompoundClipCommandTests {

    private let tolerance = 1.0 / 30.0

    // MARK: - Fixtures

    /// Two adjacent clips plus a third later clip on the same track.
    private func makeProject() -> (project: Project, trackId: UUID, a: Clip, b: Clip, c: Clip) {
        let a = Clip(
            id: UUID(uuidString: "dddd0000-0000-4000-8000-000000000001")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 2),
            timelineRange: TimeRange(start: 0, duration: 2)
        )
        let b = Clip(
            id: UUID(uuidString: "dddd0000-0000-4000-8000-000000000002")!,
            kind: .video,
            sourceRange: TimeRange(start: 5, duration: 3),
            timelineRange: TimeRange(start: 2, duration: 3)
        )
        let c = Clip(
            id: UUID(uuidString: "dddd0000-0000-4000-8000-000000000003")!,
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 10, duration: 4)
        )
        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: [a, b, c])
        track.isLocked = false
        let project = Project(
            id: UUID(uuidString: "dddd0000-0000-4000-8000-0000000000ff")!,
            name: "Compound",
            timeline: Timeline(tracks: [track])
        )
        return (project, track.id, a, b, c)
    }

    // MARK: - Create

    @Test("create bundles clips into a single displayed container and stores relative children")
    func createBundlesIntoContainer() throws {
        var (project, trackId, a, b, c) = makeProject()
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000aa")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000bb")!

        let command = CreateCompoundClipCommand(
            trackId: trackId,
            clipIds: [a.id, b.id],
            compoundId: compoundId,
            containerClipId: containerId,
            compoundName: "Intro"
        )
        let result = try command.apply(to: &project)

        // The track now shows the container in place of a,b; the third clip is
        // untouched. Timeline displays a single clip for the compound.
        let clips = project.timeline.tracks[0].clips
        #expect(clips.count == 2)
        let container = clips.first { $0.id == containerId }!
        #expect(container.compoundId == compoundId)
        // Container spans the union [0,5] of a [0,2] and b [2,5].
        #expect(abs(container.timelineRange.start - 0.0) <= tolerance)
        #expect(abs(container.timelineRange.duration - 5.0) <= tolerance)
        // The third clip is unchanged.
        let keptC = clips.first { $0.id == c.id }!
        #expect(keptC == c)

        // The definition stores the children with RELATIVE ranges and no nesting.
        #expect(project.compounds.count == 1)
        let definition = project.compounds.first { $0.id == compoundId }!
        #expect(definition.name == "Intro")
        #expect(definition.childClips.count == 2)
        let childA = definition.childClips[0]
        let childB = definition.childClips[1]
        #expect(childA.id == a.id)
        #expect(abs(childA.timelineRange.start - 0.0) <= tolerance) // a was at 0 -> rel 0
        #expect(abs(childA.timelineRange.duration - 2.0) <= tolerance)
        #expect(childB.id == b.id)
        #expect(abs(childB.timelineRange.start - 2.0) <= tolerance) // b was at 2 -> rel 2
        #expect(abs(childB.timelineRange.duration - 3.0) <= tolerance)
        // No nesting: children carry no compoundId, and source ranges preserved.
        #expect(childA.compoundId == nil)
        #expect(childB.compoundId == nil)
        #expect(childA.sourceRange == a.sourceRange)
        #expect(childB.sourceRange == b.sourceRange)

        // The container id is surfaced in the affected set (single undo unit).
        #expect(result.affectedClipIds.contains(containerId))
        #expect(result.affectedClipIds.contains(a.id))
        #expect(result.affectedClipIds.contains(b.id))

        // Structural validation passes for the created project.
        try project.validateCompounds()
    }

    @Test("create rejects fewer than two clips")
    func createRejectsSingleClip() throws {
        var (project, trackId, a, _, _) = makeProject()
        let command = CreateCompoundClipCommand(trackId: trackId, clipIds: [a.id])

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &project)
        }
        // No mutation.
        #expect(project.timeline.tracks[0].clips.count == 3)
        #expect(project.compounds.isEmpty)
    }

    @Test("create rejects an unknown clip id atomically")
    func createRejectsUnknownClip() throws {
        var (project, trackId, a, _, _) = makeProject()
        let ghost = UUID()
        let command = CreateCompoundClipCommand(trackId: trackId, clipIds: [a.id, ghost])

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &project)
        }
        // No mutation, no half-created definition.
        #expect(project.timeline.tracks[0].clips.count == 3)
        #expect(project.compounds.isEmpty)
    }

    @Test("create rejects nesting a container inside another compound")
    func createRejectsNestingAtCreation() throws {
        var (project, trackId, a, b, c) = makeProject()
        // First, build a compound from a and b.
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000c1")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000c2")!
        _ = try CreateCompoundClipCommand(
            trackId: trackId, clipIds: [a.id, b.id],
            compoundId: compoundId, containerClipId: containerId
        ).apply(to: &project)

        // Now try to bundle the container together with c — must be refused.
        let nestedCommand = CreateCompoundClipCommand(
            trackId: trackId, clipIds: [containerId, c.id]
        )
        #expect(throws: EditorCommandError.self) {
            _ = try nestedCommand.apply(to: &project)
        }
        // The pre-existing compound is untouched.
        #expect(project.compounds.count == 1)
        #expect(project.compounds.first?.id == compoundId)
    }

    @Test("create is rejected on a locked track")
    func createRejectsLockedTrack() throws {
        var (project, trackId, a, b, _) = makeProject()
        project.timeline.tracks[0].isLocked = true
        let command = CreateCompoundClipCommand(trackId: trackId, clipIds: [a.id, b.id])

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &project)
        }
    }

    // MARK: - Create single undo unit + exact invert

    @Test("create is a single undo unit: invert restores the exact prior state")
    func createInvertsExactly() throws {
        var (project, trackId, a, b, _) = makeProject()
        let original = project

        // The same command instance must be used to build the inverse: invert
        // reads the container id from `self`, so a freshly-constructed command
        // (which mints a new container id) cannot reproduce the inverse.
        let command = CreateCompoundClipCommand(
            trackId: trackId,
            clipIds: [a.id, b.id]
        )
        let result = try command.apply(to: &project)
        let inverse = try command.invert(from: result)
        _ = try inverse.apply(to: &project)

        // Undo restores the project byte-for-byte (clips + compounds).
        #expect(project == original)
        #expect(project.compounds == original.compounds)
    }

    @Test("create is one undo step through EditorSession")
    func createIsOneUndoStep() async throws {
        let (project, trackId, a, b, _) = makeProject()
        let session = EditorSession(project: project)

        try await session.dispatch(
            CreateCompoundClipCommand(trackId: trackId, clipIds: [a.id, b.id])
        )
        // One dispatch -> one undo restores the original.
        try await session.undo()
        let restored = await session.snapshot()
        #expect(restored == project)
        #expect(restored.compounds.isEmpty)
    }

    // MARK: - Release restores originals

    @Test("release (user-facing) expands the container back to the original clips")
    func releaseRestoresOriginalClips() throws {
        var (project, trackId, a, b, c) = makeProject()
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000d1")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000d2")!
        _ = try CreateCompoundClipCommand(
            trackId: trackId, clipIds: [a.id, b.id],
            compoundId: compoundId, containerClipId: containerId
        ).apply(to: &project)

        // User-facing release: no restore data, so children expand in place.
        _ = try ReleaseCompoundClipCommand(
            trackId: trackId, containerClipId: containerId, compoundId: compoundId
        ).apply(to: &project)

        let clips = project.timeline.tracks[0].clips
        // Container gone; a and b restored at their ORIGINAL absolute ranges;
        // c untouched.
        #expect(clips.count == 3)
        let restoredA = clips.first { $0.id == a.id }!
        let restoredB = clips.first { $0.id == b.id }!
        let restoredC = clips.first { $0.id == c.id }!
        #expect(abs(restoredA.timelineRange.start - a.timelineRange.start) <= tolerance)
        #expect(abs(restoredA.timelineRange.duration - a.timelineRange.duration) <= tolerance)
        #expect(abs(restoredB.timelineRange.start - b.timelineRange.start) <= tolerance)
        #expect(abs(restoredB.timelineRange.duration - b.timelineRange.duration) <= tolerance)
        #expect(restoredC == c)
        // Definition removed.
        #expect(project.compounds.isEmpty)
    }

    @Test("release is one undo step through EditorSession and round-trips")
    func releaseIsOneUndoStep() async throws {
        let (project, trackId, a, b, _) = makeProject()
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000e1")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000e2")!
        let session = EditorSession(project: project)
        try await session.dispatch(
            CreateCompoundClipCommand(
                trackId: trackId, clipIds: [a.id, b.id],
                compoundId: compoundId, containerClipId: containerId
            )
        )
        let withCompound = await session.snapshot()
        try await session.dispatch(
            ReleaseCompoundClipCommand(
                trackId: trackId, containerClipId: containerId, compoundId: compoundId
            )
        )
        let released = await session.snapshot()
        #expect(released.compounds.isEmpty)

        // Undo the release -> compound is back.
        try await session.undo()
        let afterUndoRelease = await session.snapshot()
        #expect(afterUndoRelease.compounds.count == 1)
        #expect(afterUndoRelease.timeline.tracks[0].clips.contains { $0.id == containerId })

        // Redo the release -> released again.
        try await session.redo()
        let afterRedo = await session.snapshot()
        #expect(afterRedo.compounds.isEmpty)

        // Undo the create -> back to the very start.
        try await session.undo()
        try await session.undo()
        let restored = await session.snapshot()
        #expect(restored == project)
        _ = withCompound
    }

    // MARK: - Move / copy preserves internal composition (via flatten)

    @Test("moving the container preserves the internal composition relatively (flatten after move)")
    func movePreservesCompositionViaFlatten() throws {
        var (project, trackId, a, b, _) = makeProject()
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000f1")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-0000000000f2")!
        _ = try CreateCompoundClipCommand(
            trackId: trackId, clipIds: [a.id, b.id],
            compoundId: compoundId, containerClipId: containerId
        ).apply(to: &project)

        // The original (pre-compound) absolute layout, for reference.
        let originalAStart = a.timelineRange.start
        let originalBStart = b.timelineRange.start

        // Move the container by +7s in place (simulate a move edit on the
        // container). The internal children move with it by the same delta,
        // preserving their relative offsets.
        let moveDelta: TimeInterval = 7
        let trackIndex = try project.trackIndex(for: trackId)
        let containerIdx = project.timeline.tracks[trackIndex].clips.firstIndex { $0.id == containerId }!
        project.timeline.tracks[trackIndex].clips[containerIdx].timelineRange = TimeRange(
            start: project.timeline.tracks[trackIndex].clips[containerIdx].timelineRange.start + moveDelta,
            duration: project.timeline.tracks[trackIndex].clips[containerIdx].timelineRange.duration
        )

        let flattened = CompoundFlattener.flatten(project)
        let flatClips = flattened.tracks[0].clips
        let flatA = flatClips.first { $0.id == a.id }!
        let flatB = flatClips.first { $0.id == b.id }!
        // Both children shifted by exactly the move delta; their relative gap
        // (b.start - a.start) is unchanged.
        #expect(abs(flatA.timelineRange.start - (originalAStart + moveDelta)) <= tolerance)
        #expect(abs(flatB.timelineRange.start - (originalBStart + moveDelta)) <= tolerance)
        let originalGap = originalBStart - originalAStart
        let movedGap = flatB.timelineRange.start - flatA.timelineRange.start
        #expect(abs(movedGap - originalGap) <= tolerance)
    }

    @Test("copying the container duplicates the composition intact (flatten sees both)")
    func copyPreservesCompositionViaFlatten() throws {
        var (project, trackId, a, b, _) = makeProject()
        let compoundId = UUID(uuidString: "dddd0000-0000-4000-8000-000000001001")!
        let containerId = UUID(uuidString: "dddd0000-0000-4000-8000-000000001002")!
        _ = try CreateCompoundClipCommand(
            trackId: trackId, clipIds: [a.id, b.id],
            compoundId: compoundId, containerClipId: containerId
        ).apply(to: &project)

        // Simulate a copy: add a second container referencing the same
        // definition, positioned later on the track. Inc 1 lets a copy share
        // the definition (the flatten pass expands by reference), so both
        // containers emit the same children at their respective starts.
        let copyContainer = Clip(
            kind: .video,
            sourceRange: TimeRange(start: 0, duration: 5),
            timelineRange: TimeRange(start: 20, duration: 5),
            compoundId: compoundId
        )
        let trackIndex = try project.trackIndex(for: trackId)
        project.timeline.tracks[trackIndex].clips.append(copyContainer)

        let flattened = CompoundFlattener.flatten(project)
        let flatClips = flattened.tracks[0].clips
        // No container survives the flatten.
        #expect(flatClips.allSatisfy { $0.compoundId == nil })
        // The composition is duplicated intact: there is one child-sized clip
        // at the original span [0,2] AND one at the copy's offset [20,22].
        let atOriginal = flatClips.filter {
            abs($0.timelineRange.start - 0.0) <= tolerance &&
            abs($0.timelineRange.duration - a.timelineRange.duration) <= tolerance
        }
        let atCopy = flatClips.filter {
            abs($0.timelineRange.start - 20.0) <= tolerance &&
            abs($0.timelineRange.duration - a.timelineRange.duration) <= tolerance
        }
        #expect(atOriginal.count == 1)
        #expect(atCopy.count == 1)
        // And the second child of each instance lands 2s later (relative offset
        // preserved across the copy).
        let secondAtOriginal = flatClips.filter {
            abs($0.timelineRange.start - 2.0) <= tolerance
        }
        let secondAtCopy = flatClips.filter {
            abs($0.timelineRange.start - 22.0) <= tolerance
        }
        #expect(secondAtOriginal.count == 1)
        #expect(secondAtCopy.count == 1)
    }

    @Test("flatten of a created-then-released project equals flatten of the original")
    func flattenMatchesAfterReleaseRoundTrip() throws {
        var (project, trackId, a, b, _) = makeProject()
        let baseline = CompoundFlattener.flatten(project)

        let compoundId = UUID()
        let containerId = UUID()
        let create = CreateCompoundClipCommand(
            trackId: trackId, clipIds: [a.id, b.id],
            compoundId: compoundId, containerClipId: containerId
        )
        let createResult = try create.apply(to: &project)
        // Flattening the compound project must reproduce the same on-timeline
        // layout as the original (this is the preview/export parity basis).
        let compoundFlat = CompoundFlattener.flatten(project)
        // Clip count differs (container vs 2 children), but the on-timeline
        // span coverage is identical: every clip's absolute timeline range in
        // the baseline is covered by a clip in the compound flatten.
        let baselineSpans = Set(baseline.tracks[0].clips.map {
            "\(rounded($0.timelineRange.start))x\(rounded($0.timelineRange.duration))"
        })
        let compoundSpans = Set(compoundFlat.tracks[0].clips.map {
            "\(rounded($0.timelineRange.start))x\(rounded($0.timelineRange.duration))"
        })
        #expect(baselineSpans == compoundSpans)

        // Release (inverse) and confirm flatten still matches the baseline.
        let inverse = try create.invert(from: createResult)
        _ = try inverse.apply(to: &project)
        let restoredFlat = CompoundFlattener.flatten(project)
        let restoredSpans = Set(restoredFlat.tracks[0].clips.map {
            "\(rounded($0.timelineRange.start))x\(rounded($0.timelineRange.duration))"
        })
        #expect(restoredSpans == baselineSpans)
    }

    private func rounded(_ value: TimeInterval) -> Int {
        Int((value * 1_000_000).rounded())
    }
}
