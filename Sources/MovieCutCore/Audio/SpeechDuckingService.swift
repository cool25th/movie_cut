import Foundation

/// F-14 / CA-31(a): ducks every overlapping audio-track clip under a speech
/// clip's voiced intervals (silence-analysis complement). The PLAN is
/// platform-neutral and lives here — both view models consume it and keep
/// only selection guards, session dispatch, and status messages, so the
/// Mac and iOS passes cannot drift apart.
public enum SpeechDuckingService {

    /// Default silence-analysis threshold for ducking passes (dB).
    public static let defaultSilenceThresholdDB: Float = -40

    /// Default minimum silence duration for ducking passes (seconds).
    public static let defaultMinimumSilenceDuration: TimeInterval = 0.35

    /// The outcome of a ducking pass — each VM maps the cases onto its own
    /// status message and dispatches `SetAudioDuckingCommand` for `.ducked`.
    public enum Outcome: Equatable, Sendable {
        /// Ducking ranges per clip, plus how many voiced intervals drove them.
        case ducked(rangesByClip: [UUID: [TimeRange]], voiceIntervalCount: Int)
        /// The speech clip has no detectable voiced intervals.
        case noVoicedIntervals
        /// No audio-track clip overlaps the speech clip.
        case noOverlappingAudio
    }

    /// Computes the ducking plan for one speech clip against the project.
    public static func plan(
        project: Project,
        speechClip: Clip,
        asset: MediaAsset,
        duckLevel: Double = AudioDuckingPlanner.defaultDuckingLevel,
        thresholdDB: Float = defaultSilenceThresholdDB,
        minimumSilenceDuration: TimeInterval = defaultMinimumSilenceDuration
    ) async throws -> Outcome {
        let provider = SilenceDetectionProvider(
            silenceThresholdDB: thresholdDB,
            minimumSilenceDuration: minimumSilenceDuration
        )
        let analysis = try await provider.analyze(asset: asset, in: project)
        let silenceRanges = analysis.suggestions.flatMap { suggestion -> [TimeRange] in
            guard case .silenceRemoval(let ranges) = suggestion else { return [] }
            return ranges.compactMap { speechClip.timelineMapping(for: $0)?.timelineRange }
        }
        let voiceIntervals = AudioDuckingPlanner.voiceIntervals(
            speechTimelineRange: speechClip.timelineRange,
            silenceRangesInTimeline: silenceRanges
        )
        guard !voiceIntervals.isEmpty else { return .noVoicedIntervals }

        var rangesByClip: [UUID: [TimeRange]] = [:]
        for track in project.timeline.tracks where track.kind == .audio {
            for clip in track.clips
            where clip.id != speechClip.id && clip.timelineRange.overlaps(speechClip.timelineRange) {
                let ranges = AudioDuckingPlanner.duckingRanges(
                    forTarget: clip.timelineRange,
                    voiceIntervals: voiceIntervals
                )
                if !ranges.isEmpty {
                    rangesByClip[clip.id] = ranges
                }
            }
        }
        guard !rangesByClip.isEmpty else { return .noOverlappingAudio }
        return .ducked(rangesByClip: rangesByClip, voiceIntervalCount: voiceIntervals.count)
    }
}

extension Clip {
    /// Maps an asset-time range into timeline seconds through the clip's
    /// canonical mapping (rate/ramp aware), clamped to the clip's span.
    /// The single shared source for subtitle alignment, auto-highlights,
    /// and ducking — this used to live duplicated in both view models.
    public func timelineMapping(
        for sourceRange: TimeRange
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange)? {
        guard
            sourceRange.start.isFinite,
            sourceRange.duration.isFinite,
            sourceRange.duration > 0
        else {
            return nil
        }
        let sourceStart = max(sourceRange.start, self.sourceRange.start)
        let sourceEnd = min(sourceRange.end, self.sourceRange.end)
        guard sourceEnd > sourceStart else { return nil }
        guard let mapping = makeTimeMapping() else { return nil }
        let timelineStart = mapping.timelineTime(forSourceTime: sourceStart)
        let timelineEnd = min(timelineRange.end, mapping.timelineTime(forSourceTime: sourceEnd))
        guard timelineEnd > timelineStart else { return nil }
        return (
            sourceRange: TimeRange(start: sourceStart, duration: sourceEnd - sourceStart),
            timelineRange: TimeRange(start: timelineStart, duration: timelineEnd - timelineStart)
        )
    }
}
