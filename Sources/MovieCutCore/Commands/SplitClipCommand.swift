import Foundation

/// Splits a clip into two clips at a timeline time.
public struct SplitClipCommand: EditorCommand {
    /// The command identifier.
    public let id: UUID

    /// The clip to split.
    public var clipId: UUID

    /// The track expected to contain the clip.
    public var trackId: UUID?

    /// The timeline split time in seconds.
    public var splitTime: TimeInterval

    /// The identifier assigned to the new trailing clip.
    public var newClipId: UUID

    /// Creates a split command.
    public init(
        id: UUID = UUID(),
        clipId: UUID,
        trackId: UUID? = nil,
        splitTime: TimeInterval,
        newClipId: UUID = UUID()
    ) {
        self.id = id
        self.clipId = clipId
        self.trackId = trackId
        self.splitTime = splitTime
        self.newClipId = newClipId
    }

    public func apply(to project: inout Project) throws -> CommandResult {
        let location = if let trackId {
            try project.clipLocation(for: clipId, in: trackId)
        } else {
            try project.clipLocation(for: clipId)
        }
        try project.ensureTrackIsEditable(at: location.trackIndex)

        let clip = project.timeline.tracks[location.trackIndex].clips[location.clipIndex]
        guard splitTime > clip.timelineRange.start, splitTime < clip.timelineRange.end else {
            throw EditorCommandError.invalidCommand("Split time must be inside the clip range.")
        }

        // Map the split boundary to source time through the canonical mapping
        // so a 2x clip's timeline split advances the source by the right amount
        // (Step 3 of the core-editing repair). Previously split assumed
        // timeline 1s == source 1s, which was wrong for any non-1x clip.
        let mapping = clip.makeTimeMapping()
            ?? ClipTimeMapping(
                sourceRange: clip.sourceRange,
                timelineStart: clip.timelineRange.start,
                timelineDuration: clip.timelineRange.duration,
                playbackRate: clip.playbackRate,
                speedRampPoints: clip.speedRampPoints,
                isReversed: clip.isReversed,
                kind: clip.kind
            )

        let splitSourceTime = mapping.sourceTime(forTimelineTime: splitTime)
        let firstTimelineDuration = splitTime - clip.timelineRange.start
        let secondTimelineDuration = clip.timelineRange.end - splitTime

        // Assign each resulting clip the source sub-range it actually plays.
        // `splitSourceTime` is already reverse-correct (the mapping walks source
        // `.end -> .start` for a reversed clip), but the *assignment* of the two
        // sub-ranges must flip for reverse playback: a reversed clip walks source
        // backward, so by the split point the timeline-left half has already
        // played the *upper* source sub-range down to `splitSourceTime`. Without
        // this branch a reversed source `0...10` split at timeline 4s would put
        // `0...6` on the first half (which should play `10->6`) — the halves get
        // swapped. Timeline ranges never flip: the timeline always advances
        // forward regardless of playback direction.
        let firstSourceRange: TimeRange
        let secondSourceRange: TimeRange
        if clip.isReversed {
            // first  plays source [splitSourceTime, sourceEnd] (walks end -> split)
            // second plays source [sourceStart, splitSourceTime] (walks split -> start)
            let firstSourceDuration = max(0, clip.sourceRange.end - splitSourceTime)
            let secondSourceDuration = max(0, splitSourceTime - clip.sourceRange.start)
            guard secondSourceDuration >= 0 else {
                throw EditorCommandError.invalidCommand("Split time exceeds the clip source range.")
            }
            firstSourceRange = TimeRange(start: splitSourceTime, duration: firstSourceDuration)
            secondSourceRange = TimeRange(start: clip.sourceRange.start, duration: secondSourceDuration)
        } else {
            let firstSourceDuration = max(0, splitSourceTime - clip.sourceRange.start)
            let secondSourceDuration = max(0, clip.sourceRange.end - splitSourceTime)
            guard secondSourceDuration >= 0 else {
                throw EditorCommandError.invalidCommand("Split time exceeds the clip source range.")
            }
            firstSourceRange = TimeRange(start: clip.sourceRange.start, duration: firstSourceDuration)
            secondSourceRange = TimeRange(start: splitSourceTime, duration: secondSourceDuration)
        }

        var firstClip = clip
        firstClip.timelineRange.duration = firstTimelineDuration
        firstClip.sourceRange = firstSourceRange
        // Re-normalize speed-ramp points into each sub-clip's own source
        // sub-range so the ramp curve still spans [0,1] after the split (Step 5
        // of the core-editing repair). The ramp curve is defined over the
        // source domain; reverse only flips playback order, not the
        // source-to-rate mapping, so feeding each new clip's own `sourceRange`
        // is correct for both forward and reverse clips.
        if clip.speedRampPoints.count >= 2 {
            firstClip.speedRampPoints = clip.speedRampPoints.renormalized(
                fromParentSourceStart: clip.sourceRange.start,
                parentSourceDuration: clip.sourceRange.duration,
                intoSubSourceRange: firstSourceRange
            )
        }

        var secondClip = clip
        secondClip.id = newClipId
        secondClip.timelineRange = TimeRange(start: splitTime, duration: secondTimelineDuration)
        secondClip.sourceRange = secondSourceRange
        if clip.speedRampPoints.count >= 2 {
            secondClip.speedRampPoints = clip.speedRampPoints.renormalized(
                fromParentSourceStart: clip.sourceRange.start,
                parentSourceDuration: clip.sourceRange.duration,
                intoSubSourceRange: secondSourceRange
            )
        }

        project.timeline.tracks[location.trackIndex].clips[location.clipIndex] = firstClip
        project.timeline.tracks[location.trackIndex].clips.insert(secondClip, at: location.clipIndex + 1)

        return CommandResult(
            affectedClipIds: [clipId, newClipId],
            description: "Split clip \(clipId)",
            undoValues: [
                "trackId": .uuid(project.timeline.tracks[location.trackIndex].id),
                "clipIndex": .int(location.clipIndex),
                "clip": .clip(clip)
            ]
        )
    }

    public func invert(from result: CommandResult) throws -> any EditorCommand {
        if
            case .uuid(let trackId)? = result.undoValues["trackId"],
            case .int(let clipIndex)? = result.undoValues["clipIndex"],
            case .clip(let clip)? = result.undoValues["clip"]
        {
            return MergeSplitClipCommand(
                originalClipId: clipId,
                splitClipId: newClipId,
                trackId: trackId,
                originalClipIndex: clipIndex,
                originalClip: clip,
                splitTime: splitTime
            )
        }

        return MergeSplitClipCommand(
            originalClipId: clipId,
            splitClipId: newClipId,
            trackId: trackId,
            originalClipIndex: nil,
            originalClip: nil,
            splitTime: splitTime
        )
    }
}

struct MergeSplitClipCommand: EditorCommand {
    let id: UUID
    let originalClipId: UUID
    let splitClipId: UUID
    let trackId: UUID?
    let originalClipIndex: Int?
    let originalClip: Clip?
    let splitTime: TimeInterval

    init(
        id: UUID = UUID(),
        originalClipId: UUID,
        splitClipId: UUID,
        trackId: UUID?,
        originalClipIndex: Int?,
        originalClip: Clip?,
        splitTime: TimeInterval
    ) {
        self.id = id
        self.originalClipId = originalClipId
        self.splitClipId = splitClipId
        self.trackId = trackId
        self.originalClipIndex = originalClipIndex
        self.originalClip = originalClip
        self.splitTime = splitTime
    }

    func apply(to project: inout Project) throws -> CommandResult {
        let originalLocation = if let trackId {
            try project.clipLocation(for: originalClipId, in: trackId)
        } else {
            try project.clipLocation(for: originalClipId)
        }
        let splitLocation = if let trackId {
            try project.clipLocation(for: splitClipId, in: trackId)
        } else {
            try project.clipLocation(for: splitClipId)
        }
        guard originalLocation.trackIndex == splitLocation.trackIndex else {
            throw EditorCommandError.invalidCommand("Split clips must be on the same track to merge.")
        }
        try project.ensureTrackIsEditable(at: originalLocation.trackIndex)

        guard abs(originalLocation.clipIndex - splitLocation.clipIndex) == 1 else {
            throw EditorCommandError.invalidCommand("Split clips must be adjacent to merge.")
        }

        let firstIndex = min(originalLocation.clipIndex, splitLocation.clipIndex)
        let secondIndex = max(originalLocation.clipIndex, splitLocation.clipIndex)
        project.timeline.tracks[originalLocation.trackIndex].clips.remove(at: secondIndex)

        if let originalClip {
            project.timeline.tracks[originalLocation.trackIndex].clips[firstIndex] = originalClip
        } else {
            let remainingClip = project.timeline.tracks[originalLocation.trackIndex].clips[firstIndex]
            let mergedTimelineStart = min(remainingClip.timelineRange.start, splitTime)
            let mergedTimelineEnd = max(remainingClip.timelineRange.end, splitTime)
            project.timeline.tracks[originalLocation.trackIndex].clips[firstIndex].timelineRange = TimeRange(
                start: mergedTimelineStart,
                duration: mergedTimelineEnd - mergedTimelineStart
            )
        }

        return CommandResult(
            affectedClipIds: [originalClipId, splitClipId],
            description: "Merged split clip \(splitClipId)"
        )
    }

    func invert(from result: CommandResult) throws -> any EditorCommand {
        SplitClipCommand(clipId: originalClipId, trackId: trackId, splitTime: splitTime, newClipId: splitClipId)
    }
}
