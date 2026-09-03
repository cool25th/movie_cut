import Foundation
import Testing
@testable import MovieCutCore

/// CODEX-20: RemoveTrackCommand silently skipped the lock guard every other
/// mutating command routes through — the track-management sheet's
/// swipe-delete destroyed a locked track and every clip on it. Removal now
/// rejects with trackLocked like SlideClip/trim/append-effect.
@Suite("RemoveTrackCommand lock guard (CODEX-20)")
struct RemoveTrackLockGuardTests {
    private func makeProject(locked: Bool) -> Project {
        var project = Project(name: "lock-remove")
        var track = Track(kind: .video, name: "V", zIndex: 0)
        track.isLocked = locked
        track.clips = [
            Clip(
                assetId: UUID(),
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 1),
                timelineRange: TimeRange(start: 0, duration: 1)
            )
        ]
        project.timeline.tracks = [track]
        return project
    }

    @Test("a LOCKED track is rejected — the track and its clips survive")
    func lockedTrackRejected() throws {
        var project = makeProject(locked: true)
        let lockedTrack = project.timeline.tracks[0]

        #expect(throws: EditorCommandError.trackLocked(lockedTrack.id)) {
            try RemoveTrackCommand(track: lockedTrack).apply(to: &project)
        }
        #expect(project.timeline.tracks.count == 1,
                "the locked track must survive the removal attempt")
        #expect(project.timeline.tracks[0].clips.count == 1,
                "every clip on the locked track must survive")
    }

    @Test("an UNLOCKED track still removes normally")
    func unlockedTrackRemoves() throws {
        var project = makeProject(locked: false)
        let track = project.timeline.tracks[0]

        try RemoveTrackCommand(track: track).apply(to: &project)
        #expect(project.timeline.tracks.isEmpty)
    }

    @Test("the session path surfaces the rejection without mutating state")
    func sessionPathRejectsCleanly() async throws {
        let session = EditorSession(project: makeProject(locked: true))
        let lockedTrack = await session.snapshot().timeline.tracks[0]

        await #expect(throws: EditorCommandError.trackLocked(lockedTrack.id)) {
            try await session.dispatch(RemoveTrackCommand(track: lockedTrack))
        }
        let after = await session.snapshot()
        #expect(after.timeline.tracks.count == 1)
        // A rejected command must not pollute the undo stack — undo on the
        // now-empty stack throws nothingToUndo (the pre-rejection state IS
        // the current state; there is nothing to step back to).
        await #expect(throws: EditorCommandError.nothingToUndo) {
            try await session.undo()
        }
        let postUndo = await session.snapshot()
        #expect(postUndo.timeline.tracks.count == 1,
                "undo after a rejected removal must not resurrect an earlier state")
    }
}
