import AppKit
import AVFoundation
import Foundation
import MovieCutCore
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorViewModel {
    struct TextTemplate: Identifiable {
        let id: String
        let name: String
        let fontName: String
        let fontSize: Double
        let isBold: Bool
        let alignment: TextAlignment
        let animation: TextAnimationType?
    }

    static let textTemplates: [TextTemplate] = [
        TextTemplate(id: "title", name: "Title", fontName: "HelveticaNeue-Bold", fontSize: 36, isBold: true, alignment: .center, animation: .fadeIn),
        TextTemplate(id: "subtitle", name: "Subtitle", fontName: "HelveticaNeue", fontSize: 24, isBold: false, alignment: .center, animation: .slideUp),
        TextTemplate(id: "caption", name: "Caption", fontName: "SFPro-Medium", fontSize: 18, isBold: false, alignment: .center, animation: nil),
        TextTemplate(id: "lower_third", name: "Lower Third", fontName: "HelveticaNeue-Bold", fontSize: 20, isBold: true, alignment: .leading, animation: .slideUp),
        TextTemplate(id: "credit", name: "Credits", fontName: "HelveticaNeue-Light", fontSize: 14, isBold: false, alignment: .center, animation: .typewriter),
    ]

    var currentProject: Project
    var canvasSelection: AspectRatio = .landscape16x9
    var selectedClipIds: Set<UUID> = [] {
        didSet {
            loadSelectedClipProcessingState()
        }
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
    var selectedEQPreset: String = "flat"
    var isBackgroundRemoved: Bool = false
    var selectedStyle: String = "none"
    var exportResolution: String = "1080p"
    var exportQuality: String = "high"
    var selectedAssetId: UUID?
    var playbackEngine: PlaybackEngine
    var exportEngine: ExportEngine
    var musicLibrary: MusicLibrary
    var transcriptionService: TranscriptionService
    var templateStore: TemplateStore
    var generatedSubtitleSegments: [TranscriptionSegment] = []
    var pendingSubtitleClips: [Clip] = []
    var playheadTime: TimeInterval = 0
    var timelineZoom: Double = 80
    var lastErrorMessage: String?
    var lastExportURL: URL?
    var isCloudSyncing: Bool = false
    var cloudSyncError: String?
    var exportFormat: String = "mp4"
    var cloudProjects: [CloudProjectInfo] = []

    @ObservationIgnored private var session: EditorSession
    @ObservationIgnored private let projectStore = ProjectStore()
    @ObservationIgnored private var waveformCache: [UUID: [CGFloat]] = [:]
    @ObservationIgnored private var clipEQPresets: [UUID: String] = [:]
    @ObservationIgnored private var noiseReductionClipIds: Set<UUID> = []
    @ObservationIgnored private var backgroundRemovedClipIds: Set<UUID> = []
    @ObservationIgnored private var clipStyles: [UUID: String] = [:]

    init(project: Project = EditorViewModel.defaultProject()) {
        let project = EditorViewModel.ensureDefaultTracks(in: project)
        self.currentProject = project
        self.canvasSelection = project.canvas.aspectRatio
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()
        self.musicLibrary = MusicLibrary.placeholder()
        self.transcriptionService = TranscriptionService()
        self.templateStore = TemplateStore()
        self.session = EditorSession(project: project)

        for bundle in TemplateStore.builtInTemplates() {
            self.templateStore.add(bundle)
        }
    }

    var mediaAssets: [MediaAsset] {
        currentProject.mediaLibrary.assets.values.sorted {
            $0.originalURL.lastPathComponent.localizedStandardCompare($1.originalURL.lastPathComponent) == .orderedAscending
        }
    }

    var selectedAsset: MediaAsset? {
        guard let selectedAssetId else { return nil }
        return currentProject.mediaLibrary.assets[selectedAssetId]
    }

    var selectedClip: Clip? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == selectedClipId }
    }

    var selectedTranscribableAsset: MediaAsset? {
        if
            let selectedClip,
            let assetId = selectedClip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            asset.kind == .audio || asset.kind == .video
        {
            return asset
        }

        if let selectedAsset, selectedAsset.kind == .audio || selectedAsset.kind == .video {
            return selectedAsset
        }

        return nil
    }

    func waveform(for clip: Clip) -> [CGFloat] {
        if let cached = waveformCache[clip.id] { return cached }

        guard
            clip.kind == .video || clip.kind == .audio,
            let assetId = clip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            asset.kind == .video || asset.kind == .audio,
            let waveformData = WaveformGenerator.generate(for: asset)
        else {
            waveformCache[clip.id] = []
            return []
        }

        let samples = waveformData.samples.map { CGFloat($0) }
        waveformCache[clip.id] = samples
        return samples
    }

    var canGenerateSubtitles: Bool {
        selectedTranscribableAsset != nil
    }

    var selectedClipTrackId: UUID? {
        guard let selectedClipId else { return nil }
        return currentProject.timeline.tracks.first { track in
            track.clips.contains { $0.id == selectedClipId }
        }?.id
    }

    var visibleTimelineDuration: TimeInterval {
        max(10, currentProject.timeline.duration, playheadTime)
    }

    func newProject() {
        let project = Self.defaultProject()
        session = EditorSession(project: project)
        currentProject = project
        canvasSelection = project.canvas.aspectRatio
        selectedClipId = nil
        selectedAssetId = nil
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        lastErrorMessage = nil
        lastExportURL = nil
    }

    func openProject(from url: URL) async {
        do {
            let loadedProject = try await projectStore.load(from: url)
            let project = Self.ensureDefaultTracks(in: loadedProject)
            session = EditorSession(project: project)
            currentProject = project
            canvasSelection = project.canvas.aspectRatio
            selectedClipId = nil
            selectedAssetId = nil
            playbackEngine.clear()
            playheadTime = 0
            clearGeneratedSubtitles()
            clearClipProcessingState()
            lastErrorMessage = nil
            lastExportURL = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveProject(to url: URL) async {
        do {
            let snapshot = await session.snapshot()
            try await projectStore.save(snapshot, to: url)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func saveProject() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "moviecut") ?? .json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).moviecut"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        await saveProject(to: url)
    }

    func syncToCloud() async {
        isCloudSyncing = true
        defer { isCloudSyncing = false }

        do {
            let sync = CloudSyncService()
            try await sync.sync(project: currentProject)
            cloudSyncError = nil
        } catch {
            cloudSyncError = error.localizedDescription
        }
    }

    func loadFromCloud() async {
        isCloudSyncing = true
        defer { isCloudSyncing = false }

        do {
            let sync = CloudSyncService()
            let projects = try await sync.listRemoteProjects()
            cloudProjects = projects
            cloudSyncError = nil
        } catch {
            cloudSyncError = error.localizedDescription
        }
    }

    func listCloudProjects() async {
        await loadFromCloud()
    }

    func openCloudProject(name: String) async {
        isCloudSyncing = true
        defer { isCloudSyncing = false }

        do {
            let sync = CloudSyncService()
            let project = try await sync.download(name: name)
            let loaded = Self.ensureDefaultTracks(in: project)
            session = EditorSession(project: loaded)
            currentProject = loaded
            canvasSelection = loaded.canvas.aspectRatio
            selectedClipId = nil
            selectedAssetId = nil
            playbackEngine.clear()
            playheadTime = 0
            clearGeneratedSubtitles()
            clearClipProcessingState()
            lastErrorMessage = nil
            lastExportURL = nil
            cloudSyncError = nil
        } catch {
            cloudSyncError = error.localizedDescription
        }
    }

    func exportProject() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true

        // Set default extension based on selected format
        let ext = exportFormat == "mov" ? "mov" : "mp4"
        panel.nameFieldStringValue = "\(currentProject.name).\(ext)"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        lastExportURL = nil

        // Configure export engine with current settings
        exportEngine.exportResolution = exportResolution
        exportEngine.exportQuality = exportQuality
        exportEngine.exportFormat = exportFormat
        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds

        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.export(project: snapshot, to: url, audioProcessing: buildAudioProcessingOptions())
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func cancelExport() {
        exportEngine.cancelExport()
    }

    func importMedia(_ urls: [URL]) async {
        do {
            for url in urls {
                let asset = MediaImporter.probe(url: url)
                try await session.dispatch(ImportMediaCommand(asset: asset))
                selectedAssetId = asset.id
            }
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addClipToTimeline() async {
        guard let selectedAsset else { return }
        await addClipToTimeline(selectedAsset)
    }

    func addClipToTimeline(_ asset: MediaAsset) async {
        do {
            let track = try await ensureTrack(for: trackKind(for: asset.kind))
            let duration = defaultDuration(for: asset)
            let start = currentProject.timeline.duration
            let clip = Clip(
                assetId: asset.id,
                kind: clipKind(for: asset.kind),
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: start, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addMusicTrack(_ track: MovieCutCore.MusicTrack) async {
        do {
            let duration = track.duration > 0 ? track.duration : 5
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
            selectedAssetId = asset.id
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addTextClip(text: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        do {
            let track = try await ensureTrack(for: .text)
            let duration: TimeInterval = 5
            let start = playheadTime
            let content = TextClipContent(text: trimmedText)
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: start, duration: duration),
                textContent: content
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addSticker(_ sticker: StickerAsset) async {
        let stickerText = sticker.emoji ?? sticker.name
        guard !stickerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        do {
            let track = try await ensureTrack(for: .text)
            let duration: TimeInterval = 3
            let content = TextClipContent(
                text: stickerText,
                fontFamily: "Apple Color Emoji",
                fontSize: 48,
                alignment: .center
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
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addTextFromTemplate(_ template: TextTemplate) async {
        do {
            let track = try await ensureTrack(for: .text)
            let duration: TimeInterval = 5
            let content = TextClipContent(
                text: template.name,
                fontFamily: template.fontName,
                fontSize: template.fontSize,
                alignment: template.alignment,
                animation: template.animation.map { TextAnimation(type: $0) }
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
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
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

    func undo() async {
        do {
            try await session.undo()
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func redo() async {
        do {
            try await session.redo()
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func togglePlayPause() {
        playbackEngine.togglePlayPause()
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

    func updateSelectedTransform(_ transform: ClipTransform) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transform(transform)))
    }

    func updateSelectedOpacity(_ opacity: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .opacity(opacity)))
    }

    func updateSelectedVolume(_ volume: Double) async {
        guard let selectedClipId else { return }
        await apply(SetVolumeCommand(clipId: selectedClipId, volume: volume))
    }

    func updateSelectedAudioFade(fadeInDuration: TimeInterval? = nil, fadeOutDuration: TimeInterval? = nil) async {
        guard let selectedClipId, let selectedClip else { return }
        await apply(AudioFadeCommand(
            clipId: selectedClipId,
            fadeInDuration: fadeInDuration ?? selectedClip.fadeInDuration,
            fadeOutDuration: fadeOutDuration ?? selectedClip.fadeOutDuration
        ))
    }

    func applyEQPreset(_ preset: String) async {
        guard let clipId = selectedClipId else { return }

        selectedEQPreset = preset
        if preset == "flat" {
            clipEQPresets.removeValue(forKey: clipId)
        } else {
            clipEQPresets[clipId] = preset
        }
    }

    func toggleBackgroundRemoval(_ enabled: Bool) async {
        guard let clipId = selectedClipId else { return }

        isBackgroundRemoved = enabled
        if enabled {
            backgroundRemovedClipIds.insert(clipId)
        } else {
            backgroundRemovedClipIds.remove(clipId)
        }
    }

    func applyStyleTransfer(_ style: String) async {
        guard let clipId = selectedClipId else { return }

        selectedStyle = style
        if style == "none" {
            clipStyles.removeValue(forKey: clipId)
        } else {
            clipStyles[clipId] = style
        }

        guard let clip = currentProject.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == clipId })
        else {
            return
        }

        var effects = clip.effects.filter { $0.type != .styleTransfer }
        if let styleIndex = styleTransferIndex(for: style) {
            effects.append(Effect(
                type: .styleTransfer,
                parameters: [
                    "styleIndex": styleIndex,
                    "intensity": 0.75
                ]
            ))
        }

        await apply(SetClipPropertyCommand(clipId: clipId, property: .effects(effects)))
    }

    func applyDucking(to clipId: UUID, duckLevel: Double = 0.3) async {
        await apply(AudioDuckingCommand(clipId: clipId, duckLevel: duckLevel))
    }

    func updateSelectedPlaybackRate(_ rate: Double) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .playbackRate(rate)))
        playbackEngine.setRate(Float(rate))
    }

    func updateSelectedSpeedRampPoints(_ points: [SpeedRampPoint]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .speedRampPoints(points)))
    }

    func updateSelectedKeyframes(_ keyframes: [Keyframe]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .keyframes(keyframes)))
    }

    func updateCanvas(_ canvas: CanvasPreset) async {
        await apply(SetProjectCanvasCommand(canvas: canvas))
    }

    func updateSelectedTransition(_ transition: Transition?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transition(transition)))
    }

    func updateSelectedTextContent(_ textContent: TextClipContent?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .textContent(textContent)))
    }

    func updateSelectedChromaKey(_ chromaKey: ChromaKeySettings?) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .chromaKey(chromaKey)))
    }

    func updateSelectedColorCorrection(_ colorCorrection: ColorCorrection?) async {
        guard let selectedClipId else { return }
        await apply(SetColorCorrectionCommand(clipId: selectedClipId, colorCorrection: colorCorrection))
    }

    func autoEnhance() async {
        guard let clipId = selectedClipId else { return }
        try? await autoColorCorrect(for: clipId)
    }

    func suggestCuts() async throws {
        guard let clipId = selectedClipId else { return }
        try? await autoCutSilence(for: clipId)
        try? await detectAndSplitScenes(for: clipId)
    }

    func autoColorCorrect() async {
        guard let clipId = selectedClipId else { return }
        try? await autoColorCorrect(for: clipId)
    }

    func autoColorCorrect(for clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        var found: Clip?
        outer: for (ti, track) in snapshot.timeline.tracks.enumerated() {
            for (ci, c) in track.clips.enumerated() {
                if c.id == clipId { found = c; break outer }
            }
        }
        guard var clip = found else {
            throw EditorCommandError.invalidCommand("Clip not found")
        }
        var colorCorrection = clip.colorCorrection ?? ColorCorrection()
        colorCorrection.brightness = 0.05
        colorCorrection.contrast = 1.1
        colorCorrection.saturation = 1.1

        try await session.dispatch(SetColorCorrectionCommand(clipId: clipId, colorCorrection: colorCorrection))
        try await refreshFromSession()
    }

    func applyNoiseReduction(for clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)

        let service = NoiseReductionService()
        let denoisedURL = try await service.applyNoiseReduction(to: AVAsset(url: asset.originalURL))
        let denoisedAsset = MediaAsset(
            originalURL: denoisedURL,
            kind: .audio,
            duration: asset.duration,
            metadata: MediaMetadata(fileSize: fileSize(for: denoisedURL))
        )

        try await session.dispatch(ImportMediaCommand(asset: denoisedAsset))

        switch clip.kind {
        case .audio:
            try await session.dispatch(
                SetClipSourceAssetCommand(clipId: clipId, assetId: denoisedAsset.id, kind: .audio)
            )
            waveformCache.removeValue(forKey: clipId)
            selectedAssetId = denoisedAsset.id
        case .video:
            let audioTrack = try await ensureTrack(for: .audio)
            let denoisedClip = Clip(
                assetId: denoisedAsset.id,
                kind: .audio,
                sourceRange: clip.sourceRange,
                timelineRange: clip.timelineRange,
                volume: clip.volume,
                fadeInDuration: clip.fadeInDuration,
                fadeOutDuration: clip.fadeOutDuration,
                playbackRate: clip.playbackRate
            )

            try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: denoisedClip))
            try await session.dispatch(SetClipPropertyCommand(clipId: clipId, property: .volume(0)))
            selectedAssetId = denoisedAsset.id
            selectedClipId = denoisedClip.id
        case .image, .text:
            throw EditorCommandError.invalidCommand("Select an audio or video clip for noise reduction.")
        }

        try await refreshFromSession()
    }

    func extractAudio(from clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        guard asset.kind == .video else {
            throw EditorCommandError.invalidCommand("Audio can only be extracted from video clips.")
        }

        let sourceAsset = AVAsset(url: asset.originalURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutExtractedAudio_\(clipId.uuidString)")
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: sourceAsset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw EditorCommandError.invalidCommand("Could not create audio export session.")
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        let sourceStart = CMTime(seconds: clip.sourceRange.start, preferredTimescale: 600)
        let sourceDur = CMTime(seconds: clip.sourceRange.duration, preferredTimescale: 600)
        exportSession.timeRange = CMTimeRange(start: sourceStart, duration: sourceDur)

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw EditorCommandError.invalidCommand(
                exportSession.error?.localizedDescription ?? "Audio extraction failed."
            )
        }

        let audioAsset = MediaAsset(
            originalURL: outputURL,
            kind: .audio,
            duration: clip.sourceRange.duration,
            metadata: MediaMetadata(fileSize: fileSize(for: outputURL))
        )

        try await session.dispatch(ImportMediaCommand(asset: audioAsset))

        let audioTrack = try await ensureTrack(for: .audio)
        let audioClip = Clip(
            assetId: audioAsset.id,
            kind: .audio,
            sourceRange: TimeRange(start: 0, duration: clip.sourceRange.duration),
            timelineRange: clip.timelineRange,
            volume: clip.volume,
            fadeInDuration: clip.fadeInDuration,
            fadeOutDuration: clip.fadeOutDuration,
            playbackRate: clip.playbackRate
        )

        try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: audioClip))
        selectedAssetId = audioAsset.id
        selectedClipId = audioClip.id
        try await refreshFromSession()
    }

    func addMarkerAtPlayhead() {
        let time = max(0, playheadTime)
        let markerName = "Marker \(currentProject.markers.count + 1)"
        let marker = Marker(time: time, name: markerName, color: "#FFD60A")

        Task { await apply(AddMarkerCommand(marker: marker)) }
    }

    func updateSelectedMask(_ mask: Mask?) async {
        guard let selectedClipId else { return }
        await apply(SetClipMaskCommand(clipId: selectedClipId, mask: mask))
    }

    func updateSelectedReversePlayback(_ isReversed: Bool) async {
        guard let selectedClipId, let selectedClip, selectedClip.isReversed != isReversed else { return }
        await apply(ReverseClipCommand(clipId: selectedClipId))
    }

    func freezeSelectedFrame(freezeDuration: TimeInterval = 2.0) async {
        guard let selectedClipId, let selectedClip else { return }

        let freezeTime = playheadTime - selectedClip.timelineRange.start
        guard freezeTime > 0, freezeTime < selectedClip.timelineRange.duration else {
            lastErrorMessage = "Move the playhead inside the selected clip to freeze a frame."
            return
        }

        await apply(FreezeFrameCommand(clipId: selectedClipId, freezeTime: freezeTime, freezeDuration: freezeDuration))
    }

    func updateSelectedEffects(_ effects: [Effect]) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .effects(effects)))
    }

    func prepareSubtitles(for clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)

        clearGeneratedSubtitles()
        transcriptionService.isTranscribing = true
        transcriptionService.progress = 0
        defer {
            transcriptionService.isTranscribing = false
            transcriptionService.progress = 1
        }

        let provider = SpeechTranscriptionProvider()
        let result = try await provider.transcribe(audioURL: asset.originalURL, language: nil)
        let subtitleClips = subtitleClips(from: result, alignedTo: clip)

        generatedSubtitleSegments = result.segments

        guard !subtitleClips.isEmpty else {
            lastErrorMessage = nil
            return
        }

        let textTrack = try await ensureTrack(for: .text)
        for subtitleClip in subtitleClips {
            try await session.dispatch(AddClipCommand(trackId: textTrack.id, clip: subtitleClip))
        }

        selectedClipId = subtitleClips.first?.id
        try await refreshFromSession()
    }

    func prepareSubtitles() async {
        guard let asset = selectedTranscribableAsset else {
            lastErrorMessage = "Select an audio or video clip to generate subtitles."
            return
        }

        clearGeneratedSubtitles()

        do {
            let result = try await transcriptionService.transcribe(asset: asset)
            generatedSubtitleSegments = result.segments
            pendingSubtitleClips = transcriptionService.subtitles(from: result, in: currentProject)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func applyGeneratedSubtitles() async {
        let clips = pendingSubtitleClips
        guard !clips.isEmpty else { return }

        do {
            let textTrack = try await ensureTrack(for: .text)
            for clip in clips {
                try await session.dispatch(AddClipCommand(trackId: textTrack.id, clip: clip))
            }
            pendingSubtitleClips = []
            selectedClipId = clips.first?.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func generateSubtitles() async {
        await prepareSubtitles()
        await applyGeneratedSubtitles()
    }

    func autoCutSilence(
        for clipId: UUID,
        thresholdDB: Float = -40,
        minDuration: TimeInterval = 0.5
    ) async throws {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        let provider = SilenceDetectionProvider(
            silenceThresholdDB: thresholdDB,
            minimumSilenceDuration: minDuration
        )

        let result = try await provider.analyze(asset: asset, in: snapshot)
        let timelineSuggestions = timelineSuggestions(from: result.suggestions, alignedTo: clip)
        guard !timelineSuggestions.isEmpty else {
            lastErrorMessage = nil
            return
        }

        let commands = try await AutoCutEngine.apply(suggestions: timelineSuggestions, to: session)
        for command in commands {
            try await session.dispatch(command)
        }

        try await refreshFromSession()
    }

    func detectAndSplitScenes(for clipId: UUID, threshold: Float = 0.3) async throws {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        guard asset.kind == .video else {
            throw EditorCommandError.invalidCommand("Select a video clip to detect scenes.")
        }

        let trackId = try trackId(containing: clipId, in: snapshot)
        let provider = SceneChangeProvider()
        provider.changeThreshold = threshold

        let result = try await provider.analyze(asset: asset, in: snapshot)
        let sourceTimes = result.suggestions.flatMap { suggestion -> [TimeInterval] in
            guard case .sceneChanges(let times) = suggestion else { return [] }
            return times
        }
        let splitTimes = sourceTimes.compactMap { time -> TimeInterval? in
            let pointRange = TimeRange(start: time, duration: .ulpOfOne)
            guard let timelineTime = timelineMapping(for: pointRange, in: clip)?.timelineRange.start,
                  timelineTime > clip.timelineRange.start,
                  timelineTime < clip.timelineRange.end else {
                return nil
            }
            return timelineTime
        }

        let uniqueSplitTimes = Array(Set(splitTimes.filter { $0.isFinite })).sorted(by: >)
        guard !uniqueSplitTimes.isEmpty else {
            lastErrorMessage = nil
            return
        }

        for splitTime in uniqueSplitTimes {
            try await splitClipAtTime(splitTime, clipId: clipId, trackId: trackId)
        }

        try await refreshFromSession()
    }

    func autoReframe(for clipId: UUID, targetAspect: CGFloat) async throws {
        guard targetAspect.isFinite, targetAspect > 0 else {
            throw EditorCommandError.invalidCommand("Target aspect ratio must be greater than zero.")
        }

        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        guard asset.kind == .video else {
            throw EditorCommandError.invalidCommand("Select a video clip to auto reframe.")
        }

        let provider = AutoReframeProvider()
        let avAsset = AVAsset(url: asset.originalURL)
        let frames = await provider.calculateCropFrames(for: avAsset, targetAspect: targetAspect)
        let canvasSize = effectiveCanvasSize(in: snapshot)

        var generatedKeyframes: [Keyframe] = []
        for frame in frames {
            let pointRange = TimeRange(start: frame.time, duration: .ulpOfOne)
            guard let mapping = timelineMapping(for: pointRange, in: clip) else {
                continue
            }

            let localTime = mapping.timelineRange.start - clip.timelineRange.start
            let posX = Double(frame.rect.midX - 0.5) * Double(canvasSize.width)
            let posY = Double(frame.rect.midY - 0.5) * Double(canvasSize.height)
            let scale = Double(1.0 / max(frame.rect.width, .leastNonzeroMagnitude))

            generatedKeyframes.append(Keyframe(property: .positionX, time: localTime, value: posX))
            generatedKeyframes.append(Keyframe(property: .positionY, time: localTime, value: posY))
            generatedKeyframes.append(Keyframe(property: .scaleX, time: localTime, value: scale))
            generatedKeyframes.append(Keyframe(property: .scaleY, time: localTime, value: scale))
        }

        guard !generatedKeyframes.isEmpty else {
            lastErrorMessage = nil
            return
        }

        let reframedProperties: Set<AnimatableProperty> = [.positionX, .positionY, .scaleX, .scaleY]
        let preservedKeyframes = clip.keyframes.filter { !reframedProperties.contains($0.property) }
        let updatedKeyframes = (preservedKeyframes + generatedKeyframes).sorted {
            if $0.time == $1.time {
                return $0.property.rawValue < $1.property.rawValue
            }
            return $0.time < $1.time
        }

        // Persist auto-reframe keyframes on the clip; export forwards clip.keyframes to CustomVideoCompositor.
        try await session.dispatch(SetClipPropertyCommand(clipId: clipId, property: .keyframes(updatedKeyframes)))
        try await refreshFromSession()
    }

    private func apply(_ command: any EditorCommand) async {
        do {
            try await session.dispatch(command)
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func refreshFromSession() async throws {
        currentProject = await session.snapshot()
        canvasSelection = currentProject.canvas.aspectRatio

        selectedClipIds.formIntersection(currentClipIds)

        if let selectedAssetId, currentProject.mediaLibrary.assets[selectedAssetId] == nil {
            self.selectedAssetId = nil
        }

        playheadTime = min(playheadTime, max(0, currentProject.timeline.duration))
        lastErrorMessage = nil
    }

    private func clearGeneratedSubtitles() {
        generatedSubtitleSegments = []
        pendingSubtitleClips = []
    }

    private func clearClipProcessingState() {
        clipEQPresets = [:]
        backgroundRemovedClipIds = []
        clipStyles = [:]
        noiseReductionClipIds = []
        loadSelectedClipProcessingState()
    }

    private func loadSelectedClipProcessingState() {
        guard let selectedClipId else {
            selectedEQPreset = "flat"
            isBackgroundRemoved = false
            selectedStyle = "none"
            return
        }

        selectedEQPreset = clipEQPresets[selectedClipId] ?? "flat"
        isBackgroundRemoved = backgroundRemovedClipIds.contains(selectedClipId)
        selectedStyle = clipStyles[selectedClipId] ?? "none"
    }

    private func styleTransferIndex(for style: String) -> Double? {
        switch style {
        case "comic":
            return 1
        case "noir":
            return 2
        case "vintage":
            return 3
        case "cyberpunk":
            return 4
        case "watercolor":
            return 5
        default:
            return nil
        }
    }

    private var currentClipIds: Set<UUID> {
        Set(currentProject.timeline.tracks.flatMap(\.clips).map(\.id))
    }

    private func splitClipAtTime(_ splitTime: TimeInterval, clipId: UUID, trackId: UUID?) async throws {
        try await session.dispatch(
            SplitClipCommand(clipId: clipId, trackId: trackId, splitTime: splitTime)
        )
    }

    private func trackId(containing clipId: UUID, in project: Project) throws -> UUID {
        for track in project.timeline.tracks where track.clips.contains(where: { $0.id == clipId }) {
            return track.id
        }

        throw EditorCommandError.clipNotFound(clipId)
    }

    private func effectiveCanvasSize(in project: Project) -> CGSize {
        let timelineSize = project.timeline.canvasSize
        if timelineSize.width > 0, timelineSize.height > 0 {
            return timelineSize
        }

        return project.canvas.size
    }

    private func sourceClipAndAsset(for clipId: UUID, in project: Project) throws -> (clip: Clip, asset: MediaAsset) {
        for track in project.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                guard let assetId = clip.assetId else {
                    throw EditorCommandError.invalidCommand("Selected clip has no source media.")
                }
                guard let asset = project.mediaLibrary.assets[assetId] else {
                    throw EditorCommandError.assetNotFound(assetId)
                }
                guard asset.kind == .audio || asset.kind == .video else {
                    throw EditorCommandError.invalidCommand("Select an audio or video clip.")
                }
                return (clip, asset)
            }
        }

        throw EditorCommandError.clipNotFound(clipId)
    }

    private func subtitleClips(from result: TranscriptionResult, alignedTo clip: Clip) -> [Clip] {
        result.segments.compactMap { segment in
            let sourceRange = TimeRange(
                start: segment.startTime,
                duration: max(0, segment.endTime - segment.startTime)
            )
            guard let mapping = timelineMapping(for: sourceRange, in: clip) else {
                return nil
            }

            return Clip(
                kind: .text,
                sourceRange: mapping.sourceRange,
                timelineRange: mapping.timelineRange,
                textContent: TextClipContent(
                    text: segment.text,
                    fontFamily: "SFPro-Medium",
                    fontSize: 18
                )
            )
        }
    }

    private func timelineSuggestions(
        from suggestions: [AnalysisSuggestion],
        alignedTo clip: Clip
    ) -> [AnalysisSuggestion] {
        suggestions.compactMap { suggestion in
            switch suggestion {
            case .silenceRemoval(let ranges):
                let mappedRanges = ranges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
                return mappedRanges.isEmpty ? nil : .silenceRemoval(ranges: mappedRanges)
            case .autoCut(let editedRanges):
                let mappedRanges = editedRanges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
                return mappedRanges.isEmpty ? nil : .autoCut(editedRanges: mappedRanges)
            case .sceneChanges(let times):
                let mappedTimes = times.compactMap { time -> TimeInterval? in
                    let pointRange = TimeRange(start: time, duration: .ulpOfOne)
                    return timelineMapping(for: pointRange, in: clip)?.timelineRange.start
                }
                return mappedTimes.isEmpty ? nil : .sceneChanges(times: mappedTimes)
            }
        }
    }

    private func timelineMapping(
        for sourceRange: TimeRange,
        in clip: Clip
    ) -> (sourceRange: TimeRange, timelineRange: TimeRange)? {
        guard
            sourceRange.start.isFinite,
            sourceRange.duration.isFinite,
            sourceRange.duration > 0
        else {
            return nil
        }

        let sourceStart = max(sourceRange.start, clip.sourceRange.start)
        let sourceEnd = min(sourceRange.end, clip.sourceRange.end)
        guard sourceEnd > sourceStart else { return nil }

        let playbackRate = max(clip.playbackRate, 0.25)
        let timelineStart = clip.timelineRange.start + (sourceStart - clip.sourceRange.start) / playbackRate
        let timelineEnd = min(
            clip.timelineRange.end,
            timelineStart + (sourceEnd - sourceStart) / playbackRate
        )
        guard timelineEnd > timelineStart else { return nil }

        return (
            sourceRange: TimeRange(start: sourceStart, duration: sourceEnd - sourceStart),
            timelineRange: TimeRange(start: timelineStart, duration: timelineEnd - timelineStart)
        )
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

    private func syncTimelinePlayhead(to playbackTime: TimeInterval) {
        guard let clip = selectedClip else {
            playheadTime = min(max(0, playbackTime), max(0, currentProject.timeline.duration))
            return
        }

        let sourceOffset = max(0, playbackTime - clip.sourceRange.start)
        let timelineOffset = sourceOffset / max(clip.playbackRate, 0.25)
        let timelineTime = clip.timelineRange.start + timelineOffset
        playheadTime = min(max(0, timelineTime), clip.timelineRange.end)
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

    private func clipKind(for mediaKind: MediaKind) -> ClipKind {
        switch mediaKind {
        case .video:
            return .video
        case .audio:
            return .audio
        case .image:
            return .image
        }
    }

    private func trackKind(for mediaKind: MediaKind) -> TrackKind {
        switch mediaKind {
        case .video, .image:
            return .video
        case .audio:
            return .audio
        }
    }

    private func defaultDuration(for asset: MediaAsset) -> TimeInterval {
        if let duration = asset.duration, duration > 0 {
            return duration
        }
        return asset.kind == .image ? 5 : 5
    }

    private func fileSize(for url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(value)
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

    private func renderEmojiSticker(_ emoji: String, id: UUID) throws -> URL {
        let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent("MovieCutStickers", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        let fileURL = folderURL.appendingPathComponent("\(id.uuidString).png")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }

        let size = CGSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: NSPoint(x: 0, y: 0), size: size).fill()

        let font = NSFont.systemFont(ofSize: 280)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let attributedEmoji = NSAttributedString(string: emoji, attributes: attributes)
        let textSize = attributedEmoji.size()
        let origin = CGPoint(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2
        )
        attributedEmoji.draw(at: origin)
        image.unlockFocus()

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: fileURL, options: .atomic)
        return fileURL
    }


    func toggleNoiseReduction(_ enabled: Bool) {
        guard let clipId = selectedClipId else { return }
        if enabled {
            noiseReductionClipIds.insert(clipId)
        } else {
            noiseReductionClipIds.remove(clipId)
        }
    }

    private func buildAudioProcessingOptions() -> ClipAudioProcessingOptions {
        let snapshot = currentProject
        var voiceClipIds: Set<UUID> = []
        for track in snapshot.timeline.tracks where track.kind == .video {
            for clip in track.clips where clip.volume > 0 {
                voiceClipIds.insert(clip.id)
            }
        }

        var eqPresets: [UUID: EqualizerPreset] = [:]
        for (clipId, presetName) in clipEQPresets {
            let matched = equalizerPreset(for: presetName)
            if let matched {
                eqPresets[clipId] = matched
            }
        }

        return ClipAudioProcessingOptions(
            eqPresets: eqPresets,
            noiseReductionClipIds: noiseReductionClipIds,
            duckLevel: 0.3,
            voiceClipIds: voiceClipIds
        )
    }

    private func equalizerPreset(for option: String) -> EqualizerPreset? {
        switch option {
        case "flat":
            return nil
        case "bassBoost":
            return .bassBoost
        case "trebleBoost":
            return .trebleBoost
        case "voice":
            return .voiceEnhance
        case "cinema":
            return .loudness
        default:
            return EqualizerPreset.all.first { $0.name.lowercased() == option.lowercased() }
        }
    }

    // MARK: - Phase 3-1: AI Analysis & Voiceover

    var analysisResult: AnalysisResult?

    /// Available analysis providers (silence detection, scene change detection).
    let analysisProviders: [any AnalysisProvider] = [
        SilenceDetectionProvider(),
        SceneChangeProvider()
    ]

    /// Currently selected analysis provider index.
    var selectedAnalysisProviderIndex: Int = 0

    func sessionSnapshot() async -> Project {
        await session.snapshot()
    }

    func applyAnalysisSuggestion(_ suggestion: AnalysisSuggestion) async throws -> [any EditorCommand] {
        try await AutoCutEngine.apply(suggestions: [suggestion], to: session)
    }

    func dispatchCommand(_ command: any EditorCommand) async throws {
        try await session.dispatch(command)
        try await refreshFromSession()
    }

    func runAnalysis() async {
        guard let asset = selectedTranscribableAsset else {
            lastErrorMessage = "Select an audio or video clip to analyze."
            return
        }

        let provider = analysisProviders.indices.contains(selectedAnalysisProviderIndex)
            ? analysisProviders[selectedAnalysisProviderIndex]
            : analysisProviders[0]

        do {
            let snapshot = await session.snapshot()
            let result = try await provider.analyze(asset: asset, in: snapshot)
            analysisResult = result
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func applyAllSuggestions() async {
        guard let result = analysisResult else { return }
        do {
            let commands = try await AutoCutEngine.apply(suggestions: result.suggestions, to: session)
            for command in commands {
                try await session.dispatch(command)
            }
            analysisResult = nil
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addVoiceoverAudio(from url: URL) async {
        do {
            let asset = MediaImporter.probe(url: url)
            try await session.dispatch(ImportMediaCommand(asset: asset))

            let audioTrack = try await ensureTrack(for: .audio)
            let duration = asset.duration ?? 5
            let clip = Clip(
                assetId: asset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: clip))
            selectedAssetId = asset.id
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Phase 3-2: Templates

    func createProject(from bundle: TemplateBundle) async {
        let project = templateStore.createProject(from: bundle)
        session = EditorSession(project: project)
        currentProject = project
        canvasSelection = project.canvas.aspectRatio
        selectedClipId = nil
        selectedAssetId = nil
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        analysisResult = nil
        lastErrorMessage = nil
        lastExportURL = nil
    }

    func createProjectFromTemplate(_ bundle: TemplateBundle) async {
        await createProject(from: bundle)
    }

    private static func defaultProject() -> Project {
        ensureDefaultTracks(in: Project(name: "Untitled"))
    }

    private static func ensureDefaultTracks(in project: Project) -> Project {
        var project = project
        if project.timeline.tracks.isEmpty {
            project.timeline.tracks = [
                Track(kind: .video, name: "Video 1", zIndex: 0),
                Track(kind: .audio, name: "Audio 1", zIndex: 1),
                Track(kind: .text, name: "Text 1", zIndex: 2)
            ]
        }
        return project
    }
}
