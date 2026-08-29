import Foundation

public extension Track {
    /// Clips ordered for same-track layer display.
    var clipsForLayerDisplay: [Clip] {
        clips.sorted(by: Self.clipLayerOrder)
    }

    /// Assigns deterministic contiguous clip zIndexes inside this track.
    mutating func normalizeClipZIndexes() {
        clips = clips
            .sorted(by: Self.clipLayerOrder)
            .enumerated()
            .map { index, clip in
                var normalizedClip = clip
                normalizedClip.zIndex = index
                return normalizedClip
            }
    }

    /// Packs clips end-to-start from zero while preserving duration and chronological order.
    mutating func compactClipsMagnetically() throws {
        guard !isLocked else { return }

        var nextStart: TimeInterval = 0
        clips = try clips
            .sorted(by: Self.clipTimelineOrder)
            .map { clip in
                guard clip.timelineRange.duration >= 0 else {
                    throw EditorCommandError.invalidCommand("Clip duration cannot be negative.")
                }

                var compactedClip = clip
                compactedClip.timelineRange = TimeRange(
                    start: max(0, nextStart),
                    duration: clip.timelineRange.duration
                )
                nextStart = compactedClip.timelineRange.end
                return compactedClip
            }
    }

    static func clipLayerOrder(_ lhs: Clip, _ rhs: Clip) -> Bool {
        if lhs.zIndex != rhs.zIndex {
            return lhs.zIndex < rhs.zIndex
        }
        return clipTimelineOrder(lhs, rhs)
    }

    static func clipTimelineOrder(_ lhs: Clip, _ rhs: Clip) -> Bool {
        if lhs.timelineRange.start != rhs.timelineRange.start {
            return lhs.timelineRange.start < rhs.timelineRange.start
        }
        if lhs.timelineRange.duration != rhs.timelineRange.duration {
            return lhs.timelineRange.duration < rhs.timelineRange.duration
        }
        // BUG-ACC-04: a start+duration tie must not fall through to the
        // UUID comparison — random UUIDs made magnetic compaction order
        // adjustment-vs-content coin-flips (measured ~50%: an adjustment
        // borrowing the video's span could compact FIRST, shoving the real
        // content to the back half and killing the export on an
        // empty-source request). An adjustment layer is an overlay — it
        // never displaces renderable content in a tie.
        if lhs.isAdjustmentLayer != rhs.isAdjustmentLayer {
            return !lhs.isAdjustmentLayer
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension Project {
    mutating func trackIndex(for trackId: UUID) throws -> Int {
        guard let index = timeline.tracks.firstIndex(where: { $0.id == trackId }) else {
            throw EditorCommandError.trackNotFound(trackId)
        }
        return index
    }

    mutating func clipLocation(for clipId: UUID) throws -> (trackIndex: Int, clipIndex: Int) {
        for trackIndex in timeline.tracks.indices {
            if let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) {
                return (trackIndex, clipIndex)
            }
        }
        throw EditorCommandError.clipNotFound(clipId)
    }

    mutating func clipLocation(for clipId: UUID, in trackId: UUID) throws -> (trackIndex: Int, clipIndex: Int) {
        let trackIndex = try trackIndex(for: trackId)
        guard let clipIndex = timeline.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipId }) else {
            throw EditorCommandError.clipNotFound(clipId)
        }
        return (trackIndex, clipIndex)
    }

    func ensureTrackIsEditable(at index: Int) throws {
        let track = timeline.tracks[index]
        if track.isLocked {
            throw EditorCommandError.trackLocked(track.id)
        }
    }

    mutating func removeClip(id clipId: UUID) throws -> (trackId: UUID, clipIndex: Int, clip: Clip) {
        let location = try clipLocation(for: clipId)
        try ensureTrackIsEditable(at: location.trackIndex)
        let trackId = timeline.tracks[location.trackIndex].id
        let clip = timeline.tracks[location.trackIndex].clips.remove(at: location.clipIndex)
        return (trackId, location.clipIndex, clip)
    }

    mutating func insertClip(_ clip: Clip, into trackId: UUID, at insertionIndex: Int?) throws {
        let trackIndex = try trackIndex(for: trackId)
        try ensureTrackIsEditable(at: trackIndex)

        if let insertionIndex {
            guard insertionIndex >= 0, insertionIndex <= timeline.tracks[trackIndex].clips.count else {
                throw EditorCommandError.invalidCommand("Clip insertion index is out of bounds.")
            }
            timeline.tracks[trackIndex].clips.insert(clip, at: insertionIndex)
        } else {
            timeline.tracks[trackIndex].clips.append(clip)
        }
    }

    mutating func normalizeTrackZIndexes() {
        for index in timeline.tracks.indices {
            timeline.tracks[index].zIndex = index
        }
    }

    mutating func normalizeClipZIndexes(in trackId: UUID) throws {
        let trackIndex = try trackIndex(for: trackId)
        timeline.tracks[trackIndex].normalizeClipZIndexes()
    }

    mutating func compactTrackMagnetically(_ trackId: UUID) throws {
        let trackIndex = try trackIndex(for: trackId)
        try ensureTrackIsEditable(at: trackIndex)
        try timeline.tracks[trackIndex].compactClipsMagnetically()
    }

    /// The id of the primary (main) video track — the first track whose kind is
    /// `.video`. This is the only track subject to magnetic compaction; every
    /// other track (secondary video, audio, text/sticker) is freely positioned.
    /// Derived from track ordering, never persisted on `Track` (so legacy
    /// `.moviecut` decode is unaffected and the R504 "presentation-only"
    /// contract on `Track.swift` holds). Step 2 of the core-editing repair
    /// handoff.
    func mainVideoTrackId() -> UUID? {
        timeline.tracks.first { $0.kind == .video }?.id
    }

    /// Whether `trackId` is the magnetic (main video) track and therefore
    /// subject to gap-closing compaction on add/move/duplicate. All other
    /// tracks preserve freely-positioned clip offsets.
    func isMagneticTrack(_ trackId: UUID) -> Bool {
        trackId == mainVideoTrackId()
    }

    mutating func restoreClips(_ clips: [Clip], in trackId: UUID) throws {
        let trackIndex = try trackIndex(for: trackId)
        try ensureTrackIsEditable(at: trackIndex)
        timeline.tracks[trackIndex].clips = clips
    }

    mutating func trackClipSnapshot(for trackId: UUID) throws -> [Clip] {
        let trackIndex = try trackIndex(for: trackId)
        return timeline.tracks[trackIndex].clips
    }
}
