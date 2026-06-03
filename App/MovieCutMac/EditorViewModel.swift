import AppKit
import Foundation
import MovieCutCore
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class EditorViewModel {
    var currentProject: Project
    var canvasSelection: AspectRatio = .landscape16x9
    var selectedClipIds: Set<UUID> = []
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

    @ObservationIgnored private var session: EditorSession
    @ObservationIgnored private let projectStore = ProjectStore()
    @ObservationIgnored private var waveformCache: [UUID: [CGFloat]] = [:]

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

    func exportProject() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).mp4"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        lastExportURL = nil

        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.export(project: snapshot, to: url)
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

    func addMusicTrack(_ track: MusicTrack) async {
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

    func addSticker(_ sticker: StickerAsset) async {
        do {
            let imageURL: URL
            if let stickerImageURL = sticker.imageURL {
                imageURL = stickerImageURL
            } else if let emoji = sticker.emoji {
                imageURL = try renderEmojiSticker(emoji, id: sticker.id)
            } else {
                return
            }

            let asset = MediaImporter.probe(url: imageURL)
            try await session.dispatch(ImportMediaCommand(asset: asset))

            let track = try await ensureTrack(for: .video)
            let duration: TimeInterval = 3
            let start = playheadTime
            let clip = Clip(
                assetId: asset.id,
                kind: .image,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: start, duration: duration)
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedAssetId = asset.id
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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

    private var currentClipIds: Set<UUID> {
        Set(currentProject.timeline.tracks.flatMap(\.clips).map(\.id))
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
