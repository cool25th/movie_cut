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

    // MARK: - Slip

    /// The result of a slip: only the source range changes, so the whole return
    /// is the new source window. The clip's `timelineRange` and the timeline's
    /// total length are unchanged (the caller keeps the existing timeline range).
    public struct SlipResult: Sendable, Equatable {
        /// The new source media range. Its duration equals the clip's current
        /// source duration (slip translates the window, it does not resize it).
        public let source: TimeRange
    }

    /// Slip moves only the clip's `sourceRange`: the same on-timeline span now
    /// plays a different window of source media. The clip's `timelineRange` and
    /// the timeline's total length are preserved.
    ///
    /// Speed/ramp/reverse clips route through `Clip.makeTimeMapping()` exactly
    /// as the trim path does — slip does not introduce a second time-calculation
    /// scheme. Because speed-ramp points are normalized to source time and the
    /// rendered timeline duration is a function of `sourceRange.duration` (not
    /// `sourceRange.start`), translating the window leaves the rendered timeline
    /// span invariant, which is what keeps the timeline range valid.
    ///
    /// - Parameters:
    ///   - clip: the clip being slipped.
    ///   - sourceDelta: the signed number of source seconds to shift the window
    ///     by. Positive shifts the window toward the end of the asset (later
    ///     frames play at the same timeline position); negative toward the start.
    ///   - assetDuration: the source asset's real duration for video/audio clips,
    ///     used to clamp the window inside `[0, assetDuration]`. Pass `nil` for
    ///     image/text clips (no slip meaning — the function returns nil).
    ///   - minimumSourceDuration: the floor for the resulting source duration.
    ///     The slip preserves duration, so this only rejects degenerate inputs.
    /// - Returns: the new source range, or `nil` if the clip has no temporal
    ///   source (image), a degenerate mapping, or `assetDuration` cannot fit the
    ///   current window at all. Out-of-bounds requests are clamped, not rejected.
    public static func slip(
        clip: Clip,
        sourceDelta: TimeInterval,
        assetDuration: TimeInterval?,
        minimumSourceDuration: TimeInterval
    ) -> SlipResult? {
        guard sourceDelta.isFinite else { return nil }
        // Image/text clips have no temporal source to slip through.
        guard clip.kind == .video || clip.kind == .audio else { return nil }

        let source = clip.sourceRange
        guard source.duration.isFinite, source.duration > 0 else { return nil }
        guard source.duration >= minimumSourceDuration else { return nil }

        // Reuse the canonical mapping so any future ramp/reverse change is
        // picked up from one place. We do not invent a parallel calculation.
        guard clip.makeTimeMapping() != nil else { return nil }

        // No finite asset bound: there is nothing to clamp against, so the
        // window simply translates. (Audio/video always carry an asset, but the
        // parameter is optional to mirror `compute`.)
        guard let assetDuration, assetDuration.isFinite, assetDuration > 0 else {
            let newStart = source.start + sourceDelta
            return SlipResult(source: TimeRange(start: newStart, duration: source.duration))
        }

        // Clamp the translated window inside [0, assetDuration]. Duration is
        // preserved; only the start moves. This never produces an invalid state
        // (negative duration or out-of-asset window).
        let duration = source.duration
        let maxStart = max(0, assetDuration - duration)
        let rawStart = source.start + sourceDelta
        let clampedStart = min(max(rawStart, 0), maxStart)
        return SlipResult(source: TimeRange(start: clampedStart, duration: duration))
    }

    // MARK: - Slide

    /// One clip's updated placement produced by `slide`. The clip keeps its own
    /// `sourceRange` and its rendered timeline duration; only its timeline start
    /// moves.
    public struct SlideClipPlacement: Sendable, Equatable {
        /// The clip identifier this placement updates.
        public let clipId: UUID
        /// The new timeline range. Duration is unchanged from the input clip;
        /// only `start` differs.
        public let timeline: TimeRange
    }

    /// The result of a slide: the moved clip's new timeline range plus the
    /// adjusted boundary ranges of any neighbors that were trimmed to keep the
    /// total timeline length constant. The moved clip's `sourceRange` is
    /// unchanged.
    public struct SlideResult: Sendable, Equatable {
        /// The moved clip's new timeline placement.
        public let target: SlideClipPlacement
        /// Neighbor clips whose end (previous neighbor) or start (next neighbor)
        /// was adjusted to absorb the move. Empty when the clip is the only clip
        /// or when the slide was clamped to zero. Order is unspecified.
        public let neighbors: [SlideClipPlacement]
    }

    /// Slide moves the clip on the timeline and trims the adjacent neighbors'
    /// boundaries to keep the total timeline length constant. The clip's own
    /// `sourceRange` and rendered timeline duration are preserved.
    ///
    /// The clip's own source mapping is consulted (via `Clip.makeTimeMapping()`)
    /// to derive the authoritative rendered timeline duration — the same path
    /// the trim and split commands use — so speed/ramp clips keep their correct
    /// timeline span. No new time-calculation scheme is introduced.
    ///
    /// Neighbors are identified by timeline adjacency in `clips` (sorted by
    /// timeline start). The previous neighbor's end is pushed forward/back to
    /// meet the moved clip's new start; the next neighbor's start is pushed to
    /// meet the moved clip's new end. Neighbors are never shrunk below
    /// `minimumDuration`; the requested delta is clamped to whatever the
    /// neighbors (and the track's left edge) can absorb, so the result never
    /// produces an invalid state.
    ///
    /// - Parameters:
    ///   - clips: the clips on the same track as the target, in any order (the
    ///     function sorts by timeline start to find adjacency). The array is not
    ///     mutated.
    ///   - targetIndex: the index into `clips` of the clip being slid.
    ///   - timelineDelta: signed timeline seconds to move the clip by. Positive
    ///     moves the clip later; negative earlier.
    ///   - minimumDuration: the minimum allowed timeline duration for any clip
    ///     after adjustment (target and neighbors).
    /// - Returns: the updated placements, or `nil` if `targetIndex` is out of
    ///   bounds, the target has a degenerate mapping, or the slide is not
    ///   possible (e.g. a single clip with no room, or every neighbor already at
    ///   minimum). When neighbors cannot absorb the full delta, the delta is
    ///   clamped to the feasible range rather than returning nil, unless even a
    ///   zero delta is invalid.
    public static func slide(
        clips: [Clip],
        targetIndex: Int,
        timelineDelta: TimeInterval,
        minimumDuration: TimeInterval
    ) -> SlideResult? {
        guard timelineDelta.isFinite else { return nil }
        guard clips.indices.contains(targetIndex) else { return nil }
        let target = clips[targetIndex]

        // Rendered duration via the canonical mapping (speed/ramp aware). The
        // slide preserves this span; we do not recompute timeline length here.
        guard let mapping = target.makeTimeMapping() else { return nil }
        let rendered = mapping.renderedTimelineDuration
        guard rendered.isFinite, rendered > 0 else { return nil }
        guard rendered >= minimumDuration else { return nil }

        // Build the adjacency ordering. Stable sort by timeline start; ties keep
        // the target findable by identity.
        let ordered = clips.enumerated().sorted { a, b in
            if a.element.timelineRange.start == b.element.timelineRange.start {
                return a.offset < b.offset
            }
            return a.element.timelineRange.start < b.element.timelineRange.start
        }
        guard let orderedTarget = ordered.first(where: { $0.offset == targetIndex }) else { return nil }
        let orderedPosition = ordered.firstIndex(where: { $0.offset == targetIndex }) ?? 0

        let prev = orderedPosition > 0 ? ordered[orderedPosition - 1].element : nil
        let next = orderedPosition < ordered.count - 1 ? ordered[orderedPosition + 1].element : nil

        let targetStart = orderedTarget.element.timelineRange.start
        let targetEnd = orderedTarget.element.timelineRange.end

        // The slide cannot push the clip before the track's left edge (0) nor
        // past the start of the next clip minus minimum, and the previous clip
        // must keep at least minimumDuration. Compute the feasible delta range
        // and clamp the request into it.
        var minDelta = -targetStart // cannot go below timeline 0
        var maxDelta = TimeInterval.infinity

        if let prev {
            // Moving earlier shrinks the gap / grows prev; prev.end follows the
            // new target start. Prev must keep >= minimumDuration.
            let prevStart = prev.timelineRange.start
            let earliestTargetStart = prevStart + minimumDuration
            minDelta = max(minDelta, earliestTargetStart - targetStart)
        }

        if let next {
            // Moving later grows the gap / shrinks next; next.start follows the
            // new target end. Next must keep >= minimumDuration.
            let nextEnd = next.timelineRange.end
            let latestTargetEnd = nextEnd - minimumDuration
            maxDelta = min(maxDelta, latestTargetEnd - targetEnd)
        }

        // If the feasible window is empty/invalid, no slide is possible.
        guard minDelta.isFinite, maxDelta.isFinite || maxDelta == .infinity else { return nil }
        guard minDelta <= maxDelta else { return nil }

        let clampedDelta = min(max(timelineDelta, minDelta), maxDelta)

        let newTargetStart = targetStart + clampedDelta
        let newTargetEnd = newTargetStart + rendered
        let newTarget = SlideClipPlacement(
            clipId: target.id,
            timeline: TimeRange(start: newTargetStart, duration: rendered)
        )

        var neighbors: [SlideClipPlacement] = []

        // Previous neighbor's end snaps to the moved clip's new start. Its
        // source range is the caller's concern; slide only reports timeline
        // placements (own source preservation applies to the target; neighbors
        // keep their source range and just play a longer/shorter span).
        if let prev {
            let prevStart = prev.timelineRange.start
            let newPrevDuration = max(newTargetStart - prevStart, minimumDuration)
            guard newPrevDuration >= minimumDuration else { return nil }
            neighbors.append(SlideClipPlacement(
                clipId: prev.id,
                timeline: TimeRange(start: prevStart, duration: newPrevDuration)
            ))
        }

        // Next neighbor's start snaps to the moved clip's new end. Its duration
        // shrinks/grows to keep the total length constant.
        if let next {
            let nextEnd = next.timelineRange.end
            let newNextDuration = max(nextEnd - newTargetEnd, minimumDuration)
            guard newNextDuration >= minimumDuration else { return nil }
            neighbors.append(SlideClipPlacement(
                clipId: next.id,
                timeline: TimeRange(start: newTargetEnd, duration: newNextDuration)
            ))
        }

        return SlideResult(target: newTarget, neighbors: neighbors)
    }
}
