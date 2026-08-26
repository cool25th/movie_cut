import Foundation
import AVFoundation
import MovieCutCore
import PhotosUI
import SwiftUI

/// CA-17: subtitle sidecar export formats — the same pair the Mac offers.
enum SubtitleExportFormat: String, CaseIterable, Identifiable {
    case srt = "srt"
    case vtt = "vtt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .srt: "SubRip (.srt)"
        case .vtt: "WebVTT (.vtt)"
        }
    }
}

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
    // CA-17: subtitle export state — SRT/VTT written from timeline text clips.
    var lastSubtitleExportURL: URL? = nil

    private var session: EditorSession
    private let projectStore: ProjectStore
    /// SURV-01 (리뷰 2026-08-26): 관리 임포트 루트 — Application Support는
    /// OS가 정리하지 않으므로 복구 프로젝트가 참조하는 원본이 살아남는다.
    private let importsRootDirectory: URL?
    private var sfxURLResolver: [String: URL]

    /// BUG-IOS-02: crash-recovery autosave state. Committed edits persist to
    /// the shared Core `ProjectStore`; a launch-time recovery restores work
    /// that would previously vanish on every app termination or OS eviction.
    /// Failure surfaces non-blocking (editing continues).
    var autosaveFailureMessage: String?
    var recoveredUnsavedWork = false

    /// - Parameter autosaveDirectory: test seam — routes the crash-recovery
    ///   autosave to an explicit directory. nil uses the production location.
    /// - Parameter importsDirectory: SURV-01 test seam — routes managed media
    ///   imports to an explicit root. nil uses the production location.
    init(autosaveDirectory: URL? = nil, importsDirectory: URL? = nil) {
        // BUG-IOS-02: every launch used to start from a fresh project — work
        // was lost on termination or OS eviction. Restore the crash-recovery
        //   autosave when one exists (same Core ProjectStore contract as Mac).
        let project = Self.defaultProject()
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        session = EditorSession(project: project)
        projectStore = autosaveDirectory.map { ProjectStore(autosaveDirectory: $0) } ?? ProjectStore()
        importsRootDirectory = importsDirectory ?? ProjectStore.defaultImportsDirectory()
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

    /// SURV-01 2차: assets whose originals are gone from this device — the
    /// relink banner drives ``relinkMedia(_:to:)`` over this list (Mac
    /// `missingMediaAssets` parity).
    var missingMediaAssets: [MediaAsset] {
        mediaAssets.filter { !FileManager.default.fileExists(atPath: $0.originalURL.path) }
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
        // BUG-02: reject unknown extensions / signature-less content at
        // import with an explicit reason (was a silent `.video` default).
        var asset: MediaAsset
        do {
            asset = try MediaImporter.validatedProbe(url: url)
        } catch {
            self.lastErrorMessage = error.localizedDescription
            return
        }
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

    /// Pixel aspect (width/height) of the selected clip's source media — the
    /// input the crop presets need so a chosen ratio selects a region of that
    /// PIXEL aspect. Mirrors the Mac EditorViewModel helper.
    var selectedClipSourceAspect: Double? {
        guard let assetId = selectedClip?.assetId,
              let asset = currentProject.mediaLibrary.assets[assetId],
              let width = asset.metadata.width,
              let height = asset.metadata.height,
              width > 0, height > 0 else {
            return nil
        }
        return Double(width) / Double(height)
    }

    /// Commits a crop rect (G-23) as one undoable property edit. A full-frame
    /// rect is stored as nil so never-cropped projects keep the byte-identical
    /// JSON encoding (cropRect key omitted).
    func updateSelectedCropRect(_ cropRect: NormalizedRect?) async {
        guard let selectedClipId else { return }
        let normalized = cropRect.flatMap { CropPixelProcessor.isFullFrame($0) ? nil : $0 }
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .cropRect(normalized)))
    }

    func setTransition(_ type: TransitionType) async {
        guard let selectedClipId else { return }

        let transition: MovieCutCore.Transition?
        if type == .none {
            transition = nil
        } else {
            transition = MovieCutCore.Transition(type: type, duration: selectedClip?.transition?.duration ?? 0.5)
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
        scheduleAutosave()
    }

    /// BUG-IOS-01: template application routes through
    /// `ReplaceProjectCommand` — the picker used to swap `currentProject`
    /// directly, leaving the session holding the OLD project so the next
    /// edit or undo reverted the whole template.
    func applyTemplateProject(_ project: Project) async {
        do {
            try await session.dispatch(ReplaceProjectCommand(project: project))
            await refreshFromSession()
            selectedClipId = nil
            playheadTime = 0
            isPlaying = false
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Crash-recovery persistence (BUG-IOS-02)

    /// Restores the crash-recovery autosave at launch, when present. Call
    /// once from the root view's `task` before user interaction.
    func restoreAutosaveIfAvailable() async {
        guard let recovered = await projectStore.loadAutosaveIfAvailable() else {
            // AUTOSAVE-02: a recovery file that existed but could not be
            // decoded is surfaced (the store removed the damaged file; the
            // user should know their recovery was lost, not wonder).
            if let failure = await projectStore.lastAutosaveLoadFailure {
                lastErrorMessage = String(
                    format: NSLocalizedString(
                        "A damaged recovery file was found and removed: %@",
                        comment: "Shown when the crash-recovery file could not be decoded"
                    ),
                    failure.userMessage
                )
            }
            cleanupStaleImports()
            return
        }
        let project = Self.defaultProjectIfEmpty(recovered)
        session = EditorSession(project: project)
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        recoveredUnsavedWork = true

        // SURV-01 (리뷰 2026-08-26): 복구 프로젝트가 참조하는 원본 중 이
        // 기기에 없는 파일은 표면화 — 조용히 빈 클립으로 재생되는 대신
        // relink 배너가 재배치를 안내한다(2차).
        let missingMedia = missingMediaAssets
        if !missingMedia.isEmpty {
            lastErrorMessage = "\(missingMedia.count) imported media file(s) are missing from this device. Use Relink to relocate them."
        }
        cleanupStaleImports()
    }

    /// SURV-01 2차: the stale-imports policy — per-project import
    /// directories that no live project references AND that sat untouched
    /// past the grace period are removed. Runs after the recovery attempt so
    /// a project being recovered on THIS launch (already installed as
    /// `currentProject`) is always kept.
    func cleanupStaleImports() {
        ProjectStore.cleanupOrphanedImports(
            importsRoot: importsRootDirectory,
            keepingProjectIds: [currentProject.id]
        )
    }

    /// Clears the recovery file (clean quit semantics).
    func clearRecoveryAutosave() async {
        await projectStore.clearAutosave()
    }

    /// BUG-IOS-06: the ONE file-based photo/video import path. Both picker
    /// surfaces (the top bar and the media browser) previously each had their
    /// own copy — the browser's loaded the ENTIRE asset into memory
    /// (`loadTransferable(Data.self)` — a 4K video could OOM) and swallowed
    /// every failure. Requests a FILE URL, streams a 1 MiB-buffered copy into
    /// the managed imports directory, imports through the validated probe,
    /// and adds the clip to the timeline. Failures surface through
    /// `lastErrorMessage`.
    func importFromPhotosPicker(_ item: PhotosPickerItem) async {
        guard let stagedURL = try? await item.loadTransferable(type: URL.self) else {
            lastErrorMessage = "The selected item couldn't be loaded. Try picking it again."
            return
        }

        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension
            ?? (stagedURL.pathExtension.isEmpty ? "mov" : stagedURL.pathExtension)
        // SURV-01 (리뷰 2026-08-26): 임시 디렉터리 대신 관리 Imports 영역
        // (Application Support/MovieCut/Imports/<projectId>/)으로 복사 —
        // OS가 임시 파일을 정리하면 복구 프로젝트만 남고 원본이 사라졌다.
        let fileURL = stagedImportDestination(fileExtension: fileExtension)

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.copyFileBuffered(from: stagedURL, to: fileURL)
            await importMedia(from: fileURL, kind: Self.mediaKind(for: fileExtension))
            if var importedAsset = mediaAssets.first(where: { $0.originalURL == fileURL }) {
                // SURV-01 2차: stamp the imports-root-relative reference so a
                // later container move (reinstall/restore) rebases the URL
                // instead of losing the media. Only meaningful under the
                // managed root — the temp fallback keeps absolute-only.
                if importsRootDirectory != nil {
                    importedAsset.managedImportPath = "\(currentProject.id.uuidString)/\(fileURL.lastPathComponent)"
                    try? await session.dispatch(UpdateMediaAssetCommand(asset: importedAsset))
                    await refreshFromSession()
                }
                await addClipToTimeline(asset: importedAsset)
            }
        } catch {
            lastErrorMessage = "Couldn't import the selected media: \(error.localizedDescription)"
        }
    }

    /// SURV-01 2차: re-links a missing media asset from a user-picked
    /// replacement. The picked file is copied INTO the managed imports root
    /// (so the relinked original survives like any staged import), the
    /// asset's UUID is kept so clip references survive, and the relative
    /// reference is stamped for future rebases. Mac `relinkMedia` parity.
    func relinkMedia(_ asset: MediaAsset, to replacementURL: URL) async -> Bool {
        do {
            // The picker hands out security-scoped URLs; the copy must run
            // inside the scope.
            let didStartAccess = replacementURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess {
                    replacementURL.stopAccessingSecurityScopedResource()
                }
            }
            let fileExtension = replacementURL.pathExtension.isEmpty
                ? "mov"
                : replacementURL.pathExtension
            let destination = stagedImportDestination(fileExtension: fileExtension)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.copyFileBuffered(from: replacementURL, to: destination)

            var relocated = try MediaImporter.validatedProbe(url: destination)
            relocated.id = asset.id
            relocated.duration = relocated.duration ?? asset.duration
            if importsRootDirectory != nil {
                relocated.managedImportPath = "\(currentProject.id.uuidString)/\(destination.lastPathComponent)"
            }
            try await session.dispatch(UpdateMediaAssetCommand(asset: relocated))
            await refreshFromSession()
            if missingMediaAssets.isEmpty {
                lastErrorMessage = nil
            }
            return true
        } catch {
            lastErrorMessage = "Couldn't relink the selected media: \(error.localizedDescription)"
            return false
        }
    }

    /// SURV-01: 관리 임포트 복사 목적지 — 프로젝트별 하위 디렉터리 안의
    /// 고유 파일명. App Support를 쓸 수 없는 극단적 환경은 임시 폴더로
    /// 폴백(기존 동작).
    func stagedImportDestination(fileExtension: String) -> URL {
        let root = importsRootDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSImports", isDirectory: true)
        return root
            .appendingPathComponent(currentProject.id.uuidString, isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
    }

    /// Streams a file copy in bounded chunks so a large 4K video never has to
    /// fit in memory.
    private static func copyFileBuffered(from source: URL, to destination: URL) throws {
        let chunkSize = 1024 * 1024
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.closeFile()
            try? output.closeFile()
        }
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            try output.write(contentsOf: chunk)
        }
    }

    static func mediaKind(for fileExtension: String) -> MediaKind {
        let imageExtensions = ["heic", "jpeg", "jpg", "png", "tif", "tiff", "webp"]
        return imageExtensions.contains(fileExtension.lowercased()) ? .image : .video
    }

    /// UX-REC-02: discard the silently-restored recovery and start fresh.
    /// The launch restore previously had no discard option — an old recovery
    /// file was adopted with no way back to a blank project.
    func discardRecoveredProject() async {
        let project = Self.defaultProject()
        session = EditorSession(project: project)
        currentProject = project
        selectedClipId = nil
        playheadTime = 0
        isPlaying = false
        recoveredUnsavedWork = false
        lastErrorMessage = nil
        await clearRecoveryAutosave()
    }

    /// AUTOSAVE-02: serialized autosave coordinator. The old fire-and-forget
    /// Task per commit had NO ordering guarantee — under rapid edits a STALE
    /// snapshot could land last and win. Every save is enqueued onto one
    /// serial worker that always writes the LATEST snapshot; per-save state
    /// updates (success clears the warning, failure sets it) only apply when
    /// that save was still the newest — a newer edit supersedes them.
    @ObservationIgnored private var autosaveGeneration = 0
    @ObservationIgnored private var autosaveWorker: Task<Void, Never>?

    private func scheduleAutosave() {
        autosaveGeneration &+= 1
        let generation = autosaveGeneration
        let snapshot = currentProject

        autosaveWorker?.cancel()
        autosaveWorker = Task { [projectStore, weak self] in
            // Debounce: coalesce bursts of commits into one write.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            do {
                try await projectStore.saveAutosave(snapshot)
                await MainActor.run {
                    guard let self, self.autosaveGeneration == generation else { return }
                    self.autosaveSaveSucceeded()
                }
            } catch {
                let classified = FileOperationError.classify(error)
                await MainActor.run {
                    guard let self, self.autosaveGeneration == generation else { return }
                    self.autosaveSaveFailed(classified)
                }
            }
        }
    }

    private func autosaveSaveSucceeded() {
        guard autosaveFailureMessage != nil else { return }
        autosaveFailureMessage = nil
    }

    /// 리뷰 2026-08-26 (Phase 2): scenePhase background 진입 시 즉시 flush —
    /// 150ms 디바운스는 서스펜션 중 절대 발화하지 않으므로, 대기 중인 편집이
    /// OS eviction에서 실종된다. 디바운스를 취소하고 최신 스냅샷을 바로 기록.
    func flushAutosave() async {
        guard autosaveWorker != nil else { return }
        autosaveWorker?.cancel()
        autosaveWorker = nil
        autosaveGeneration &+= 1
        let generation = autosaveGeneration
        let snapshot = currentProject
        do {
            try await projectStore.saveAutosave(snapshot)
            if autosaveGeneration == generation {
                autosaveSaveSucceeded()
            }
        } catch {
            let classified = FileOperationError.classify(error)
            if autosaveGeneration == generation {
                autosaveSaveFailed(classified)
            }
        }
    }

    private func autosaveSaveFailed(_ failure: FileOperationError) {
        autosaveFailureMessage = failure.userMessage
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

    /// A recovered project keeps its timeline; missing default tracks are
    /// re-seeded the same way the Mac launch path does.
    private static func defaultProjectIfEmpty(_ project: Project) -> Project {
        var project = project
        if !project.timeline.tracks.contains(where: { $0.kind == .video }) {
            project.timeline.tracks.append(Track(kind: .video, name: "Video", zIndex: 0))
        }
        if !project.timeline.tracks.contains(where: { $0.kind == .audio }) {
            project.timeline.tracks.append(Track(kind: .audio, name: "Audio", zIndex: 1))
        }
        return project
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

    /// CA-08: applies a built-in subtitle style preset to the SELECTED text
    /// clip (Mac `applySubtitleStylePreset` parity). The preset configures
    /// font/color/stroke/background/position/karaoke highlight in one tap —
    /// text, word timings, karaoke flag, and animation stay with the clip.
    func applySubtitleStylePreset(_ preset: SubtitleStylePreset) async {
        guard let selectedClipId,
              let clip = currentProject.timeline.tracks
                  .flatMap(\.clips)
                  .first(where: { $0.id == selectedClipId }),
              var textContent = clip.textContent else {
            lastErrorMessage = "Select a text clip before applying a style preset."
            return
        }

        let canvasSize = currentProject.canvas.size
        textContent = preset.applying(to: textContent, canvasSize: canvasSize)
        await apply(SetClipPropertyCommand(clipId: selectedClipId, property: .textContent(textContent)))
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

    /// STICKER-01 (리뷰 2026-08-26): iOS 스티커 선택이 입력을 버리지 않고
    /// 타임라인에 스티커 클립을 추가한다. Mac addSticker 패리티 — emoji
    /// 스티커 우선(이미지 지원 스티커는 Mac 전용 StickerImageProvider 포트
    /// 전까지 미지원).
    func addSticker(_ sticker: StickerAsset) async {
        let stickerText = sticker.emoji ?? sticker.name
        guard !stickerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

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

            let duration: TimeInterval = 3
            let canvasSize = currentProject.canvas.size
            let placement = CanvasGeometry.defaultStickerPlacement(for: sticker)
            let stickerPosition = CGPoint(
                x: canvasSize.width * placement.xRatio,
                y: canvasSize.height * placement.yRatio
            )
            let content = TextClipContent(
                text: stickerText,
                fontFamily: "Apple Color Emoji",
                fontSize: max(84, min(Double(canvasSize.width), Double(canvasSize.height)) * placement.fontScale),
                fontColor: "#FFFFFF",
                alignment: .center,
                position: stickerPosition,
                animation: TextAnimation(preset: .popIn, duration: 0.25),
                contentKind: .sticker,
                stickerAssetID: sticker.id,
                stickerImageURL: nil
            )
            let clip = Clip(
                assetId: nil,
                kind: .text,
                sourceRange: TimeRange(start: 0, duration: duration),
                timelineRange: TimeRange(start: playheadTime, duration: duration),
                transform: ClipTransform(
                    position: stickerPosition,
                    scale: CGSize(width: placement.transformScale, height: placement.transformScale)
                ),
                textContent: content
            )

            try await session.dispatch(AddClipCommand(trackId: track.id, clip: clip))
            selectedClipId = clip.id
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// CA-17: exports timeline text clips as a subtitle sidecar file
    /// (SRT or VTT). Uses the same `SubtitleDocument` serializer the Mac
    /// consumes, so the output is byte-identical across platforms.
    /// Returns the written file URL, or nil when no text clips exist.
    @discardableResult
    func exportSubtitles(format: SubtitleExportFormat) -> URL? {
        let segments = timelineSubtitleSegments()
        guard !segments.isEmpty else {
            lastErrorMessage = "There are no text clips to export as subtitles."
            lastSubtitleExportURL = nil
            return nil
        }

        let content: String
        switch format {
        case .srt:
            content = SubtitleDocument.srtString(from: segments)
        case .vtt:
            content = SubtitleDocument.vttString(from: segments)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCut-Subtitles")
            .appendingPathExtension(format.rawValue)

        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            lastSubtitleExportURL = url
            lastErrorMessage = nil
            return url
        } catch {
            lastErrorMessage = "Failed to write subtitles: \(error.localizedDescription)"
            lastSubtitleExportURL = nil
            return nil
        }
    }

    /// CA-17: the subtitle segment set derived from timeline TEXT-track
    /// clips (stickers excluded) — the same derivation the Mac export uses.
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
        // BUG-IOS-01: route through the session command — the previous direct
        // `currentProject.canvas = preset` mutation was invisible to the
        // EditorSession, so the next dispatch or undo reverted it.
        do {
            try await session.dispatch(SetProjectCanvasCommand(canvas: preset))
            await refreshFromSession()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
