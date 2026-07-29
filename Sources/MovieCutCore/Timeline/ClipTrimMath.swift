import Foundation

/// Pure, clip-agnostic trim calculation shared by the keyboard and drag trim
/// paths so they always agree on the source/timeline ranges for any speed or
/// ramp (Step 5 of the core-editing repair handoff).
///
/// Before this, the keyboard path (`EditorViewModel.trimSelectedClip*ToPlayhead`)
/// computed source ranges via `ClipTimeMapping`, while the drag path
/// (`TimelineView.leftTrimGesture`/`rightTrimGesture`) assumed timeline 1s ==
/// source 1s and never consulted the mapping. Now both call this function.
public enum ClipTrimMath {
    /// Which edge of the clip is being trimmed.
    public enum TrimEdge: Sendable, Equatable {
        case start
        case end
    }

    /// Computes the validated new source and timeline ranges for a trim.
    ///
    /// - Parameters:
    ///   - clip: the clip being trimmed (its `sourceRange`/`timelineRange`/
    ///     `playbackRate`/`speedRampPoints`/`kind` define the mapping).
    ///   - edge: `.start` or `.end`.
    ///   - targetTimelineTime: the absolute timeline time the user dragged/
    ///     moved the playhead to.
    ///   - assetDuration: the source asset's real duration for video/audio
    ///     clips, used to guard against trimming the source beyond the asset.
    ///     Pass `nil` for image clips (unbounded extension allowed).
    ///   - minimumDuration: the minimum allowed timeline duration.
    /// - Returns: the new `(source, timeline)` ranges, or `nil` if the trim is
    ///   invalid (target outside the clip, below minimum duration, degenerate
    ///   mapping). Callers ignore `nil` (no commit, no preview change).
    public static func compute(
        clip: Clip,
        edge: TrimEdge,
        targetTimelineTime: TimeInterval,
        assetDuration: TimeInterval?,
        minimumDuration: TimeInterval
    ) -> (source: TimeRange, timeline: TimeRange)? {
        guard targetTimelineTime.isFinite else { return nil }
        guard let mapping = clip.makeTimeMapping() else { return nil }

        let rendered = mapping.renderedTimelineDuration
        guard rendered.isFinite, rendered > 0 else { return nil }

        switch edge {
        case .start:
            return computeStartTrim(
                clip: clip,
                mapping: mapping,
                targetTimelineTime: targetTimelineTime,
                assetDuration: assetDuration,
                minimumDuration: minimumDuration
            )
        case .end:
            return computeEndTrim(
                clip: clip,
                mapping: mapping,
                targetTimelineTime: targetTimelineTime,
                assetDuration: assetDuration,
                minimumDuration: minimumDuration
            )
        }
    }

    // MARK: - Internals

    private static func computeStartTrim(
        clip: Clip,
        mapping: ClipTimeMapping,
        targetTimelineTime: TimeInterval,
        assetDuration: TimeInterval?,
        minimumDuration: TimeInterval
    ) -> (source: TimeRange, timeline: TimeRange)? {
        let timelineStart = clip.timelineRange.start
        let timelineEnd = clip.timelineRange.end

        // Clamp target into the trimmable start region: must leave a minimum
        // duration at the end, and cannot start after the current end.
        let maxStart = timelineEnd - minimumDuration
        guard maxStart > timelineStart else { return nil }
        let clampedTarget = min(max(targetTimelineTime, timelineStart), maxStart)
        let newDuration = timelineEnd - clampedTarget
        guard newDuration >= minimumDuration else { return nil }

        // Map the new timeline start to the source time played there. The
        // mapping is reverse-aware, but which source edge this maps to depends
        // on playback direction, so the range assembly must branch.
        let mappedSource = mapping.sourceTime(forTimelineTime: clampedTarget)
        guard mappedSource.isFinite else { return nil }

        if clip.isReversed {
            // Reverse: the timeline start plays sourceRange.end and source
            // walks down as the timeline advances. A start trim moves the
            // opening play point inward, so the mapped source becomes the
            // clip's NEW source end while the start (.start) stays fixed.
            // Without this branch the start trim would move sourceRange.start
            // and keep exactly the frames the user wanted to discard.
            let newSourceEnd = mappedSource
            guard newSourceEnd > clip.sourceRange.start else { return nil }
            let newSourceDuration = newSourceEnd - clip.sourceRange.start
            guard newSourceDuration > 0 else { return nil }
            return (
                source: TimeRange(start: clip.sourceRange.start, duration: newSourceDuration),
                timeline: TimeRange(start: clampedTarget, duration: newDuration)
            )
        }

        // Forward: the new timeline start maps to a new source start.
        let newSourceStart = mappedSource
        // Guard source start: cannot go before 0.
        guard newSourceStart >= 0 else { return nil }
        // Guard source start against the clip's own source range (the new start
        // must be within the existing source range; we don't extend the start
        // backward past the asset here).
        guard newSourceStart < clip.sourceRange.end else { return nil }

        let newSourceDuration = clip.sourceRange.end - newSourceStart
        guard newSourceDuration > 0 else { return nil }

        return (
            source: TimeRange(start: newSourceStart, duration: newSourceDuration),
            timeline: TimeRange(start: clampedTarget, duration: newDuration)
        )
    }

    private static func computeEndTrim(
        clip: Clip,
        mapping: ClipTimeMapping,
        targetTimelineTime: TimeInterval,
        assetDuration: TimeInterval?,
        minimumDuration: TimeInterval
    ) -> (source: TimeRange, timeline: TimeRange)? {
        let timelineStart = clip.timelineRange.start

        // Clamp target into the trimmable end region: must leave a minimum
        // duration at the start.
        let minEnd = timelineStart + minimumDuration
        let clampedTarget = max(targetTimelineTime, minEnd)
        let newDuration = clampedTarget - timelineStart
        guard newDuration >= minimumDuration else { return nil }

        // Map the new timeline end to the source time played there. The mapping
        // is reverse-aware; the source edge this maps to depends on direction.
        let mappedSource = mapping.sourceTime(forTimelineTime: clampedTarget)
        guard mappedSource.isFinite else { return nil }

        // Guard the source end against the asset duration for video/audio.
        // Image clips have no asset limit (assetDuration == nil) and can be
        // extended indefinitely; their source range is meaningless so we skip
        // the source-consistency guards and just return the new timeline span.
        if clip.kind == .image {
            return (
                source: clip.sourceRange,
                timeline: TimeRange(start: timelineStart, duration: newDuration)
            )
        }

        if clip.isReversed {
            // Reverse: the timeline end plays sourceRange.start and the closing
            // play point walks down as the end moves out. An end trim moves the
            // closing play point inward, so the mapped source becomes the clip's
            // NEW source start while the end stays fixed. The asset-duration
            // guard does not bind here (we are raising sourceRange.start toward
            // the fixed end, never extending past the asset).
            let newSourceStart = mappedSource
            guard newSourceStart >= 0 else { return nil }
            guard newSourceStart < clip.sourceRange.end else { return nil }
            let newSourceDuration = clip.sourceRange.end - newSourceStart
            guard newSourceDuration > 0 else { return nil }
            return (
                source: TimeRange(start: newSourceStart, duration: newSourceDuration),
                timeline: TimeRange(start: timelineStart, duration: newDuration)
            )
        }

        // Forward: the new timeline end maps to a new source end.
        let newSourceEnd = mappedSource

        if let assetDuration, assetDuration.isFinite, assetDuration > 0 {
            guard newSourceEnd <= assetDuration else {
                // Clamp the source end to the asset; recompute the timeline end
                // from the clamped source via the inverse mapping so the two
                // stay consistent.
                let clampedSourceEnd = min(newSourceEnd, assetDuration)
                let clampedTimelineEnd = mapping.timelineTime(forSourceTime: clampedSourceEnd)
                let clampedTimelineDuration = clampedTimelineEnd - timelineStart
                guard clampedTimelineDuration >= minimumDuration else { return nil }
                return (
                    source: TimeRange(start: clip.sourceRange.start, duration: clampedSourceEnd - clip.sourceRange.start),
                    timeline: TimeRange(start: timelineStart, duration: clampedTimelineDuration)
                )
            }
        }

        guard newSourceEnd > clip.sourceRange.start else { return nil }
        let newSourceDuration = newSourceEnd - clip.sourceRange.start
        guard newSourceDuration > 0 else { return nil }

        return (
            source: TimeRange(start: clip.sourceRange.start, duration: newSourceDuration),
            timeline: TimeRange(start: timelineStart, duration: newDuration)
        )
    }
}
