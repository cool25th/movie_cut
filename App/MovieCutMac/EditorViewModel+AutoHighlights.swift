import Foundation
import MovieCutCore

/// Auto-highlights boundary of the EditorViewModel decomposition (F-20).
/// Pure method moves from the main file, no behavior change; the stored
/// `highlightCandidates` state stays in the main class body. Unblocked by
/// the analysis-support helpers moving to their own file (see
/// EditorViewModel+AnalysisSupport.swift).
extension EditorViewModel {
    // MARK: - Auto highlights (F-20)

    var canDetectHighlights: Bool {
        guard let clip = selectedClip else { return false }
        return clip.kind == .video || clip.kind == .audio
    }

    /// Runs the silence, scene, and beat providers on the selected clip and
    /// scores highlight candidates by combining their outputs (F-20).
    func detectHighlights() async {
        guard let clipId = selectedClipId, canDetectHighlights else {
            lastErrorMessage = "Select a video or audio clip to find highlights."
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Scoring highlights..."

        do {
            let snapshot = await session.snapshot()
            let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)

            // Silence (speech density) — already source-time ranges mapped to timeline.
            let silenceProvider = SilenceDetectionProvider()
            let silenceResult = try await silenceProvider.analyze(asset: asset, in: snapshot)
            let silenceTimeline: [TimeRange] = silenceResult.suggestions.flatMap { suggestion -> [TimeRange] in
                guard case .silenceRemoval(let ranges) = suggestion else { return [] }
                return ranges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
            }

            // Scene changes (visual activity) — video only.
            var sceneTimeline: [TimeInterval] = []
            if asset.kind == .video {
                let sceneProvider = SceneChangeProvider()
                let sceneResult = try await sceneProvider.analyze(asset: asset, in: snapshot)
                sceneTimeline = sceneResult.suggestions.flatMap { suggestion -> [TimeInterval] in
                    guard case .sceneChanges(let times) = suggestion else { return [] }
                    return times.compactMap {
                        timelineMapping(for: TimeRange(start: $0, duration: .ulpOfOne), in: clip)?.timelineRange.start
                    }
                }
            }

            // Beats (audio energy proxy).
            let beatProvider = BeatDetectionProvider()
            let beatSourceTimes = try await beatProvider.analyze(asset: asset)
            let beatTimeline: [TimeInterval] = beatSourceTimes.compactMap {
                timelineMapping(for: TimeRange(start: $0, duration: .ulpOfOne), in: clip)?.timelineRange.start
            }

            let candidates = HighlightScorer.scoreHighlights(
                duration: clip.timelineRange.duration,
                silenceRanges: silenceTimeline.map { shift($0, by: -clip.timelineRange.start) },
                sceneChangeTimes: sceneTimeline.map { $0 - clip.timelineRange.start },
                energyMarkers: beatTimeline.map { $0 - clip.timelineRange.start }
            ).map { candidate in
                var shifted = candidate
                shifted.range = shift(candidate.range, by: clip.timelineRange.start)
                return shifted
            }

            highlightCandidates = candidates
            recordAnalysisResult(
                action: "Highlights",
                count: candidates.count,
                message: candidates.isEmpty
                    ? "No highlight candidates found."
                    : "Found \(candidates.count) highlight candidate(s).",
                clipId: clipId
            )
            lastStatusMessage = candidates.isEmpty
                ? "No highlight candidates found."
                : "Found \(candidates.count) highlight candidate(s). Create a sequence from one below."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func clearHighlights() {
        highlightCandidates = []
    }

    /// Creates a new project/sequence containing only the candidate window of
    /// the selected clip's source media (F-20).
    func createSequenceFromHighlight(_ candidate: HighlightCandidate) async {
        guard let clipId = selectedClipId else { return }

        do {
            let snapshot = await session.snapshot()
            let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)

            // Map the timeline-space candidate window back to source time
            // through the canonical mapping (Step 3). The ratio fallback only
            // runs if the clip's ranges are degenerate.
            let sourceStart: TimeInterval
            let sourceDuration: TimeInterval
            if let mapping = clip.makeTimeMapping() {
                sourceStart = mapping.sourceTime(forTimelineTime: candidate.range.start)
                let sourceEnd = mapping.sourceTime(forTimelineTime: candidate.range.end)
                sourceDuration = max(0, sourceEnd - sourceStart)
            } else {
                let timelineDuration = max(clip.timelineRange.duration, .leastNonzeroMagnitude)
                let ratio = clip.sourceRange.duration / timelineDuration
                let localStart = candidate.range.start - clip.timelineRange.start
                sourceStart = clip.sourceRange.start + max(0, localStart) * ratio
                sourceDuration = candidate.range.duration * ratio
            }

            var newProject = Project(name: "Highlight")
            newProject.canvas = snapshot.canvas
            newProject.exportSettings = snapshot.exportSettings
            newProject = Self.ensureDefaultTracks(in: newProject)

            let highlightClip = Clip(
                assetId: asset.id,
                kind: clip.kind,
                sourceRange: TimeRange(start: sourceStart, duration: sourceDuration),
                timelineRange: TimeRange(start: 0, duration: candidate.range.duration)
            )

            var importedLibrary = newProject.mediaLibrary
            importedLibrary.assets[asset.id] = asset
            newProject.mediaLibrary = importedLibrary

            let trackKind: TrackKind = clip.kind == .audio ? .audio : .video
            if let trackIndex = newProject.timeline.tracks.firstIndex(where: { $0.kind == trackKind }) {
                newProject.timeline.tracks[trackIndex].clips.append(highlightClip)
            } else {
                var track = Track(kind: trackKind, name: trackKind == .audio ? "Audio 1" : "Video 1")
                track.clips = [highlightClip]
                newProject.timeline.tracks.append(track)
            }

            // Route through the command path instead of replacing the session:
            // ReplaceProjectCommand swaps the project wholesale while pushing
            // the previous project onto the undo stack, so Cmd+Z restores the
            // pre-highlight project. Replacing the session here used to destroy
            // the undo stack entirely.
            try await session.dispatch(ReplaceProjectCommand(
                project: newProject,
                previousProject: snapshot
            ))
            try await refreshFromSession()
            selectedClipId = highlightClip.id
            selectedAssetId = asset.id
            playbackEngine.clear()
            playheadTime = 0
            highlightCandidates = []
            lastErrorMessage = nil
            lastStatusMessage = String(
                format: "Created a %.0fs highlight sequence.",
                candidate.range.duration
            )
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    private func shift(_ range: TimeRange, by delta: TimeInterval) -> TimeRange {
        TimeRange(start: range.start + delta, duration: range.duration)
    }
}
