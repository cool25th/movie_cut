import Foundation
import Testing
@testable import MovieCutCore

/// Task 7.3 / requirement 2.4 — undo round-trip verification for the
/// destructive editing operations covered by the parity matrix
/// (requirement 2.1: split/trim/move/delete/ripple; requirement 2.2:
/// reverse/freeze).
///
/// This is a MODEL-LEVEL state comparison, not a pixel comparison. For each
/// destructive operation it captures a whole-`Project` value snapshot before
/// the edit, applies the command through `EditorSession.dispatch`, then undoes
/// and asserts `Project ==` the pre-edit snapshot. `Project: Equatable` is a
/// synthesized value comparison over every timeline/library/setting field, so
/// equality here means the entire editing state round-tripped exactly.
///
/// `EditorSession` undo is snapshot-based (it restores whole-project value
/// snapshots rather than relying on each command's `invert()`), so a passing
/// round-trip here is direct evidence that the snapshot captured before the
/// destructive edit is the state restored after undo — the property
/// requirement 2.4 requires. Each test also asserts the edit changed state
/// first, so the round-trip cannot pass vacuously.
@Suite("Undo round-trip parity (requirement 2.4)")
struct UndoRoundTripTests {
    // MARK: - Trim

    @Test("trim end undo restores the exact pre-trim project")
    func trimEndUndoRestoresExactState() async throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let track = makeTrack(clips: [clip])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let before = await session.snapshot()

        // Destructive trim: shrink the clip from [0,4] to [0,1].
        try await session.dispatch(TrimClipCommand(
            clipId: clip.id,
            trackId: track.id,
            newSourceRange: TimeRange(start: 0, duration: 1),
            newTimelineRange: TimeRange(start: 0, duration: 1)
        ))

        let after = await session.snapshot()
        #expect(after != before, "trim did not change project state")
        #expect(
            after.timeline.tracks[0].clips.first?.timelineRange.duration == 1,
            "trim did not shorten the clip"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after trim did not restore the exact pre-trim Project snapshot"
        )
    }

    // MARK: - Move

    @Test("move clip undo restores the exact pre-move project")
    func moveClipUndoRestoresExactState() async throws {
        // The main (first) video track is magnetic, so a same-track move of a
        // single clip is compacted back to start=0 and has no observable
        // effect. Moving the clip to a SECOND (non-magnetic) video track
        // preserves the requested timeline start, which is the observable move
        // the parity scenario exercises.
        let mainTrack = makeTrack(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, clips: [])
        let overlayTrack = makeTrack(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            name: "Overlay",
            zIndex: 1
        )
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let session = EditorSession(project: makeProject(tracks: [mainTrack, overlayTrack]))

        // Seed the overlay track with the clip via AddClipCommand so the
        // subsequent move has a real source location.
        try await session.dispatch(AddClipCommand(trackId: overlayTrack.id, clip: clip))
        let before = await session.snapshot()
        #expect(before.timeline.tracks[1].clips.first?.timelineRange.start == 0)

        // Destructive cross-track move: relocate the clip on the non-magnetic
        // overlay track from start=0 to start=8.
        try await session.dispatch(MoveClipCommand(
            clipId: clip.id,
            sourceTrackId: overlayTrack.id,
            targetTrackId: overlayTrack.id,
            newTimelineRange: TimeRange(start: 8, duration: 4)
        ))

        let after = await session.snapshot()
        #expect(after != before, "move did not change project state")
        #expect(
            after.timeline.tracks[1].clips.first?.timelineRange.start == 8,
            "move did not relocate the clip"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after move did not restore the exact pre-move Project snapshot"
        )
    }

    // MARK: - Ripple delete

    @Test("ripple delete undo restores the exact pre-delete project")
    func rippleDeleteUndoRestoresExactState() async throws {
        let clipA = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let clipB = makeClip(
            sourceRange: TimeRange(start: 4, duration: 4),
            timelineRange: TimeRange(start: 4, duration: 4)
        )
        let track = makeTrack(clips: [clipA, clipB])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let before = await session.snapshot()

        // Destructive ripple delete: removes clipA and closes the gap, shifting
        // clipB left by 4.
        try await session.dispatch(RippleDeleteCommand(clipId: clipA.id))

        let after = await session.snapshot()
        #expect(after != before, "ripple delete did not change project state")
        #expect(
            after.timeline.tracks[0].clips.count == 1,
            "ripple delete did not remove one clip"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after ripple delete did not restore the exact pre-delete Project snapshot"
        )
    }

    // MARK: - Normal delete (gap preserved)

    @Test("normal delete undo restores the exact pre-delete project")
    func normalDeleteUndoRestoresExactState() async throws {
        let clipA = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let clipB = makeClip(
            sourceRange: TimeRange(start: 4, duration: 4),
            timelineRange: TimeRange(start: 8, duration: 4)
        )
        let track = makeTrack(clips: [clipA, clipB])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let before = await session.snapshot()

        // Destructive normal delete: removes clipA but leaves clipB at start=8
        // (a real on-timeline gap), unlike ripple.
        try await session.dispatch(DeleteClipCommand(clipId: clipA.id))

        let after = await session.snapshot()
        #expect(after != before, "normal delete did not change project state")
        #expect(
            after.timeline.tracks[0].clips.count == 1,
            "normal delete did not remove one clip"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after normal delete did not restore the exact pre-delete Project snapshot"
        )
    }

    // MARK: - Reverse playback

    @Test("reverse playback undo restores the exact pre-reverse project")
    func reverseUndoRestoresExactState() async throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let track = makeTrack(clips: [clip])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let before = await session.snapshot()
        #expect(
            before.timeline.tracks[0].clips.first?.isReversed == false,
            "fixture clip should start non-reversed"
        )

        // Destructive reverse: toggles isReversed on the clip.
        try await session.dispatch(ReverseClipCommand(clipId: clip.id))

        let after = await session.snapshot()
        #expect(after != before, "reverse did not change project state")
        #expect(
            after.timeline.tracks[0].clips.first?.isReversed == true,
            "reverse did not flip isReversed"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after reverse did not restore the exact pre-reverse Project snapshot"
        )
    }

    // MARK: - Freeze frame

    @Test("freeze frame undo restores the exact pre-freeze project")
    func freezeFrameUndoRestoresExactState() async throws {
        let clip = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let track = makeTrack(clips: [clip])
        let session = EditorSession(project: makeProject(tracks: [track]))

        let before = await session.snapshot()
        let beforeClipCount = before.timeline.tracks[0].clips.count

        // Destructive freeze: splits the clip into a leading segment, a 2.0s
        // freeze hold, and a trailing segment (3 clips from 1).
        try await session.dispatch(FreezeFrameCommand(
            clipId: clip.id,
            freezeTime: 1.0,
            freezeDuration: 2.0
        ))

        let after = await session.snapshot()
        #expect(after != before, "freeze did not change project state")
        #expect(
            after.timeline.tracks[0].clips.count == beforeClipCount + 2,
            "freeze did not split into leading/freeze/trailing clips"
        )

        try await session.undo()
        let restored = await session.snapshot()
        #expect(
            restored == before,
            "undo after freeze did not restore the exact pre-freeze Project snapshot"
        )
    }

    // MARK: - Chained destructive edits

    @Test("a chain of destructive edits undoes stepwise to exact prior states")
    func chainedDestructiveEditsUndoStepwise() async throws {
        // One fixture session subjected to a realistic sequence of destructive
        // parity operations. Each undo must restore the exact prior snapshot,
        // proving no destructive command leaks partial state that a later undo
        // cannot recover (the regression class requirement 2.4 guards).
        let mainTrack = makeTrack(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000001")!,
            clips: []
        )
        let overlayTrack = makeTrack(
            id: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
            name: "Overlay",
            zIndex: 1
        )
        let clipA = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 0, duration: 4)
        )
        let clipB = makeClip(
            sourceRange: TimeRange(start: 0, duration: 4),
            timelineRange: TimeRange(start: 4, duration: 4)
        )
        let session = EditorSession(project: makeProject(tracks: [mainTrack, overlayTrack]))
        // Seed both clips onto the non-magnetic overlay track so the move in
        // the chain is observable (the main track would compact it away).
        try await session.dispatch(AddClipCommand(trackId: overlayTrack.id, clip: clipA))
        try await session.dispatch(AddClipCommand(trackId: overlayTrack.id, clip: clipB))

        let original = await session.snapshot()
        var states: [Project] = [original]

        // Trim clipB's end, then move it across the timeline, then reverse it,
        // then ripple-delete clipA. Each is destructive and covered by a parity
        // scenario above. All run on the non-magnetic overlay track so the move
        // is observable.
        let commands: [any EditorCommand] = [
            TrimClipCommand(
                clipId: clipB.id,
                trackId: overlayTrack.id,
                newSourceRange: TimeRange(start: 0, duration: 2),
                newTimelineRange: TimeRange(start: 4, duration: 2)
            ),
            MoveClipCommand(
                clipId: clipB.id,
                sourceTrackId: overlayTrack.id,
                targetTrackId: overlayTrack.id,
                newTimelineRange: TimeRange(start: 8, duration: 2)
            ),
            ReverseClipCommand(clipId: clipB.id),
            RippleDeleteCommand(clipId: clipA.id)
        ]

        for command in commands {
            try await session.dispatch(command)
            states.append(await session.snapshot())
        }
        let final = states.last!
        #expect(final != original, "destructive chain did not change project state")

        // Undo stepwise: each undo must restore the exact previous snapshot.
        for index in stride(from: states.count - 1, through: 1, by: -1) {
            try await session.undo()
            #expect(
                await session.snapshot() == states[index - 1],
                "undo step \(index) did not restore the exact prior Project snapshot"
            )
        }
        #expect(await session.snapshot() == original)
    }

    // MARK: - Builders

    private func makeProject(tracks: [Track]) -> Project {
        Project(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!,
            name: "Undo Round-Trip Project",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            appVersion: "0.1.0",
            schemaVersion: 1,
            mediaLibrary: MediaLibrary(),
            timeline: Timeline(
                id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!,
                frameRate: Rational(numerator: 30, denominator: 1),
                canvasSize: CGSize(width: 1920, height: 1080),
                aspectRatio: .landscape16x9,
                tracks: tracks,
                markers: []
            ),
            markers: [],
            canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
            exportSettings: ExportSettings(resolution: .p1080, frameRate: .fps30, codec: .h264, audioCodec: .aac)
        )
    }

    private func makeTrack(
        id: UUID = UUID(),
        kind: TrackKind = .video,
        name: String = "Video 1",
        zIndex: Int = 0,
        clips: [Clip] = []
    ) -> Track {
        Track(id: id, kind: kind, name: name, zIndex: zIndex, clips: clips)
    }

    private func makeClip(
        id: UUID = UUID(),
        assetId: UUID? = nil,
        kind: ClipKind = .video,
        sourceRange: TimeRange = TimeRange(start: 0, duration: 4),
        timelineRange: TimeRange = TimeRange(start: 0, duration: 4)
    ) -> Clip {
        Clip(
            id: id,
            assetId: assetId,
            kind: kind,
            sourceRange: sourceRange,
            timelineRange: timelineRange,
            effects: []
        )
    }
}
