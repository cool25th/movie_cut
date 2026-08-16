import Foundation
import MovieCutCore

/// Timeline-editing boundary — extracted out of the EditorViewModel body
/// (EXECUTION_PLAN Inc 2, completed 2026-08-17 with user-approved access
/// normalization of the shared command infrastructure).
///
/// Pure move: selection accessors, playhead cursor navigation, clip-boundary
/// jumps, and the edit-operation cluster (split/trim/move/track toggles,
/// link groups, duplicate/copy/cut/paste, delete, scrub debounce), relocated
/// verbatim (no new logic). The shared dispatch infrastructure (`session`,
/// `apply`, `refreshFromSession`, clipboard/scrub stored state) stays in the
/// main file and is internal so this extension can drive it. Transport
/// (JKL shuttle, seek, zoom) is deliberately NOT here — it is the next
/// boundary in the roadmap.
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

    var canCopySelectedClips: Bool {
        canCopyClips(selectedClipIds)
    }

    var canCutSelectedClips: Bool {
        canCutClips(selectedClipIds)
    }

    var canPasteClips: Bool {
        clipClipboardPayload != nil
    }

    func canCopyClips(_ clipIds: Set<UUID>) -> Bool {
        !clipIds.isEmpty && clipIds.isSubset(of: currentClipIds)
    }

    func canCutClips(_ clipIds: Set<UUID>) -> Bool {
        guard canCopyClips(clipIds) else { return false }
        return currentProject.timeline.tracks.allSatisfy { track in
            track.isLocked ? clipIds.isDisjoint(with: Set(track.clips.map(\.id))) : true
        }
    }

    func splitClip() async {
        guard let selectedClipId, let selectedClip, let selectedClipTrackId else { return }
        guard selectedClip.timelineRange.contains(playheadTime) else {
            lastErrorMessage = "Move the playhead inside the selected clip to split."
            return
        }

        do {
            try await session.dispatch(
                SplitClipCommand(clipId: selectedClipId, trackId: selectedClipTrackId, splitTime: playheadTime)
            )
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Blade tool: split the topmost video clip under the playhead (S9). Reuses
    /// `SplitClipCommand` so the split is speed/ramp/reverse-aware and export-
    /// consistent. Called by a timeline click in blade mode after the playhead
    /// is moved to the click position.
    func bladeSplitAtPlayhead() async {
        let time = playheadTime
        // Find the topmost (highest zIndex) video clip whose range contains the
        // playhead, across all tracks.
        let snapshot = await session.snapshot()
        let candidate = snapshot.timeline.tracks
            .flatMap { track in track.clips.map { (track.id, $0) } }
            .filter { $0.1.kind == .video && $0.1.timelineRange.contains(time) }
            .max { $0.1.zIndex < $1.1.zIndex }
        guard let candidate else { return }
        let (trackId, clip) = (candidate.0, candidate.1)
        do {
            try await session.dispatch(
                SplitClipCommand(clipId: clip.id, trackId: trackId, splitTime: time)
            )
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func trimClip(
        clipId: UUID,
        trackId: UUID?,
        sourceRange: TimeRange,
        timelineRange: TimeRange
    ) async {
        selectedClipId = clipId
        await apply(
            TrimClipCommand(
                clipId: clipId,
                trackId: trackId,
                newSourceRange: sourceRange,
                newTimelineRange: timelineRange
            )
        )
    }

    func trimSelectedClipStartToPlayhead() async {
        guard let selectedClipId, let selectedClip else { return }
        let trimTime = playheadTime

        // Route through the shared ClipTrimMath so the keyboard path and the
        // drag path produce identical ranges at any speed or ramp, and so the
        // source range is guarded against the asset duration (Step 5).
        guard let result = ClipTrimMath.compute(
            clip: selectedClip,
            edge: .start,
            targetTimelineTime: trimTime,
            assetDuration: assetDuration(for: selectedClip),
            minimumDuration: Self.minimumTimelineClipDuration
        ) else {
            lastErrorMessage = "Move the playhead inside the selected clip to trim its start."
            return
        }

        await trimClip(
            clipId: selectedClipId,
            trackId: selectedClipTrackId,
            sourceRange: result.source,
            timelineRange: result.timeline
        )
    }

    func trimSelectedClipEndToPlayhead() async {
        guard let selectedClipId, let selectedClip else { return }
        let trimTime = playheadTime

        guard let result = ClipTrimMath.compute(
            clip: selectedClip,
            edge: .end,
            targetTimelineTime: trimTime,
            assetDuration: assetDuration(for: selectedClip),
            minimumDuration: Self.minimumTimelineClipDuration
        ) else {
            lastErrorMessage = "Move the playhead inside the selected clip to trim its end."
            return
        }

        await trimClip(
            clipId: selectedClipId,
            trackId: selectedClipTrackId,
            sourceRange: result.source,
            timelineRange: result.timeline
        )
    }

    /// Resolves the source asset duration for a clip, used by the shared trim
    /// math to guard against trimming the source past the asset's real end.
    /// Returns nil for image clips (unbounded) and for clips with no asset.
    private func assetDuration(for clip: Clip) -> TimeInterval? {
        guard let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId] else {
            return nil
        }
        return asset.duration
    }

    /// Clip-id-keyed asset duration lookup for views (TimelineView drag trim)
    /// that don't hold the Clip value directly. Step 5.
    func assetDuration(forClipID clipId: UUID) -> TimeInterval? {
        guard let clip = currentProject.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clipId }) else {
            return nil
        }
        return assetDuration(for: clip)
    }

    // MARK: - Clip link groups (F-04)

    func moveClip(
        clipId: UUID,
        sourceTrackId: UUID?,
        targetTrackId: UUID?,
        timelineRange: TimeRange
    ) async {
        selectedClipId = clipId
        await apply(
            MoveClipCommand(
                clipId: clipId,
                sourceTrackId: sourceTrackId,
                targetTrackId: targetTrackId,
                newTimelineRange: timelineRange
            )
        )
    }

    func toggleTrackMute(_ track: Track) async {
        await apply(SetTrackPropertyCommand(trackId: track.id, property: .isMuted(!track.isMuted)))
    }

    func toggleTrackLock(_ track: Track) async {
        await apply(SetTrackPropertyCommand(trackId: track.id, property: .isLocked(!track.isLocked)))
    }

    func toggleTrackHidden(_ track: Track) async {
        await apply(SetTrackPropertyCommand(trackId: track.id, property: .isHidden(!track.isHidden)))
    }

    func rippleDeleteClip(clipId: UUID) async {
        selectedClipId = clipId
        await apply(RippleDeleteCommand(clipId: clipId))
        if selectedClipId == clipId {
            selectedClipId = nil
        }
    }

    func duplicateClip(clipId: UUID) async {
        selectedClipId = clipId
        await duplicateClips([clipId])
    }

    /// True when any selected clip belongs to a link group.
    var hasGroupedSelection: Bool {
        timelineClips(in: selectedClipIds).contains { $0.groupId != nil }
    }

    /// Returns the clip ids linked to the given clip, including the clip
    /// itself. Ungrouped clips link only to themselves.
    func linkedClipIds(for clipId: UUID) -> Set<UUID> {
        guard
            let clip = timelineClips(in: [clipId]).first,
            let groupId = clip.groupId
        else {
            return [clipId]
        }

        var linked: Set<UUID> = [clipId]
        for track in currentProject.timeline.tracks {
            for trackClip in track.clips where trackClip.groupId == groupId {
                linked.insert(trackClip.id)
            }
        }
        return linked
    }

    /// Timeline tap selection that treats link groups as a unit: selecting a
    /// grouped clip selects its whole group, and command-deselecting a grouped
    /// clip removes the whole group from the selection.
    func selectTimelineClip(_ clipId: UUID, extendSelection: Bool) {
        let linked = linkedClipIds(for: clipId)
        if extendSelection {
            if selectedClipIds.contains(clipId) {
                selectedClipIds.subtract(linked)
            } else {
                selectedClipIds.formUnion(linked)
            }
        } else {
            selectedClipIds = linked
        }
    }

    /// Links the selected clips into a new group.
    func groupSelectedClips() async {
        let clipIds = timelineOrderedClipIds(from: selectedClipIds)
        guard clipIds.count >= 2 else {
            lastErrorMessage = NSLocalizedString("Select at least two clips to group.", comment: "")
            return
        }

        do {
            try await session.dispatch(GroupClipsCommand(clipIds: clipIds, groupId: UUID()))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = String(
                format: NSLocalizedString("Grouped %d clips", comment: ""),
                clipIds.count
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Removes link-group membership from the selected clips.
    func ungroupSelectedClips() async {
        let groupedClipIds = timelineClips(in: selectedClipIds)
            .filter { $0.groupId != nil }
            .map(\.id)
        guard !groupedClipIds.isEmpty else { return }

        do {
            try await session.dispatch(GroupClipsCommand(clipIds: groupedClipIds, groupId: nil))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = String(
                format: NSLocalizedString("Ungrouped %d clips", comment: ""),
                groupedClipIds.count
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func timelineClips(in clipIds: Set<UUID>) -> [Clip] {
        currentProject.timeline.tracks.flatMap { track in
            track.clips.filter { clipIds.contains($0.id) }
        }
    }

    func duplicateSelectedClips() async {
        await duplicateClips(selectedClipIds)
    }

    func duplicateClips(_ clipIds: Set<UUID>) async {
        let orderedClipIds = timelineOrderedClipIds(from: clipIds)
        guard !orderedClipIds.isEmpty else { return }

        do {
            for clipId in orderedClipIds {
                try await session.dispatch(DuplicateClipCommand(clipId: clipId))
            }
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copySelectedClips() {
        copyClips(selectedClipIds)
    }

    func copyClips(_ clipIds: Set<UUID>) {
        guard !clipIds.isEmpty else { return }

        do {
            clipClipboardPayload = try ClipboardPayload(project: currentProject, clipIds: clipIds)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func cutSelectedClips() async {
        await cutClips(selectedClipIds)
    }

    func cutClips(_ clipIds: Set<UUID>) async {
        guard !clipIds.isEmpty else { return }

        do {
            let payload = try ClipboardPayload(project: currentProject, clipIds: clipIds)
            try await session.dispatch(CutClipsCommand(clipIds: clipIds))
            clipClipboardPayload = payload
            selectedClipIds.subtract(clipIds)
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func pasteClipsAtPlayhead() async {
        guard let clipClipboardPayload else { return }

        let clipIdsBeforePaste = currentClipIds
        do {
            try await session.dispatch(PasteClipsCommand(
                payload: clipClipboardPayload,
                anchorTime: max(0, playheadTime)
            ))
            try await refreshFromSession()
            selectedClipIds = currentClipIds.subtracting(clipIdsBeforePaste)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func copyClip(clipId: UUID, targetTrackId: UUID, targetStartTime: TimeInterval) async {
        selectedClipId = clipId
        await apply(
            CopyClipCommand(
                clipId: clipId,
                targetTrackId: targetTrackId,
                targetStartTime: max(0, targetStartTime)
            )
        )
    }

    func deleteClip() async {
        await deleteClips(selectedClipIds)
    }

    func rippleDeleteSelectedClip() async {
        guard let selectedClipId else { return }
        await rippleDeleteClip(clipId: selectedClipId)
    }

    func deleteClips(_ clipIds: Set<UUID>) async {
        let orderedClipIds = timelineOrderedClipIds(from: clipIds)
        guard !orderedClipIds.isEmpty else { return }

        do {
            for clipId in orderedClipIds {
                try await session.dispatch(DeleteClipCommand(clipId: clipId))
            }
            selectedClipIds.subtract(Set(orderedClipIds))
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func scrubPlayhead(to time: TimeInterval, phase: TimelineScrubPhase = .ended) {
        let duration = max(0, currentProject.timeline.duration)
        let safeTime = time.isFinite ? time : 0
        let clampedTime = min(duration, max(0, safeTime))

        switch phase {
        case .began:
            pendingScrubTask?.cancel()
            pendingScrubTask = nil
            pendingScrubTime = nil
            if playbackEngine.isPlaying {
                playbackEngine.pause()
            }
            applyScrubTime(clampedTime)

        case .changed:
            pendingScrubTime = clampedTime
            guard pendingScrubTask == nil else { return }
            pendingScrubTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard let self, !Task.isCancelled else { return }
                let latestTime = self.pendingScrubTime
                self.pendingScrubTime = nil
                self.pendingScrubTask = nil
                if let latestTime {
                    self.applyScrubTime(latestTime)
                }
            }

        case .ended:
            pendingScrubTask?.cancel()
            pendingScrubTask = nil
            pendingScrubTime = nil
            applyScrubTime(clampedTime)
        }
    }

    private func applyScrubTime(_ time: TimeInterval) {
        playheadTime = time
        playbackEngine.seek(to: time)
    }

    private func timelineOrderedClipIds(from clipIds: Set<UUID>) -> [UUID] {
        var orderedClipIds: [UUID] = []
        for track in currentProject.timeline.tracks {
            for clip in track.clips where clipIds.contains(clip.id) {
                orderedClipIds.append(clip.id)
            }
        }
        return orderedClipIds
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
