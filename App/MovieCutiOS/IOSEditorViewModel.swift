import Foundation
import AVFoundation
import MovieCutCore

@MainActor
@Observable
final class IOSEditorViewModel {
    var currentProject: Project
    var selectedClipId: UUID?
    var playheadTime: TimeInterval
    var isPlaying: Bool
    var lastErrorMessage: String? = nil
    var exportEngine: IOSExportEngine = IOSExportEngine()

    private let session: EditorSession

    init() {
        let project = Self.defaultProject()
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        session = EditorSession(project: project)
    }

    var mediaAssets: [MediaAsset] {
        currentProject.mediaLibrary.assets.values.sorted {
            $0.originalURL.lastPathComponent.localizedStandardCompare($1.originalURL.lastPathComponent) == .orderedAscending
        }
    }

    var selectedClip: Clip? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == selectedClipId }
    }

    var lastExportURL: URL? {
        exportEngine.lastExportURL
    }

    var isExporting: Bool {
        exportEngine.isExporting
    }

    var exportProgress: Double {
        exportEngine.exportProgress
    }

    func importMedia(from url: URL, kind: MediaKind? = nil) async {
        var asset = MediaImporter.probe(url: url)
        if let kind {
            asset.kind = kind
        }
        asset.duration = await duration(for: url, kind: asset.kind)

        do {
            try await session.dispatch(ImportMediaCommand(asset: asset))
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func addClipToTimeline(asset: MediaAsset) async {
        do {
            var snapshot = await session.snapshot()
            if snapshot.mediaLibrary.assets[asset.id] == nil {
                try await session.dispatch(ImportMediaCommand(asset: asset))
                snapshot = await session.snapshot()
            }

            guard let track = snapshot.timeline.tracks.first(where: { $0.kind == trackKind(for: asset.kind) }) else {
                return
            }

            let duration = defaultDuration(for: asset)
            let start = snapshot.timeline.duration
            let clip = Clip(
                assetId: asset.id,
                kind: clipKind(for: asset.kind),
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: start, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func splitClip() async {
        guard
            let selectedClipId,
            let selectedClip,
            let trackId = selectedClipTrackId,
            selectedClip.timelineRange.contains(playheadTime)
        else { return }

        do {
            try await session.dispatch(SplitClipCommand(clipId: selectedClipId, trackId: trackId, splitTime: playheadTime))
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func deleteClip() async {
        guard let selectedClipId else { return }

        do {
            try await session.dispatch(DeleteClipCommand(clipId: selectedClipId))
            self.selectedClipId = nil
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func undo() async {
        do {
            try await session.undo()
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func redo() async {
        do {
            try await session.redo()
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func togglePlayPause() {
        isPlaying.toggle()
    }

    func updateSelectedOpacity(_ opacity: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .opacity(opacity)))
    }

    func updateSelectedVolume(_ volume: Double) async {
        guard let selectedClipId else { return }
        await apply(SetVolumeCommand(clipId: selectedClipId, volume: volume))
    }

    func updateSelectedPlaybackRate(_ rate: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .playbackRate(rate)))
    }

    func updateSelectedColorCorrection(_ correction: ColorCorrection) async {
        guard let selectedClipId else { return }
        await apply(SetColorCorrectionCommand(clipId: selectedClipId, colorCorrection: correction))
    }

    func setTransition(_ type: TransitionType) async {
        guard let selectedClipId else { return }

        let transition: Transition?
        if type == .none {
            transition = nil
        } else {
            transition = Transition(type: type, duration: selectedClip?.transition?.duration ?? 0.5)
        }

        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transition(transition)))
    }

    func duplicateClip() async {
        guard let selectedClipId else { return }

        let originalClipId = selectedClipId
        let originalClip = selectedClip
        let originalTrackId = selectedClipTrackId

        do {
            try await session.dispatch(DuplicateClipCommand(clipId: originalClipId))
            await refreshFromSession()

            if let duplicateClip = duplicatedClip(
                after: originalClip,
                trackId: originalTrackId,
                excluding: originalClipId
            ) {
                self.selectedClipId = duplicateClip.id
                playheadTime = duplicateClip.timelineRange.start
            }
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func rippleDeleteClip() async {
        guard let selectedClipId else { return }

        do {
            try await session.dispatch(RippleDeleteCommand(clipId: selectedClipId))
            self.selectedClipId = nil
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    @discardableResult
    func exportProject() async throws -> URL {
        try await exportEngine.exportProject(currentProject)
    }

    func cancelExport() {
        exportEngine.cancelExport()
    }

    func clearError() { lastErrorMessage = nil }

    private var selectedClipTrackId: UUID? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == selectedClipId }
        }?.id
    }

    private func apply(_ command: any EditorCommand) async {
        do {
            try await session.dispatch(command)
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    private func refreshFromSession() async {
        self.lastErrorMessage = nil
        currentProject = await session.snapshot()
        if selectedClipId != nil, selectedClip == nil {
            selectedClipId = nil
        }
        playheadTime = min(max(0, playheadTime), currentProject.timeline.duration)
        if currentProject.timeline.duration == 0 {
            isPlaying = false
        }
    }

    private func duplicatedClip(after originalClip: Clip?, trackId: UUID?, excluding originalClipId: UUID) -> Clip? {
        guard
            let originalClip,
            let trackId,
            let track = currentProject.timeline.tracks.first(where: { $0.id == trackId })
        else { return nil }

        return track.clips.first { clip in
            clip.id != originalClipId
                && clip.assetId == originalClip.assetId
                && clip.kind == originalClip.kind
                && clip.sourceRange == originalClip.sourceRange
                && abs(clip.timelineRange.start - originalClip.timelineRange.end) < 0.0001
                && abs(clip.timelineRange.duration - originalClip.timelineRange.duration) < 0.0001
        }
    }

    private func duration(for url: URL, kind: MediaKind) async -> TimeInterval? {
        guard kind != .image else { return nil }
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.seconds.isFinite else {
            return nil
        }
        return duration.seconds > 0 ? duration.seconds : nil
    }

    private func defaultDuration(for asset: MediaAsset) -> TimeInterval {
        if let duration = asset.duration, duration > 0 {
            return duration
        }
        return 5
    }

    private func clipKind(for mediaKind: MediaKind) -> ClipKind {
        switch mediaKind {
        case .video: .video
        case .audio: .audio
        case .image: .image
        }
    }

    private func trackKind(for mediaKind: MediaKind) -> TrackKind {
        switch mediaKind {
        case .video, .image: .video
        case .audio: .audio
        }
    }

    private static func defaultProject() -> Project {
        let tracks = [
            Track(kind: .video, name: "Video", zIndex: 0),
            Track(kind: .audio, name: "Audio", zIndex: 1),
            Track(kind: .text, name: "Text", zIndex: 2)
        ]
        return Project(name: "Untitled Project", timeline: Timeline(tracks: tracks))
    }

    func addTextClip(text: String, fontName: String, fontSize: Double, color: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        do {
            let snapshot = await session.snapshot()
            let track: Track
            if let existingTrack = snapshot.timeline.tracks.first(where: { $0.kind == .text }) {
                track = existingTrack
            } else {
                let textTrack = Track(
                    kind: .text,
                    name: "Text",
                    zIndex: snapshot.timeline.tracks.count
                )
                try await session.dispatch(CreateTrackCommand(track: textTrack))
                track = textTrack
            }

            let duration: TimeInterval = 5
            let content = TextClipContent(
                text: trimmedText,
                fontFamily: fontName,
                fontSize: fontSize,
                fontColor: color
            )
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration),
                textContent: content
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func trimClip(clipId: UUID, newStart: TimeInterval, newDuration: TimeInterval) async {
        guard newStart.isFinite, newDuration.isFinite, newDuration >= 0 else { return }

        let trackAndClip = currentProject.timeline.tracks.compactMap { track -> (Track, Clip)? in
            guard let clip = track.clips.first(where: { $0.id == clipId }) else { return nil }
            return (track, clip)
        }.first
        guard let (track, clip) = trackAndClip else { return }

        let sourceStartDelta = newStart - clip.timelineRange.start
        let sourceRange = TimeRange(
            start: max(0, clip.sourceRange.start + sourceStartDelta),
            duration: newDuration
        )
        let timelineRange = TimeRange(start: newStart, duration: newDuration)

        do {
            try await session.dispatch(
                TrimClipCommand(
                    clipId: clipId,
                    trackId: track.id,
                    newSourceRange: sourceRange,
                    newTimelineRange: timelineRange
                )
            )
            selectedClipId = clipId
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func applyEffect(_ effectType: String) async {
        guard
            let selectedClipId,
            let selectedClip,
            let type = EffectType(rawValue: effectType)
        else { return }

        var effects = selectedClip.effects
        effects.append(Effect(type: type))

        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .effects(effects)))
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }
}
