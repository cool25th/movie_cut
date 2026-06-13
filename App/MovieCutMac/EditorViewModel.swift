import AppKit
import AVFoundation
import Combine
import Foundation
import ImageIO
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

    private struct TimelineNavigationPoint {
        var time: TimeInterval
        var clipId: UUID
        var trackIndex: Int
        var clipIndex: Int
        var isEnd: Bool
    }

    private static let minimumVoiceoverDuration: TimeInterval = 0.1
    private static let minimumTimelineClipDuration: TimeInterval = 0.1
    private static let timelineZoomStep: Double = 20
    private static let minimumTimelineZoom: Double = 20
    private static let maximumTimelineZoom: Double = 300

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
    /// Timeline clip the generated/imported subtitles are aligned to (F-13).
    private var subtitleAlignmentClipId: UUID?
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

    func trimSelectedClipStartToPlayhead() async {
        guard let selectedClipId, let selectedClip else { return }
        let trimTime = playheadTime

        guard trimTime > selectedClip.timelineRange.start,
              trimTime < selectedClip.timelineRange.end
        else {
            lastErrorMessage = "Move the playhead inside the selected clip to trim its start."
            return
        }

        let newDuration = selectedClip.timelineRange.end - trimTime
        guard newDuration >= Self.minimumTimelineClipDuration else {
            lastErrorMessage = "Trimmed clip would be too short."
            return
        }

        let playbackRate = min(max(selectedClip.playbackRate, 0.25), 4.0)
        let sourceDelta = (trimTime - selectedClip.timelineRange.start) * playbackRate
        let newSourceStart = min(selectedClip.sourceRange.end, selectedClip.sourceRange.start + sourceDelta)
        let newSourceDuration = selectedClip.sourceRange.end - newSourceStart
        guard newSourceDuration > 0 else {
            lastErrorMessage = "Trimmed source range would be empty."
            return
        }

        await trimClip(
            clipId: selectedClipId,
            trackId: selectedClipTrackId,
            sourceRange: TimeRange(start: newSourceStart, duration: newSourceDuration),
            timelineRange: TimeRange(start: trimTime, duration: newDuration)
        )
    }

    func trimSelectedClipEndToPlayhead() async {
        guard let selectedClipId, let selectedClip else { return }
        let trimTime = playheadTime

        guard trimTime > selectedClip.timelineRange.start,
              trimTime < selectedClip.timelineRange.end
        else {
            lastErrorMessage = "Move the playhead inside the selected clip to trim its end."
            return
        }

        let newDuration = trimTime - selectedClip.timelineRange.start
        guard newDuration >= Self.minimumTimelineClipDuration else {
            lastErrorMessage = "Trimmed clip would be too short."
            return
        }

        let playbackRate = min(max(selectedClip.playbackRate, 0.25), 4.0)
        let newSourceDuration = min(selectedClip.sourceRange.duration, newDuration * playbackRate)
        guard newSourceDuration > 0 else {
            lastErrorMessage = "Trimmed source range would be empty."
            return
        }

        await trimClip(
            clipId: selectedClipId,
            trackId: selectedClipTrackId,
            sourceRange: TimeRange(start: selectedClip.sourceRange.start, duration: newSourceDuration),
            timelineRange: TimeRange(start: selectedClip.timelineRange.start, duration: newDuration)
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

    // MARK: - Clip link groups (F-04)

    /// True when the current selection can be linked into a group.
    var canGroupSelectedClips: Bool {
        selectedClipIds.count >= 2
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

    func seekBySeconds(_ seconds: TimeInterval) {
        if playbackEngine.playerItem != nil {
            let nextPlaybackTime = playbackEngine.currentTime + seconds
            playbackEngine.seek(to: max(0, nextPlaybackTime))
            syncTimelinePlayhead(to: playbackEngine.currentTime)
            return
        }

        let duration = max(0, currentProject.timeline.duration)
        playheadTime = min(max(0, playheadTime + seconds), duration)
    }

    func jumpToPreviousClipBoundary() {
        guard let point = timelineNavigationPoints()
            .last(where: { $0.time < playheadTime - 0.001 })
        else {
            return
        }

        selectedClipId = point.clipId
        seekPlayhead(to: point.time)
    }

    func jumpToNextClipBoundary() {
        guard let point = timelineNavigationPoints()
            .first(where: { $0.time > playheadTime + 0.001 })
        else {
            return
        }

        selectedClipId = point.clipId
        seekPlayhead(to: point.time)
    }

    func zoomTimelineIn() {
        timelineZoom = min(Self.maximumTimelineZoom, timelineZoom + Self.timelineZoomStep)
    }

    func zoomTimelineOut() {
        timelineZoom = max(Self.minimumTimelineZoom, timelineZoom - Self.timelineZoomStep)
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

    /// F-14: ducks every overlapping audio clip under the selected speech
    /// clip's voiced intervals (silence-analysis complement), writing
    /// range-based ducking metadata that preview and export both consume.
    func autoDuckOtherAudio(
        duckLevel: Double = AudioDuckingPlanner.defaultDuckingLevel,
        thresholdDB: Float = -40,
        minimumSilenceDuration: TimeInterval = 0.35
    ) async {
        guard let speechClipId = selectedClipId else {
            lastErrorMessage = "Select the speech clip (voiceover or video) to duck music under."
            return
        }

        do {
            let snapshot = await session.snapshot()
            let (speechClip, asset) = try sourceClipAndAsset(for: speechClipId, in: snapshot)
            guard speechClip.kind == .audio || speechClip.kind == .video else {
                lastErrorMessage = "Ducking needs an audio or video speech clip selection."
                return
            }

            lastErrorMessage = nil
            lastStatusMessage = "Analyzing speech for ducking..."

            let provider = SilenceDetectionProvider(
                silenceThresholdDB: thresholdDB,
                minimumSilenceDuration: minimumSilenceDuration
            )
            let analysis = try await provider.analyze(asset: asset, in: snapshot)
            let silenceTimelineRanges: [TimeRange] = analysis.suggestions.flatMap { suggestion -> [TimeRange] in
                guard case .silenceRemoval(let ranges) = suggestion else { return [] }
                return ranges.compactMap { timelineMapping(for: $0, in: speechClip)?.timelineRange }
            }

            let voiceIntervals = AudioDuckingPlanner.voiceIntervals(
                speechTimelineRange: speechClip.timelineRange,
                silenceRangesInTimeline: silenceTimelineRanges
            )
            guard !voiceIntervals.isEmpty else {
                lastStatusMessage = "No voiced intervals detected in the selected clip; nothing to duck."
                return
            }

            var duckingByClip: [UUID: [TimeRange]] = [:]
            for track in snapshot.timeline.tracks where track.kind == .audio {
                for clip in track.clips
                    where clip.id != speechClipId && clip.timelineRange.overlaps(speechClip.timelineRange)
                {
                    let ranges = AudioDuckingPlanner.duckingRanges(
                        forTarget: clip.timelineRange,
                        voiceIntervals: voiceIntervals
                    )
                    if !ranges.isEmpty {
                        duckingByClip[clip.id] = ranges
                    }
                }
            }

            guard !duckingByClip.isEmpty else {
                lastStatusMessage = "No overlapping audio clips found to duck under the selection."
                return
            }

            try await session.dispatch(SetAudioDuckingCommand(
                duckingRangesByClip: duckingByClip,
                level: duckLevel
            ))
            try await refreshFromSession()
            lastStatusMessage = "Ducked \(duckingByClip.count) audio clip(s) under \(voiceIntervals.count) voiced interval(s) at \(Int(duckLevel * 100))% volume."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Clears range-based ducking from the selected clip.
    func clearDuckingOnSelectedClip() async {
        guard let selectedClipId, let selectedClip, !selectedClip.duckingRanges.isEmpty else { return }
        await apply(SetAudioDuckingCommand(duckingRangesByClip: [selectedClipId: []], level: nil))
        lastStatusMessage = "Cleared audio ducking on the selected clip."
    }

    /// F-15: detects beats in the selected audio/video clip and adds beat
    /// markers, which immediately become drag snap targets.
    func detectBeats() async {
        guard let selectedClipId else {
            lastErrorMessage = "Select a music clip to detect beats."
            return
        }

        do {
            let snapshot = await session.snapshot()
            let (clip, asset) = try sourceClipAndAsset(for: selectedClipId, in: snapshot)
            guard clip.kind == .audio || clip.kind == .video else {
                lastErrorMessage = "Beat detection needs an audio or video clip selection."
                return
            }

            lastErrorMessage = nil
            lastStatusMessage = "Detecting beats..."

            let provider = BeatDetectionProvider()
            let beatTimes = try await provider.analyze(asset: asset)
            let timelineBeats: [TimeInterval] = beatTimes.compactMap { time in
                timelineMapping(
                    for: TimeRange(start: time, duration: .ulpOfOne),
                    in: clip
                )?.timelineRange.start
            }

            guard !timelineBeats.isEmpty else {
                lastStatusMessage = "No beats detected in the selected clip."
                return
            }

            let markers = timelineBeats.enumerated().map { index, time in
                Marker(time: time, name: "Beat \(index + 1)", color: "FF9F0A", kind: .beat)
            }
            try await session.dispatch(AddMarkersCommand(markers: markers))
            try await refreshFromSession()

            let bpmText = BeatDetectionProvider.estimatedBPM(from: beatTimes)
                .map { String(format: " (~%.0f BPM)", $0) } ?? ""
            lastStatusMessage = "Added \(markers.count) beat markers\(bpmText). Clips snap to beats while dragging."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Removes every generated beat marker in one undoable step.
    func clearBeatMarkers() async {
        guard hasBeatMarkers else { return }
        await apply(RemoveMarkersCommand(kind: .beat))
        lastStatusMessage = "Removed all beat markers."
    }

    var hasBeatMarkers: Bool {
        currentProject.markers.contains { $0.kind == .beat }
    }

    var canDetectBeats: Bool {
        guard let selectedClip else { return false }
        return selectedClip.kind == .audio || selectedClip.kind == .video
    }

    // MARK: - User text style presets (F-12R)

    var userTextStylePresets: [UserTextStylePreset] = []

    func loadUserTextStylePresets() {
        userTextStylePresets = UserTextStylePresetStore.load(from: UserTextStylePresetStore.defaultStoreURL())
    }

    /// Captures the selected text clip's style as a reusable preset.
    func saveSelectedTextStyleAsPreset() {
        guard let textContent = selectedClip?.textContent else {
            lastErrorMessage = "Select a text clip to save its style."
            return
        }

        let name = "My Style \(userTextStylePresets.count + 1)"
        let preset = UserTextStylePreset(name: name, capturing: textContent)
        userTextStylePresets.append(preset)
        persistUserTextStylePresets()
        lastStatusMessage = "Saved text style preset \"\(name)\"."
    }

    /// Applies a saved preset's style to the selected text clip.
    func applyUserTextStylePreset(_ preset: UserTextStylePreset) async {
        guard let textContent = selectedClip?.textContent else { return }
        await updateSelectedTextContent(preset.applying(to: textContent))
        lastStatusMessage = "Applied text style preset \"\(preset.name)\"."
    }

    func deleteUserTextStylePreset(_ presetId: UUID) {
        userTextStylePresets.removeAll { $0.id == presetId }
        persistUserTextStylePresets()
    }

    private func persistUserTextStylePresets() {
        do {
            try UserTextStylePresetStore.save(
                userTextStylePresets,
                to: UserTextStylePresetStore.defaultStoreURL()
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Text-to-speech (F-17)

    var ttsVoices: [TextToSpeechVoice] = []
    var selectedTTSVoiceId: String?

    var canGenerateSpeechFromSelection: Bool {
        guard let content = selectedClip?.textContent, content.contentKind != .sticker else { return false }
        return !content.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadTTSVoices() {
        guard ttsVoices.isEmpty else { return }
        ttsVoices = TextToSpeechSynthesizer.availableVoices()
        if selectedTTSVoiceId == nil {
            selectedTTSVoiceId = ttsVoices.first { $0.language.hasPrefix("en") }?.id ?? ttsVoices.first?.id
        }
    }

    /// Synthesizes the selected text clip's text to a spoken audio clip aligned
    /// to the text clip's timeline start, and inserts it on the audio track.
    func generateSpeechFromSelectedText() async {
        guard let textClip = selectedClip,
              let content = textClip.textContent,
              content.contentKind != .sticker else {
            lastErrorMessage = "Select a text clip to generate speech."
            return
        }

        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            lastErrorMessage = "The selected text clip has no text to speak."
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Generating speech..."

        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("MovieCutTTS", isDirectory: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).caf")

            let synthesizer = TextToSpeechSynthesizer()
            let options = TextToSpeechSynthesizer.Options(voiceIdentifier: selectedTTSVoiceId)
            let duration = try await synthesizer.synthesize(text: text, to: url, options: options)

            var asset = MediaImporter.probe(url: url)
            let resolvedDuration = sanitizedDuration(audioDuration(for: url) ?? duration)
                ?? max(duration, Self.minimumVoiceoverDuration)
            asset.duration = resolvedDuration
            try await session.dispatch(ImportMediaCommand(asset: asset))

            let audioTrack = try await ensureTrack(for: .audio)
            let clip = Clip(
                assetId: asset.id,
                kind: .audio,
                sourceRange: TimeRange(start: 0, duration: resolvedDuration),
                timelineRange: TimeRange(start: textClip.timelineRange.start, duration: resolvedDuration)
            )
            try await session.dispatch(AddClipCommand(trackId: audioTrack.id, clip: clip))
            selectedAssetId = asset.id
            selectedClipId = clip.id
            try await refreshFromSession()

            lastStatusMessage = String(
                format: "Generated %.1fs of speech aligned to the text clip.",
                resolvedDuration
            )
        } catch TextToSpeechError.noAudioProduced {
            lastStatusMessage = nil
            lastErrorMessage = "No speech audio was produced. Check that a system voice is installed."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
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

    /// Sets or clears the canvas background fill (F-11).
    func updateCanvasBackground(_ background: CanvasBackground?) async {
        await apply(SetCanvasBackgroundCommand(background: background))
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

    // MARK: - Chroma key eyedropper (F-10)

    /// Whether the preview is in eyedropper mode for picking the key color.
    var isChromaKeyEyedropperActive = false

    func toggleChromaKeyEyedropper() {
        isChromaKeyEyedropperActive.toggle()
        lastStatusMessage = isChromaKeyEyedropperActive
            ? "Eyedropper on: click the preview to pick the key color."
            : nil
    }

    /// Samples the selected video clip's frame at a normalized preview point and
    /// sets it as the chroma key color (F-10 eyedropper).
    func pickChromaKeyColor(atNormalizedPoint point: CGPoint) async {
        defer { isChromaKeyEyedropperActive = false }

        guard let selectedClipId, let clip = selectedClip, clip.kind == .video,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId] else {
            lastErrorMessage = "Select a video clip to pick a key color."
            return
        }
        _ = selectedClipId

        let localTime = max(0, playheadTime - clip.timelineRange.start)
        let sourceTime = clip.sourceRange.start + localTime
        let avAsset = AVAsset(url: asset.originalURL)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        do {
            let cmTime = CMTime(seconds: sourceTime, preferredTimescale: 600)
            let cgImage = try generator.copyCGImage(at: cmTime, actualTime: nil)
            guard let color = PixelSampler.color(in: cgImage, atNormalizedPoint: point) else {
                lastErrorMessage = "Couldn't sample that point."
                return
            }

            let hex = PixelSampler.hexString(from: color)
            var settings = clip.chromaKey ?? ChromaKeySettings.greenScreen()
            settings.keyColor = hex
            await updateSelectedChromaKey(settings)
            lastErrorMessage = nil
            lastStatusMessage = "Key color set to \(hex)."
        } catch {
            lastErrorMessage = "Couldn't read the frame: \(error.localizedDescription)"
        }
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

    // MARK: - Auto cut preview (F-18)

    /// Silence threshold in dB (lower = stricter; only quieter audio counts as silence).
    var autoCutThresholdDB: Float = -40
    /// Minimum silence length in seconds to consider for removal.
    var autoCutMinSilence: TimeInterval = 0.5
    /// Seconds preserved on each side of detected silence so speech edges survive.
    var autoCutPadding: TimeInterval = 0.1
    /// Removable timeline ranges currently shown as a preview (empty = no preview).
    var autoCutPreviewRanges: [TimeRange] = []
    /// The clip the active preview was computed for.
    private(set) var autoCutPreviewClipId: UUID?

    var hasAutoCutPreview: Bool { !autoCutPreviewRanges.isEmpty }

    var autoCutPreviewTotalDuration: TimeInterval {
        AutoCutPlanner.totalDuration(of: autoCutPreviewRanges)
    }

    /// Computes the removable silence ranges for the selected clip and stores
    /// them as a preview WITHOUT modifying the timeline (F-18 AC②).
    func previewAutoCutOnSelection() async {
        guard let clipId = selectedClipId, canRunAutoCutOnSelection else {
            lastErrorMessage = "Select an audio or video clip to auto cut silence."
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Analyzing silence..."

        do {
            let snapshot = await session.snapshot()
            let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
            let provider = SilenceDetectionProvider(
                silenceThresholdDB: autoCutThresholdDB,
                minimumSilenceDuration: autoCutMinSilence
            )
            let result = try await provider.analyze(asset: asset, in: snapshot)
            let silenceTimelineRanges: [TimeRange] = result.suggestions.flatMap { suggestion -> [TimeRange] in
                guard case .silenceRemoval(let ranges) = suggestion else { return [] }
                return ranges.compactMap { timelineMapping(for: $0, in: clip)?.timelineRange }
            }

            let removable = AutoCutPlanner.removableRanges(
                fromSilence: silenceTimelineRanges,
                within: clip.timelineRange,
                padding: autoCutPadding
            )

            autoCutPreviewRanges = removable
            autoCutPreviewClipId = clipId

            if removable.isEmpty {
                lastStatusMessage = "No removable silence found with the current settings."
            } else {
                lastStatusMessage = String(
                    format: "Preview: %d range(s), %.1fs removable. Review and Apply.",
                    removable.count,
                    autoCutPreviewTotalDuration
                )
            }
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Discards the auto-cut preview without changing the timeline (F-18 AC②).
    func cancelAutoCutPreview() {
        autoCutPreviewRanges = []
        autoCutPreviewClipId = nil
        lastStatusMessage = "Auto cut preview cancelled."
    }

    /// Applies the previewed removable ranges as a single undo unit (F-18 AC③).
    func applyAutoCutPreview() async {
        let ranges = autoCutPreviewRanges
        guard !ranges.isEmpty else { return }

        do {
            try await session.dispatch(AutoCutCommand(removableRanges: ranges))
            try await refreshFromSession()
            let count = ranges.count
            recordAnalysisResult(
                action: "Auto Cut",
                count: count,
                message: "Removed \(count) silent \(count == 1 ? "range" : "ranges").",
                clipId: autoCutPreviewClipId
            )
            lastErrorMessage = nil
            lastStatusMessage = "Removed \(count) silent \(count == 1 ? "range" : "ranges")."
            autoCutPreviewRanges = []
            autoCutPreviewClipId = nil
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
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

    /// Imports an external `.cube` LUT, validates it, copies it into Application
    /// Support, and appends an `.externalLUT` effect to the selected clip (F-09).
    func importExternalLUT(from url: URL) async {
        guard let selectedClipId, let clip = selectedClip else {
            lastErrorMessage = "Select a clip to apply the LUT to."
            return
        }

        do {
            // Validate by parsing before copying so bad files report clearly.
            let lut = try CubeLUTParser.parse(contentsOf: url)

            let directory = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("MovieCut/LUTs", isDirectory: true)
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("MovieCutLUTs", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)

            var effects = clip.effects
            effects.append(Effect(
                type: .externalLUT,
                parameters: ["intensity": 1.0],
                lutPath: destination.path
            ))
            try await session.dispatch(SetClipPropertyCommand(clipId: selectedClipId, property: .effects(effects)))
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = "Imported \(url.lastPathComponent) (\(lut.dimension)-size LUT)."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = "Could not import LUT: \(lutErrorDescription(error))"
        }
    }

    private func lutErrorDescription(_ error: Error) -> String {
        guard let parseError = error as? CubeLUTParser.ParseError else {
            return error.localizedDescription
        }
        switch parseError {
        case .missingSize: return "missing LUT_3D_SIZE."
        case .unsupported1D: return "1D LUTs are not supported."
        case .sizeOutOfRange(let size): return "unsupported cube size \(size)."
        case .entryCountMismatch(let expected, let found): return "expected \(expected) entries, found \(found)."
        case .malformedEntry(let line): return "malformed data line \"\(line)\"."
        }
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
            subtitleAlignmentClipId = source.clip?.id
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

    // MARK: - Subtitle editing & SRT (F-13)

    func updateGeneratedSubtitleSegment(
        _ segmentId: UUID,
        text: String? = nil,
        startTime: TimeInterval? = nil,
        endTime: TimeInterval? = nil
    ) async {
        guard let index = generatedSubtitleSegments.firstIndex(where: { $0.id == segmentId }) else { return }

        var segment = generatedSubtitleSegments[index]
        if let text {
            segment.text = text
        }
        if let startTime {
            segment.startTime = max(0, startTime)
        }
        if let endTime {
            segment.endTime = endTime
        }
        segment.endTime = max(segment.endTime, segment.startTime + 0.1)
        generatedSubtitleSegments[index] = segment
        generatedSubtitleSegments.sort { $0.startTime < $1.startTime }
        await rebuildPendingSubtitleClips()
    }

    func splitGeneratedSubtitleSegment(_ segmentId: UUID) async {
        guard let index = generatedSubtitleSegments.firstIndex(where: { $0.id == segmentId }) else { return }

        let segment = generatedSubtitleSegments[index]
        let duration = segment.endTime - segment.startTime
        guard duration >= 0.4 else {
            lastErrorMessage = "Segment is too short to split."
            return
        }

        let midTime = segment.startTime + duration / 2
        let words = segment.text.split(separator: " ", omittingEmptySubsequences: true)
        let firstText: String
        let secondText: String
        if words.count >= 2 {
            let half = (words.count + 1) / 2
            firstText = words[..<half].joined(separator: " ")
            secondText = words[half...].joined(separator: " ")
        } else {
            firstText = segment.text
            secondText = segment.text
        }

        var first = segment
        first.text = firstText
        first.endTime = midTime
        let second = TranscriptionSegment(
            text: secondText,
            startTime: midTime,
            endTime: segment.endTime,
            confidence: segment.confidence
        )
        generatedSubtitleSegments.replaceSubrange(index...index, with: [first, second])
        await rebuildPendingSubtitleClips()
        lastStatusMessage = "Split subtitle segment at \(SubtitleDocument.srtTimestamp(from: midTime))."
    }

    func mergeGeneratedSubtitleSegmentWithNext(_ segmentId: UUID) async {
        guard let index = generatedSubtitleSegments.firstIndex(where: { $0.id == segmentId }),
              index + 1 < generatedSubtitleSegments.count
        else {
            lastErrorMessage = "No following segment to merge with."
            return
        }

        var merged = generatedSubtitleSegments[index]
        let next = generatedSubtitleSegments[index + 1]
        merged.text = [merged.text, next.text]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        merged.endTime = max(merged.endTime, next.endTime)
        generatedSubtitleSegments.replaceSubrange(index...(index + 1), with: [merged])
        await rebuildPendingSubtitleClips()
        lastStatusMessage = "Merged subtitle segment with the next one."
    }

    func deleteGeneratedSubtitleSegment(_ segmentId: UUID) async {
        generatedSubtitleSegments.removeAll { $0.id == segmentId }
        await rebuildPendingSubtitleClips()
    }

    func importSubtitles(from url: URL) async {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let segments = SubtitleDocument.parseSRT(text)
            guard !segments.isEmpty else {
                lastStatusMessage = nil
                lastErrorMessage = "No subtitle cues found in \(url.lastPathComponent)."
                return
            }

            generatedSubtitleSegments = segments
            if let selectedClip, selectedClip.kind == .video || selectedClip.kind == .audio {
                subtitleAlignmentClipId = selectedClip.id
            } else {
                subtitleAlignmentClipId = nil
            }
            await rebuildPendingSubtitleClips()
            lastErrorMessage = nil
            lastStatusMessage = "Imported \(segments.count) subtitle cues from \(url.lastPathComponent). Review and Apply to Timeline."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func exportSubtitles(to url: URL) {
        let segments = generatedSubtitleSegments.isEmpty
            ? timelineSubtitleSegments()
            : generatedSubtitleSegments
        guard !segments.isEmpty else {
            lastStatusMessage = nil
            lastErrorMessage = "There are no subtitle segments or timeline text clips to export."
            return
        }

        do {
            try SubtitleDocument.srtString(from: segments).write(to: url, atomically: true, encoding: .utf8)
            lastErrorMessage = nil
            lastStatusMessage = "Exported \(segments.count) subtitle cues to \(url.lastPathComponent)."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Derives SRT segments from applied text-track clips (excluding stickers).
    private func timelineSubtitleSegments() -> [TranscriptionSegment] {
        currentProject.timeline.tracks
            .filter { $0.kind == .text }
            .flatMap(\.clips)
            .compactMap { clip in
                guard let content = clip.textContent, content.contentKind != .sticker else {
                    return nil
                }
                return TranscriptionSegment(
                    text: content.text,
                    startTime: clip.timelineRange.start,
                    endTime: clip.timelineRange.end,
                    confidence: 1.0
                )
            }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Rebuilds pending subtitle clips from the edited segments using the
    /// same alignment rules as the original transcription pass.
    private func rebuildPendingSubtitleClips() async {
        let result = TranscriptionResult(segments: generatedSubtitleSegments)
        let snapshot = await session.snapshot()

        if let subtitleAlignmentClipId,
           let clip = snapshot.timeline.tracks
               .flatMap(\.clips)
               .first(where: { $0.id == subtitleAlignmentClipId }) {
            pendingSubtitleClips = subtitleClips(from: result, alignedTo: clip)
        } else {
            pendingSubtitleClips = transcriptionService.subtitles(from: result, in: snapshot)
        }
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
        let rawFrames = await provider.calculateCropFrames(for: avAsset, targetAspect: targetAspect)
        let frames = ReframeSmoothing.smooth(rawFrames)
        let canvasSize = effectiveCanvasSize(in: snapshot)

        let generatedKeyframes = reframeKeyframes(from: frames, clip: clip, canvasSize: canvasSize)
        guard !generatedKeyframes.isEmpty else {
            lastErrorMessage = nil
            return 0
        }

        let updatedKeyframes = mergedReframeKeyframes(existing: clip.keyframes, generated: generatedKeyframes)
        // Persist auto-reframe keyframes on the clip; export forwards clip.keyframes to CustomVideoCompositor.
        try await session.dispatch(SetClipPropertyCommand(clipId: clipId, property: .keyframes(updatedKeyframes)))
        try await refreshFromSession()
        return generatedKeyframes.count
    }

    /// Maps smoothed crop frames to position/scale keyframes in clip-local time.
    private func reframeKeyframes(from frames: [CropFrame], clip: Clip, canvasSize: CGSize) -> [Keyframe] {
        var generatedKeyframes: [Keyframe] = []
        for frame in frames {
            let pointRange = TimeRange(start: frame.time, duration: .ulpOfOne)
            guard let mapping = timelineMapping(for: pointRange, in: clip) else { continue }

            let localTime = mapping.timelineRange.start - clip.timelineRange.start
            let posX = Double(frame.rect.midX - 0.5) * Double(canvasSize.width)
            let posY = Double(frame.rect.midY - 0.5) * Double(canvasSize.height)
            let scale = Double(1.0 / max(frame.rect.width, .leastNonzeroMagnitude))

            generatedKeyframes.append(Keyframe(property: .positionX, time: localTime, value: posX))
            generatedKeyframes.append(Keyframe(property: .positionY, time: localTime, value: posY))
            generatedKeyframes.append(Keyframe(property: .scaleX, time: localTime, value: scale))
            generatedKeyframes.append(Keyframe(property: .scaleY, time: localTime, value: scale))
        }
        return generatedKeyframes
    }

    private func mergedReframeKeyframes(existing: [Keyframe], generated: [Keyframe]) -> [Keyframe] {
        let reframedProperties: Set<AnimatableProperty> = [.positionX, .positionY, .scaleX, .scaleY]
        let preserved = existing.filter { !reframedProperties.contains($0.property) }
        return (preserved + generated).sorted {
            $0.time == $1.time ? $0.property.rawValue < $1.property.rawValue : $0.time < $1.time
        }
    }

    // MARK: - Auto reframe preview (F-19)

    /// Smoothed crop frames currently previewed (empty = no preview).
    var reframePreviewFrames: [CropFrame] = []
    private var reframePreviewKeyframes: [Keyframe] = []
    private(set) var reframePreviewClipId: UUID?

    var hasReframePreview: Bool { !reframePreviewFrames.isEmpty }

    /// Computes smoothed reframe frames/keyframes for the selected video clip
    /// and stores them as a preview WITHOUT modifying the clip (F-19 preview).
    func previewAutoReframeOnSelection() async {
        guard let clipId = selectedClipId, canAutoReframeSelection else {
            lastErrorMessage = "Select a video clip to auto reframe."
            return
        }

        lastErrorMessage = nil
        lastStatusMessage = "Analyzing subject for reframe..."

        do {
            let snapshot = await session.snapshot()
            let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
            guard asset.kind == .video else {
                lastErrorMessage = "Auto reframe needs a video clip."
                return
            }

            let targetAspect = canvasAspectValue(in: snapshot)
            let provider = AutoReframeProvider()
            let avAsset = AVAsset(url: asset.originalURL)
            let rawFrames = await provider.calculateCropFrames(for: avAsset, targetAspect: targetAspect)
            let frames = ReframeSmoothing.smooth(rawFrames)
            let canvasSize = effectiveCanvasSize(in: snapshot)
            let keyframes = reframeKeyframes(from: frames, clip: clip, canvasSize: canvasSize)

            guard !keyframes.isEmpty else {
                reframePreviewFrames = []
                reframePreviewKeyframes = []
                reframePreviewClipId = nil
                lastStatusMessage = "No subject frames detected; nothing to reframe."
                return
            }

            reframePreviewFrames = frames
            reframePreviewKeyframes = keyframes
            reframePreviewClipId = clipId
            lastStatusMessage = String(
                format: "Preview: %d crop frames, %d keyframes. Review and Apply.",
                frames.count,
                keyframes.count
            )
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Discards the reframe preview without changing the clip (F-19).
    func cancelAutoReframePreview() {
        reframePreviewFrames = []
        reframePreviewKeyframes = []
        reframePreviewClipId = nil
        lastStatusMessage = "Auto reframe preview cancelled."
    }

    /// Commits the previewed reframe keyframes to the clip.
    func applyAutoReframePreview() async {
        guard let clipId = reframePreviewClipId, !reframePreviewKeyframes.isEmpty else { return }

        do {
            let snapshot = await session.snapshot()
            guard let clip = snapshot.timeline.tracks.flatMap(\.clips).first(where: { $0.id == clipId }) else {
                cancelAutoReframePreview()
                return
            }

            let updated = mergedReframeKeyframes(existing: clip.keyframes, generated: reframePreviewKeyframes)
            try await session.dispatch(SetClipPropertyCommand(clipId: clipId, property: .keyframes(updated)))
            try await refreshFromSession()

            let count = reframePreviewKeyframes.count
            recordAnalysisResult(
                action: "Auto Reframe",
                count: count,
                message: "Applied \(count) reframe keyframes.",
                clipId: clipId
            )
            lastErrorMessage = nil
            lastStatusMessage = "Applied \(count) reframe keyframes."
            reframePreviewFrames = []
            reframePreviewKeyframes = []
            reframePreviewClipId = nil
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    private func canvasAspectValue(in project: Project) -> CGFloat {
        let size = effectiveCanvasSize(in: project)
        return size.width / max(size.height, 1)
    }

    // MARK: - Auto highlights (F-20)

    /// Scored highlight candidates for the selected clip (empty = none).
    var highlightCandidates: [HighlightCandidate] = []

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

            // Map the timeline-space candidate window back to source time.
            let timelineDuration = max(clip.timelineRange.duration, .leastNonzeroMagnitude)
            let ratio = clip.sourceRange.duration / timelineDuration
            let localStart = candidate.range.start - clip.timelineRange.start
            let sourceStart = clip.sourceRange.start + max(0, localStart) * ratio
            let sourceDuration = candidate.range.duration * ratio

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

            session = EditorSession(project: newProject)
            currentProject = newProject
            canvasSelection = newProject.canvas.aspectRatio
            syncExportUI(from: newProject.exportSettings)
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

    // MARK: - Assistant (F-21)

    /// The last assistant outcome message shown in the panel.
    var assistantResultMessage: String?
    /// Suggestions shown when the last instruction was not understood.
    var assistantSuggestions: [String] = []

    /// Parses a natural-language instruction and executes the mapped intent
    /// across the targeted clips using existing commands (F-21).
    func runAssistantCommand(_ text: String) async {
        assistantResultMessage = nil
        assistantSuggestions = []

        switch AssistantCommandParser.parse(text) {
        case .unrecognized(let suggestions):
            assistantSuggestions = suggestions
            assistantResultMessage = "I couldn't map that to an edit. Try one of the examples."
            lastStatusMessage = nil

        case .recognized(let intent):
            await executeAssistantIntent(intent)
        }
    }

    private func executeAssistantIntent(_ intent: AssistantIntent) async {
        do {
            let snapshot = await session.snapshot()

            if case .addMarker = intent.action {
                let name = "Marker \(snapshot.markers.count + 1)"
                try await session.dispatch(AddMarkerCommand(marker: Marker(time: playheadTime, name: name)))
                try await refreshFromSession()
                assistantResultMessage = "Added a marker at the playhead."
                lastStatusMessage = assistantResultMessage
                return
            }

            let clips = assistantTargetClips(intent.target, in: snapshot)
            guard !clips.isEmpty else {
                assistantResultMessage = "No matching clips for that instruction."
                lastStatusMessage = nil
                return
            }

            var applied = 0
            for clip in clips {
                if let command = assistantCommand(for: intent.action, clip: clip) {
                    try await session.dispatch(command)
                    applied += 1
                }
            }
            try await refreshFromSession()

            assistantResultMessage = applied == 0
                ? "That instruction doesn't apply to the selected clips."
                : "\(assistantActionLabel(intent.action)) applied to \(applied) clip(s)."
            lastStatusMessage = assistantResultMessage
        } catch {
            assistantResultMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }

    private func assistantTargetClips(_ target: AssistantTarget, in project: Project) -> [Clip] {
        let allClips = project.timeline.tracks.flatMap(\.clips)
        switch target {
        case .selection:
            return allClips.filter { selectedClipIds.contains($0.id) }
        case .allClips:
            return allClips
        case .videoClips:
            return allClips.filter { $0.kind == .video }
        case .audioClips:
            return allClips.filter { $0.kind == .audio }
        case .textClips:
            return allClips.filter { $0.kind == .text }
        }
    }

    private func assistantCommand(for action: AssistantAction, clip: Clip) -> (any EditorCommand)? {
        switch action {
        case .applyFilter(let type):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            var effects = clip.effects.filter { $0.type != type }
            effects.append(Effect(type: type))
            return SetClipPropertyCommand(clipId: clip.id, property: .effects(effects))

        case .removeFilters:
            guard !clip.effects.isEmpty else { return nil }
            return SetClipPropertyCommand(clipId: clip.id, property: .effects([]))

        case .setVolume(let value):
            guard clip.kind == .video || clip.kind == .audio else { return nil }
            return SetVolumeCommand(clipId: clip.id, volume: value)

        case .setFade(let seconds):
            guard clip.kind == .video || clip.kind == .audio else { return nil }
            let clamped = min(max(seconds, 0), clip.timelineRange.duration / 2)
            return AudioFadeCommand(clipId: clip.id, fadeInDuration: clamped, fadeOutDuration: clamped)

        case .removeFade:
            guard clip.fadeInDuration > 0 || clip.fadeOutDuration > 0 else { return nil }
            return AudioFadeCommand(clipId: clip.id, fadeInDuration: 0, fadeOutDuration: 0)

        case .adjustBrightness(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            // Reconstruct via init so the value re-clamps to its valid range.
            let updated = ColorCorrection(
                brightness: current.brightness + delta,
                contrast: current.contrast,
                saturation: current.saturation,
                warmth: current.warmth,
                tint: current.tint
            )
            return SetClipPropertyCommand(clipId: clip.id, property: .colorCorrection(updated))

        case .adjustContrast(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            let updated = ColorCorrection(
                brightness: current.brightness,
                contrast: current.contrast + delta,
                saturation: current.saturation,
                warmth: current.warmth,
                tint: current.tint
            )
            return SetClipPropertyCommand(clipId: clip.id, property: .colorCorrection(updated))

        case .adjustSaturation(let delta):
            guard clip.kind == .video || clip.kind == .image else { return nil }
            let current = clip.colorCorrection ?? ColorCorrection()
            let updated = ColorCorrection(
                brightness: current.brightness,
                contrast: current.contrast,
                saturation: current.saturation + delta,
                warmth: current.warmth,
                tint: current.tint
            )
            return SetClipPropertyCommand(clipId: clip.id, property: .colorCorrection(updated))

        case .addMarker:
            return nil
        }
    }

    private func assistantActionLabel(_ action: AssistantAction) -> String {
        switch action {
        case .applyFilter(let type): return "Filter (\(type.rawValue))"
        case .removeFilters: return "Remove filters"
        case .setVolume(let value): return "Volume \(Int(value * 100))%"
        case .setFade(let seconds): return String(format: "Fade %.1fs", seconds)
        case .removeFade: return "Remove fade"
        case .adjustBrightness: return "Brightness"
        case .adjustContrast: return "Contrast"
        case .adjustSaturation: return "Saturation"
        case .addMarker: return "Marker"
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
        subtitleAlignmentClipId = nil
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

        let probe = await Self.appMetadataProbe(
            for: url,
            kind: asset.kind,
            baseMetadata: asset.metadata
        )
        asset.duration = probe.duration ?? asset.duration
        asset.metadata = probe.metadata

        return await Self.enrichAssetWithThumbnail(asset)
    }

    private nonisolated static func appMetadataProbe(
        for url: URL,
        kind: MediaKind,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        switch kind {
        case .video:
            return await videoMetadataProbe(for: url, baseMetadata: baseMetadata)
        case .audio:
            return await audioMetadataProbe(for: url, baseMetadata: baseMetadata)
        case .image:
            return (nil, imageMetadataProbe(for: url, baseMetadata: baseMetadata))
        }
    }

    private nonisolated static func videoMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        let avAsset = AVURLAsset(url: url)
        var metadata = baseMetadata

        let duration = await Self.avAssetDuration(for: avAsset)
        guard let videoTrack = await Self.firstTrack(in: avAsset, mediaType: .video) else {
            return (duration, metadata)
        }

        if let dimensions = await Self.videoDisplayDimensions(for: videoTrack) {
            metadata.width = dimensions.width
            metadata.height = dimensions.height
        }
        if let frameRate = await Self.videoFrameRate(for: videoTrack) {
            metadata.frameRate = frameRate
        }
        if let codec = await Self.codecDescription(for: videoTrack) {
            metadata.codec = codec
        }

        return (duration, metadata)
    }

    private nonisolated static func audioMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        let avAsset = AVURLAsset(url: url)
        var metadata = baseMetadata

        let duration = await Self.avAssetDuration(for: avAsset)
        guard let audioTrack = await Self.firstTrack(in: avAsset, mediaType: .audio) else {
            return (duration, metadata)
        }

        if let audioDescription = await Self.audioFormatDescription(for: audioTrack) {
            if let sampleRate = audioDescription.sampleRate {
                metadata.sampleRate = sampleRate
            }
            if let channelCount = audioDescription.channelCount {
                metadata.channelCount = channelCount
            }
        }
        if let codec = await Self.codecDescription(for: audioTrack) {
            metadata.codec = codec
        }

        return (duration, metadata)
    }

    private nonisolated static func imageMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) -> MediaMetadata {
        var metadata = baseMetadata

        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? NSNumber {
                metadata.width = width.intValue
            }
            if let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                metadata.height = height.intValue
            }
        }

        if metadata.width == nil || metadata.height == nil,
           let image = NSImage(contentsOf: url),
           let representation = image.representations.first {
            if metadata.width == nil, representation.pixelsWide > 0 {
                metadata.width = representation.pixelsWide
            }
            if metadata.height == nil, representation.pixelsHigh > 0 {
                metadata.height = representation.pixelsHigh
            }
        }

        return metadata
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
        await avAssetDuration(for: AVURLAsset(url: url))
    }

    private nonisolated static func avAssetDuration(for asset: AVURLAsset) async -> TimeInterval? {
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

    private nonisolated static func firstTrack(
        in asset: AVURLAsset,
        mediaType: AVMediaType
    ) async -> AVAssetTrack? {
        do {
            return try await asset.loadTracks(withMediaType: mediaType).first
        } catch {
            return nil
        }
    }

    private nonisolated static func videoDisplayDimensions(for track: AVAssetTrack) async -> (width: Int, height: Int)? {
        do {
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedBounds = CGRect(origin: CGPoint(x: 0, y: 0), size: naturalSize)
                .applying(preferredTransform)
            let width = Int(abs(transformedBounds.width).rounded())
            let height = Int(abs(transformedBounds.height).rounded())

            if width > 0, height > 0 {
                return (width, height)
            }

            let fallbackWidth = Int(abs(naturalSize.width).rounded())
            let fallbackHeight = Int(abs(naturalSize.height).rounded())
            guard fallbackWidth > 0, fallbackHeight > 0 else {
                return nil
            }
            return (fallbackWidth, fallbackHeight)
        } catch {
            return nil
        }
    }

    private nonisolated static func videoFrameRate(for track: AVAssetTrack) async -> Double? {
        do {
            let frameRate = try await track.load(.nominalFrameRate)
            guard frameRate.isFinite, frameRate > 0 else {
                return nil
            }
            return Double(frameRate)
        } catch {
            return nil
        }
    }

    private nonisolated static func audioFormatDescription(for track: AVAssetTrack) async -> (sampleRate: Int?, channelCount: Int?)? {
        guard let formatDescription = await Self.firstFormatDescription(for: track),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        let sampleRate = streamDescription.mSampleRate.isFinite && streamDescription.mSampleRate > 0
            ? Int(streamDescription.mSampleRate.rounded())
            : nil
        let channelCount = streamDescription.mChannelsPerFrame > 0
            ? Int(streamDescription.mChannelsPerFrame)
            : nil
        return (sampleRate, channelCount)
    }

    private nonisolated static func codecDescription(for track: AVAssetTrack) async -> String? {
        guard let formatDescription = await Self.firstFormatDescription(for: track) else {
            return nil
        }

        return codecName(from: CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    private nonisolated static func firstFormatDescription(for track: AVAssetTrack) async -> CMFormatDescription? {
        do {
            return try await track.load(.formatDescriptions).first
        } catch {
            return nil
        }
    }

    private nonisolated static func codecName(from mediaSubType: FourCharCode) -> String? {
        guard let subtype = fourCharacterCodeString(from: mediaSubType) else {
            return nil
        }

        switch subtype {
        case "avc1":
            return "H.264"
        case "hvc1", "hev1":
            return "HEVC"
        case "apch":
            return "ProRes 422 HQ"
        case "apcn":
            return "ProRes 422"
        case "apcs":
            return "ProRes 422 LT"
        case "apco":
            return "ProRes 422 Proxy"
        case "ap4h":
            return "ProRes 4444"
        case "mp4a":
            return "AAC"
        case "lpcm":
            return "PCM"
        default:
            return subtype
        }
    }

    private nonisolated static func fourCharacterCodeString(from code: FourCharCode) -> String? {
        var bigEndianCode = code.bigEndian
        let bytes = withUnsafeBytes(of: &bigEndianCode) { Array($0) }
        guard bytes.allSatisfy({ byte in
            byte >= 32 && byte <= 126
        }) else {
            return nil
        }

        let string = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return string?.isEmpty == false ? string : nil
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
