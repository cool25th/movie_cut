import AppKit
import AVFoundation
import Combine
import CoreImage
import Foundation
import ImageIO
import MovieCutCore
import Observation
import UniformTypeIdentifiers

enum TimelineScrubPhase: Sendable {
    case began
    case changed
    case ended
}

@MainActor
@Observable
final class EditorViewModel {
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
    /// Minimum allowed timeline clip duration. Internal so TimelineView's drag
    /// trim and this view model's keyboard trim share one constant (Step 5 of
    /// the core-editing repair: single source of truth for the trim minimum).
    static let minimumTimelineClipDuration: TimeInterval = 0.1
    static let timelineZoomStep: Double = 20
    static let minimumTimelineZoom: Double = 20
    static let maximumTimelineZoom: Double = 300
    private static let motionTrackingKeyframeProperties: Set<AnimatableProperty> = [.positionX, .positionY]

    var currentProject: Project
    var canvasSelection: AspectRatio = .landscape16x9
    var selectedClipIds: Set<UUID> = [] {
        didSet {
            loadSelectedClipProcessingState()
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
    /// G-23 canvas crop editor: while true the preview shows the uncropped
    /// source with a crop window (CropCanvasView) instead of the baked-in
    /// cropped composition. Mutually exclusive with the mask editor.
    var isCropEditorActive: Bool = false
    var selectedAssetId: UUID?
    /// Which clip-scoped section tab the inspector shows. Owned by the view
    /// model (not view @State) so the UI test harness can drive it via
    /// `MOVIECUT_UITEST_INSPECTOR_TAB` — each tab renders a different section,
    /// which lets the dhash goldens capture them as distinct editor states.
    var selectedInspectorSubtab: InspectorSubtab = .basic
    var playbackEngine: PlaybackEngine
    /// When true, refreshFromSession skips the per-dispatch composition rebuild.
    /// Used by the parity harness to batch a single rebuild after applying all
    /// scenario gates (otherwise each gate's dispatch spawns a racing
    /// restorePlaybackAfterRebuild task that hangs). Step 6.
    var suppressCompositionRebuild = false
    var exportEngine: ExportEngine
    /// Shared home recent-projects store, configured by AppStageRouter. Keeping
    /// the reference here lets every successful Save/Cmd-S update Home instead
    /// of only the router's open path.
    @ObservationIgnored var recentProjectsStore: RecentProjectsStore?
    var musicLibrary: MusicLibrary
    var transcriptionService: TranscriptionService
    var templateStore: TemplateStore
    var sfxURLResolver: [String: URL]
    var generatedSubtitleSegments: [TranscriptionSegment] = []
    var pendingSubtitleClips: [Clip] = []
    /// Karaoke highlight for generated subtitle clips (G-01 Inc 2): when on,
    /// applied text clips carry `karaokeEnabled` plus the highlight color, and
    /// the shared TextOverlayPixelProcessor progressively recolors words as
    /// playback crosses each word's start time.
    var isKaraokeSubtitlesEnabled = false
    var karaokeHighlightColorHex = "#FFD60A"
    /// Timeline clip the generated/imported subtitles are aligned to (F-13).
    private var subtitleAlignmentClipId: UUID?
    var playheadTime: TimeInterval = 0
    var timelineZoom: Double = 80
    /// Active timeline tool (S9). `.select` by default; `.blade`, `.slip`, `.slide` provide pro modes.
    var timelineTool: EditTool = .select
    /// Timeline navigation context (Inc 2). `.root` for the main timeline or `.compound` when editing inside a compound clip.
    var timelineContext: TimelineContext = .root
    /// J/K/L shuttle state (S9). Direction + repeated-tap count drive speed.
    var shuttleDirection: ShuttleDirection = .stopped
    var shuttleTapCount: Int = 0
    var lastErrorMessage: String?
    var lastStatusMessage: String?
    #if DEBUG || MOVIECUT_HARNESS
    /// Container-staged artifact paths for the headless harness: when a
    /// sandboxed build blocks the final move out of the container, the export
    /// is still intact at the staging path. The harness reads this to report
    /// `container_artifacts=` in its status line. Declared here (not in the
    /// UITestHarness extension) because extensions cannot hold stored
    /// properties; reset at the start of each harness run.
    var containerArtifactPaths: [String] = []
    #endif
    var quickToolProgressMessage: String?
    var isMotionTrackingSelectionActive: Bool = false
    var isMotionTrackingRunning: Bool = false
    var motionTrackingInitialRect: CGRect = CGRect(x: 0.35, y: 0.25, width: 0.30, height: 0.40)
    var motionTrackingResults: [TrackingResult] = []
    var motionTrackingClipId: UUID?
    var recentAnalysisResults: [AnalysisHistoryItem] = []
    // G-25 Inc 9 master loudness meter (spec §7·§11④): MEASURED values from
    // the project's real preview mix, refreshed by measureMasterLoudness().
    var masterLoudness: AudioGraphLoudness.Measurement?
    var isMeasuringMasterLoudness = false
    var masterLoudnessError: String?
    /// Monotonic committed session/mix generation. It advances for every
    /// committed session refresh and every session replacement, even when the
    /// resulting Project value compares equal to the UI's provisional snapshot.
    /// Async meter work captures this value so stale results cannot cross an
    /// edit, undo/redo, or project/session lifetime boundary.
    @ObservationIgnored var masterLoudnessRevision: UInt64 = 0
    /// Latest user intent for the project master preset. Picker events update
    /// this synchronously on MainActor; one worker drains/coalesces them so
    /// rapid selections cannot commit out of order.
    @ObservationIgnored var desiredMasterAudioProcessing: MasterAudioProcessing?
    @ObservationIgnored var masterAudioProcessingMutationGeneration: UInt64 = 0
    @ObservationIgnored var masterAudioProcessingMutationTask: Task<Void, Never>?
    var lastExportURL: URL?
    var exportFormat: String = "mp4"

    @ObservationIgnored @Published var lastAutoSaveDate: Date = .distantPast

    @ObservationIgnored var session: EditorSession
    @ObservationIgnored private let projectStore: ProjectStore
    /// Single owner of compound flattening. Engines receive the same value
    /// snapshot and never compute or cache flattened timelines themselves.
    @ObservationIgnored private let flattenedTimelineCache = FlattenedTimelineCache()
    var clipClipboardPayload: ClipboardPayload?

    private static func makeProjectStore() -> ProjectStore {
        #if DEBUG || MOVIECUT_HARNESS
        if let dir = ProcessInfo.processInfo.environment["MOVIECUT_AUTOSAVE_DIR"], !dir.isEmpty {
            return ProjectStore(autosaveDirectory: URL(fileURLWithPath: dir))
        }
        #endif
        return ProjectStore()
    }

    /// Recomputes compound flattening exactly once for this committed project
    /// state and distributes the identical snapshot to both rendering engines.
    private func refreshFlattenedTimeline(for project: Project) async {
        await flattenedTimelineCache.update(for: project)
        await flattenedTimelineCache.distribute(
            to: [playbackEngine, exportEngine],
            project: project
        )
    }

    /// Diagnostic seam used by integration validation to pin that both real
    /// engines are attached to the exact same snapshot.
    func renderingEnginesHoldIdenticalTimeline() async -> Bool {
        await FlattenedTimelineParity.bothHoldIdentical(
            for: currentProject.id,
            playbackEngine,
            exportEngine
        )
    }

    /// Invalidates any measurement tied to the previous committed mix.
    /// Call this on every EditorSession commit refresh and on every fresh
    /// EditorSession replacement; Project equality is intentionally irrelevant.
    func invalidateMasterLoudnessContext() {
        masterLoudnessRevision &+= 1
        masterLoudness = nil
        masterLoudnessError = nil
    }

    /// Re-bases the serialized master-preset queue on a fresh project session.
    func resetMasterAudioProcessingMutationContext(to processing: MasterAudioProcessing?) {
        masterAudioProcessingMutationGeneration &+= 1
        desiredMasterAudioProcessing = processing
    }

    /// Writes the current project to the crash-recovery autosave off the edit
    /// path (fire-and-forget so edits stay responsive).
    ///
    /// BUG-01: a failed autosave (disk full, permission loss) is SURFACED via
    /// ``autosaveFailureMessage`` instead of being swallowed by `try?` — the
    /// user must know crash recovery stopped backing their edits up. Still
    /// non-blocking: editing continues, and the warning clears on the next
    /// successful autosave.
    private func scheduleAutosave() {
        let snapshot = currentProject
        Task { [projectStore, weak self] in
            do {
                try await projectStore.saveAutosave(snapshot)
                self?.autosaveSaveSucceeded()
            } catch {
                self?.autosaveSaveFailed(FileOperationError.classify(error))
            }
        }
    }

    /// Awaitable autosave flush (used by automation to deterministically persist
    /// recovery state before quitting; same path as the edit-driven autosave).
    func flushAutosave() async {
        do {
            try await projectStore.saveAutosave(currentProject)
            autosaveSaveSucceeded()
        } catch {
            autosaveSaveFailed(FileOperationError.classify(error))
        }
    }

    /// Non-blocking crash-recovery warning. nil while autosaves succeed;
    /// set when the latest autosave failed (shown in the status bar).
    var autosaveFailureMessage: String?
    @ObservationIgnored private var consecutiveAutosaveFailures = 0

    private func autosaveSaveSucceeded() {
        guard autosaveFailureMessage != nil || consecutiveAutosaveFailures > 0 else { return }
        consecutiveAutosaveFailures = 0
        autosaveFailureMessage = nil
    }

    private func autosaveSaveFailed(_ failure: FileOperationError) {
        consecutiveAutosaveFailures += 1
        autosaveFailureMessage = String(
            format: NSLocalizedString(
                "Autosave failed: %@. Changes are not being backed up for crash recovery — check free disk space.",
                comment: "Warning shown when the crash-recovery autosave cannot be written"
            ),
            failure.userMessage
        )
    }

    /// A project recovered from a non-clean previous session, if any.
    func recoverableProject() async -> Project? {
        await projectStore.loadAutosaveIfAvailable()
    }

    /// The reason a recovery file existed but could not be loaded (corrupt),
    /// if the last `recoverableProject()` call hit that case. The launch flow
    /// surfaces this so the user is told their recovery file was damaged
    /// instead of the previous silent `try?` swallow.
    func autosaveLoadFailure() async -> FileOperationError? {
        await projectStore.lastAutosaveLoadFailure
    }

    /// Removes the crash-recovery autosave (clean quit or after a manual save).
    func clearRecoveryAutosave() async {
        await projectStore.clearAutosave()
    }
    private var currentProjectURL: URL?
    /// Whether the current project has unsaved changes. Observed so the UI can
    /// reflect the dirty state (e.g. window title dot) and guard destructive
    /// session replacements (new/open/close) until the user confirms.
    private(set) var isDirty = false
    /// Snapshot of the project as last saved (or loaded). Used to recompute
    /// isDirty after undo/redo so that returning to the saved state clears the
    /// dirty flag — a plain boolean set on every mutation would stay true even
    /// after undoing back to the on-disk bytes.
    @ObservationIgnored private var lastSavedProject: Project?
    @ObservationIgnored private var isAutoSaveRunning = false
    private var isSavingCurrentProject = false
    /// Waveform bins per clip, populated lazily off the main thread. Observed
    /// (not ignored) so that filling a cache miss after a background decode
    /// triggers the timeline canvas to redraw with real samples.
    private var waveformCache: [UUID: [CGFloat]] = [:]
    /// Clip IDs whose waveform is currently decoding in the background, to
    /// avoid scheduling redundant decodes for the same miss.
    @ObservationIgnored private var waveformInFlight: Set<UUID> = []
    @ObservationIgnored private var clipEQPresets: [UUID: String] = [:]
    @ObservationIgnored private var noiseReductionClipIds: Set<UUID> = []
    @ObservationIgnored private var backgroundRemovedClipIds: Set<UUID> = []
    @ObservationIgnored private var clipStyles: [UUID: String] = [:]
    @ObservationIgnored private var motionTrackingAppliedKeyframeCounts: [UUID: Int] = [:]
    @ObservationIgnored var pendingScrubTask: Task<Void, Never>?
    @ObservationIgnored var pendingScrubTime: TimeInterval?

    /// - Parameter autosaveDirectory: test seam — routes the crash-recovery
    ///   autosave to an explicit directory (e.g. a read-only path to exercise
    ///   the BUG-01 failure surfacing). nil uses the production location.
    init(project: Project? = nil, autosaveDirectory: URL? = nil) {
        self.projectStore = autosaveDirectory.map { ProjectStore(autosaveDirectory: $0) }
            ?? EditorViewModel.makeProjectStore()
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

        // Bind the initial project to the single flatten cache. Subsequent
        // committed mutations refresh synchronously in refreshFromSession().
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshFlattenedTimeline(for: project)
        }
    }

    var projectDisplayName: String {
        let trimmedName = currentProject.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled" : trimmedName
    }

    var projectSaveStatusLabel: String {
        if isSavingCurrentProject {
            return "Saving…"
        }

        if currentProjectURL != nil {
            return "Saved"
        }

        return "Autosave on"
    }

    var projectSaveStatusSystemImage: String {
        if isSavingCurrentProject {
            return "arrow.triangle.2.circlepath"
        }

        if currentProjectURL != nil {
            return "checkmark.circle"
        }

        return "arrow.clockwise.circle"
    }

    var canvasAspectBadgeText: String {
        let canvas = currentProject.canvas
        return canvas.aspectRatio.shortDisplayName(forSize: canvas.size)
    }

    var exportResolutionBadgeText: String {
        let renderSize = ExportPlanner().renderSize(
            for: currentProject.exportSettings.resolution,
            canvas: currentProject.canvas
        )
        return "\(Self.pixelDimensionText(renderSize.width))×\(Self.pixelDimensionText(renderSize.height))"
    }

    var canvasResolutionBadgeText: String {
        "\(canvasAspectBadgeText) · \(exportResolutionBadgeText)"
    }

    private static func pixelDimensionText(_ value: CGFloat) -> String {
        "\(max(Int(value.rounded()), 1))"
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

    /// Pixel aspect (width/height) of the selected clip's source media, used
    /// by the crop presets so a "9:16" preset selects a region that is 9:16 in
    /// source pixels. Falls back to 16:9 when metadata is missing.
    var selectedClipSourceAspect: Double? {
        guard let width = selectedClipSourceAsset?.metadata.width,
              let height = selectedClipSourceAsset?.metadata.height,
              width > 0, height > 0 else {
            return nil
        }
        return Double(width) / Double(height)
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

    var canTrackMotionSelection: Bool {
        selectedClip?.kind == .video && selectedClipSourceAsset?.kind == .video
    }

    var selectedClipMotionTrackingKeyframeCount: Int {
        guard let clip = selectedClip,
              motionTrackingClipId == clip.id || motionTrackingAppliedKeyframeCounts[clip.id] != nil
        else {
            return 0
        }

        return clip.keyframes.filter { Self.motionTrackingKeyframeProperties.contains($0.property) }.count
    }

    var motionTrackingOverlayRect: CGRect? {
        guard let clip = selectedClip, motionTrackingClipId == clip.id else {
            return nil
        }

        if let currentRect = currentMotionTrackingResultRect(for: clip) {
            return currentRect
        }

        if isMotionTrackingSelectionActive || isMotionTrackingRunning {
            return motionTrackingInitialRect
        }

        return nil
    }

    var isMotionTrackingOverlayEditable: Bool {
        isMotionTrackingSelectionActive && !isMotionTrackingRunning
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

    /// Returns cached waveform bins for a clip, or an empty array when the
    /// waveform has not been decoded yet. This is a **pure read** — it never
    /// writes to `waveformCache` and never schedules a decode, so it is safe to
    /// call during a SwiftUI `body` evaluation without the "modifying state
    /// during view update" anti-pattern. A miss is resolved by
    /// ``requestWaveformDecode(for:)``, which the view invokes from a lifecycle
    /// modifier (`.task`), not from body.
    ///
    /// Because `waveformCache` is observed (not `@ObservationIgnored`), reading
    /// it in body registers the observation dependency, so the canvas redraws
    /// once the background decode writes the real bins.
    func waveform(for clip: Clip) -> [CGFloat] {
        waveformCache[clip.id] ?? []
    }

    /// Triggers a background waveform decode for a clip if one has not already
    /// been requested. Intended to be called from a SwiftUI lifecycle modifier
    /// (`.task` / `.onAppear`), NOT from `body` evaluation, so the cache writes
    /// it performs (the in-flight mark and the eventual decoded-bin write) never
    /// happen during a view update.
    func requestWaveformDecode(for clip: Clip) {
        guard clip.kind == .video || clip.kind == .audio,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId],
              asset.kind == .video || asset.kind == .audio
        else {
            // Not a decodable media kind: record the negative result so the
            // view stops requesting. Written here (outside body), not in
            // waveform(for:).
            if waveformCache[clip.id] == nil { waveformCache[clip.id] = [] }
            return
        }
        startWaveformDecode(for: clip.id, asset: asset)
    }

    /// Invalidates the cached waveform for a clip and re-requests a decode for
    /// its current asset. Called when the clip's source asset changes (e.g.
    /// after noise reduction via `SetClipSourceAssetCommand`): the clip id is
    /// unchanged, so the view's `.task(id:)` — which now keys on
    /// `WaveformRequestKey(clip:)`, including the asset — would re-run anyway,
    /// but having the asset-swap site re-request directly is more robust than
    /// relying on the view to notice. Performs all writes outside body.
    func invalidateWaveform(for clip: Clip) {
        waveformCache.removeValue(forKey: clip.id)
        waveformInFlight.remove(clip.id)
        requestWaveformDecode(for: clip)
    }

    /// Cancels any in-flight decode for a clip without touching the cache.
    /// Test/inspection helper.
    func cancelWaveformDecode(forClip clipId: UUID) {
        waveformInFlight.remove(clipId)
    }

    /// Whether a decode is currently in flight (queued/running) for a clip.
    /// Test/inspection helper.
    func isWaveformDecodeRequested(forClip clipId: UUID) -> Bool {
        waveformInFlight.contains(clipId)
    }

    /// Schedules exactly one background waveform decode per clip id while a
    /// decode for that clip is already in flight.
    private func startWaveformDecode(for clipId: UUID, asset: MediaAsset) {
        guard !waveformInFlight.contains(clipId) else { return }
        waveformInFlight.insert(clipId)

        Task { @MainActor [weak self] in
            let waveformData = await WaveformGenerator.generateAsync(for: asset)
            guard let self else { return }
            // The asset may have been swapped out while decoding; only commit
            // if this clip is still in flight for this decode.
            guard self.waveformInFlight.remove(clipId) != nil else { return }
            self.waveformCache[clipId] = waveformData?.samples.map { CGFloat($0) } ?? []
        }
    }


    var canGenerateSubtitles: Bool {
        if selectedClipId != nil {
            return selectedTranscribableClipAndAsset != nil
        }

        guard let selectedAsset else { return false }
        return Self.isTranscribable(selectedAsset)
    }

    var isCardEditorMode: Bool {
        currentProject.cardDocument != nil
    }

    /// Applies a complete template set through one Core command. The gallery
    /// and DEBUG actual-app harness share this entry point.
    @discardableResult
    func applyCardTemplate(_ template: CardTemplateSet) async -> Bool {
        await applyCardTemplate(template, seed: UInt64.random(in: UInt64.min...UInt64.max))
    }

    /// Seeded overload used by deterministic actual-app evidence.
    @discardableResult
    func applyCardTemplate(_ template: CardTemplateSet, seed: UInt64) async -> Bool {
        await dispatchCardMutation(
            ApplyCardTemplateCommand(template: template, seed: seed),
            successMessage: "Applied \(template.name)."
        )
    }

    /// Applies one document-wide master style through one Core command while
    /// retaining page-local overrides.
    @discardableResult
    func setCardMasterStyle(_ masterStyle: CardMasterStyle) async -> Bool {
        await dispatchCardMutation(
            SetCardMasterStyleCommand(masterStyle: masterStyle),
            successMessage: "Updated the card master style."
        )
    }

    /// Adds a blank body page after the selected page, or at the end when no
    /// selection is supplied. The returned identifier is the persisted page ID.
    @discardableResult
    func addCardPage(after pageId: UUID?, pageID: UUID = UUID()) async -> UUID? {
        let snapshot = await session.snapshot()
        guard let document = snapshot.cardDocument else {
            lastErrorMessage = "This project does not contain a card document."
            return nil
        }

        let insertionIndex: Int
        if let pageId {
            guard let sourceIndex = document.pages.firstIndex(where: { $0.id == pageId }) else {
                lastErrorMessage = "The selected card page no longer exists."
                return nil
            }
            insertionIndex = sourceIndex + 1
        } else {
            insertionIndex = document.pages.endIndex
        }

        let page = CardPage(id: pageID, role: .body)
        let didApply = await dispatchCardMutation(
            AddCardPageCommand(page: page, insertionIndex: insertionIndex),
            successMessage: "Added page \(insertionIndex + 1)."
        )
        return didApply ? page.id : nil
    }

    /// Duplicates a page through the Core command layer and returns the fresh,
    /// stable identifier selected by the command.
    @discardableResult
    func duplicateCardPage(_ pageId: UUID, duplicatePageID: UUID = UUID()) async -> UUID? {
        let didApply = await dispatchCardMutation(
            DuplicateCardPageCommand(pageId: pageId, duplicatePageId: duplicatePageID),
            successMessage: "Duplicated the selected page."
        )
        return didApply ? duplicatePageID : nil
    }

    /// Deletes a page and returns the adjacent surviving page that the UI should
    /// select. The final page remains protected by the Core command invariant.
    @discardableResult
    func deleteCardPage(_ pageId: UUID) async -> UUID? {
        let snapshot = await session.snapshot()
        guard let pages = snapshot.cardDocument?.pages,
              let deletedIndex = pages.firstIndex(where: { $0.id == pageId }) else {
            lastErrorMessage = "The selected card page no longer exists."
            return nil
        }

        let didApply = await dispatchCardMutation(
            DeleteCardPageCommand(pageId: pageId),
            successMessage: "Deleted page \(deletedIndex + 1)."
        )
        guard didApply, let remainingPages = currentProject.cardDocument?.pages, !remainingPages.isEmpty else {
            return nil
        }
        return remainingPages[min(deletedIndex, remainingPages.count - 1)].id
    }

    /// Reorders a page to its final array index. Drag/drop and accessible move
    /// controls intentionally share this single command-backed entry point.
    @discardableResult
    func moveCardPage(_ pageId: UUID, to destinationIndex: Int) async -> Bool {
        let snapshot = await session.snapshot()
        guard let pages = snapshot.cardDocument?.pages,
              let sourceIndex = pages.firstIndex(where: { $0.id == pageId }) else {
            lastErrorMessage = "The selected card page no longer exists."
            return false
        }
        guard sourceIndex != destinationIndex else { return true }

        return await dispatchCardMutation(
            MoveCardPageCommand(pageId: pageId, destinationIndex: destinationIndex),
            successMessage: "Moved page to position \(destinationIndex + 1)."
        )
    }

    /// Changes the card aspect preset while leaving normalized element frames
    /// and all stable page/element identifiers untouched.
    @discardableResult
    func setCardFormat(_ format: CardFormat) async -> Bool {
        let snapshot = await session.snapshot()
        guard let document = snapshot.cardDocument else {
            lastErrorMessage = "This project does not contain a card document."
            return false
        }
        guard document.format != format else { return true }

        return await dispatchCardMutation(
            SetCardFormatCommand(format: format),
            successMessage: "Changed card format to \(format.accessibilityTitle)."
        )
    }

    /// Commits one completed card-canvas interaction. Gesture ticks and inline
    /// IME composition stay local to CardCanvasView; callers invoke this only at
    /// move/resize/edit completion so the session records exactly one snapshot.
    @discardableResult
    func updateCardElement(pageId: UUID, element: CardElement) async -> Bool {
        await dispatchCardMutation(
            UpdateCardElementCommand(
                pageId: pageId,
                elementId: element.id,
                element: element
            ),
            successMessage: "Updated card element \(element.id.uuidString)."
        )
    }

    /// Imports or reuses an image and updates the selected image/logo element in
    /// one Core command. Non-image inputs fail before any project mutation.
    @discardableResult
    func replaceCardElementImage(
        pageId: UUID,
        elementId: UUID,
        with url: URL
    ) async -> Bool {
        let probedAsset: MediaAsset
        do {
            probedAsset = try await mediaAssetWithAppProbe(for: url)
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
        }
        guard probedAsset.kind == .image else {
            lastStatusMessage = nil
            lastErrorMessage = "Card image replacement requires an image file."
            return false
        }

        let replacementAsset = currentProject.mediaLibrary.assets.values.first {
            $0.kind == .image && $0.originalURL.standardizedFileURL == url.standardizedFileURL
        } ?? probedAsset

        let didApply = await dispatchCardMutation(
            ReplaceCardElementImageCommand(
                pageId: pageId,
                elementId: elementId,
                asset: replacementAsset
            ),
            successMessage: "Replaced the selected card image with \(url.lastPathComponent)."
        )
        if didApply {
            selectedAssetId = replacementAsset.id
        }
        return didApply
    }

    @discardableResult
    func newProject() async -> Bool {
        guard await confirmDiscardUnsavedChanges() else { return false }
        let project = Self.defaultProject()
        session = EditorSession(project: project)
        currentProject = project
        invalidateMasterLoudnessContext()
        resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)
        await refreshFlattenedTimeline(for: project)
        currentProjectURL = nil
        canvasSelection = project.canvas.aspectRatio
        syncExportUI(from: project.exportSettings)
        selectedClipId = nil
        selectedAssetId = nil
        isMaskEditorActive = false
        isCropEditorActive = false
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        recentAnalysisResults = []
        lastErrorMessage = nil
        lastStatusMessage = nil
        lastExportURL = nil
        // A brand-new project is its own clean baseline.
        lastSavedProject = project
        isDirty = false
        return true
    }

    func openProject(from url: URL) async {
        guard await confirmDiscardUnsavedChanges() else { return }
        do {
            // Signpost covers decode + migrate + validate + session swap — the
            // SLO doc's "10-minute project opens in <=3s" probe direction.
            try await AppLog.time(.importLog, "import.openProject") {
                let loadedProject = try await projectStore.load(from: url)
                let project = Self.ensureDefaultTracks(in: loadedProject)
                session = EditorSession(project: project)
                currentProject = project
                invalidateMasterLoudnessContext()
                resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)
                await refreshFlattenedTimeline(for: project)
                currentProjectURL = url
                canvasSelection = project.canvas.aspectRatio
                syncExportUI(from: project.exportSettings)
                selectedClipId = nil
                selectedAssetId = nil
                isMaskEditorActive = false
                isCropEditorActive = false
                playbackEngine.clear()
                playheadTime = 0
                clearGeneratedSubtitles()
                clearClipProcessingState()
                recentAnalysisResults = []
                lastErrorMessage = nil
                lastStatusMessage = nil
                lastExportURL = nil
                // The loaded file is the clean baseline.
                lastSavedProject = project
                isDirty = false
                // Under App Sandbox, media imported before bookmarks existed (or
                // whose files moved) can't be re-reached. Surface a relocate hint
                // instead of failing silently on the next playback/export. (S2)
                reportMediaNeedingRelocation(in: project)
            }
        } catch {
            AppLog.importLog.error("project load failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            lastStatusMessage = nil
        }
    }

    /// Scans the project's assets for ones that no longer resolve and reports
    /// how many need re-linking. Unlike the previous behavior (which only told
    /// the user to re-import, creating a new asset UUID and breaking clip
    /// references), the missing assets are now also surfaced via
    /// ``missingMediaAssets`` so the UI can offer a re-link action that
    /// preserves the asset UUID (see ``relinkMedia(_:to:)``).
    private func reportMediaNeedingRelocation(in project: Project) {
        evaluateMissingMedia(in: project)
        if !missingMediaAssets.isEmpty {
            lastStatusMessage = """
            \(missingMediaAssets.count) media file(s) can’t be found. \
            Use “Re-link Missing Media” to locate them.
            """
        }
    }


    /// Assets in the current project whose source files can't be found. Drives
    /// the re-link UI; populated by `reportMediaNeedingRelocation`.
    @ObservationIgnored private(set) var missingMediaAssets: [MediaAsset] = []

    /// Re-links a missing media asset to a new file location, preserving the
    /// asset's UUID so existing clips keep their references.
    ///
    /// The previous workaround was "re-import," which created a brand-new asset
    /// (new UUID) and silently orphaned every clip still pointing at the old
    /// asset. This instead re-probes the new URL for fresh metadata + a fresh
    /// security-scoped bookmark, then updates the asset in place via
    /// `UpdateMediaAssetCommand` so undo works and the asset id is stable.
    @discardableResult
    func relinkMedia(_ asset: MediaAsset, to newURL: URL) async -> Bool {
        do {
            // Re-probe the new location for current metadata + bookmark, but
            // KEEP the original asset's UUID and id so clip references survive.
            var relocated = try MediaImporter.validatedProbe(url: newURL)
            relocated.id = asset.id
            relocated.originalBookmark = SecurityScopedAccess.makeBookmark(for: newURL)
            let probe = await Self.appMetadataProbe(
                for: newURL,
                kind: relocated.kind,
                baseMetadata: relocated.metadata
            )
            relocated.duration = probe.duration ?? relocated.duration
            relocated.metadata = probe.metadata
            try await session.dispatch(UpdateMediaAssetCommand(asset: relocated))
            try await refreshFromSession()
            // Re-evaluate missing media now that one asset is reachable again.
            let snapshot = await session.snapshot()
            reportMediaNeedingRelocation(in: snapshot)
            if missingMediaAssets.isEmpty {
                lastStatusMessage = "All media files are linked."
            }
            lastErrorMessage = nil
            return true
        } catch {
            lastErrorMessage = FileOperationError.classify(error).userMessage
            return false
        }
    }

    /// Presents an `NSOpenPanel` for each missing media asset so the user can
    /// relocate it in place. Walks the current `missingMediaAssets` list; the
    /// user can cancel any single file (it stays missing) or cancel the whole
    /// pass (remaining files stay missing). Each successful pick preserves the
    /// asset UUID via ``relinkMedia(_:to:)``.
    @MainActor

    func saveProject(to url: URL) async {
        do {
            let snapshot = await session.snapshot()
            try await projectStore.save(snapshot, to: url)
            currentProjectURL = url
            lastErrorMessage = nil
            // Record the saved bytes so undo/redo back to this state clears
            // the dirty flag.
            lastSavedProject = snapshot
            isDirty = false
            // A successful manual save is now the durable baseline; retaining
            // crash recovery would incorrectly offer stale unsaved work later.
            await projectStore.clearAutosave()
            if let recentProjectsStore {
                await recordCurrentProjectToRecent(recentProjectsStore, savedTo: url)
            }
        } catch {
            // Classify the failure so the user gets an actionable message
            // (e.g. "disk is out of space") instead of a raw Foundation string.
            lastErrorMessage = FileOperationError.classify(error).userMessage
        }
    }

    /// Loads a crash-recovered in-memory project into a fresh session.
    func adoptRecoveredProject(_ recovered: Project) async {
        let project = Self.ensureDefaultTracks(in: recovered)
        session = EditorSession(project: project)
        currentProject = project
        invalidateMasterLoudnessContext()
        resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)
        await refreshFlattenedTimeline(for: project)
        currentProjectURL = nil
        canvasSelection = project.canvas.aspectRatio
        syncExportUI(from: project.exportSettings)
        selectedClipId = nil
        selectedAssetId = nil
        isMaskEditorActive = false
        isCropEditorActive = false
        playbackEngine.clear()
        playheadTime = 0
        clearGeneratedSubtitles()
        clearClipProcessingState()
        recentAnalysisResults = []
        lastErrorMessage = nil
        lastStatusMessage = "Recovered unsaved work."
        lastExportURL = nil
        // Recovered work was never saved: no clean baseline, so it is dirty.
        lastSavedProject = nil
        isDirty = true
    }

    // MARK: - Project package (F-23)


    /// Imports a `.mctemplate` package as the current project, resolving its
    /// bundled media. The user can then replace media via normal import.
    func importProjectPackage() async {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if let type = UTType(filenameExtension: ProjectPackage.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard await confirmDiscardUnsavedChanges() else { return }

        do {
            let project = try ProjectPackage.load(from: url)
            session = EditorSession(project: project)
            currentProject = project
            invalidateMasterLoudnessContext()
            resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)
            currentProjectURL = nil
            canvasSelection = project.canvas.aspectRatio
            syncExportUI(from: project.exportSettings)
            selectedClipId = nil
            selectedAssetId = nil
            playbackEngine.clear()
            playheadTime = 0
            clearGeneratedSubtitles()
            clearClipProcessingState()
            recentAnalysisResults = []
            lastExportURL = nil
            lastErrorMessage = nil
            lastStatusMessage = "Imported \(url.lastPathComponent). Replace any missing media via the library."
            // The imported package is the clean baseline for this session.
            lastSavedProject = project
            isDirty = false
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = "Could not import package: \(error.localizedDescription)"
        }
    }

    func saveProject() async {
        // Deterministic path injection for the ungated home relaunch XCUITest.
        // This does not enable MOVIECUT_UITEST or alter app routing; it only
        // replaces NSSavePanel so the test can exercise the real save/store path.
        if let injectedPath = ProcessInfo.processInfo.environment["MOVIECUT_UITEST_HOME_SAVE_PATH"],
           !injectedPath.isEmpty {
            await saveProject(to: URL(filePath: injectedPath))
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "moviecut") ?? .json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).moviecut"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        await saveProject(to: url)
    }

    /// Guards session-replacing operations (new/open/import/template/cloud)
    /// when there are unsaved changes. Returns true to proceed; false to cancel.
    ///
    /// All branching decisions live in `UnsavedChangesPolicy` (pure, unit-tested
    /// in Core). This method is only the AppKit presentation layer: it obtains a
    /// user choice (from an `NSAlert`, or injected by a test harness), performs
    /// the save the policy asks for, then maps the policy's decision to a bool.
    ///
    /// The "a failed save never discards work" rule is enforced by the policy's
    /// `resolveAfterSave`, not by this method.
    ///
    /// Harness coverage: historically the guard was skipped wholesale under
    /// `MOVIECUT_UITEST=1`, so the UI test harness could never reach it. The
    /// `MOVIECUT_UITEST_UNSAVED_RESPONSE=save|discard|cancel` gate instead
    /// *injects* a choice, driving the real guard (and real save) path so the
    /// three branches are exercisable by XCUITest without an Accessibility
    /// permission dependency.
    func confirmDiscardUnsavedChanges() async -> Bool {
        guard isDirty else { return true }

        let env = ProcessInfo.processInfo.environment

        // Injected choice: run the real guard + save path for any of the three
        // branches. Falls through to the live alert only when no choice is
        // injected, so ordinary test runs are unaffected.
        if let raw = env["MOVIECUT_UITEST_UNSAVED_RESPONSE"],
           let choice = UnsavedChangesUserChoice(rawValue: raw) {
            return await applyUnsavedChoice(choice)
        }

        // Other automation contexts (import/export E2E, bootstrap) never expect
        // a modal: keep the prior bypass so they are not blocked.
        if env["MOVIECUT_UITEST"] == "1" || env["MOVIECUT_BOOTSTRAP_PROJECT"] != nil {
            return true
        }

        return await applyUnsavedChoice(presentUnsavedChangesAlert())
    }

    /// Maps a user choice through the policy, performing any save it requests,
    /// and returns whether the caller may proceed. Shared by the live alert path
    /// and the injected harness path so both run the identical decision logic.
    private func applyUnsavedChoice(_ choice: UnsavedChangesUserChoice) async -> Bool {
        let decision = UnsavedChangesPolicy.decide(
            isDirty: isDirty,
            userChoice: choice,
            hasSaveURL: currentProjectURL != nil
        )

        switch decision {
        case .proceed:
            return true
        case .cancel:
            return false
        case .needsSave:
            // Existing save URL: save in place, then resolve.
            guard let url = currentProjectURL else { return false }
            await saveProject(to: url)
            let resolved = UnsavedChangesPolicy.resolveAfterSave(decision, didSaveSucceed: lastErrorMessage == nil)
            return resolved == .proceed
        case .needsSaveAs:
            // No save URL yet: present Save As, then save and resolve.
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "moviecut") ?? .json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(currentProject.name).moviecut"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            await saveProject(to: url)
            let resolved = UnsavedChangesPolicy.resolveAfterSave(decision, didSaveSucceed: lastErrorMessage == nil)
            return resolved == .proceed
        }
    }

    /// Presents the Save / Don't Save / Cancel alert and returns the user's
    /// choice as a policy input. Cancel is the default for an unknown response
    /// (e.g. closing the alert), preserving work.
    private func presentUnsavedChangesAlert() -> UnsavedChangesUserChoice {
        let alert = NSAlert()
        alert.messageText = "Save changes to \"\(currentProject.name)\"?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    /// Used by the termination guard to save before quitting. Returns whether
    /// the project was saved successfully (or there was nothing to save), so a
    /// failed save cancels termination instead of discarding work.
    @discardableResult
    func terminateAfterSaving() async -> Bool {
        if currentProjectURL == nil {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "moviecut") ?? .json]
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "\(currentProject.name).moviecut"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            await saveProject(to: url)
        } else {
            await saveProject(to: currentProjectURL!)
        }
        return lastErrorMessage == nil
    }

    // MARK: - Periodic project autosave (named-file durability)
    //
    // This 30s timer writes the current project to a NAMED file
    // (Application Support/MovieCut/Autosave/<name>-<uuid>.moviecut) every 30s
    // so a long unsaved session is durable on disk. It is DISTINCT from the
    // crash-recovery path in ProjectStore (recovery.moviecut, written on every
    // edit via scheduleAutosave): that one is a single rolling recovery
    // snapshot offered on next launch; this one is a per-project durable copy.
    // Both paths go through ProjectStore.save, so both now surface classified
    // FileOperationError messages (e.g. disk-full) instead of raw strings.
    // The harness calls stopAutoSave() to make export/reload deterministic.

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
                lastErrorMessage = FileOperationError.classify(error).userMessage
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

    /// BUG-04 (CA-03 audit): export/package pre-flight. Missing-media
    /// detection and the relink prompt only run at project OPEN — a disk
    /// ejected mid-session used to fail the export minutes into the render.
    /// Re-evaluate reachability NOW and refuse explicitly with relink
    /// guidance before any render work starts.
    func ensureAllMediaReachableForExport() -> Bool {
        evaluateMissingMedia(in: currentProject)
        guard !missingMediaAssets.isEmpty else { return true }
        lastExportURL = nil
        lastStatusMessage = nil
        lastErrorMessage = String(
            format: NSLocalizedString(
                "Can't export: %d media file(s) can't be found. Use “Re-link Missing Media” to locate them, then export again.",
                comment: "Export pre-flight refusal when source media is unreachable"
            ),
            missingMediaAssets.count
        )
        return false
    }

    func exportProject() async {
        guard ensureAllMediaReachableForExport() else { return }
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

        await exportProject(to: url)
    }

    /// Exports to an explicit URL using the same engine path as `exportProject()`
    /// but without the save panel. Used by automation and the XCUITest harness so
    /// the real export pipeline is exercised end-to-end.
    func exportProject(to url: URL) async {
        guard ensureAllMediaReachableForExport() else { return }
        let reconciledSettings = reconciledExportSettingsFromLegacyUI()
        if currentProject.exportSettings != reconciledSettings {
            await apply(SetProjectExportSettingsCommand(exportSettings: reconciledSettings))
            guard lastErrorMessage == nil else { return }
        }

        let settings = currentProject.exportSettings
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

    /// Exports the project to a movie with an explicit average video bitrate via
    /// the planner-backed `AVAssetWriter` path, instead of the preset approximation.
    func exportWithExplicitBitrate() async {
        guard ensureAllMediaReachableForExport() else { return }
        let reconciledSettings = reconciledExportSettingsFromLegacyUI()
        if currentProject.exportSettings != reconciledSettings {
            await apply(SetProjectExportSettingsCommand(exportSettings: reconciledSettings))
            guard lastErrorMessage == nil else { return }
        }

        let settings = currentProject.exportSettings
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).\(settings.containerFormat.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportVideoWithExplicitBitrate(
                project: snapshot,
                to: url,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Exports a ProRes 422 master in a QuickTime container.
    func exportProResMaster() async {
        guard ensureAllMediaReachableForExport() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name)-prores.mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await exportProResMaster(to: url)
    }

    /// Exports a ProRes 422 master to an explicit URL (no save panel). Used by
    /// automation and the harness.
    func exportProResMaster(to url: URL) async {
        guard ensureAllMediaReachableForExport() else { return }
        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportVideoWithExplicitBitrate(
                project: snapshot,
                to: url,
                profileOverride: .proRes422,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Exports a 10-bit HDR master (HEVC Main 10, Rec. 2020 + HLG). CapCut has no
    /// HDR delivery; this is a Pro mastering output.
    func exportHDRMaster() async {
        guard FeatureFlag.hdrMaster else {
            lastErrorMessage = "HDR mastering is not available in this build."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name)-hdr.mov"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await exportHDRMaster(to: url)
    }

    /// Exports an HDR master to an explicit URL (no save panel). Used by
    /// automation and the harness.
    func exportHDRMaster(to url: URL) async {
        // Belt-and-suspenders: even if a harness or internal caller invokes
        // this directly (bypassing the menu), refuse when the flag is off. The
        // v1 render pipeline is 8-bit SDR, so an HDR export would re-tag
        // 8-bit pixels as HDR — the output would lie about its own depth.
        guard FeatureFlag.hdrMaster else {
            lastErrorMessage = "HDR mastering is not available in this build."
            return
        }
        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportVideoWithExplicitBitrate(
                project: snapshot,
                to: url,
                profileOverride: .hevcHDR,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Exports the project's mixed audio as a standalone `.m4a` file.
    func exportAudioOnly() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m4a") ?? .audio]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).m4a"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        await exportAudioOnly(to: url)
    }

    /// Exports mixed project audio to an explicit URL without presenting a save
    /// panel. Used by automation to verify audio-only outputs headlessly.
    func exportAudioOnly(to url: URL) async {
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportAudioOnly(
                project: snapshot,
                to: url,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Exports an animated GIF rendered from the timeline.
    func exportAnimatedGIF() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name).gif"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportAnimatedGIF(
                project: snapshot,
                to: url,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Renders the frame at the playhead to a PNG still image.
    func exportStillFrame() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(currentProject.name)-frame.png"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        exportEngine.backgroundRemovedClipIds = backgroundRemovedClipIds
        lastExportURL = nil
        do {
            let snapshot = await session.snapshot()
            lastExportURL = try await exportEngine.exportStillFrame(
                project: snapshot,
                at: playheadTime,
                to: url,
                audioProcessing: buildAudioProcessingOptions()
            )
            lastErrorMessage = nil
        } catch {
            lastExportURL = nil
            lastErrorMessage = error.localizedDescription
        }
    }


    func importMedia(_ urls: [URL]) async {
        guard !urls.isEmpty else {
            reportInvalidMediaLibraryDrop()
            return
        }

        do {
            for url in urls {
                let asset = try await mediaAssetWithAppProbe(for: url)
                try await session.dispatch(ImportMediaCommand(asset: asset))
                selectedAssetId = asset.id
                // CA-22: kick off background proxy generation for video
                // imports when the user hasn't disabled it and thermal state
                // permits. Fire-and-forget — the import returns immediately.
                scheduleAutoProxyGeneration(for: asset)
            }
            try await refreshFromSession()
            reportMediaLibraryDropSuccess(count: urls.count)
        } catch {
            setDropError(error.localizedDescription)
        }
    }

    /// CA-22 2차: imported video assets that still have no proxy — drives the
    /// inspector's "Generate missing proxies" (resume) affordance.
    var videoAssetsMissingProxy: Int {
        currentProject.mediaLibrary.assets.values
            .filter { $0.kind == .video && $0.proxy == nil }
            .count
    }

    /// CA-22: tracked in-flight proxy generation tasks (auto + resume). The
    /// handles back the cancel control; the key set doubles as the
    /// duplicate-work guard.
    @ObservationIgnored
    private var proxyGenerationTasks: [UUID: Task<Void, Never>] = [:]

    /// CA-22: assets with a proxy generation currently in flight. Observable
    /// so the inspector's Playback section can show progress and Cancel.
    private(set) var autoProxyGenerating: Set<UUID> = []

    /// CA-22 2차: generations ended by cancellation since the last status
    /// read — distinguishes "user cancelled" from "failed" in UI and tests.
    /// Plain var (not private(set)) so the Media extension's catch can bump it.
    var autoProxyCancelledCount = 0

    /// CA-22 2차: cancels every in-flight proxy generation. Partial proxy
    /// files are removed by the generator's cancellation path, so a later
    /// resume starts clean rather than adopting a truncated file.
    func cancelAutoProxyGeneration() {
        for task in proxyGenerationTasks.values {
            task.cancel()
        }
        if !autoProxyGenerating.isEmpty {
            lastErrorMessage = nil
            lastStatusMessage = "Proxy generation cancelled."
        }
    }

    /// CA-22 2차: resume entry — generates proxies for every video asset that
    /// does not have one yet. Covers both a prior cancel and the thermal-skip
    /// path from auto generation; explicit user action, so it does not consult
    /// the auto-on-import setting (only the thermal gate, matching manual
    /// per-asset generation).
    func resumeMissingProxies() async {
        // Await any in-flight (or cancelling) generations first so a
        // cancel→resume sequence doesn't skip the asset that is still winding
        // down — without this the filter below would race the cancelled task.
        for task in proxyGenerationTasks.values {
            await task.value
        }
        let snapshot = await session.snapshot()
        guard !ThermalState.current.shouldBlockExport else {
            lastErrorMessage = nil
            lastStatusMessage = "Device is hot — try generating proxies again after it cools."
            return
        }
        let missing = snapshot.mediaLibrary.assets.values
            .filter { $0.kind == .video && $0.proxy == nil && !autoProxyGenerating.contains($0.id) }
        guard !missing.isEmpty else {
            lastErrorMessage = nil
            lastStatusMessage = "All video assets already have proxies."
            return
        }
        lastErrorMessage = nil
        lastStatusMessage = "Generating proxies for \(missing.count) video asset(s)..."
        for asset in missing {
            scheduleProxyGeneration(for: asset)
        }
    }

    /// CA-22: schedules a background proxy generation for a newly imported
    /// video asset. Checks the user's `autoGenerateProxyOnImport` setting and
    /// the thermal state (critical → skip); the fire-and-forget Task means
    /// the import flow never blocks on transcoding.
    private func scheduleAutoProxyGeneration(for asset: MediaAsset) {
        // UITest determinism: background transcodes would race the proxy-badge
        // and parity gates (badge flips mid-assert, extra encode load). The
        // CA-22 gate opts back in explicitly; users are unaffected.
        #if DEBUG || MOVIECUT_HARNESS
        if ProcessInfo.processInfo.environment["MOVIECUT_UITEST"] == "1",
           ProcessInfo.processInfo.environment["MOVIECUT_UITEST_AUTO_PROXY"] != "1" {
            return
        }
        #endif
        guard currentProject.playbackSettings.autoGenerateProxyOnImport else { return }
        scheduleProxyGeneration(for: asset)
    }

    /// Shared scheduler for the auto (import) and resume (explicit) paths.
    /// Both go through the tracked-task path so Cancel covers everything.
    private func scheduleProxyGeneration(for asset: MediaAsset) {
        guard asset.kind == .video,
              asset.proxy == nil,
              !autoProxyGenerating.contains(asset.id)
        else { return }

        // Critical thermal: generating a proxy now risks a thermal shutdown
        // mid-encode. The user can still generate manually after cooling
        // (resumeMissingProxies surfaces that path).
        guard !ThermalState.current.shouldBlockExport else { return }

        autoProxyGenerating.insert(asset.id)
        let assetId = asset.id
        proxyGenerationTasks[assetId] = Task { [weak self] in
            await self?.generateProxy(for: assetId)
            await MainActor.run {
                self?.autoProxyGenerating.remove(assetId)
                self?.proxyGenerationTasks[assetId] = nil
            }
        }
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
                let asset = try await mediaAssetWithAppProbe(for: url)
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
                // CA-22 2차: timeline import is the primary import surface —
                // auto proxy generation must fire here too, not just on the
                // media-library import path (1차 gap).
                scheduleAutoProxyGeneration(for: asset)
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


    func reportUnsupportedTimelineDrop() {
        setDropError(Self.DropFeedbackMessage.unsupportedTimelinePayload)
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

#if DEBUG || MOVIECUT_HARNESS
    func addUITestTextAnimationClip(preset: TextAnimationPreset) async {
        do {
            let track = try await ensureTrack(for: .text)
            let position = CGPoint(x: 160, y: 120)
            let animationDuration = preset == .none
                ? 0.5
                : min(max(preset.duration, 0.35), 1.2)
            let content = TextClipContent(
                text: "ANIMATE",
                fontFamily: "Helvetica Neue",
                fontSize: 92,
                fontColor: "#FFFFFF",
                alignment: .center,
                backgroundColor: "#FF00FF",
                position: CGPoint(x: 0, y: 0),
                animation: TextAnimation(preset: preset, duration: animationDuration)
            )
            let keyframes = uiTestTextAnimationKeyframes(
                for: preset,
                position: position,
                duration: 2.0,
                animationDuration: animationDuration
            )
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: 2.0),
                timelineRange: TimeRange(start: playheadTime, duration: 2.0),
                transform: ClipTransform(position: position),
                keyframes: keyframes,
                textContent: content
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func uiTestTextAnimationKeyframes(
        for preset: TextAnimationPreset,
        position: CGPoint,
        duration: TimeInterval,
        animationDuration: TimeInterval
    ) -> [Keyframe] {
        guard preset != .none else { return [] }

        let enterEnd = min(max(animationDuration, 0.1), duration)
        let exitStart = max(duration - enterEnd, 0)
        func keyframe(_ property: AnimatableProperty, _ time: TimeInterval, _ value: Double, _ mode: InterpolationMode = .easeOut) -> Keyframe {
            Keyframe(property: property, time: time, value: value, interpolation: mode)
        }

        switch preset {
        case .none:
            return []
        case .fadeIn:
            return [
                keyframe(.opacity, 0, 0),
                keyframe(.opacity, enterEnd, 1)
            ]
        case .fadeOut:
            return [
                keyframe(.opacity, 0, 1),
                keyframe(.opacity, exitStart, 1),
                keyframe(.opacity, duration, 0, .easeIn)
            ]
        case .fadeInOut:
            return [
                keyframe(.opacity, 0, 0),
                keyframe(.opacity, enterEnd, 1),
                keyframe(.opacity, exitStart, 1),
                keyframe(.opacity, duration, 0, .easeIn)
            ]
        case .slideInLeft:
            return [
                keyframe(.positionX, 0, Double(position.x - 160)),
                keyframe(.positionX, enterEnd, Double(position.x))
            ]
        case .slideInRight:
            return [
                keyframe(.positionX, 0, Double(position.x + 160)),
                keyframe(.positionX, enterEnd, Double(position.x))
            ]
        case .slideInUp:
            return [
                keyframe(.positionY, 0, Double(position.y - 120)),
                keyframe(.positionY, enterEnd, Double(position.y))
            ]
        case .slideInDown:
            return [
                keyframe(.positionY, 0, Double(position.y + 120)),
                keyframe(.positionY, enterEnd, Double(position.y))
            ]
        case .typewriter:
            return [
                keyframe(.opacity, 0, 0),
                keyframe(.opacity, 0.08, 1, .hold)
            ]
        case .bounceIn:
            return [
                keyframe(.scaleX, 0, 0.55), keyframe(.scaleY, 0, 0.55),
                keyframe(.scaleX, enterEnd * 0.65, 1.18), keyframe(.scaleY, enterEnd * 0.65, 1.18),
                keyframe(.scaleX, enterEnd, 1), keyframe(.scaleY, enterEnd, 1)
            ]
        case .zoomIn:
            return [
                keyframe(.scaleX, 0, 0.2), keyframe(.scaleY, 0, 0.2),
                keyframe(.scaleX, enterEnd, 1), keyframe(.scaleY, enterEnd, 1)
            ]
        case .popIn:
            return [
                keyframe(.scaleX, 0, 0.1), keyframe(.scaleY, 0, 0.1),
                keyframe(.scaleX, enterEnd * 0.7, 1.25), keyframe(.scaleY, enterEnd * 0.7, 1.25),
                keyframe(.scaleX, enterEnd, 1), keyframe(.scaleY, enterEnd, 1)
            ]
        case .wave:
            return [
                keyframe(.rotation, 0, -8),
                keyframe(.rotation, enterEnd * 0.5, 8, .easeInOut),
                keyframe(.rotation, enterEnd, 0, .easeInOut)
            ]
        }
    }

    func addUITestTextTemplateClip(template: MovieCutCore.TextTemplate) async {
        do {
            let track = try await ensureTrack(for: .text)
            let duration: TimeInterval = 2.0
            let position = CGPoint(x: 160, y: 120)
            let scaleFactor = min(1.0, max(0.32, 320.0 / 1920.0 * 2.15))
            var content = template.content
            content.position = CGPoint(x: 0, y: 0)
            content.fontSize = max(22, min(76, content.fontSize * scaleFactor))
            if content.backgroundColor == nil,
               template.name == "Title" || template.name == "Subtitle" || template.name == "Credits" {
                content.backgroundColor = "#00000066"
            }
            if content.animation == nil {
                content.animation = template.animation
            }
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration),
                transform: ClipTransform(position: position),
                textContent: content
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func addUITestChapterMarkers(includeBeatChapters: Bool) async {
        do {
            var settings = currentProject.exportSettings
            settings.includeChapters = true
            settings.includeBeatChapters = includeBeatChapters
            await apply(SetProjectExportSettingsCommand(exportSettings: settings))

            let markers = [
                Marker(time: 0.25, name: "Intro", color: "#FFD60A", kind: .standard),
                Marker(time: 1.25, name: "Outro", color: "#34C759", kind: .standard)
            ]
            await apply(AddMarkersCommand(markers: markers))

            if includeBeatChapters {
                await apply(AddMarkersCommand(markers: [
                    Marker(time: 0.75, name: "Beat 1", color: "#FF9F0A", kind: .beat)
                ]))
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
#endif

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
                animation: TextAnimation(preset: .popIn, duration: 0.25),
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
    // Methods live in EditorViewModel+TextStylePresets.swift (boundary
    // decomposition, review 2026-08-28 #7). Stored state stays here.

    var userTextStylePresets: [UserTextStylePreset] = []

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


    func updateCanvas(_ canvas: CanvasPreset) async {
        await apply(SetProjectCanvasCommand(canvas: canvas))
    }

    /// Sets or clears the canvas background fill (F-11).
    func updateCanvasBackground(_ background: CanvasBackground?) async {
        await apply(SetCanvasBackgroundCommand(background: background))
    }


    /// Updates the project's playback (preview) settings. Toggling proxy
    /// playback requires reloading the preview composition so the proxy (or
    /// original) URL is picked up on the next build.
    func updatePlaybackSettings(
        useProxyPlayback: Bool? = nil,
        proxyResolution: ProxyResolution? = nil,
        autoProxyOnThermalPressure: Bool? = nil,
        autoGenerateProxyOnImport: Bool? = nil
    ) async {
        var settings = currentProject.playbackSettings
        if let useProxyPlayback {
            settings.useProxyPlayback = useProxyPlayback
        }
        if let proxyResolution {
            settings.proxyResolution = proxyResolution
        }
        if let autoProxyOnThermalPressure {
            settings.autoProxyOnThermalPressure = autoProxyOnThermalPressure
        }
        if let autoGenerateProxyOnImport {
            settings.autoGenerateProxyOnImport = autoGenerateProxyOnImport
        }

        await apply(SetProjectPlaybackSettingsCommand(playbackSettings: settings))
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


    // MARK: - Color scopes (Phase 2A)

    /// Scopes of the selected clip's frame with its grade applied, shown in the
    /// grading panel. Computed from the cached thumbnail (cheap, grade-accurate)
    /// rather than a live frame grab.
    var scopeHistogram: ScopeAnalyzer.Histogram?
    var scopeWaveform: [[Int]]?
    var scopeVectorscope: ScopeAnalyzer.Vectorscope?
    var scopeRGBParade: ScopeAnalyzer.RGBParade?

    @ObservationIgnored private let scopeContext = CIContext(options: RenderColorConfiguration.contextOptions.merging([.useSoftwareRenderer: false]) { _, new in new })

    private func clearScopes() {
        scopeHistogram = nil
        scopeWaveform = nil
        scopeVectorscope = nil
        scopeRGBParade = nil
    }


    /// Recomputes ``scopeHistogram`` from the selected clip's graded thumbnail.
    func refreshScopes() {
        guard let clip = selectedClip,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId],
              let thumbnailData = asset.thumbnailData,
              let source = CIImage(data: thumbnailData) else {
            clearScopes()
            return
        }

        var image = source
        if let colorCorrection = clip.colorCorrection {
            image = ColorCorrectionPixelProcessor.apply(colorCorrection, to: image)
        }
        if let colorGrade = clip.colorGrade {
            image = ColorGradePixelProcessor.apply(colorGrade, to: image)
        }

        let width = 96
        let height = 54
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { clearScopes(); return }
        let scaled = image.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / extent.width,
            y: CGFloat(height) / extent.height
        ))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            scopeContext.render(
                scaled,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: bounds,
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        scopeHistogram = ScopeAnalyzer.histogram(rgba: bytes, binCount: 64)
        scopeWaveform = ScopeAnalyzer.lumaWaveform(rgba: bytes, width: width, height: height, columns: width, levels: 48)
        scopeVectorscope = ScopeAnalyzer.vectorscope(rgba: bytes, size: 48)
        scopeRGBParade = ScopeAnalyzer.rgbParade(rgba: bytes, width: width, height: height, columns: width, levels: 48)
    }


    func suggestCuts() async throws {
        guard let clipId = selectedClipId else { return }
        // Attempt BOTH tools (a silence-cut result is still useful when scene
        // detection fails), but never swallow the failures — report which
        // ones failed so the user knows what they got.
        var failures: [String] = []
        do {
            _ = try await autoCutSilence(for: clipId)
        } catch {
            failures.append("silence cut")
        }
        do {
            _ = try await detectAndSplitScenes(for: clipId)
        } catch {
            failures.append("scene detection")
        }
        if !failures.isEmpty {
            lastStatusMessage = nil
            lastErrorMessage = "Cut suggestion failed for: \(failures.joined(separator: ", "))."
        }
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
            // The clip id is unchanged but the source asset (and thus the audio
            // waveform) is new. Invalidate the stale waveform and re-request a
            // decode for the new asset. The view's .task(id:) now keys on
            // WaveformRequestKey(clip:) too, but re-requesting here is the
            // robust path — the asset-swap site knows the content changed.
            if let updatedClip = currentProject.timeline.tracks
                .flatMap(\.clips)
                .first(where: { $0.id == clipId }) {
                invalidateWaveform(for: updatedClip)
            } else {
                waveformCache.removeValue(forKey: clipId)
                waveformInFlight.remove(clipId)
            }
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

    @discardableResult
    func extractAudio(from clipId: UUID) async throws -> Clip {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        guard clip.kind == .video, asset.kind == .video else {
            throw EditorCommandError.invalidCommand("Audio can only be extracted from video clips.")
        }
        guard await Self.videoAssetContainsAudioTrack(asset.originalURL) else {
            throw EditorCommandError.invalidCommand("Selected video clip has no audio track to extract.")
        }

        let extractedClipId = UUID()
        try await session.dispatch(ExtractAudioCommand(
            clipId: clipId,
            extractedClipId: extractedClipId
        ))
        selectedAssetId = asset.id
        selectedClipId = extractedClipId
        playheadTime = clip.timelineRange.start
        try await refreshFromSession()

        guard let extractedClip = currentProject.timeline.tracks
            .flatMap(\.clips)
            .first(where: { $0.id == extractedClipId })
        else {
            throw EditorCommandError.clipNotFound(extractedClipId)
        }
        return extractedClip
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

    func beginMotionTrackingSelection() {
        guard let clipId = selectedClipId, canTrackMotionSelection else {
            reportQuickToolFailure("Select a video clip to track motion.")
            return
        }

        motionTrackingClipId = clipId
        motionTrackingResults = []
        isMotionTrackingSelectionActive = true
        lastErrorMessage = nil
        lastStatusMessage = "Adjust the tracking box on the preview, then start tracking."
    }

    func updateMotionTrackingInitialRect(_ rect: CGRect) {
        guard let normalized = MotionTrackingProvider.clampedNormalizedRect(rect) else { return }
        motionTrackingInitialRect = normalized
        if let selectedClipId {
            motionTrackingClipId = selectedClipId
        }
    }

    func cancelMotionTrackingSelection() {
        isMotionTrackingSelectionActive = false
        if motionTrackingResults.isEmpty {
            motionTrackingClipId = nil
        }
        lastStatusMessage = "Motion tracking selection cancelled."
    }

    func trackMotionInSelectedClip() async {
        await trackMotionInSelectedClip(rect: motionTrackingInitialRect)
    }

    func trackMotionInSelectedClip(rect: CGRect) async {
        guard let clipId = selectedClipId, canTrackMotionSelection else {
            reportQuickToolFailure("Select a video clip to track motion.")
            return
        }
        guard let normalizedRect = MotionTrackingProvider.clampedNormalizedRect(rect) else {
            reportQuickToolFailure("Draw a valid tracking box on the preview.")
            return
        }

        motionTrackingInitialRect = normalizedRect
        motionTrackingClipId = clipId
        motionTrackingResults = []
        isMotionTrackingSelectionActive = false
        isMotionTrackingRunning = true
        quickToolProgressMessage = "Tracking motion..."
        lastErrorMessage = nil
        lastStatusMessage = "Tracking motion..."

        do {
            let keyframeCount = try await trackMotion(for: clipId, initialRect: normalizedRect)
            let message = keyframeCount == 0
                ? "Motion tracker found no frames; clip unchanged."
                : "Added \(keyframeCount) motion tracking \(keyframeCount == 1 ? "keyframe" : "keyframes")."
            recordAnalysisResult(
                action: "Motion Tracking",
                count: keyframeCount,
                message: message,
                clipId: clipId
            )
            reportQuickToolSuccess(message)
        } catch {
            motionTrackingResults = []
            reportQuickToolFailure(error)
        }

        isMotionTrackingRunning = false
    }

    func clearMotionTrackingOnSelectedClip() async {
        guard let clipId = selectedClipId, let clip = selectedClip else { return }

        let preserved = clip.keyframes.filter { !Self.motionTrackingKeyframeProperties.contains($0.property) }
        await apply(SetClipPropertyCommand(clipId: clipId, property: .keyframes(preserved)))

        motionTrackingResults = []
        motionTrackingAppliedKeyframeCounts[clipId] = nil
        if motionTrackingClipId == clipId {
            motionTrackingClipId = nil
            isMotionTrackingSelectionActive = false
        }
        lastStatusMessage = "Cleared motion tracking keyframes."
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

    func extractAudioFromSelectedClip() async {
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
        scrubPlayhead(to: marker.time)
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
        if isMaskEditorActive {
            isCropEditorActive = false
        }
    }

    /// G-23: enters/leaves the canvas crop editor. Entering closes the mask
    /// editor — both are full-canvas overlays and would visually conflict.
    func setCropEditorActive(_ active: Bool) {
        isCropEditorActive = active
        if active {
            isMaskEditorActive = false
        }
    }

    func addMask() async {
        guard let selectedClipId else { return }
        isMaskEditorActive = true
        isCropEditorActive = false
        await apply(SetClipMaskCommand(clipId: selectedClipId, mask: defaultMask()))
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
            AppLog.ai.error("transcription failed: \(error.localizedDescription, privacy: .public)")
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }
    }

    func applyGeneratedSubtitles() async {
        let clips = applyingKaraokeSettings(to: pendingSubtitleClips)
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

    /// Stamps the karaoke flag and highlight color onto generated subtitle
    /// clips when the AutoSubtitles karaoke toggle is on. Applied once, at
    /// "Apply to Timeline" — the AddClipCommand already carries the karaoke
    /// content, so undoing the apply reverts the whole setting.
    private func applyingKaraokeSettings(to clips: [Clip]) -> [Clip] {
        guard isKaraokeSubtitlesEnabled else { return clips }
        return clips.map { clip in
            guard var textContent = clip.textContent else { return clip }
            textContent.karaokeEnabled = true
            textContent.highlightFontColor = karaokeHighlightColorHex
            var updated = clip
            updated.textContent = textContent
            return updated
        }
    }

    /// G-01 Inc 3: applies a built-in subtitle style preset to the selected
    /// text clip in one command (single undo, immediate preview via the
    /// shared text renderer). Text, word timings, and the karaoke flag stay
    /// with the clip — a preset never silently flips karaoke on/off.
    func applySubtitleStylePreset(_ preset: SubtitleStylePreset) async {
        guard let selectedClip, var textContent = selectedClip.textContent else {
            lastErrorMessage = "Select a subtitle clip before applying a style preset."
            return
        }
        let canvasSize = currentProject.canvas.size
        textContent = preset.applying(to: textContent, canvasSize: canvasSize)
        await updateSelectedTextContent(textContent)
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
    func trackMotion(for clipId: UUID, initialRect: CGRect) async throws -> Int {
        let snapshot = await session.snapshot()
        let (clip, asset) = try sourceClipAndAsset(for: clipId, in: snapshot)
        guard asset.kind == .video else {
            throw EditorCommandError.invalidCommand("Select a video clip to track motion.")
        }

        let provider = MotionTrackingProvider()
        let results = try await provider.track(
            videoURL: asset.originalURL,
            initialRect: initialRect,
            timeRange: clip.sourceRange
        )
        let canvasSize = effectiveCanvasSize(in: snapshot)
        let generatedKeyframes = motionTrackingKeyframes(from: results, clip: clip, canvasSize: canvasSize)
        guard !generatedKeyframes.isEmpty else {
            lastErrorMessage = nil
            return 0
        }

        let updatedKeyframes = mergedMotionTrackingKeyframes(existing: clip.keyframes, generated: generatedKeyframes)
        try await session.dispatch(SetClipPropertyCommand(clipId: clipId, property: .keyframes(updatedKeyframes)))
        motionTrackingResults = results
        motionTrackingClipId = clipId
        motionTrackingAppliedKeyframeCounts[clipId] = generatedKeyframes.count
        try await refreshFromSession()
        return generatedKeyframes.count
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

    /// Maps tracked boxes to position keyframes in clip-local time.
    private func motionTrackingKeyframes(from results: [TrackingResult], clip: Clip, canvasSize: CGSize) -> [Keyframe] {
        var generatedKeyframes: [Keyframe] = []
        for result in results {
            let pointRange = TimeRange(start: result.timestamp, duration: .ulpOfOne)
            guard let mapping = timelineMapping(for: pointRange, in: clip) else { continue }

            let localTime = mapping.timelineRange.start - clip.timelineRange.start
            let posX = Double(result.rect.midX - 0.5) * Double(canvasSize.width)
            let posY = Double(0.5 - result.rect.midY) * Double(canvasSize.height)

            generatedKeyframes.append(Keyframe(property: .positionX, time: localTime, value: posX))
            generatedKeyframes.append(Keyframe(property: .positionY, time: localTime, value: posY))
        }
        return generatedKeyframes
    }

    private func mergedMotionTrackingKeyframes(existing: [Keyframe], generated: [Keyframe]) -> [Keyframe] {
        let preserved = existing.filter { !Self.motionTrackingKeyframeProperties.contains($0.property) }
        return (preserved + generated).sorted {
            $0.time == $1.time ? $0.property.rawValue < $1.property.rawValue : $0.time < $1.time
        }
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

    private func currentMotionTrackingResultRect(for clip: Clip) -> CGRect? {
        guard !motionTrackingResults.isEmpty else { return nil }

        // Map the playhead timeline time to source time through the canonical
        // mapping so the nearest tracking result is found at the correct source
        // offset for any rate or speed ramp (Step 3).
        let sourceTime: TimeInterval
        if let mapping = clip.makeTimeMapping() {
            sourceTime = mapping.sourceTime(forTimelineTime: playheadTime)
        } else {
            let clipLocalTimelineTime = min(
                max(playheadTime - clip.timelineRange.start, 0),
                max(clip.timelineRange.duration, 0)
            )
            sourceTime = clip.sourceRange.start + (clipLocalTimelineTime * max(clip.playbackRate, 0.25))
        }

        return motionTrackingResults.min {
            abs($0.timestamp - sourceTime) < abs($1.timestamp - sourceTime)
        }?.rect
    }

    // MARK: - Auto highlights (F-20)
    // Methods live in EditorViewModel+AutoHighlights.swift (boundary
    // decomposition). Stored state stays here.

    /// Scored highlight candidates for the selected clip (empty = none).
    var highlightCandidates: [HighlightCandidate] = []

    // MARK: - Assistant (F-21)

    /// The last assistant outcome message shown in the panel.
    var assistantResultMessage: String?
    /// Suggestions shown when the last instruction was not understood.
    var assistantSuggestions: [String] = []

    /// Parses a natural-language instruction and executes the mapped intent
    /// across the targeted clips using existing commands (F-21).
    ///
    /// Routed through `AIEditingProvider` (requirement 10.3) — see
    /// `executeAssistantPlan(for:)` in `EditorViewModel+AssistantProvider.swift`.
    func runAssistantCommand(_ text: String) async {
        await executeAssistantPlan(for: text)
    }

    /// Applies one parsed intent to the timeline.
    ///
    /// Internal (not private) so `EditorViewModel+AssistantProvider.swift` can feed
    /// the intents produced by `AIEditingProvider.plan` through the same path the
    /// legacy direct-parse flow used (requirement 10.3).
    func executeAssistantIntent(_ intent: AssistantIntent) async {
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

    func apply(_ command: any EditorCommand) async {
        do {
            try await session.dispatch(command)
            try await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func dispatchCardMutation(
        _ command: any EditorCommand,
        successMessage: String
    ) async -> Bool {
        do {
            try await session.dispatch(command)
            try await refreshFromSession()
            lastErrorMessage = nil
            lastStatusMessage = successMessage
            return true
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
            return false
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

    func refreshFromSession() async throws {
        currentProject = await session.snapshot()
        invalidateMasterLoudnessContext()
        await refreshFlattenedTimeline(for: currentProject)
        canvasSelection = currentProject.canvas.aspectRatio
        syncExportUI(from: currentProject.exportSettings)

        selectedClipIds.formIntersection(currentClipIds)

        if let selectedAssetId, currentProject.mediaLibrary.assets[selectedAssetId] == nil {
            self.selectedAssetId = nil
        }

        playheadTime = min(playheadTime, max(0, currentProject.timeline.duration))
        lastErrorMessage = nil
        lastStatusMessage = nil

        // Step 1: rebuild the preview composition so the main Preview reflects
        // the committed project state (multi-track, transitions, effects,
        // audio mix). This runs on every committed mutation (command dispatch
        // / undo / redo / import) but NOT during in-progress drags, which
        // mutate `currentProject` directly without going through the session
        // — so drag ticks don't trigger a rebuild storm. Playback state is
        // preserved inside `rebuildPreviewComposition`.
        //
        // The parity harness suppresses this during multi-gate scenario setup
        // (each gate dispatches and would otherwise spawn a racing
        // restorePlaybackAfterRebuild) and triggers a single rebuild at the end.
        if !suppressCompositionRebuild {
            rebuildPreviewComposition()
        }

        // Recompute the dirty flag from the project content rather than
        // blanket-setting true. This makes undo/redo back to the saved state
        // clear the flag: a project that equals its last-saved snapshot is not
        // dirty even if it was reached through edits then undos. When there is
        // no saved snapshot yet (new unsaved project), any committed change is
        // dirty.
        if let lastSavedProject {
            isDirty = currentProject != lastSavedProject
        } else {
            isDirty = true
        }
        scheduleAutosave()
        refreshScopes()
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

    // recordAnalysisResult + clipDescription live in
    // EditorViewModel+AnalysisSupport.swift (shared analysis boundary).

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

        if let clip = selectedClip {
            selectedEQPreset = clip.equalizer?.preset.rawValue ?? clipEQPresets[selectedClipId] ?? "flat"
        } else {
            selectedEQPreset = clipEQPresets[selectedClipId] ?? "flat"
        }
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

    var currentClipIds: Set<UUID> {
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

    private func isStickerClip(_ clip: Clip) -> Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || isLegacyStickerContent(textContent)
    }

    private func isLegacyStickerContent(_ textContent: TextClipContent) -> Bool {
        textContent.fontFamily == "Apple Color Emoji"
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

    private func subtitleClips(from result: TranscriptionResult, alignedTo clip: Clip) -> [Clip] {
        result.segments.compactMap { segment in
            let sourceRange = TimeRange(
                start: segment.startTime,
                duration: max(0, segment.endTime - segment.startTime)
            )
            guard let mapping = timelineMapping(for: sourceRange, in: clip) else {
                return nil
            }

            var textContent = TextClipContent(
                text: segment.text,
                fontFamily: "SFPro-Medium",
                fontSize: 18
            )
            // Word timings must be relative to the generated clip's timeline
            // start — the karaoke renderer's local time — so each word maps
            // through the same speed-aware mapping as its segment. Without
            // this the aligned path dropped words and karaoke silently fell
            // back to the uniform render (G-01 Inc 2).
            if let words = segment.words, !words.isEmpty {
                let relativeWords = words.compactMap { word -> WordTiming? in
                    let wordRange = TimeRange(
                        start: word.startTime,
                        duration: max(0, word.endTime - word.startTime)
                    )
                    guard let wordMapping = timelineMapping(for: wordRange, in: clip) else {
                        return nil
                    }
                    let localStart = wordMapping.timelineRange.start - mapping.timelineRange.start
                    guard localStart.isFinite, localStart >= 0 else { return nil }
                    return WordTiming(
                        text: word.text,
                        startTime: localStart,
                        endTime: localStart + wordMapping.timelineRange.duration,
                        confidence: word.confidence
                    )
                }
                if relativeWords.count == TextOverlayPixelProcessor.karaokeWordRanges(in: segment.text).count {
                    textContent.wordTimings = relativeWords
                }
            }

            return Clip(
                kind: .text,
                sourceRange: mapping.sourceRange,
                timelineRange: mapping.timelineRange,
                textContent: textContent
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

    /// Rebuilds the preview composition from the current project so the main
    /// Preview reflects the timeline as a whole (multi-track, transitions,
    /// effects, audio mix, masks, subtitles) rather than the selected clip's
    /// raw source asset. Playback state (time, play/pause, preview volume) is
    /// preserved across the rebuild. Used by PreviewPanel and the actual-app
    /// E2E harness. Step 1 of the core-editing repair handoff.
    func rebuildPreviewComposition(preservingPlayback preserve: Bool = true) {
        let snapshotTime = playbackEngine.currentTime
        let wasPlaying = playbackEngine.isPlaying
        let snapshotVolume = Double(playbackEngine.player.volume)

        let project = currentProject
        let audio = buildAudioProcessingOptions()
        playbackEngine.loadProject(project, audioProcessing: audio)

        if preserve {
            // Composition install is async (Task inside loadProject). Restore
            // playback state once the new item reports ready; if the rebuild
            // fails, lastCompositionError is surfaced to the UI instead.
            restorePlaybackAfterRebuild(targetTime: snapshotTime,
                                        shouldPlay: wasPlaying,
                                        volume: snapshotVolume)
        }
    }

    private func restorePlaybackAfterRebuild(targetTime: TimeInterval, shouldPlay: Bool, volume: Double) {
        // Capture the generation at request time so we can detect if a newer
        // rebuild supersedes this one (in which case that newer request owns
        // playback restoration and we should bail out instead of waiting
        // forever on a generation that will never match again).
        let requestedGeneration = playbackEngine.currentCompositionGeneration
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Wait for the composition to install. Bail if a newer rebuild
            // supersedes us, or if the build failed, or after ~3s.
            for _ in 0..<150 {
                if self.playbackEngine.lastCompositionError != nil { return }
                if self.playbackEngine.currentCompositionGeneration != requestedGeneration { return }
                if self.playbackEngine.playerItem != nil { break }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            guard self.playbackEngine.playerItem != nil,
                  self.playbackEngine.lastCompositionError == nil,
                  self.playbackEngine.currentCompositionGeneration == requestedGeneration else { return }

            self.playbackEngine.player.volume = Float(volume)
            self.playbackEngine.seek(to: min(max(0, targetTime), self.playbackEngine.duration))
            if shouldPlay {
                self.playbackEngine.play()
            }
        }
    }

    /// BUG-02: the probe is VALIDATED — unknown extensions and content whose
    /// header bytes match no known media signature are rejected at import
    /// with an explicit reason instead of exploding at preview/export.
    private func mediaAssetWithAppProbe(for url: URL) async throws(MediaImportValidationError) -> MediaAsset {
        var asset = try MediaImporter.validatedProbe(url: url)

        // Capture a security-scoped bookmark at import time so the file stays
        // reachable after restart under App Sandbox. (S2)
        asset.originalBookmark = SecurityScopedAccess.makeBookmark(for: url)

        let probe = await Self.appMetadataProbe(
            for: url,
            kind: asset.kind,
            baseMetadata: asset.metadata
        )
        asset.duration = probe.duration ?? asset.duration
        asset.metadata = probe.metadata

        return await Self.enrichAssetWithThumbnail(asset)
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

    func toggleNoiseReduction(_ enabled: Bool) {
        guard let clipId = selectedClipId else { return }
        if enabled {
            noiseReductionClipIds.insert(clipId)
        } else {
            noiseReductionClipIds.remove(clipId)
        }
    }

    func buildAudioProcessingOptions() -> ClipAudioProcessingOptions {
        let snapshot = currentProject
        var voiceClipIds: Set<UUID> = []
        for track in snapshot.timeline.tracks where track.kind == .video {
            for clip in track.clips where clip.volume > 0 {
                voiceClipIds.insert(clip.id)
            }
        }

        var eqPresets: [UUID: EqualizerPreset] = [:]
        for track in snapshot.timeline.tracks {
            for clip in track.clips {
                if let preset = clip.resolvedEqualizerPreset() {
                    eqPresets[clip.id] = preset
                }
            }
        }
        for (clipId, presetName) in clipEQPresets where eqPresets[clipId] == nil {
            if let matched = equalizerPreset(for: presetName) {
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
        switch EqualizerPresetID(rawValue: option) {
        case .flat, .custom:
            return nil
        case .voiceEnhance, .bassBoost, .trebleBoost:
            return EqualizerPreset.preset(for: EqualizerPresetID(rawValue: option)!)
        default:
            if option == "voice" {
                return .voiceEnhance
            }
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
            var asset = try MediaImporter.validatedProbe(url: url)
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
        guard await confirmDiscardUnsavedChanges() else { return }
        let project = templateStore.createProject(from: bundle)
        session = EditorSession(project: project)
        currentProject = project
        invalidateMasterLoudnessContext()
        resetMasterAudioProcessingMutationContext(to: project.masterAudioProcessing)
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
        // The template-generated project is the clean baseline.
        lastSavedProject = project
        isDirty = false
    }

    func createProjectFromTemplate(_ bundle: TemplateBundle) async {
        await createProject(from: bundle)
    }

    /// One-click "Photo to Video" workflow (home onboarding card 3 / G-21
    /// partial): creates a 9:16 photo-slideshow project from the chosen image
    /// URLs and drops them sequentially on the first video track. The built-in
    /// `photoSlideshowTemplate` seeds the canvas, music track, and title so the
    /// user only needs to pick photos, then export. Any image placeholder clips
    /// the template created are replaced by the imported photos.
    ///
    /// Adjacent photos receive the requested transition (cross-dissolve by
    /// default) so the slideshow is immediately watchable — not a sequence of
    /// hard cuts. The empty Music track is preserved as a ready BGM slot.
    ///
    /// After success, the editor stage is shown with the first photo selected
    /// and the playhead at the start, so the user lands ready to edit/export.
    func createPhotoSlideshow(
        fromPhotoURLs urls: [URL],
        pace: PhotoSlideshowPace = .normal,
        transitionStyle: PhotoSlideshowTransition = .crossDissolve,
        kenBurnsEnabled: Bool = true
    ) async {
        let imageURLs = urls.filter { url in
            (try? MediaImporter.validatedProbe(url: url))?.kind == .image
        }
        guard !imageURLs.isEmpty else {
            lastErrorMessage = "Please choose at least one image to create a photo video."
            return
        }

        guard let slideshowTemplate = templateStore.bundles.first(where: {
            $0.identifier == "com.moviecut.template.photo-slideshow"
        }) ?? templateStore.bundles.first else {
            // Fallback: no slideshow template registered — start a blank project.
            guard await newProject() else { return }
            await importMediaAndAddToTimeline(imageURLs, startTime: 0)
            return
        }

        // Seed the project from the template (canvas, music track, title).
        await createProject(from: slideshowTemplate)

        // Replace the template's image placeholder clips with the user's photos,
        // laid out sequentially on the first video track.
        do {
            let snapshot = await session.snapshot()
            guard let videoTrack = snapshot.timeline.tracks.first(where: { $0.kind == .video }) else {
                await importMediaAndAddToTimeline(imageURLs, preferredTrackId: nil, startTime: 0)
                return
            }

            // Remove placeholder image clips the template generated, keeping the
            // track but emptying it so the imported photos are the only clips.
            for placeholder in snapshot.timeline.tracks.first(where: { $0.id == videoTrack.id })?.clips ?? []
                where placeholder.kind == .image {
                try await session.dispatch(DeleteClipCommand(clipId: placeholder.id))
            }

            // Resolve the transition applied between adjacent photos. The first
            // photo has no preceding boundary, so it stays a hard cut.
            let boundaryTransition: Transition? = transitionStyle.transitionType.map {
                Transition(type: $0, duration: min(PhotoSlideshowDefaults.transitionDuration, pace.clipDuration / 2))
            }

            var insertionStart: TimeInterval = 0
            for (index, url) in imageURLs.enumerated() {
                let asset = try await mediaAssetWithAppProbe(for: url)
                try await session.dispatch(ImportMediaCommand(asset: asset))

                let duration = max(0.1, pace.clipDuration)
                // Apply the chosen transition to every photo after the first.
                let clipTransition = index == 0 ? nil : boundaryTransition
                // A subtle slow zoom-in (1.0x → 1.12x) brings still photos to
                // life. Disabled when the user opts out of motion in the
                // slideshow options sheet.
                let clipKenBurns = kenBurnsEnabled ? KenBurnsEffect.defaultZoomIn() : nil
                let clip = Clip(
                    assetId: asset.id,
                    kind: .image,
                    sourceRange: TimeRange(start: 0, duration: duration),
                    timelineRange: TimeRange(start: insertionStart, duration: duration),
                    transition: clipTransition,
                    kenBurnsEffect: clipKenBurns
                )
                try await session.dispatch(AddClipCommand(trackId: videoTrack.id, clip: clip))
                insertionStart += duration
                selectedAssetId = asset.id
                selectedClipId = clip.id
            }

            playheadTime = 0
            try await refreshFromSession()
            reportTimelineFileDropSuccess(count: imageURLs.count)
            lastStatusMessage = "Photo video ready — add music or export when you're happy."
        } catch {
            try? await refreshFromSession()
            setDropError(error.localizedDescription)
        }
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

    // Internal (was private) so the decomposition extension files can share
    // it — same-target visibility widening only, see +AnalysisSupport.swift.
    static func ensureDefaultTracks(in project: Project) -> Project {
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

    // MARK: - Inspector methods kept in the main file
    // These depend on private stored state of the main file (clipEQPresets,
    // backgroundRemovedClipIds, clipStyles/styleTransferIndex, scopeContext,
    // lutErrorDescription), so they deliberately did not move to
    // EditorViewModel+Inspector.swift (pure-move boundary rule).

    func applyEQPreset(_ preset: String) async {
        guard let clipId = selectedClipId, let clip = selectedClip else { return }

        let presetID = EqualizerPresetID(rawValue: preset) ?? .flat
        selectedEQPreset = presetID.rawValue

        let settings: ClipEqualizerSettings?
        switch presetID {
        case .flat:
            settings = nil
            clipEQPresets.removeValue(forKey: clipId)
        case .custom:
            settings = .custom(bands: clip.equalizer?.bands ?? EqualizerPreset.flat.bands)
            clipEQPresets[clipId] = presetID.rawValue
        case .voiceEnhance, .bassBoost, .trebleBoost:
            settings = .settings(for: presetID)
            clipEQPresets[clipId] = presetID.rawValue
        }

        await apply(SetClipPropertyCommand(clipId: clipId, property: .equalizer(settings)))
    }

    func updateSelectedEQBandGain(frequency: Float, gain: Float) async {
        guard let clipId = selectedClipId, let clip = selectedClip else { return }

        let targetFrequencies = EqualizerPreset.bandFrequencies
        var bands = ClipEqualizerSettings.normalizedBands(clip.equalizer?.bands ?? EqualizerPreset.flat.bands)
        guard let index = targetFrequencies.firstIndex(where: { abs($0 - frequency) < 0.5 }) else { return }

        bands[index] = EQBand(frequency: targetFrequencies[index], gain: gain)
        selectedEQPreset = EqualizerPresetID.custom.rawValue
        clipEQPresets[clipId] = EqualizerPresetID.custom.rawValue
        await apply(SetClipPropertyCommand(
            clipId: clipId,
            property: .equalizer(.custom(bands: bands))
        ))
    }

    func toggleBackgroundRemoval(_ enabled: Bool) async {
        guard let clipId = selectedClipId, let clip = selectedClip else { return }

        isBackgroundRemoved = enabled
        if enabled {
            backgroundRemovedClipIds.insert(clipId)
        } else {
            backgroundRemovedClipIds.remove(clipId)
        }

        // Persist on the clip so preview and export both reflect it (F-08).
        guard clip.kind == .video else {
            lastErrorMessage = "Background removal applies to video clips."
            return
        }
        await apply(SetClipPropertyCommand(clipId: clipId, property: .isBackgroundRemoved(enabled)))
        lastStatusMessage = enabled
            ? "Background removal on. Frames without a detected person are left unchanged."
            : "Background removal off."
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

    /// On-device auto white balance: analyzes the selected clip's source
    /// thumbnail (gray-world) and sets a corrective grade. No cloud round-trip.
    func autoColorSelectedClip() async {
        guard let rgba = selectedClipThumbnailRGBA() else { return }
        await updateSelectedColorGrade(AutoColorAnalyzer.autoWhiteBalanceGrade(rgba: rgba))
    }

    /// On-device auto levels: stretches the selected clip's luma range for
    /// optimal contrast. No cloud round-trip.
    func autoLevelsSelectedClip() async {
        guard let rgba = selectedClipThumbnailRGBA() else { return }
        await updateSelectedColorGrade(AutoColorAnalyzer.autoLevelsGrade(rgba: rgba))
    }

    /// On-device one-tap auto enhance: white balance + contrast in one grade.
    func autoEnhanceSelectedClip() async {
        guard let rgba = selectedClipThumbnailRGBA() else { return }
        await updateSelectedColorGrade(AutoColorAnalyzer.autoEnhanceGrade(rgba: rgba))
    }

    /// Renders the selected clip's source thumbnail to a small RGBA buffer for
    /// on-device analysis (auto color, scopes).
    private func selectedClipThumbnailRGBA(width: Int = 96, height: Int = 54) -> [UInt8]? {
        guard let clip = selectedClip,
              let assetId = clip.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId],
              let thumbnailData = asset.thumbnailData,
              let source = CIImage(data: thumbnailData) else {
            return nil
        }

        let extent = source.extent
        guard extent.width > 0, extent.height > 0 else { return nil }
        let scaled = source.transformed(by: CGAffineTransform(
            scaleX: CGFloat(width) / extent.width,
            y: CGFloat(height) / extent.height
        ))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            scopeContext.render(
                scaled,
                toBitmap: base,
                rowBytes: width * 4,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return bytes
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

    /// CA-26 — LUT export. An active external LUT re-exports the MANAGED
    /// ORIGINAL FILE byte-for-byte (parse → serialize is NOT lossless:
    /// DOMAIN lines, comments, the source title, source precision, and
    /// out-of-0…1 values would be lost); otherwise the clip's basic color
    /// correction is baked through the production processor. The bake scope
    /// (basic correction only — 3-way/HSL/masks excluded) is surfaced in the
    /// status message so users don't assume a full-grade bake.
    ///
    /// Parsing/baking, serialization, and file writes run OFF the main
    /// actor (a 65³ serialize is seconds of string work); only the UI state
    /// updates below hop back to MainActor.
    func exportLUTForSelectedClip(to url: URL) async {
        if let lutEffect = selectedClip?.effects.first(where: { $0.type == .externalLUT }),
           let path = lutEffect.lutPath {
            let source = URL(fileURLWithPath: path)
            do {
                // Same file (path-variant) → nothing to do; copyItem would
                // throw on identical source/destination.
                if source.standardizedFileURL != url.standardizedFileURL {
                    try await Task.detached(priority: .userInitiated) {
                        if FileManager.default.fileExists(atPath: url.path) {
                            try FileManager.default.removeItem(at: url)
                        }
                        try FileManager.default.copyItem(at: source, to: url)
                    }.value
                }
                lastErrorMessage = nil
                lastStatusMessage = "Exported LUT (byte-for-byte copy of the imported file)."
            } catch {
                lastStatusMessage = nil
                lastErrorMessage = "Could not export LUT: \(error.localizedDescription)"
            }
            return
        }

        guard let clip = selectedClip, let correction = clip.colorCorrection,
              !ColorCorrectionPixelProcessor.isIdentity(correction) else {
            lastStatusMessage = nil
            lastErrorMessage = "Nothing to export: apply an external LUT or a color correction first."
            return
        }
        let title = url.deletingPathExtension().lastPathComponent
        do {
            let dimension = try await Task.detached(priority: .userInitiated) {
                let lut = try CubeLUTExporter.bake(colorCorrection: correction)
                let text = try CubeLUTExporter.serialize(lut, title: title)
                try text.write(to: url, atomically: true, encoding: .utf8)
                return lut.dimension
            }.value
            lastErrorMessage = nil
            lastStatusMessage = "Baked basic color correction to a \(dimension)-size LUT (3-way/HSL/masks excluded)."
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = "Could not write LUT: \(error.localizedDescription)"
        }
    }

    // MARK: - Media methods kept in the main file
    // evaluateMissingMedia assigns the private(set) missingMediaAssets;
    // the reportInvalid*Drop trio uses the private DropFeedbackMessage type;
    // relinkMedia and the importMedia family share private helpers with
    // non-media features (see EditorViewModel+Media.swift header). Pure-move
    // boundary rule: no access promotions here.

    /// Recomputes ``missingMediaAssets`` from a project snapshot. Public so the
    /// re-link regression test can drive the same detection the launch path
    /// uses, without a full project-load round-trip.
    func evaluateMissingMedia(in project: Project) {
        let unreachable = project.mediaLibrary.assets.values.filter { asset in
            SecurityScopedAccess.needsRelocation(asset)
                || !FileManager.default.fileExists(atPath: asset.originalURL.path)
        }
        missingMediaAssets = unreachable.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func reportInvalidTimelineFileDrop() {
        setDropError(Self.DropFeedbackMessage.invalidTimelineFilePayload)
    }

    func reportInvalidTimelineLibraryAssetDrop() {
        setDropError(Self.DropFeedbackMessage.invalidTimelineLibraryAssetPayload)
    }

    func reportInvalidMediaLibraryDrop() {
        setDropError(Self.DropFeedbackMessage.invalidMediaLibraryPayload)
    }
}

