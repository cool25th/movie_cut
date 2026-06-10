import AppKit
import AVFoundation
import Combine
import Foundation
import MovieCutCore
import Observation
import UniformTypeIdentifiers

enum CanvasOverlayAlignment: Sendable {
    case leading
    case centerX
    case trailing
    case top
    case centerY
    case bottom
}

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

    struct AnalysisHistoryItem: Identifiable {
        let id = UUID()
        let action: String
        let count: Int?
        let clipDescription: String?
        let message: String
        let timestamp: Date
    }

    private enum DropFeedbackMessage {
        static let invalidTimelineFilePayload = "Drop did not include valid media files."
        static let invalidTimelineLibraryAssetPayload = "Drop did not include valid library assets."
        static let unsupportedTimelinePayload = "Drop media files or library assets onto the timeline."
        static let invalidMediaLibraryPayload = "Drop did not include supported media files."

        static func importedMediaFiles(_ count: Int) -> String {
            "Imported \(count) \(plural(count, singular: "media file", plural: "media files"))."
        }

        static func addedMediaFilesToTimeline(_ count: Int) -> String {
            "Added \(count) \(plural(count, singular: "media file", plural: "media files")) to the timeline."
        }

        static func addedLibraryAssetsToTimeline(_ count: Int) -> String {
            "Added \(count) \(plural(count, singular: "library asset", plural: "library assets")) to the timeline."
        }

        private static func plural(_ count: Int, singular: String, plural: String) -> String {
            count == 1 ? singular : plural
        }
    }

    private static let minimumVoiceoverDuration: TimeInterval = 0.1

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
    var exportFrameRate: ExportFrameRate = .fps30
    var exportCodec: ExportCodec = .h264
    var exportAudioCodec: MovieCutCore.AudioCodec = .aac
    var isMaskEditorActive: Bool = false
    var selectedAssetId: UUID?
    var playbackEngine: PlaybackEngine
    var exportEngine: ExportEngine
    var musicLibrary: MusicLibrary
    var transcriptionService: TranscriptionService
    var templateStore: TemplateStore
    var sfxURLResolver: [String: URL]
    var generatedSubtitleSegments: [TranscriptionSegment] = []
    var pendingSubtitleClips: [Clip] = []
    var playheadTime: TimeInterval = 0
    var timelineZoom: Double = 80
    var lastErrorMessage: String?
    var lastStatusMessage: String?
    var quickToolProgressMessage: String?
    var recentAnalysisResults: [AnalysisHistoryItem] = []
    var lastExportURL: URL?
    var isCloudSyncing: Bool = false
    var cloudSyncError: String?
    var exportFormat: String = "mp4"
    var cloudProjects: [CloudProjectInfo] = []

    @ObservationIgnored @Published var lastAutoSaveDate: Date = .distantPast

    @ObservationIgnored private var session: EditorSession
    @ObservationIgnored private let projectStore = ProjectStore()
    @ObservationIgnored private var currentProjectURL: URL?
    @ObservationIgnored private var isAutoSaveRunning = false
    @ObservationIgnored private var isSavingCurrentProject = false
    @ObservationIgnored private var waveformCache: [UUID: [CGFloat]] = [:]
    @ObservationIgnored private var clipEQPresets: [UUID: String] = [:]
    @ObservationIgnored private var noiseReductionClipIds: Set<UUID> = []
    @ObservationIgnored private var backgroundRemovedClipIds: Set<UUID> = []
    @ObservationIgnored private var clipStyles: [UUID: String] = [:]

    init(project: Project? = nil) {
        let project = EditorViewModel.ensureDefaultTracks(in: project ?? Project(name: "Untitled"))
        self.currentProject = project
        self.canvasSelection = project.canvas.aspectRatio
        self.exportResolution = Self.exportResolutionString(for: project.exportSettings.resolution)
        self.exportQuality = project.exportSettings.quality.rawValue
        self.exportFrameRate = project.exportSettings.frameRate
        self.exportCodec = project.exportSettings.codec
        self.exportAudioCodec = project.exportSettings.audioCodec
        self.exportFormat = project.exportSettings.containerFormat.rawValue
        self.playbackEngine = PlaybackEngine()
        self.exportEngine = ExportEngine()
        self.musicLibrary = MusicLibrary.placeholder()
        self.transcriptionService = TranscriptionService()
        self.templateStore = TemplateStore()
        self.sfxURLResolver = Self.makeSFXURLResolver()
        self.session = EditorSession(project: project)

        for bundle in TemplateStore.builtInTemplates() {
            self.templateStore.add(bundle)
        }

        startAutoSave()
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

    var selectedCanvasOverlayClips: [Clip] {
        var clips: [Clip] = []
        for track in currentProject.timeline.tracks {
            for clip in track.clips where selectedClipIds.contains(clip.id) {
                if clip.kind == .text, clip.textContent != nil {
                    clips.append(clip)
                }
            }
        }
        return clips
    }

    var hasMultipleSelectedCanvasOverlays: Bool {
        selectedCanvasOverlayClips.count > 1
    }

    var hasSelectedClips: Bool {
        !selectedClipIds.isEmpty
    }

    var canSplitSelectedClip: Bool {
        guard let selectedClip else { return false }
        return selectedClip.timelineRange.contains(playheadTime)
    }

    var selectedClipIsSticker: Bool {
        guard let selectedClip else { return false }
        return isStickerClip(selectedClip)
    }

    var selectedTranscribableAsset: MediaAsset? {
        if
            let selectedClip,
            let assetId = selectedClip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            Self.isTranscribable(asset)
        {
            return asset
        }

        if let selectedAsset, Self.isTranscribable(selectedAsset) {
            return selectedAsset
        }

        return nil
    }

    var selectedTranscribableClipAndAsset: (clip: Clip, asset: MediaAsset)? {
        guard
            let selectedClip,
            let assetId = selectedClip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            Self.isTranscribable(asset)
        else {
            return nil
        }

        return (selectedClip, asset)
    }

    var selectedClipSourceAsset: MediaAsset? {
        guard let assetId = selectedClip?.assetId else { return nil }
        return currentProject.mediaLibrary.assets[assetId]
    }

    var canRunAutoCutOnSelection: Bool {
        guard let clip = selectedClip, let asset = selectedClipSourceAsset else { return false }
        return (clip.kind == .audio || clip.kind == .video) && (asset.kind == .audio || asset.kind == .video)
    }

    var canDetectSceneChangesForSelection: Bool {
        selectedClip?.kind == .video && selectedClipSourceAsset?.kind == .video
    }

    var canAutoReframeSelection: Bool {
        selectedClip?.kind == .video && selectedClipSourceAsset?.kind == .video
    }

    var canApplyNoiseReductionToSelection: Bool {
        guard let clip = selectedClip, let asset = selectedClipSourceAsset else { return false }
        return (clip.kind == .audio || clip.kind == .video) && (asset.kind == .audio || asset.kind == .video)
    }

    var canExtractAudioFromSelection: Bool {
        selectedClip?.kind == .video && selectedClipSourceAsset?.kind == .video
    }

    var previousMarker: Marker? {
        currentProject.markers
            .filter { $0.time < playheadTime - 0.001 }
            .sorted { $0.time < $1.time }
            .last
    }

    var nextMarker: Marker? {
        currentProject.markers
            .filter { $0.time > playheadTime + 0.001 }
            .sorted { $0.time < $1.time }
            .first
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

    func thumbnailData(for clip: Clip) -> Data? {
        guard
            clip.kind == .video || clip.kind == .image,
            let assetId = clip.assetId,
            let asset = currentProject.mediaLibrary.assets[assetId],
            asset.kind == .video || asset.kind == .image
        else {
            return nil
        }

        return asset.thumbnailData
    }

    var canGenerateSubtitles: Bool {
        if selectedClipId != nil {
            return selectedTranscribableClipAndAsset != nil
        }

        guard let selectedAsset else { return false }
        return Self.isTranscribable(selectedAsset)
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

    func newProject() {
        let project = Self.defaultProject()
        session = EditorSession(project: project)
        currentProject = project
        currentProjectURL = nil
        canvasSelection = project.canvas.aspectRatio
        syncExportUI(from: project.exportSettings)
        selectedClipId = nil
        selectedAssetId = nil
        isMaskEditorActive = false
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        recentAnalysisResults = []
        lastErrorMessage = nil
        lastStatusMessage = nil
        lastExportURL = nil
    }

    func openProject(from url: URL) async {
        do {
            let loadedProject = try await projectStore.load(from: url)
            let project = Self.ensureDefaultTracks(in: loadedProject)
            session = EditorSession(project: project)
            currentProject = project
            currentProjectURL = url
            canvasSelection = project.canvas.aspectRatio
            syncExportUI(from: project.exportSettings)
            selectedClipId = nil
            selectedAssetId = nil
            isMaskEditorActive = false
            playbackEngine.clear()
            playheadTime = 0
            clearGeneratedSubtitles()
            clearClipProcessingState()
            recentAnalysisResults = []
            lastErrorMessage = nil
            lastStatusMessage = nil
            lastExportURL = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }

    func saveProject(to url: URL) async {
        do {
            let snapshot = await session.snapshot()
            try await projectStore.save(snapshot, to: url)
            currentProjectURL = url
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

    func startAutoSave() {
        guard !isAutoSaveRunning else { return }

        isAutoSaveRunning = true
        scheduleNextAutoSave()
    }

    func stopAutoSave() {
        isAutoSaveRunning = false
    }

    func saveCurrentProject() {
        guard !isSavingCurrentProject else { return }

        isSavingCurrentProject = true
        Task { @MainActor in
            defer { isSavingCurrentProject = false }

            do {
                let snapshot = await session.snapshot()
                let url = currentProjectURL ?? defaultAutoSaveURL(for: snapshot)
                try await projectStore.save(snapshot, to: url)
                if currentProjectURL == nil {
                    currentProjectURL = url
                }
                lastAutoSaveDate = Date()
                lastErrorMessage = nil
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleNextAutoSave() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self else { return }

            self.saveCurrentProject()
            if self.isAutoSaveRunning {
                self.scheduleNextAutoSave()
            }
        }
    }

    private func defaultAutoSaveURL(for project: Project) -> URL {
        let baseDirectory = (
            try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        ) ?? FileManager.default.temporaryDirectory

        let sanitizedName = project.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let fileName = sanitizedName.isEmpty ? "Untitled" : sanitizedName

        return baseDirectory
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("Autosave", isDirectory: true)
            .appendingPathComponent("\(fileName)-\(project.id.uuidString).moviecut")
    }

    private nonisolated static func proxyDirectory(for projectId: UUID) -> URL {
        let baseDirectory = (
            try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        ) ?? FileManager.default.temporaryDirectory

        return baseDirectory
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("Proxies", isDirectory: true)
            .appendingPathComponent(projectId.uuidString, isDirectory: true)
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
            syncExportUI(from: loaded.exportSettings)
            selectedClipId = nil
            selectedAssetId = nil
            isMaskEditorActive = false
            playbackEngine.clear()
            playheadTime = 0
            clearGeneratedSubtitles()
            clearClipProcessingState()
            recentAnalysisResults = []
            lastErrorMessage = nil
            lastExportURL = nil
            cloudSyncError = nil
        } catch {
            cloudSyncError = error.localizedDescription
        }
    }

    func exportProject() async {
        let reconciledSettings = reconciledExportSettingsFromLegacyUI()
        if currentProject.exportSettings != reconciledSettings {
            await apply(SetProjectExportSettingsCommand(exportSettings: reconciledSettings))
            guard lastErrorMessage == nil else { return }
        }

        let settings = currentProject.exportSettings
        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            .mpeg4Movie,
            .quickTimeMovie,
            UTType(filenameExtension: "m4v") ?? .mpeg4Movie
        ]
        panel.canCreateDirectories = true

        panel.nameFieldStringValue = "\(currentProject.name).\(settings.containerFormat.fileExtension)"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        lastExportURL = nil

        exportEngine.exportResolution = Self.exportResolutionString(for: settings.resolution)
        exportEngine.exportQuality = settings.quality.rawValue
        exportEngine.exportFormat = settings.containerFormat.rawValue
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
        guard !urls.isEmpty else {
            reportInvalidMediaLibraryDrop()
            return
        }

        do {
            for url in urls {
                let asset = await mediaAssetWithAppProbe(for: url)
                try await session.dispatch(ImportMediaCommand(asset: asset))
                selectedAssetId = asset.id
            }
            try await refreshFromSession()
            reportMediaLibraryDropSuccess(count: urls.count)
        } catch {
            setDropError(error.localizedDescription)
        }
    }

    func addClipToTimeline() async {
        guard let selectedAsset else { return }
        await addClipToTimeline(selectedAsset)
    }

    func addClipToTimeline(_ asset: MediaAsset) async {
        await addMediaAssetToTimeline(asset, preferredTrackId: nil, startTime: currentProject.timeline.duration)
    }

    func importMediaAndAddToTimeline(
        _ urls: [URL],
        preferredTrackId: UUID? = nil,
        startTime: TimeInterval
    ) async {
        guard !urls.isEmpty else {
            reportInvalidTimelineFileDrop()
            return
        }

        var needsRefresh = false
        do {
            var insertionStart = max(0, startTime)
            for url in urls {
                let asset = await mediaAssetWithAppProbe(for: url)
                try await session.dispatch(ImportMediaCommand(asset: asset))
                needsRefresh = true

                let clip = try await insertMediaAssetOnTimeline(
                    asset,
                    preferredTrackId: preferredTrackId,
                    startTime: insertionStart
                )
                insertionStart = clip.timelineRange.end
                selectedAssetId = asset.id
                selectedClipId = clip.id
                playheadTime = clip.timelineRange.start
            }

            try await refreshFromSession()
            reportTimelineFileDropSuccess(count: urls.count)
        } catch {
            if needsRefresh {
                try? await refreshFromSession()
            }
            setDropError(error.localizedDescription)
        }
    }

    func addImportedAssetsToTimeline(
        _ assetIds: [UUID],
        preferredTrackId: UUID? = nil,
        startTime: TimeInterval
    ) async {
        guard !assetIds.isEmpty else {
            reportInvalidTimelineLibraryAssetDrop()
            return
        }

        var needsRefresh = false
        do {
            var insertionStart = max(0, startTime)
            let snapshot = await session.snapshot()
            for assetId in assetIds {
                guard let asset = snapshot.mediaLibrary.assets[assetId] else {
                    throw EditorCommandError.assetNotFound(assetId)
                }

                let clip = try await insertMediaAssetOnTimeline(
                    asset,
                    preferredTrackId: preferredTrackId,
                    startTime: insertionStart
                )
                needsRefresh = true
                insertionStart = clip.timelineRange.end
                selectedAssetId = asset.id
                selectedClipId = clip.id
                playheadTime = clip.timelineRange.start
            }

            try await refreshFromSession()
            reportTimelineLibraryAssetDropSuccess(count: assetIds.count)
        } catch {
            if needsRefresh {
                try? await refreshFromSession()
            }
            setDropError(error.localizedDescription)
        }
    }

    func addImportedAssetToTimeline(
        _ assetId: UUID,
        preferredTrackId: UUID? = nil,
        startTime: TimeInterval
    ) async {
        await addImportedAssetsToTimeline([assetId], preferredTrackId: preferredTrackId, startTime: startTime)
    }

    func generateProxyForSelectedAsset() async {
        guard let selectedAssetId else {
            lastErrorMessage = "Select a video asset to generate a proxy."
            lastStatusMessage = nil
            return
        }

        await generateProxy(for: selectedAssetId)
    }

    func generateProxy(for assetId: UUID) async {
        let snapshot = await session.snapshot()
        guard var asset = snapshot.mediaLibrary.assets[assetId] else {
            lastErrorMessage = "Selected asset is no longer available."
            lastStatusMessage = nil
            return
        }

        guard asset.kind == .video else {
            lastErrorMessage = "Proxy generation is only available for video assets."
            lastStatusMessage = nil
            return
        }

        let directory = Self.proxyDirectory(for: snapshot.id)
        guard let plan = ProxyGenerator.makeProxyPlan(for: asset, in: directory) else {
            lastErrorMessage = "Could not create a proxy generation plan."
            lastStatusMessage = nil
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Generating proxy for \(asset.originalURL.lastPathComponent)..."

        do {
            guard let proxyInfo = try await ProxyGenerator.generateProxy(for: asset, using: plan) else {
                lastErrorMessage = "Proxy generation failed. The source file may not support proxy export."
                lastStatusMessage = nil
                return
            }

            asset.proxy = proxyInfo
            try await session.dispatch(UpdateMediaAssetCommand(asset: asset))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = "Proxy ready for \(asset.originalURL.lastPathComponent)."
        } catch {
            lastErrorMessage = "Proxy generation failed: \(error.localizedDescription)"
            lastStatusMessage = nil
        }
    }

    func setDropStatus(_ message: String) {
        lastErrorMessage = nil
        lastStatusMessage = message
    }

    func setDropError(_ message: String) {
        lastStatusMessage = nil
        lastErrorMessage = message
    }

    func reportInvalidTimelineFileDrop() {
        setDropError(Self.DropFeedbackMessage.invalidTimelineFilePayload)
    }

    func reportInvalidTimelineLibraryAssetDrop() {
        setDropError(Self.DropFeedbackMessage.invalidTimelineLibraryAssetPayload)
    }

    func reportUnsupportedTimelineDrop() {
        setDropError(Self.DropFeedbackMessage.unsupportedTimelinePayload)
    }

    func reportInvalidMediaLibraryDrop() {
        setDropError(Self.DropFeedbackMessage.invalidMediaLibraryPayload)
    }

    private func reportMediaLibraryDropSuccess(count: Int) {
        setDropStatus(Self.DropFeedbackMessage.importedMediaFiles(count))
    }

    private func reportTimelineFileDropSuccess(count: Int) {
        setDropStatus(Self.DropFeedbackMessage.addedMediaFilesToTimeline(count))
    }

    private func reportTimelineLibraryAssetDropSuccess(count: Int) {
        setDropStatus(Self.DropFeedbackMessage.addedLibraryAssetsToTimeline(count))
    }

    private func addMediaAssetToTimeline(
        _ asset: MediaAsset,
        preferredTrackId: UUID?,
        startTime: TimeInterval
    ) async {
        do {
            let clip = try await insertMediaAssetOnTimeline(
                asset,
                preferredTrackId: preferredTrackId,
                startTime: startTime
            )
            selectedAssetId = asset.id
            selectedClipId = clip.id
            playheadTime = clip.timelineRange.start
            try await refreshFromSession()
            lastErrorMessage = nil
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

    func addSFXToTimeline(_ item: SFXItem) async {
        guard let fileURL = resolveSFXURL(for: item) else {
            lastErrorMessage = "Missing bundled sound effect: \(item.fileName)"
            return
        }

        do {
            let duration = audioDuration(for: fileURL) ?? 1
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
            selectedAssetId = asset.id
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func sfxURL(for item: SFXItem) -> URL? {
        resolveSFXURL(for: item)
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
            let canvasSize = effectiveCanvasSize(in: currentProject)
            let placement = defaultStickerPlacement(for: sticker)
            let stickerPosition = CGPoint(
                x: canvasSize.width * placement.xRatio,
                y: canvasSize.height * placement.yRatio
            )
            let stickerScale = CGSize(width: placement.transformScale, height: placement.transformScale)
            let stickerImageURL = sticker.imageURL.flatMap { _ in StickerImageProvider.ensureImageURL(for: sticker) }
            let isImageBackedSticker = stickerImageURL != nil
            let content = TextClipContent(
                text: stickerText,
                fontFamily: isImageBackedSticker ? "HelveticaNeue-Bold" : "Apple Color Emoji",
                fontSize: max(84, min(Double(canvasSize.width), Double(canvasSize.height)) * placement.fontScale),
                fontColor: "#FFFFFF",
                alignment: .center,
                backgroundColor: "#00000000",
                position: stickerPosition,
                animation: TextAnimation(type: .scale, duration: 0.25),
                contentKind: .sticker,
                stickerAssetID: sticker.id,
                stickerImageURL: stickerImageURL
            )
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration),
                transform: ClipTransform(position: stickerPosition, scale: stickerScale),
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

    func addTextTemplateClip(_ template: TextTemplate) async {
        await addTextFromTemplate(template)
        if lastErrorMessage == nil {
            reportQuickToolSuccess("Added \(template.name) text template.")
        }
    }

    func addTextTemplateClip(_ template: MovieCutCore.TextTemplate) async {
        do {
            let track = try await ensureTrack(for: .text)
            let duration: TimeInterval = 5
            var content = template.content
            content.position = scaledTemplatePosition(content.position)
            if content.animation == nil {
                content.animation = template.animation
            }
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
            reportQuickToolSuccess("Added \(template.name) text template.")
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func addStickerClip(_ sticker: StickerAsset) async {
        await addSticker(sticker)
        if lastErrorMessage == nil {
            let kindLabel = sticker.isImageBacked ? "image/badge" : "emoji"
            reportQuickToolSuccess("Added \(sticker.name) \(kindLabel) sticker.")
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

    func snapPlayheadToSelectedClipStart() {
        guard let selectedClip else { return }
        seekPlayhead(to: selectedClip.timelineRange.start)
    }

    func snapPlayheadToSelectedClipEnd() {
        guard let selectedClip else { return }
        seekPlayhead(to: selectedClip.timelineRange.end)
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

    func updateSelectedStickerTransform(_ transform: ClipTransform) async {
        guard let selectedClipId, let selectedClip, isStickerClip(selectedClip) else { return }

        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .transform(transform)))
        guard lastErrorMessage == nil, var textContent = selectedClip.textContent else { return }

        let shouldPromoteToSticker = textContent.contentKind != .sticker
        let shouldSyncPosition = !pointsEqual(textContent.position, transform.position)
        guard shouldPromoteToSticker || shouldSyncPosition else { return }

        textContent.contentKind = .sticker
        if !pointsEqual(textContent.position, transform.position) {
            textContent.position = transform.position
        }

        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .textContent(textContent)))
    }

    func nudgeSelectedCanvasOverlays(dx: CGFloat, dy: CGFloat) async {
        let clips = selectedCanvasOverlayOperationClips()
        guard !clips.isEmpty else { return }

        let canvasSize = effectiveCanvasSize(in: currentProject)
        let updates = clips.map { clip in
            var transform = resolvedCanvasOverlayTransform(for: clip)
            transform.position = clampedCanvasPoint(
                CGPoint(x: transform.position.x + dx, y: transform.position.y + dy),
                canvasSize: canvasSize
            )
            return (clip: clip, transform: transform)
        }

        await dispatchCanvasOverlayUpdates(updates)
    }

    func centerSelectedCanvasOverlays() async {
        let clips = selectedCanvasOverlayOperationClips()
        guard !clips.isEmpty else { return }

        let canvasCenter = canvasCenter()

        if clips.count > 1 {
            let centers = clips.map { canvasOverlayVisualCenter(for: $0) }
            let groupCenter = boundingCenter(for: centers)
            await translateCanvasOverlayClips(
                clips,
                dx: canvasCenter.x - groupCenter.x,
                dy: canvasCenter.y - groupCenter.y
            )
            return
        }

        let canvasSize = effectiveCanvasSize(in: currentProject)
        let updates = clips.map { clip in
            var transform = resolvedCanvasOverlayTransform(for: clip)
            transform.position = clampedCanvasPoint(
                CGPoint(x: canvasCenter.x - transform.offset.x, y: canvasCenter.y - transform.offset.y),
                canvasSize: canvasSize
            )
            return (clip: clip, transform: transform)
        }

        await dispatchCanvasOverlayUpdates(updates)
    }

    func alignSelectedCanvasOverlays(_ alignment: CanvasOverlayAlignment) async {
        let clips = selectedCanvasOverlayOperationClips()
        guard !clips.isEmpty else { return }

        let canvasSize = effectiveCanvasSize(in: currentProject)
        let centers = clips.map { canvasOverlayVisualCenter(for: $0) }
        let target = alignmentTarget(for: alignment, centers: centers, canvasSize: canvasSize, isMultiple: clips.count > 1)

        let updates = clips.map { clip in
            var transform = resolvedCanvasOverlayTransform(for: clip)
            switch alignment {
            case .leading, .centerX, .trailing:
                transform.position.x = min(max(target - transform.offset.x, 0), canvasSize.width)
            case .top, .centerY, .bottom:
                transform.position.y = min(max(target - transform.offset.y, 0), canvasSize.height)
            }
            return (clip: clip, transform: transform)
        }

        await dispatchCanvasOverlayUpdates(updates)
    }

    func centerSelectedSticker() async {
        guard let selectedClip, isStickerClip(selectedClip) else { return }

        var transform = selectedClip.transform
        transform.position = canvasCenter()
        transform.offset = CGPoint(x: 0, y: 0)
        await updateSelectedStickerTransform(transform)
    }

    func fitSelectedStickerToSocialSafeArea() async {
        guard let selectedClip, isStickerClip(selectedClip) else { return }

        let safeRect = socialSafeAreaRect()
        let fallbackPosition = canvasCenter()
        let currentPosition = nonZeroPoint(selectedClip.transform.position)
            ?? selectedClip.textContent.flatMap { nonZeroPoint($0.position) }
            ?? fallbackPosition

        var transform = selectedClip.transform
        transform.position = CGPoint(
            x: min(max(currentPosition.x, safeRect.minX), safeRect.maxX),
            y: min(max(currentPosition.y, safeRect.minY), safeRect.maxY)
        )

        let averageScale = (transform.scale.width + transform.scale.height) * 0.5
        let clampedScale = min(max(averageScale.isFinite ? averageScale : 1, 0.35), 1.1)
        transform.scale = CGSize(width: clampedScale, height: clampedScale)
        await updateSelectedStickerTransform(transform)
    }

    func resetSelectedStickerTransform() async {
        guard let selectedClip, isStickerClip(selectedClip) else { return }

        var transform = ClipTransform()
        transform.position = canvasCenter()
        transform.scale = CGSize(width: 1, height: 1)
        await updateSelectedStickerTransform(transform)
    }

    func moveSelectedClipLayerForward() async {
        guard let selectedClip else { return }
        await setSelectedClipZIndex(selectedClip.zIndex + 1)
    }

    func moveSelectedClipLayerBackward() async {
        guard let selectedClip else { return }
        await setSelectedClipZIndex(selectedClip.zIndex - 1)
    }

    func bringSelectedClipLayerToFront() async {
        guard let selectedClip else { return }
        let frontZIndex = (selectedClipTrack?.clips.map(\.zIndex).max() ?? selectedClip.zIndex) + 1
        await setSelectedClipZIndex(frontZIndex)
    }

    func sendSelectedClipLayerToBack() async {
        guard let selectedClip else { return }
        let backZIndex = (selectedClipTrack?.clips.map(\.zIndex).min() ?? selectedClip.zIndex) - 1
        await setSelectedClipZIndex(backZIndex)
    }

    private func setSelectedClipZIndex(_ zIndex: Int) async {
        guard let selectedClipId else { return }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .zIndex(zIndex)))
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

    func updateExportSettings(
        resolution: ExportResolution? = nil,
        frameRate: ExportFrameRate? = nil,
        codec: ExportCodec? = nil,
        audioCodec: MovieCutCore.AudioCodec? = nil,
        containerFormat: ExportContainerFormat? = nil,
        quality: ExportQuality? = nil,
        videoBitrateMbps: Int? = nil
    ) async {
        var settings = currentProject.exportSettings
        settings.resolution = resolution ?? settings.resolution
        settings.frameRate = frameRate ?? settings.frameRate
        settings.codec = codec ?? settings.codec
        settings.audioCodec = audioCodec ?? settings.audioCodec
        settings.containerFormat = containerFormat ?? settings.containerFormat
        if let quality {
            settings.quality = quality
            if quality != .custom {
                settings.videoBitrateMbps = nil
            }
        }
        if let videoBitrateMbps {
            settings.videoBitrateMbps = min(max(videoBitrateMbps, 1), 200)
        }

        await apply(SetProjectExportSettingsCommand(exportSettings: settings))
    }

    func applyExportPreset(
        named name: String,
        canvas: CanvasPreset,
        exportSettings: ExportSettings
    ) async {
        await apply(SetProjectCanvasCommand(canvas: canvas))
        guard lastErrorMessage == nil else { return }

        await apply(SetProjectExportSettingsCommand(exportSettings: exportSettings))
        guard lastErrorMessage == nil else { return }

        reportQuickToolSuccess("Applied \(name) export preset.")
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
        _ = try? await autoCutSilence(for: clipId)
        _ = try? await detectAndSplitScenes(for: clipId)
    }

    func autoColorCorrect() async {
        guard let clipId = selectedClipId else { return }
        try? await autoColorCorrect(for: clipId)
    }

    func autoColorCorrect(for clipId: UUID) async throws {
        let snapshot = await session.snapshot()
        var found: Clip?
        outer: for track in snapshot.timeline.tracks {
            for c in track.clips {
                if c.id == clipId { found = c; break outer }
            }
        }
        guard let clip = found else {
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

    func runAutoCutOnSelection() async {
        guard let clipId = selectedClipId, canRunAutoCutOnSelection else {
            reportQuickToolFailure("Select an audio or video clip to auto cut silence.")
            return
        }

        do {
            let removedRangeCount = try await autoCutSilence(for: clipId)
            let message = removedRangeCount == 0
                ? "No removable silence was detected."
                : "Removed \(removedRangeCount) silent \(removedRangeCount == 1 ? "range" : "ranges")."
            recordAnalysisResult(
                action: "Auto Cut",
                count: removedRangeCount,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func detectSceneChangesForSelection() async {
        guard let clipId = selectedClipId, canDetectSceneChangesForSelection else {
            reportQuickToolFailure("Select a video clip to detect scene changes.")
            return
        }

        do {
            let splitCount = try await detectAndSplitScenes(for: clipId)
            let message = splitCount == 0
                ? "No scene changes were detected."
                : "Split \(splitCount) scene \(splitCount == 1 ? "boundary" : "boundaries")."
            recordAnalysisResult(
                action: "Detect Scenes",
                count: splitCount,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func autoReframeSelection() async {
        guard let clipId = selectedClipId, canAutoReframeSelection else {
            reportQuickToolFailure("Select a video clip to auto reframe.")
            return
        }

        let canvasSize = effectiveCanvasSize(in: currentProject)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            reportQuickToolFailure("Set a valid canvas before auto reframing.")
            return
        }

        do {
            let keyframeCount = try await autoReframe(for: clipId, targetAspect: canvasSize.width / canvasSize.height)
            let message = keyframeCount == 0
                ? "Auto reframe found no subject frames; clip unchanged."
                : "Added \(keyframeCount) reframe \(keyframeCount == 1 ? "keyframe" : "keyframes")."
            recordAnalysisResult(
                action: "Auto Reframe",
                count: keyframeCount,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func applyNoiseReductionToSelection() async {
        guard let clipId = selectedClipId, canApplyNoiseReductionToSelection else {
            reportQuickToolFailure("Select an audio or video clip for noise reduction.")
            return
        }

        do {
            try await applyNoiseReduction(for: clipId)
            let message = "Applied noise reduction."
            recordAnalysisResult(
                action: "Noise Reduction",
                count: nil,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func extractAudioFromSelection() async {
        guard let clipId = selectedClipId, canExtractAudioFromSelection else {
            reportQuickToolFailure("Select a video clip to extract audio.")
            return
        }

        do {
            try await extractAudio(from: clipId)
            let message = "Extracted audio to a new audio clip."
            recordAnalysisResult(
                action: "Extract Audio",
                count: 1,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            reportQuickToolFailure(error)
        }
    }

    func addMarkerAtPlayhead() {
        let time = max(0, playheadTime)
        let markerName = "Marker \(currentProject.markers.count + 1)"
        let marker = Marker(time: time, name: markerName, color: "#FFD60A")

        Task {
            await apply(AddMarkerCommand(marker: marker))
            if lastErrorMessage == nil {
                reportQuickToolSuccess("Added \(markerName) at \(String(format: "%.1fs", time)).")
            }
        }
    }

    func goToPreviousMarker() {
        guard let marker = previousMarker else { return }
        goToMarker(marker)
    }

    func goToNextMarker() {
        guard let marker = nextMarker else { return }
        goToMarker(marker)
    }

    func goToMarker(_ marker: Marker) {
        seekPlayhead(to: marker.time)
        reportQuickToolSuccess("Moved to \(marker.name) at \(String(format: "%.1fs", marker.time)).")
    }

    func renameMarker(_ marker: Marker, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            reportQuickToolFailure("Marker name cannot be empty.")
            return
        }
        guard trimmedName != marker.name else { return }

        var updatedMarker = marker
        updatedMarker.name = trimmedName

        Task {
            await apply(UpdateMarkerCommand(markerId: marker.id, marker: updatedMarker))
            if lastErrorMessage == nil {
                reportQuickToolSuccess("Renamed marker to \(trimmedName).")
            }
        }
    }

    func deleteMarker(_ marker: Marker) {
        Task {
            await apply(DeleteMarkerCommand(markerId: marker.id))
            if lastErrorMessage == nil {
                reportQuickToolSuccess("Deleted marker \(marker.name).")
            }
        }
    }

    func toggleMaskEditor() {
        isMaskEditorActive.toggle()
    }

    func addMask() async {
        guard let selectedClipId else { return }
        isMaskEditorActive = true
        await apply(SetClipMaskCommand(clipId: selectedClipId, mask: defaultMask()))
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
        lastStatusMessage = nil
        lastErrorMessage = nil

        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        let providerName = transcriptionService.currentProvider.providerName

        clearGeneratedSubtitles()
        lastStatusMessage = "Transcribing with \(providerName)..."

        let result: TranscriptionResult
        do {
            result = try await transcriptionService.transcribe(asset: asset)
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            throw error
        }

        let subtitleClips = subtitleClips(from: result, alignedTo: clip)

        generatedSubtitleSegments = result.segments

        guard !result.segments.isEmpty else {
            lastErrorMessage = nil
            lastStatusMessage = "No speech found with \(providerName)."
            return
        }

        guard !subtitleClips.isEmpty else {
            lastErrorMessage = nil
            lastStatusMessage = "Transcribed \(result.segments.count) segments with \(providerName), but none overlap the selected timeline clip."
            return
        }

        do {
            let textTrack = try await ensureTrack(for: .text)
            for subtitleClip in subtitleClips {
                try await session.dispatch(AddClipCommand(trackId: textTrack.id, clip: subtitleClip))
            }

            selectedClipId = subtitleClips.first?.id
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = "Transcribed \(result.segments.count) segments with \(providerName); inserted \(subtitleClips.count) subtitle clips."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func prepareSubtitles() async {
        clearGeneratedSubtitles()
        lastStatusMessage = nil
        lastErrorMessage = nil

        do {
            let snapshot = await session.snapshot()
            let source = try selectedSubtitleSource(in: snapshot)
            let providerName = transcriptionService.currentProvider.providerName
            lastStatusMessage = "Transcribing with \(providerName)..."

            let result = try await transcriptionService.transcribe(asset: source.asset)
            let subtitleClips: [Clip]
            if let clip = source.clip {
                subtitleClips = self.subtitleClips(from: result, alignedTo: clip)
            } else {
                subtitleClips = transcriptionService.subtitles(from: result, in: snapshot)
            }

            generatedSubtitleSegments = result.segments
            pendingSubtitleClips = subtitleClips
            lastErrorMessage = nil

            if result.segments.isEmpty {
                lastStatusMessage = "No speech found with \(providerName)."
            } else if subtitleClips.isEmpty {
                lastStatusMessage = "Transcribed \(result.segments.count) segments with \(providerName), but no pending subtitle clips overlap the selected timeline clip."
            } else if source.clip != nil {
                lastStatusMessage = "Transcribed \(result.segments.count) segments with \(providerName); prepared \(subtitleClips.count) pending subtitle clips aligned to the selected timeline clip."
            } else {
                lastStatusMessage = "Transcribed \(result.segments.count) segments with \(providerName); prepared \(subtitleClips.count) pending subtitle clips starting at 00:00 because no timeline clip is selected."
            }
        } catch {
            lastStatusMessage = nil
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
            lastErrorMessage = nil
            lastStatusMessage = "Applied \(clips.count) generated subtitle clips to the timeline."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func generateSubtitles() async {
        await prepareSubtitles()
        await applyGeneratedSubtitles()
    }

    @discardableResult
    func autoCutSilence(
        for clipId: UUID,
        thresholdDB: Float = -40,
        minDuration: TimeInterval = 0.5
    ) async throws -> Int {
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
            return 0
        }

        let removedRangeCount = removalRangeCount(in: timelineSuggestions)
        let commands = try await AutoCutEngine.apply(suggestions: timelineSuggestions, to: session)
        for command in commands {
            try await session.dispatch(command)
        }

        try await refreshFromSession()
        return removedRangeCount
    }

    @discardableResult
    func detectAndSplitScenes(for clipId: UUID, threshold: Float = 0.3) async throws -> Int {
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
            return 0
        }

        for splitTime in uniqueSplitTimes {
            try await splitClipAtTime(splitTime, clipId: clipId, trackId: trackId)
        }

        try await refreshFromSession()
        return uniqueSplitTimes.count
    }

    @discardableResult
    func autoReframe(for clipId: UUID, targetAspect: CGFloat) async throws -> Int {
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
            return 0
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
        return generatedKeyframes.count
    }

    private func apply(_ command: any EditorCommand) async {
        do {
            try await session.dispatch(command)
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func defaultMask(shape: MaskShape = .rectangle) -> Mask {
        let canvasSize = currentProject.canvas.size
        return Mask(
            shape: shape,
            position: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5),
            size: CGSize(width: canvasSize.width * 0.5, height: canvasSize.height * 0.5)
        )
    }

    private func refreshFromSession() async throws {
        currentProject = await session.snapshot()
        canvasSelection = currentProject.canvas.aspectRatio
        syncExportUI(from: currentProject.exportSettings)

        selectedClipIds.formIntersection(currentClipIds)

        if let selectedAssetId, currentProject.mediaLibrary.assets[selectedAssetId] == nil {
            self.selectedAssetId = nil
        }

        playheadTime = min(playheadTime, max(0, currentProject.timeline.duration))
        lastErrorMessage = nil
        lastStatusMessage = nil
    }

    private func syncExportUI(from settings: ExportSettings) {
        exportResolution = Self.exportResolutionString(for: settings.resolution)
        exportQuality = settings.quality.rawValue
        exportFrameRate = settings.frameRate
        exportCodec = settings.codec
        exportAudioCodec = settings.audioCodec
        exportFormat = settings.containerFormat.rawValue
    }

    private func reconciledExportSettingsFromLegacyUI() -> ExportSettings {
        var settings = currentProject.exportSettings
        settings.resolution = Self.exportResolution(from: exportResolution) ?? settings.resolution
        settings.frameRate = exportFrameRate
        settings.codec = exportCodec
        settings.audioCodec = exportAudioCodec
        settings.containerFormat = ExportContainerFormat(rawValue: exportFormat.lowercased()) ?? settings.containerFormat

        if let quality = ExportQuality(rawValue: exportQuality.lowercased()) {
            settings.quality = quality
            if quality != .custom {
                settings.videoBitrateMbps = nil
            } else if settings.videoBitrateMbps == nil {
                settings.videoBitrateMbps = ExportQuality.medium.defaultVideoBitrateMbps(for: settings.resolution)
            }
        }

        return settings
    }

    private func recordAnalysisResult(
        action: String,
        count: Int?,
        message: String,
        clipId: UUID?
    ) {
        let item = AnalysisHistoryItem(
            action: action,
            count: count,
            clipDescription: clipDescription(for: clipId),
            message: message,
            timestamp: Date()
        )

        recentAnalysisResults.insert(item, at: 0)
        if recentAnalysisResults.count > 8 {
            recentAnalysisResults.removeSubrange(8...)
        }
    }

    private func clipDescription(for clipId: UUID?) -> String? {
        guard let clipId else { return nil }

        for track in currentProject.timeline.tracks {
            if let clipIndex = track.clips.firstIndex(where: { $0.id == clipId }) {
                let trackName = track.name.isEmpty ? track.kind.rawValue.capitalized : track.name
                return "\(trackName) clip \(clipIndex + 1)"
            }
        }

        return nil
    }

    private func reportQuickToolSuccess(_ message: String) {
        quickToolProgressMessage = nil
        lastErrorMessage = nil
        lastStatusMessage = message
    }

    private func reportQuickToolFailure(_ message: String) {
        quickToolProgressMessage = nil
        lastStatusMessage = nil
        lastErrorMessage = message
    }

    private func reportQuickToolFailure(_ error: Error) {
        reportQuickToolFailure(error.localizedDescription)
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
        case "cinematic":
            return 1
        case "noir":
            return 2
        case "vintage":
            return 3
        case "vivid":
            return 4
        case "cool":
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

    private func canvasCenter() -> CGPoint {
        let canvasSize = effectiveCanvasSize(in: currentProject)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGPoint(x: 0, y: 0)
        }

        return CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
    }

    private func socialSafeAreaRect() -> CGRect {
        let canvasSize = effectiveCanvasSize(in: currentProject)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 0, height: 0)
        }

        let horizontalInset = canvasSize.width * 0.12
        let verticalInset = canvasSize.height * 0.18
        return CGRect(origin: CGPoint(x: 0, y: 0), size: canvasSize).insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private func selectedCanvasOverlayOperationClips() -> [Clip] {
        let clips = selectedCanvasOverlayClips
        if clips.count > 1 {
            return clips
        }

        if let selectedClip, selectedClip.kind == .text, selectedClip.textContent != nil {
            return [selectedClip]
        }

        return clips
    }

    private func translateCanvasOverlayClips(_ clips: [Clip], dx: CGFloat, dy: CGFloat) async {
        let canvasSize = effectiveCanvasSize(in: currentProject)
        let updates = clips.map { clip in
            var transform = resolvedCanvasOverlayTransform(for: clip)
            transform.position = clampedCanvasPoint(
                CGPoint(x: transform.position.x + dx, y: transform.position.y + dy),
                canvasSize: canvasSize
            )
            return (clip: clip, transform: transform)
        }

        await dispatchCanvasOverlayUpdates(updates)
    }

    private func dispatchCanvasOverlayUpdates(_ updates: [(clip: Clip, transform: ClipTransform)]) async {
        guard !updates.isEmpty else { return }

        do {
            for update in updates {
                try await session.dispatch(SetClipPropertyCommand(clipId: update.clip.id, property: .transform(update.transform)))

                guard var textContent = update.clip.textContent else { continue }
                let shouldPromoteToSticker = isStickerClip(update.clip) && textContent.contentKind != .sticker
                let shouldSyncPosition = !pointsEqual(textContent.position, update.transform.position)
                guard shouldPromoteToSticker || shouldSyncPosition else { continue }

                if shouldPromoteToSticker {
                    textContent.contentKind = .sticker
                }
                textContent.position = update.transform.position
                try await session.dispatch(SetClipPropertyCommand(clipId: update.clip.id, property: .textContent(textContent)))
            }

            try await refreshFromSession()
        } catch {
            let message = error.localizedDescription
            try? await refreshFromSession()
            lastErrorMessage = message
        }
    }

    private func resolvedCanvasOverlayTransform(for clip: Clip) -> ClipTransform {
        var transform = clip.transform
        guard isZeroPoint(transform.position) else {
            return transform
        }

        if let textContent = clip.textContent, !isZeroPoint(textContent.position) {
            transform.position = textContent.position
        } else {
            transform.position = canvasCenter()
        }

        return transform
    }

    private func canvasOverlayVisualCenter(for clip: Clip) -> CGPoint {
        let transform = resolvedCanvasOverlayTransform(for: clip)
        return CGPoint(
            x: transform.position.x + transform.offset.x,
            y: transform.position.y + transform.offset.y
        )
    }

    private func boundingCenter(for points: [CGPoint]) -> CGPoint {
        guard let first = points.first else {
            return canvasCenter()
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        return CGPoint(x: (minX + maxX) * 0.5, y: (minY + maxY) * 0.5)
    }

    private func alignmentTarget(
        for alignment: CanvasOverlayAlignment,
        centers: [CGPoint],
        canvasSize: CGSize,
        isMultiple: Bool
    ) -> CGFloat {
        guard isMultiple, let first = centers.first else {
            let safeRect = socialSafeAreaRect()
            switch alignment {
            case .leading:
                return safeRect.minX
            case .centerX:
                return canvasSize.width * 0.5
            case .trailing:
                return safeRect.maxX
            case .top:
                return safeRect.maxY
            case .centerY:
                return canvasSize.height * 0.5
            case .bottom:
                return safeRect.minY
            }
        }

        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y

        for center in centers.dropFirst() {
            minX = min(minX, center.x)
            maxX = max(maxX, center.x)
            minY = min(minY, center.y)
            maxY = max(maxY, center.y)
        }

        switch alignment {
        case .leading:
            return minX
        case .centerX:
            return (minX + maxX) * 0.5
        case .trailing:
            return maxX
        case .top:
            return maxY
        case .centerY:
            return (minY + maxY) * 0.5
        case .bottom:
            return minY
        }
    }

    private func clampedCanvasPoint(_ point: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    private func seekPlayhead(to time: TimeInterval) {
        playheadTime = min(max(0, time), max(currentProject.timeline.duration, time))
        if playbackEngine.playerItem != nil {
            playbackEngine.seek(to: playheadTime)
        }
    }

    private func isZeroPoint(_ point: CGPoint) -> Bool {
        pointsEqual(point, CGPoint(x: 0, y: 0))
    }

    private func isStickerClip(_ clip: Clip) -> Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || isLegacyStickerContent(textContent)
    }

    private func isLegacyStickerContent(_ textContent: TextClipContent) -> Bool {
        textContent.fontFamily == "Apple Color Emoji"
    }

    private func nonZeroPoint(_ point: CGPoint) -> CGPoint? {
        pointsEqual(point, CGPoint(x: 0, y: 0)) ? nil : point
    }

    private func pointsEqual(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) <= 1.0e-9 && abs(lhs.y - rhs.y) <= 1.0e-9
    }

    private func scaledTemplatePosition(_ position: CGPoint) -> CGPoint {
        let canvasSize = effectiveCanvasSize(in: currentProject)
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return position
        }

        if abs(position.x) <= 1.0e-9 && abs(position.y) <= 1.0e-9 {
            return CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5)
        }

        return CGPoint(
            x: position.x / 1920 * canvasSize.width,
            y: position.y / 1080 * canvasSize.height
        )
    }

    private func defaultStickerPlacement(
        for sticker: StickerAsset
    ) -> (xRatio: CGFloat, yRatio: CGFloat, fontScale: Double, transformScale: CGFloat) {
        let builtInStickers = StickerLibrary.builtIn().stickers
        let stickerIndex = builtInStickers.firstIndex {
            $0.id == sticker.id || ($0.name == sticker.name && $0.emoji == sticker.emoji)
        } ?? 0
        let placements: [(xRatio: CGFloat, yRatio: CGFloat, fontScale: Double, transformScale: CGFloat)] = [
            (0.78, 0.32, 0.12, 1.00),
            (0.24, 0.30, 0.11, 0.95),
            (0.72, 0.68, 0.13, 1.08),
            (0.30, 0.70, 0.10, 0.92)
        ]

        return placements[stickerIndex % placements.count]
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
                guard Self.isTranscribable(asset) else {
                    throw EditorCommandError.invalidCommand("Select an audio or video clip.")
                }
                return (clip, asset)
            }
        }

        throw EditorCommandError.clipNotFound(clipId)
    }

    private func selectedSubtitleSource(in project: Project) throws -> (clip: Clip?, asset: MediaAsset) {
        if let selectedClipId {
            let source = try sourceClipAndAsset(for: selectedClipId, in: project)
            return (source.clip, source.asset)
        }

        if
            let selectedAssetId,
            let asset = project.mediaLibrary.assets[selectedAssetId],
            Self.isTranscribable(asset)
        {
            return (nil, asset)
        }

        throw EditorCommandError.invalidCommand("Select an audio or video clip to generate subtitles.")
    }

    private static func isTranscribable(_ asset: MediaAsset) -> Bool {
        asset.kind == .audio || asset.kind == .video
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

    private func removalRangeCount(in suggestions: [AnalysisSuggestion]) -> Int {
        suggestions.reduce(0) { count, suggestion in
            switch suggestion {
            case .silenceRemoval(let ranges), .autoCut(let ranges):
                return count + ranges.count
            case .sceneChanges:
                return count
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

    private func mediaAssetWithAppProbe(for url: URL) async -> MediaAsset {
        var asset = MediaImporter.probe(url: url)

        if (asset.kind == .video || asset.kind == .audio),
           let duration = await Self.avAssetDuration(for: url) {
            asset.duration = duration
        }

        return await Self.enrichAssetWithThumbnail(asset)
    }

    private nonisolated static func enrichAssetWithThumbnail(_ asset: MediaAsset) async -> MediaAsset {
        guard asset.kind == .video || asset.kind == .image else {
            return asset
        }

        var enrichedAsset = asset
        let thumbnailTime = Self.thumbnailTime(for: asset)
        let thumbnailSize = ThumbnailGenerator.defaultSize
        enrichedAsset.thumbnailData = await Task.detached(priority: .utility) {
            ThumbnailGenerator.generate(for: asset, at: thumbnailTime, size: thumbnailSize)
        }.value
        return enrichedAsset
    }

    private nonisolated static func thumbnailTime(for asset: MediaAsset) -> TimeInterval {
        guard asset.kind == .video else {
            return 0
        }

        guard let duration = asset.duration, duration.isFinite, duration > 0 else {
            return 0
        }

        return min(max(duration * 0.05, 0), 1)
    }

    private nonisolated static func avAssetDuration(for url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                return nil
            }
            return seconds
        } catch {
            return nil
        }
    }

    private func insertMediaAssetOnTimeline(
        _ asset: MediaAsset,
        preferredTrackId: UUID?,
        startTime: TimeInterval
    ) async throws -> Clip {
        let track = try await destinationTrack(for: asset, preferredTrackId: preferredTrackId)
        let duration = defaultDuration(for: asset)
        let clip = Clip(
            assetId: asset.id,
            kind: clipKind(for: asset.kind),
            sourceRange: TimeRange(start: 0, duration: duration),
            timelineRange: TimeRange(start: max(0, startTime), duration: duration)
        )

        try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
        let snapshot = await session.snapshot()
        return snapshot.timeline.tracks
            .flatMap(\.clips)
            .first { $0.id == clip.id } ?? clip
    }

    private func destinationTrack(for asset: MediaAsset, preferredTrackId: UUID?) async throws -> Track {
        let destinationKind = trackKind(for: asset.kind)
        let snapshot = await session.snapshot()
        if
            let preferredTrackId,
            let preferredTrack = snapshot.timeline.tracks.first(where: { $0.id == preferredTrackId }),
            preferredTrack.kind == destinationKind
        {
            return preferredTrack
        }

        return try await ensureTrack(for: destinationKind)
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

    private func audioDuration(for url: URL) -> TimeInterval? {
        guard
            let audioFile = try? AVAudioFile(forReading: url),
            audioFile.processingFormat.sampleRate > 0
        else {
            return nil
        }

        return TimeInterval(audioFile.length) / audioFile.processingFormat.sampleRate
    }

    private func resolvedVoiceoverDuration(for url: URL, fallbackDuration: TimeInterval?) -> TimeInterval {
        sanitizedDuration(audioDuration(for: url))
            ?? sanitizedDuration(fallbackDuration)
            ?? Self.minimumVoiceoverDuration
    }

    private func sanitizedDuration(_ duration: TimeInterval?) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else {
            return nil
        }

        return max(duration, Self.minimumVoiceoverDuration)
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

    func addVoiceoverAudio(from url: URL, fallbackDuration: TimeInterval? = nil) async {
        do {
            var asset = MediaImporter.probe(url: url)
            let duration = resolvedVoiceoverDuration(for: url, fallbackDuration: fallbackDuration)
            asset.duration = duration
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

    // MARK: - Phase 3-2: Templates

    func createProject(from bundle: TemplateBundle) async {
        let project = templateStore.createProject(from: bundle)
        session = EditorSession(project: project)
        currentProject = project
        canvasSelection = project.canvas.aspectRatio
        syncExportUI(from: project.exportSettings)
        selectedClipId = nil
        selectedAssetId = nil
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        analysisResult = nil
        recentAnalysisResults = []
        lastErrorMessage = nil
        lastExportURL = nil
    }

    func createProjectFromTemplate(_ bundle: TemplateBundle) async {
        await createProject(from: bundle)
    }

    private static func defaultProject() -> Project {
        ensureDefaultTracks(in: Project(name: "Untitled"))
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

    private static func exportResolutionString(for resolution: ExportResolution) -> String {
        switch resolution {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .p4K:
            return "4k"
        }
    }

    private static func exportResolution(from value: String) -> ExportResolution? {
        switch value.lowercased() {
        case "720p":
            return .p720
        case "1080p":
            return .p1080
        case "4k", "p4k":
            return .p4K
        default:
            return nil
        }
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
