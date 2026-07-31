import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for `SlipClipCommand` and `SlideClipCommand` (task 5.6,
/// requirement 8). These pin the command contracts:
///   - slip: only `sourceRange` moves; `timelineRange` and total length survive;
///   - slide: the target and neighbors move together, the target's `sourceRange`
///     is untouched, and total timeline length is preserved;
///   - both are a single undo unit (apply→invert→apply is an exact round-trip
///     for every affected clip), and both reuse the `CommandSupport`
///     locked-track guard (`ensureTrackIsEditable`).
@Suite("SlipClipCommand / SlideClipCommand")
struct SlipSlideCommandTests {
    private let tolerance = 1.0 / 30.0
    private let minimum: TimeInterval = 0.1

    // MARK: - Fixtures

    private func clip(
        id: UUID = UUID(),
        sourceDuration: TimeInterval,
        sourceStart: TimeInterval = 0,
        timelineDuration: TimeInterval? = nil,
        timelineStart: TimeInterval = 0,
        rate: Double = 1,
        kind: ClipKind = .video
    ) -> Clip {
        Clip(
            id: id,
            kind: kind,
            sourceRange: TimeRange(start: sourceStart, duration: sourceDuration),
            timelineRange: TimeRange(start: timelineStart, duration: timelineDuration ?? sourceDuration / max(rate, 0.25)),
            playbackRate: rate
        )
    }

    private func project(_ clips: [Clip], locked: Bool = false) -> (project: Project, trackId: UUID) {
        var track = Track(kind: .video, name: "V1", zIndex: 0, clips: clips)
        track.isLocked = locked
        let project = Project(name: "Test", timeline: Timeline(tracks: [track]))
        return (project, track.id)
    }

    // MARK: - SlipClipCommand

    @Test("Slip applies the new source range and leaves the timeline range untouched")
    func slipAppliesSourceOnly() throws {
        let clipId = UUID()
        let c = clip(id: clipId, sourceDuration: 6, sourceStart: 2, timelineDuration: 6, timelineStart: 1)
        let originalTimeline = c.timelineRange
        var (proj, trackId) = project([c])

        // Pre-compute via the pure math (as the view-model does), then commit.
        let slipResult = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 3, assetDuration: 12, minimumSourceDuration: minimum
        ))
        let command = SlipClipCommand(
            clipId: clipId,
            trackId: trackId,
            newSourceRange: slipResult.source,
            previousSourceRange: c.sourceRange
        )

        let result = try command.apply(to: &proj)
        let applied = proj.timeline.tracks[0].clips[0]
        #expect(abs(applied.sourceRange.start - 5.0) <= tolerance)
        #expect(abs(applied.sourceRange.duration - 6.0) <= tolerance)
        // Timeline range is invariant under slip.
        #expect(abs(applied.timelineRange.start - originalTimeline.start) <= tolerance)
        #expect(abs(applied.timelineRange.duration - originalTimeline.duration) <= tolerance)
        // Single affected clip id surfaced for the undo unit.
        #expect(result.affectedClipIds == [clipId])
    }

    @Test("Slip is an exact round-trip via invert")
    func slipInvertsExactly() throws {
        let clipId = UUID()
        let c = clip(id: clipId, sourceDuration: 4, sourceStart: 1, timelineDuration: 4, timelineStart: 0)
        var (proj, trackId) = project([c])

        let slipResult = try #require(ClipTrimMath.slip(
            clip: c, sourceDelta: 2, assetDuration: 10, minimumSourceDuration: minimum
        ))
        let command = SlipClipCommand(
            clipId: clipId,
            trackId: trackId,
            newSourceRange: slipResult.source,
            previousSourceRange: c.sourceRange
        )

        let result = try command.apply(to: &proj)
        let undo = try command.invert(from: result)
        _ = try undo.apply(to: &proj)

        let restored = proj.timeline.tracks[0].clips[0]
        #expect(abs(restored.sourceRange.start - c.sourceRange.start) <= tolerance)
        #expect(abs(restored.sourceRange.duration - c.sourceRange.duration) <= tolerance)
        #expect(abs(restored.timelineRange.start - c.timelineRange.start) <= tolerance)
        #expect(abs(restored.timelineRange.duration - c.timelineRange.duration) <= tolerance)
    }

    @Test("Slip is rejected on a locked track (guard reused from CommandSupport)")
    func slipRejectsLockedTrack() {
        let clipId = UUID()
        let c = clip(id: clipId, sourceDuration: 4, timelineDuration: 4)
        var (proj, _) = project([c], locked: true)

        let command = SlipClipCommand(
            clipId: clipId,
            newSourceRange: TimeRange(start: 2, duration: 4)
        )

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &proj)
        }
        // No mutation occurred.
        #expect(abs(proj.timeline.tracks[0].clips[0].sourceRange.start - 0.0) <= tolerance)
    }

    @Test("Slip rejects a negative-duration source range")
    func slipRejectsNegativeDuration() {
        let clipId = UUID()
        let c = clip(id: clipId, sourceDuration: 4, timelineDuration: 4)
        var (proj, _) = project([c])

        let command = SlipClipCommand(
            clipId: clipId,
            newSourceRange: TimeRange(start: 5, duration: -1)
        )

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &proj)
        }
    }

    // MARK: - SlideClipCommand

    @Test("Slide moves the target and adjusts both neighbors, keeping total length")
    func slideAppliesTargetAndNeighbors() throws {
        let aId = UUID(), bId = UUID(), cId = UUID()
        let a = clip(id: aId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(id: bId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let c = clip(id: cId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 8)
        var (proj, trackId) = project([a, b, c])
        let originalTotal = proj.timeline.duration

        let slideResult = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))
        let target = SlideClipCommand.Placement(
            clipId: slideResult.target.clipId, timeline: slideResult.target.timeline
        )
        let neighbors = slideResult.neighbors.map {
            SlideClipCommand.Placement(clipId: $0.clipId, timeline: $0.timeline)
        }
        let command = SlideClipCommand(trackId: trackId, target: target, neighbors: neighbors)

        let result = try command.apply(to: &proj)

        let applied = proj.timeline.tracks[0].clips
        let movedB = applied.first { $0.id == bId }!
        // B moves to [5,9] and keeps its 4s span...
        #expect(abs(movedB.timelineRange.start - 5.0) <= tolerance)
        #expect(abs(movedB.timelineRange.duration - 4.0) <= tolerance)
        // ...and B's own source range is untouched (slide preserves it).
        #expect(abs(movedB.sourceRange.start - 0.0) <= tolerance)
        #expect(abs(movedB.sourceRange.duration - 4.0) <= tolerance)

        let movedA = applied.first { $0.id == aId }!
        let movedC = applied.first { $0.id == cId }!
        #expect(abs(movedA.timelineRange.duration - 5.0) <= tolerance) // A grows [0,5]
        #expect(abs(movedC.timelineRange.start - 9.0) <= tolerance)    // C shrinks to [9,12]
        #expect(abs(movedC.timelineRange.duration - 3.0) <= tolerance)

        // Total length is invariant.
        #expect(abs(proj.timeline.duration - originalTotal) <= tolerance)
        // All three clips belong to the single undo unit.
        #expect(result.affectedClipIds == [aId, bId, cId])
    }

    @Test("Slide is an exact round-trip via invert for every affected clip")
    func slideInvertsExactly() throws {
        let aId = UUID(), bId = UUID(), cId = UUID()
        let a = clip(id: aId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 0)
        let b = clip(id: bId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 4)
        let c = clip(id: cId, sourceDuration: 4, sourceStart: 0, timelineDuration: 4, timelineStart: 8)
        let originals = [a, b, c]
        var (proj, trackId) = project(originals)

        let slideResult = try #require(ClipTrimMath.slide(
            clips: originals, targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))
        let target = SlideClipCommand.Placement(
            clipId: slideResult.target.clipId, timeline: slideResult.target.timeline
        )
        let neighbors = slideResult.neighbors.map {
            SlideClipCommand.Placement(clipId: $0.clipId, timeline: $0.timeline)
        }
        var previous: [UUID: Clip] = [:]
        for clip in originals { previous[clip.id] = clip }
        let command = SlideClipCommand(trackId: trackId, target: target, neighbors: neighbors, previousClips: previous)

        let result = try command.apply(to: &proj)
        let undo = try command.invert(from: result)
        _ = try undo.apply(to: &proj)

        // After undo every clip is byte-identical to its pre-slide state
        // (timeline range AND source range — slide must not corrupt neighbors'
        // source ranges on the way out either).
        let restored = proj.timeline.tracks[0].clips
        for original in originals {
            let r = restored.first { $0.id == original.id }!
            #expect(abs(r.timelineRange.start - original.timelineRange.start) <= tolerance)
            #expect(abs(r.timelineRange.duration - original.timelineRange.duration) <= tolerance)
            #expect(abs(r.sourceRange.start - original.sourceRange.start) <= tolerance)
            #expect(abs(r.sourceRange.duration - original.sourceRange.duration) <= tolerance)
        }
    }

    @Test("Slide is rejected on a locked track (guard reused from CommandSupport)")
    func slideRejectsLockedTrack() throws {
        let aId = UUID(), bId = UUID()
        let a = clip(id: aId, sourceDuration: 4, timelineDuration: 4, timelineStart: 0)
        let b = clip(id: bId, sourceDuration: 4, timelineDuration: 4, timelineStart: 4)
        var (proj, _) = project([a, b], locked: true)

        let slideResult = try #require(ClipTrimMath.slide(
            clips: [a, b], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))
        let target = SlideClipCommand.Placement(
            clipId: slideResult.target.clipId, timeline: slideResult.target.timeline
        )
        let command = SlideClipCommand(trackId: nil, target: target, neighbors: [])

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &proj)
        }
        // No mutation occurred: B is still at [4,8].
        let bNow = proj.timeline.tracks[0].clips.first { $0.id == bId }!
        #expect(abs(bNow.timelineRange.start - 4.0) <= tolerance)
    }

    @Test("Slide with a neighbor placement missing from the track rejects atomically")
    func slideRejectsMissingNeighbor() throws {
        let aId = UUID(), bId = UUID(), ghostId = UUID()
        let a = clip(id: aId, sourceDuration: 4, timelineDuration: 4, timelineStart: 0)
        let b = clip(id: bId, sourceDuration: 4, timelineDuration: 4, timelineStart: 4)
        var (proj, trackId) = project([a, b])

        // Claim a neighbor that is not on the track; apply must reject without a
        // half-applied state.
        let target = SlideClipCommand.Placement(
            clipId: bId, timeline: TimeRange(start: 5, duration: 4)
        )
        let ghostNeighbor = SlideClipCommand.Placement(
            clipId: ghostId, timeline: TimeRange(start: 0, duration: 5)
        )
        let command = SlideClipCommand(trackId: trackId, target: target, neighbors: [ghostNeighbor])

        #expect(throws: EditorCommandError.self) {
            _ = try command.apply(to: &proj)
        }
        // No mutation occurred: B is still at [4,8].
        let bNow = proj.timeline.tracks[0].clips.first { $0.id == bId }!
        #expect(abs(bNow.timelineRange.start - 4.0) <= tolerance)
    }

    @Test("Slide at 2x preserves the target's source range and rendered span")
    func slideAt2xPreservesSourceAndSpan() throws {
        let aId = UUID(), bId = UUID(), cId = UUID()
        let a = clip(id: aId, sourceDuration: 5, timelineDuration: 5, timelineStart: 0)
        // 2x clip: source 10 -> rendered timeline 5.
        let b = clip(id: bId, sourceDuration: 10, timelineDuration: 5, timelineStart: 5, rate: 2)
        let c = clip(id: cId, sourceDuration: 5, timelineDuration: 5, timelineStart: 10)
        var (proj, trackId) = project([a, b, c])

        let slideResult = try #require(ClipTrimMath.slide(
            clips: [a, b, c], targetIndex: 1, timelineDelta: 1, minimumDuration: minimum
        ))
        let target = SlideClipCommand.Placement(
            clipId: slideResult.target.clipId, timeline: slideResult.target.timeline
        )
        let neighbors = slideResult.neighbors.map {
            SlideClipCommand.Placement(clipId: $0.clipId, timeline: $0.timeline)
        }
        let command = SlideClipCommand(trackId: trackId, target: target, neighbors: neighbors)

        _ = try command.apply(to: &proj)
        let movedB = proj.timeline.tracks[0].clips.first { $0.id == bId }!
        #expect(abs(movedB.timelineRange.duration - 5.0) <= tolerance)
        #expect(abs(movedB.timelineRange.start - 6.0) <= tolerance)
        // The 2x clip's source range is preserved by slide.
        #expect(abs(movedB.sourceRange.duration - 10.0) <= tolerance)
    }
}
