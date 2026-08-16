import Foundation
import MovieCutCore

/// Timeline-editing boundary — first extraction out of the EditorViewModel
/// body (EXECUTION_PLAN Inc 2).
///
/// Pure move: selection accessors, playhead cursor navigation, and
/// clip-boundary jumps, relocated verbatim (access levels preserved, no new
/// logic). The heavier edit operations (trim/move/split dispatch, clipboard,
/// group selection, scrub debounce) remain in the main file because they are
/// blocked by private shared infrastructure (`session`, `apply`,
/// `refreshFromSession`, stored scrub state) — see
/// docs/SESSION_HANDOFF_CURRENT.md for the blocker map; this file grows as
/// later boundary passes resolve those.
extension EditorViewModel {
    private struct TimelineNavigationPoint {
        var time: TimeInterval
        var clipId: UUID
        var trackIndex: Int
        var clipIndex: Int
        var isEnd: Bool
    }

    var selectedClipId: UUID? {
        get {
            for track in currentProject.timeline.tracks {
                if let clipId = track.clips.first(where: { selectedClipIds.contains($0.id) })?.id {
                    return clipId
                }
            }
            return selectedClipIds.first
        }
        set {
            if let newValue {
                selectedClipIds = [newValue]
            } else {
                selectedClipIds = []
            }
        }
    }

    var selectedClip: Clip? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == selectedClipId }
    }

    var hasSelectedClips: Bool {
        !selectedClipIds.isEmpty
    }

    var canSplitSelectedClip: Bool {
        guard let selectedClip else { return false }
        return selectedClip.timelineRange.contains(playheadTime)
    }

    var selectedClipTrack: Track? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == selectedClipId }
        }
    }

    var selectedClipTrackId: UUID? {
        selectedClipTrack?.id
    }

    var visibleTimelineDuration: TimeInterval {
        max(10, currentProject.timeline.duration, playheadTime)
    }

    /// True when the current selection can be linked into a group.
    var canGroupSelectedClips: Bool {
        selectedClipIds.count >= 2
    }

    func snapPlayheadToSelectedClipStart() {
        guard let selectedClip else { return }
        scrubPlayhead(to: selectedClip.timelineRange.start)
    }

    func snapPlayheadToSelectedClipEnd() {
        guard let selectedClip else { return }
        scrubPlayhead(to: selectedClip.timelineRange.end)
    }

    func jumpToPreviousClipBoundary() {
        guard let point = timelineNavigationPoints()
            .last(where: { $0.time < playheadTime - 0.001 })
        else {
            return
        }

        selectedClipId = point.clipId
        scrubPlayhead(to: point.time)
    }

    func jumpToNextClipBoundary() {
        guard let point = timelineNavigationPoints()
            .first(where: { $0.time > playheadTime + 0.001 })
        else {
            return
        }

        selectedClipId = point.clipId
        scrubPlayhead(to: point.time)
    }

    private func timelineNavigationPoints() -> [TimelineNavigationPoint] {
        var points: [TimelineNavigationPoint] = []

        for (trackIndex, track) in currentProject.timeline.tracks.enumerated() {
            for (clipIndex, clip) in track.clips.enumerated() {
                points.append(
                    TimelineNavigationPoint(
                        time: clip.timelineRange.start,
                        clipId: clip.id,
                        trackIndex: trackIndex,
                        clipIndex: clipIndex,
                        isEnd: false
                    )
                )
                points.append(
                    TimelineNavigationPoint(
                        time: clip.timelineRange.end,
                        clipId: clip.id,
                        trackIndex: trackIndex,
                        clipIndex: clipIndex,
                        isEnd: true
                    )
                )
            }
        }

        return points.sorted {
            if $0.time != $1.time {
                return $0.time < $1.time
            }
            if $0.trackIndex != $1.trackIndex {
                return $0.trackIndex < $1.trackIndex
            }
            if $0.clipIndex != $1.clipIndex {
                return $0.clipIndex < $1.clipIndex
            }
            return !$0.isEnd && $1.isEnd
        }
    }
}
