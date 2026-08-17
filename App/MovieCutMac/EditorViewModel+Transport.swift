import Foundation
import MovieCutCore

/// Transport boundary — second extraction out of the EditorViewModel body
/// (boundary roadmap: selection → transport → inspector → …).
///
/// Pure move (2026-08-17): play/pause toggle, J/K/L shuttle, frame/seconds
/// seek, timeline zoom, and the playback→playhead sync helper, relocated
/// verbatim (no new logic). The shuttle stored state (`shuttleDirection`,
/// `shuttleTapCount`) and zoom constants stay in the main file as stored
/// properties; the constants are internal so this extension drives them.
extension EditorViewModel {
    func togglePlayPause() {
        playbackEngine.togglePlayPause()
    }

    // MARK: - J/K/L shuttle (S9)

    /// Shuttle direction. Kept in the App layer (not Core) because it couples to
    /// the live playback engine. `ShuttleRate` (Core) holds the pure step math.
    enum ShuttleDirection: Sendable, Equatable {
        case stopped
        case forward
        case reverse
    }

    /// L: forward play. Repeated taps raise the speed step (1× → 2× → 4×).
    func shuttleForward() {
        if shuttleDirection != .forward {
            shuttleDirection = .forward
            shuttleTapCount = 0
        }
        shuttleTapCount += 1
        let rate = ShuttleRate.forwardStep(forTapCount: shuttleTapCount)
        if !playbackEngine.isPlaying { playbackEngine.play() }
        playbackEngine.setRate(rate)
    }

    /// K: stop. Pauses and resets the shuttle step so the next L/J starts at 1×.
    func shuttleStop() {
        shuttleDirection = .stopped
        shuttleTapCount = 0
        playbackEngine.setRate(1.0)
        playbackEngine.pause()
    }

    /// J: reverse. AVPlayer cannot play at a negative rate, so this drives a
    /// back-step cadence proportional to the speed step (faster on repeated
    /// taps) rather than true reverse playback. Documented limitation of the
    /// JKL approximation (S9). True reverse playback needs a pre-rendered file.
    func shuttleReverse() {
        if shuttleDirection != .reverse {
            shuttleDirection = .reverse
            shuttleTapCount = 0
        }
        shuttleTapCount += 1
        playbackEngine.pause()
        shuttleDirection = .reverse
        // Back-step a chunk proportional to the speed step; a repeating Task
        // would be needed for continuous reverse — kept as discrete steps here.
        let stepSeconds = TimeInterval(ShuttleRate.forwardStep(forTapCount: shuttleTapCount))
        seekBySeconds(-stepSeconds)
    }

    func seekByFrames(_ frameCount: Int) {
        let frameDuration = 1.0 / 30.0

        if playbackEngine.playerItem != nil {
            let nextPlaybackTime = playbackEngine.currentTime + Double(frameCount) * frameDuration
            playbackEngine.seek(to: nextPlaybackTime)
            syncTimelinePlayhead(to: playbackEngine.currentTime)
            return
        }

        let duration = max(0, currentProject.timeline.duration)
        playheadTime = min(max(0, playheadTime + Double(frameCount) * frameDuration), duration)
    }

    func seekBySeconds(_ seconds: TimeInterval) {
        if playbackEngine.playerItem != nil {
            let nextPlaybackTime = playbackEngine.currentTime + seconds
            playbackEngine.seek(to: max(0, nextPlaybackTime))
            syncTimelinePlayhead(to: playbackEngine.currentTime)
            return
        }

        let duration = max(0, currentProject.timeline.duration)
        playheadTime = min(max(0, playheadTime + seconds), duration)
    }

    func zoomTimelineIn() {
        timelineZoom = min(Self.maximumTimelineZoom, timelineZoom + Self.timelineZoomStep)
    }

    func zoomTimelineOut() {
        timelineZoom = max(Self.minimumTimelineZoom, timelineZoom - Self.timelineZoomStep)
    }

    private func syncTimelinePlayhead(to playbackTime: TimeInterval) {
        // The playback engine reports composition timeline time, which is already
        // the project timeline domain (see PreviewPanel's
        // `.onChange(of: playbackEngine.currentTime)` invariant). Feeding it
        // through `timelineTime(forSourceTime:)` — which expects absolute source
        // seconds — would double-convert it and warp the playhead on any non-1x
        // or speed-ramp clip (e.g. a 2x clip's 1s point snapping back to ~0.5s).
        // Just clamp to the project duration, the same as the no-selection path.
        playheadTime = min(max(0, playbackTime), max(0, currentProject.timeline.duration))
    }
}
