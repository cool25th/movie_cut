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
    var musicLibrary: MusicLibrary = MusicLibrary.placeholder()
    var templateStore: TemplateStore

    private let session: EditorSession
    private var sfxURLResolver: [String: URL]

    init() {
        let project = Self.defaultProject()
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        session = EditorSession(project: project)
        sfxURLResolver = Self.makeSFXURLResolver()
        templateStore = TemplateStore()
        for bundle in TemplateStore.builtInTemplates() {
            templateStore.add(bundle)
        }
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

    func addMusicTrack(_ track: MovieCutCore.MusicTrack) async {
        do {
            let duration: TimeInterval
            if track.duration > 0 {
                duration = track.duration
            } else {
                duration = await self.duration(for: track.fileURL, kind: .audio) ?? 5
            }

            let asset = MediaAsset(
                originalURL: track.fileURL,
                kind: .audio,
                duration: duration,
                metadata: MediaMetadata(fileSize: fileSize(for: track.fileURL))
            )

            try await session.dispatch(ImportMediaCommand(asset: asset))

            let audioTrack = try await ensureTrack(for: .audio)
            let clip = Clip(
                assetId: asset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func addSFXToTimeline(_ item: SFXItem) async {
        guard let fileURL = resolveSFXURL(for: item) else {
            lastErrorMessage = "Missing bundled sound effect: \(item.fileName)"
            return
        }

        do {
            let duration = await duration(for: fileURL, kind: .audio) ?? 1
            let asset = MediaAsset(
                originalURL: fileURL,
                kind: .audio,
                duration: duration,
                metadata: MediaMetadata(fileSize: fileSize(for: fileURL))
            )

            try await session.dispatch(ImportMediaCommand(asset: asset))

            let audioTrack = try await ensureTrack(for: .audio)
            let clip = Clip(
                assetId: asset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    func sfxURL(for item: SFXItem) -> URL? {
        resolveSFXURL(for: item)
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

    func updateSelectedEffects(_ effects: [Effect]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .effects(effects)))
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

    private func ensureTrack(for kind: TrackKind) async throws -> Track {
        let snapshot = await session.snapshot()
        if let track = snapshot.timeline.tracks.first(where: { $0.kind == kind }) {
            return track
        }

        let track = Track(
            kind: kind,
            name: defaultTrackName(for: kind, index: snapshot.timeline.tracks.count + 1),
            zIndex: snapshot.timeline.tracks.count
        )
        try await session.dispatch(CreateTrackCommand(track: track))
        return track
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

    private func fileSize(for url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(value)
    }

    private func resolveSFXURL(for item: SFXItem) -> URL? {
        if let url = sfxURLResolver[item.fileName] {
            return url
        }

        guard let url = Self.bundleSFXURL(for: item.fileName) else {
            return nil
        }

        sfxURLResolver[item.fileName] = url
        return url
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

    private static func makeSFXURLResolver() -> [String: URL] {
        Dictionary(uniqueKeysWithValues: SFXLibrary.all.compactMap { item in
            guard let url = bundleSFXURL(for: item.fileName) else {
                return nil
            }
            return (item.fileName, url)
        })
    }

    private static func bundleSFXURL(for fileName: String) -> URL? {
        let fileURL = URL(fileURLWithPath: fileName)
        let resourceName = fileURL.deletingPathExtension().lastPathComponent
        let fileExtension = fileURL.pathExtension

        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "SFX") {
            return url
        }

        if let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension, subdirectory: "Resources/SFX") {
            return url
        }

        return Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
    }

    private func defaultTrackName(for kind: TrackKind, index: Int) -> String {
        switch kind {
        case .video:
            return "Video \(index)"
        case .audio:
            return "Audio \(index)"
        case .text:
            return "Text \(index)"
        }
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

    func moveClip(clipId: UUID, newStart: TimeInterval) async {
        guard newStart.isFinite else { return }

        let trackAndClip = currentProject.timeline.tracks.compactMap { track -> (Track, Clip)? in
            guard let clip = track.clips.first(where: { $0.id == clipId }) else { return nil }
            return (track, clip)
        }.first
        guard let (track, clip) = trackAndClip else { return }

        let timelineRange = TimeRange(
            start: max(0, newStart),
            duration: clip.timelineRange.duration
        )

        do {
            try await session.dispatch(
                MoveClipCommand(
                    clipId: clipId,
                    sourceTrackId: track.id,
                    targetTrackId: track.id,
                    newTimelineRange: timelineRange
                )
            )
            selectedClipId = clipId
            playheadTime = timelineRange.start
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

    func clearEffects() async {
        guard let selectedClipId else { return }

        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .effects([])))
            await refreshFromSession()
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
    }

    // MARK: - Integrated View Support

    func updateCanvasPreset(_ preset: CanvasPreset) async {
        currentProject.canvas = preset
    }

    func updateSelectedChromaKey(_ chromaKey: ChromaKeySettings?) async {
        guard let selectedClipId else { return }
        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .chromaKey(chromaKey)))
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedMask(_ mask: Mask?) async {
        guard let selectedClipId else { return }
        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .mask(mask)))
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedKeyframes(_ keyframes: [Keyframe]) async {
        guard let selectedClipId else { return }
        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .keyframes(keyframes)))
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func updateSelectedColorCorrection(_ colorCorrection: ColorCorrection?) async {
        guard let selectedClipId else { return }
        do {
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .colorCorrection(colorCorrection)))
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Sets the 3-way (lift / gamma / gain) color grade on the selected clip.
    /// Mirrors `EditorViewModel.updateSelectedColorGrade` so iOS gets an
    /// adjustable grade UI on top of the rendering parity landed in 947b88b.
    func updateSelectedColorGrade(_ colorGrade: ColorGrade?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .colorGrade(colorGrade)))
    }

    /// Sets audio fade in/out on the selected clip. Passing `nil` for a
    /// parameter keeps that clip's current value (mirrors the Mac view model).
    func updateSelectedAudioFade(fadeInDuration: TimeInterval? = nil, fadeOutDuration: TimeInterval? = nil) async {
        guard let selectedClipId, let selectedClip else { return }
        await apply(AudioFadeCommand(
            clipId: selectedClipId,
            fadeInDuration: fadeInDuration ?? selectedClip.fadeInDuration,
            fadeOutDuration: fadeOutDuration ?? selectedClip.fadeOutDuration
        ))
    }
}
