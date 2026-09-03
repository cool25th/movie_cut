#if os(iOS)
import AVFoundation
import MovieCutCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct IOSContentView: View {
    @State private var viewModel = IOSEditorViewModel()
    // 리뷰 2026-08-26 (Phase 2): background 진입 시 즉시 autosave flush —
    // 디바운스 대기 중 서스펜션되면 편집이 실종된다.
    @Environment(\.scenePhase) private var scenePhase
    // SURV-01 2차: missing-originals relink — the banner offers relocation,
    // the importer picks the replacement for the first missing asset.
    @State private var isRelinkImporterPresented = false
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var isMediaBrowserPresented = false
    @State private var isInspectorPresented = false
    @State private var isExportProgressPresented = false
    @State private var isExportResultPresented = false
    @State private var isExportErrorPresented = false
    @State private var didCancelExport = false
    // UX-REC-02: launch recovery prompt — offer Keep/Discard for restored work.
    @State private var isRecoveryPromptPresented = false
    // CA-17: subtitle export format picker.
    @State private var isSubtitleFormatPickerPresented = false
    @State private var exportErrorMessage: String?
    @State private var isImporting = false
    @State private var isTextClipPresented = false
    @State private var isFilterPickerPresented = false
    @State private var isStickerPickerPresented = false
    @State private var isChromaKeyPresented = false
    @State private var isMaskCanvasPresented = false
    @State private var isKeyframeEditorPresented = false
    @State private var isMusicLibraryPresented = false
    @State private var isSFXPickerPresented = false
    @State private var isVoiceoverPresented = false
    // CA-14: beat detection action sheet (Detect / Clear) — Mac parity entry.
    @State private var isBeatActionPresented = false
    // Review P0: the Trim entry was a no-op closure — real playhead trims.
    @State private var isTrimActionPresented = false
    // Phase-1 (review #3): project open/save + export settings + tracks.
    @State private var isProjectOpenPickerPresented = false
    @State private var isProjectSaveExporterPresented = false
    @State private var isExportSettingsPresented = false
    @State private var isTrackManagerPresented = false
    @State private var projectSaveURL: URL? = nil
    @State private var isAutoSubtitlesPresented = false
    @State private var isAutoAssistantPresented = false
    @State private var isTemplatePickerPresented = false
    @State private var isCanvasSettingsPresented = false
    @State private var isEffectsInspectorPresented = false

    private var resolvedExportErrorMessage: String {
        exportErrorMessage ?? "MovieCut could not export this project."
    }

    private var selectedClipForSheets: Clip? {
        guard let clipId = viewModel.selectedClipId else { return nil }
        for track in viewModel.currentProject.timeline.tracks {
            if let clip = track.clips.first(where: { $0.id == clipId }) {
                return clip
            }
        }
        return nil
    }

    /// CA-17: whether any non-sticker text clip exists on the timeline —
    /// controls the subtitle export menu's enabled state.
    private var hasExportableSubtitles: Bool {
        viewModel.currentProject.timeline.tracks.contains { track in
            track.kind == .text && track.clips.contains { clip in
                clip.textContent?.contentKind != .sticker
            }
        }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                VStack(spacing: 0) {
                    PreviewView(viewModel: viewModel)
                        .frame(maxWidth: .infinity)
                        .frame(height: max(240, proxy.size.height * 0.38))
                        .background(Color.black)

                    Divider()

                    VStack(spacing: 0) {
                        playheadBar

                        IOSTimelineView(viewModel: viewModel) {
                            isInspectorPresented = true
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        bottomToolbar
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .systemBackground))
                }
            }
            .navigationTitle(viewModel.currentProject.name)
            .navigationBarTitleDisplayMode(.inline)
            // 리뷰 2026-08-26 (Phase 2): leaving the foreground must flush the
            // pending autosave immediately — the debounce never fires while
            // suspended.
            .onChange(of: scenePhase) { _, phase in
                if phase == .background || phase == .inactive {
                    Task { await viewModel.flushAutosave() }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        Task { await viewModel.undo() }
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .accessibilityLabel("Undo")

                    Button {
                        Task { await viewModel.redo() }
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .accessibilityLabel("Redo")
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    PhotosPicker(selection: $selectedPhotosItem, matching: .any(of: [.videos, .images])) {
                        Image(systemName: "photo.on.rectangle")
                    }
                    .disabled(isImporting)
                    .accessibilityLabel("Import Media")

                    Button {
                        isInspectorPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Inspector")

                    Menu {
                        // Phase-1 (review #3): project open/save + export
                        // presets — the engine paths existed, no UI reached
                        // them.
                        Button {
                            isProjectOpenPickerPresented = true
                        } label: {
                            Label("Open Project…", systemImage: "folder")
                        }

                        Button {
                            isProjectSaveExporterPresented = true
                        } label: {
                            Label("Save Project", systemImage: "square.and.arrow.down")
                        }
                        .disabled(viewModel.currentProject.timeline.duration <= 0
                                  && viewModel.currentProject.mediaLibrary.assets.isEmpty)

                        Button {
                            isExportSettingsPresented = true
                        } label: {
                            Label("Export Settings", systemImage: "switch.2")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Project and export options")

                    Button {
                        Task { await startExport() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(viewModel.isExporting || viewModel.currentProject.timeline.duration <= 0)
                    .accessibilityLabel("Export")

                    if let exportURL = viewModel.lastExportURL {
                        ShareLink(item: exportURL) {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                        .accessibilityLabel("Share Export")
                    } else if let subtitleURL = viewModel.lastSubtitleExportURL {
                        // CA-17: share the subtitle sidecar when it's the
                        // latest export artifact.
                        ShareLink(item: subtitleURL) {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                        .accessibilityLabel("Share Subtitle Export")
                    } else {
                        Button {} label: {
                            Image(systemName: "square.and.arrow.up.on.square")
                        }
                        .disabled(true)
                        .accessibilityLabel("Share Export")
                    }
                }
            }
            .sheet(isPresented: $isMediaBrowserPresented) {
                NavigationStack {
                    MediaBrowserView(viewModel: viewModel)
                        .navigationTitle("Media")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isInspectorPresented) {
                IOSInspectorSheet(viewModel: viewModel)
                    .presentationDetents([.height(300), .medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task {
                // BUG-IOS-02: restore crash-recovery autosave BEFORE the
                // harness or user interaction — work from a terminated or
                // evicted session survives launches now.
                if ProcessInfo.processInfo.environment["MOVIECUT_UITEST"] != "1" {
                    await viewModel.restoreAutosaveIfAvailable()
                }
                // G-27 simulator E2E: env-gated harness (no-op in normal
                // launches) — drives the real import/preview/export/audio/
                // persistence paths and reports to Documents/g27-result.txt.
                await IOSUITestHarness.runIfRequested(viewModel: viewModel)
                // UX-REC-02: the restore above adopts silently — offer the
                // user an explicit choice to keep or discard the recovered
                // work (the old recovery file may be stale).
                if viewModel.recoveredUnsavedWork {
                    isRecoveryPromptPresented = true
                }
            }
            // AUTOSAVE-02: surface a failing crash-recovery autosave —
            // editing continues, but the user must know backups stopped.
            .overlay(alignment: .top) {
                if let autosaveWarning = viewModel.autosaveFailureMessage {
                    Label(
                        title: { Text(autosaveWarning).font(.caption) },
                        icon: { Image(systemName: "exclamationmark.triangle.fill") }
                    )
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .accessibilityLabel(Text(NSLocalizedString("Autosave failure warning", comment: "")))
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                // SURV-01 2차: originals missing from this device — offer
                // in-place relink instead of silently playing empty clips.
                else if let firstMissing = viewModel.missingMediaAssets.first {
                    HStack(spacing: 8) {
                        Label(
                            title: {
                                Text(String(
                                    format: NSLocalizedString(
                                        "%d media file(s) missing — clips will play empty until relinked",
                                        comment: "SURV-01 banner over the editor"
                                    ),
                                    viewModel.missingMediaAssets.count
                                ))
                                .font(.caption)
                            },
                            icon: { Image(systemName: "questionmark.square.dashed") }
                        )
                        Button(NSLocalizedString("Relink", comment: "SURV-01 banner action")) {
                            isRelinkImporterPresented = true
                        }
                        .font(.caption.bold())
                    }
                    .foregroundStyle(.orange)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(Text(NSLocalizedString("Missing media relink banner", comment: "")))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .id(firstMissing.id)
                }
            }
            .fileImporter(
                isPresented: $isRelinkImporterPresented,
                allowedContentTypes: [.movie, .video, .audio, .image],
                allowsMultipleSelection: false
            ) { result in
                guard case .success(let urls) = result, let replacement = urls.first,
                      let missing = viewModel.missingMediaAssets.first else {
                    return
                }
                Task { await viewModel.relinkMedia(missing, to: replacement) }
            }
            .alert(
                NSLocalizedString("Recovered unsaved work", comment: ""),
                isPresented: $isRecoveryPromptPresented
            ) {
                Button(NSLocalizedString("Keep", comment: "")) {
                    viewModel.recoveredUnsavedWork = false
                }
                Button(NSLocalizedString("Discard", comment: ""), role: .destructive) {
                    Task { await viewModel.discardRecoveredProject() }
                }
            } message: {
                Text(NSLocalizedString(
                    "MovieCut restored your last session. Keep the recovered project, or discard it and start fresh?",
                    comment: ""
                ))
            }
            .sheet(isPresented: $isExportProgressPresented) {
                IOSExportProgressSheet(
                    progress: viewModel.exportProgress,
                    cancelAction: {
                        didCancelExport = true
                        viewModel.cancelExport()
                        isExportProgressPresented = false
                    }
                )
                .presentationDetents([.height(220)])
                .interactiveDismissDisabled(viewModel.isExporting)
            }
            .sheet(isPresented: $isExportResultPresented) {
                if let exportURL = viewModel.lastExportURL {
                    IOSExportResultSheet(exportURL: exportURL)
                        .presentationDetents([.height(240)])
                }
            }
            .alert("Export Failed", isPresented: $isExportErrorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(resolvedExportErrorMessage)
            }
            .sheet(isPresented: $isTextClipPresented) {
                IOSTextClipSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isFilterPickerPresented) {
                IOSFilterPickerView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isStickerPickerPresented) {
                stickerPickerSheet
            }
            .sheet(isPresented: $isMusicLibraryPresented) {
                musicLibrarySheet
            }
            .sheet(isPresented: $isSFXPickerPresented) {
                sfxPickerSheet
            }
            // CA-14: Detect/Clear beat markers on the selected clip. Clear
            // stays available whenever beat markers exist even if the
            // current selection cannot run a new detection.
            // Phase-1 (review #3): project open — the shared Core ProjectStore
            // codec (.moviecut), wholesale replacement via ReplaceProjectCommand.
            .fileImporter(
                isPresented: $isProjectOpenPickerPresented,
                allowedContentTypes: [moviecutType],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    // STAB-03③: the security scope must stay open for the
                    // WHOLE async load — a `defer` in this synchronous
                    // callback fires right after the Task is scheduled, so
                    // Files/iCloud-backed URLs lose access before
                    // ProjectStore.load reaches them.
                    Task {
                        let secured = url.startAccessingSecurityScopedResource()
                        defer { if secured { url.stopAccessingSecurityScopedResource() } }
                        await viewModel.openProject(from: url)
                    }
                }
            }
            // Phase-1 (review #3): project save — default filename from the
            // project name, .moviecut extension enforced by the exporter.
            .fileExporter(
                isPresented: $isProjectSaveExporterPresented,
                document: MovieCutProjectDocument(project: viewModel.currentProject),
                contentType: moviecutType,
                defaultFilename: viewModel.currentProject.name
            ) { result in
                // STAB-03④: on success the exporter has ALREADY written the
                // document — re-saving through saveProject(to:) writes the
                // same URL a second time and can surface a spurious failure
                // for a save that succeeded.
                if case .failure(let error) = result {
                    viewModel.lastErrorMessage = "Could not save project: \(error.localizedDescription)"
                }
            }
            .sheet(isPresented: $isExportSettingsPresented) {
                exportSettingsSheet
            }
            .sheet(isPresented: $isTrackManagerPresented) {
                trackManagerSheet
            }
            // Review P0: playhead-relative trims on the selected clip — the
            // engine math existed but no UI reached it.
            .confirmationDialog(
                "Trim Clip",
                isPresented: $isTrimActionPresented,
                titleVisibility: .visible
            ) {
                Button("Trim Start to Playhead") {
                    Task { await viewModel.trimSelectedClipStartToPlayhead() }
                }
                Button("Trim End to Playhead") {
                    Task { await viewModel.trimSelectedClipEndToPlayhead() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Moves the selected clip's start or end to the playhead. Undo reverts the whole trim.")
            }
            .confirmationDialog(
                "Beat Markers",
                isPresented: $isBeatActionPresented,
                titleVisibility: .visible
            ) {
                Button("Detect Beats") {
                    Task { await viewModel.detectBeats() }
                }
                if viewModel.hasBeatMarkers {
                    Button("Clear Beat Markers", role: .destructive) {
                        Task { await viewModel.clearBeatMarkers() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adds beat markers to the selected audio or video clip. Clips snap to beats while dragging.")
            }
            .sheet(isPresented: $isVoiceoverPresented) {
                voiceoverSheet
            }
            .sheet(isPresented: $isAutoSubtitlesPresented) {
                autoSubtitlesSheet
            }
            .sheet(isPresented: $isAutoAssistantPresented) {
                autoAssistantSheet
            }
            .sheet(isPresented: $isTemplatePickerPresented) {
                templatePickerSheet
            }
            .sheet(isPresented: $isCanvasSettingsPresented) {
                canvasSettingsSheet
            }
            .sheet(isPresented: $isChromaKeyPresented) {
                chromaKeySheet
            }
            .sheet(isPresented: $isMaskCanvasPresented) {
                maskCanvasSheet
            }
            .sheet(isPresented: $isEffectsInspectorPresented) {
                effectsInspectorSheet
            }
            .sheet(isPresented: $isKeyframeEditorPresented) {
                keyframeEditorSheet
            }
            // CA-17: subtitle export format picker — SRT or VTT.
            .confirmationDialog(
                "Export Subtitles",
                isPresented: $isSubtitleFormatPickerPresented,
                titleVisibility: .visible
            ) {
                Button("SubRip (.srt)") {
                    viewModel.exportSubtitles(format: .srt)
                }
                Button("WebVTT (.vtt)") {
                    viewModel.exportSubtitles(format: .vtt)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose a subtitle file format. The file will appear in the share button above.")
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.lastErrorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.lastErrorMessage ?? "An unknown error occurred.")
            }
            .onChange(of: selectedPhotosItem) { _, newItem in
                guard let newItem else { return }

                Task {
                    isImporting = true
                    await importPhotosItem(newItem)
                    selectedPhotosItem = nil
                    isImporting = false
                }
            }
        }
    }

    @ViewBuilder
    private var stickerPickerSheet: some View {
        NavigationStack {
            // STICKER-01 (리뷰 2026-08-26): the selection used to be discarded
            // (`onSelect: { _ in }`) — it now lands on the timeline.
            IOSStickerPickerView(viewModel: viewModel, onSelect: { sticker in
                Task { await viewModel.addSticker(sticker) }
            })
                .navigationTitle("Stickers")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var musicLibrarySheet: some View {
        NavigationStack {
            IOSMusicLibraryView(viewModel: viewModel)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var sfxPickerSheet: some View {
        NavigationStack {
            IOSSFXPickerView(viewModel: viewModel)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var voiceoverSheet: some View {
        NavigationStack {
            IOSVoiceoverRecordingView(viewModel: viewModel)
                .navigationTitle("Voiceover")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var autoSubtitlesSheet: some View {
        NavigationStack {
            IOSAutoSubtitlesView(viewModel: viewModel)
                .navigationTitle("Auto Subtitles")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var autoAssistantSheet: some View {
        NavigationStack {
            IOSAutoAssistantView(viewModel: viewModel)
                .navigationTitle("AI Assistant")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var templatePickerSheet: some View {
        NavigationStack {
            IOSTemplatePickerView(viewModel: viewModel)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var canvasSettingsSheet: some View {
        NavigationStack {
            IOSCanvasSettingsView(
                canvas: viewModel.currentProject.canvas,
                onChange: { newPreset in
                    Task { await viewModel.updateCanvasPreset(newPreset) }
                }
            )
            .navigationTitle("Canvas Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var chromaKeySheet: some View {
        if let clip = selectedClipForSheets {
            NavigationStack {
                IOSChromaKeyView(clip: clip) { chromaKey in
                    Task { await viewModel.updateSelectedChromaKey(chromaKey) }
                }
                .navigationTitle("Chroma Key")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var maskCanvasSheet: some View {
        if let clip = selectedClipForSheets {
            NavigationStack {
                IOSMaskCanvasView(
                    mask: Binding(
                        get: { clip.mask },
                        set: { newMask in
                            Task { await viewModel.updateSelectedMask(newMask) }
                        }
                    ),
                    canvasSize: viewModel.currentProject.canvas.size
                )
                .navigationTitle("Mask")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var effectsInspectorSheet: some View {
        if let clip = selectedClipForSheets {
            NavigationStack {
                IOSEffectsInspectorView(viewModel: viewModel, clip: clip)
                    .navigationTitle("Effects")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var keyframeEditorSheet: some View {
        if let clip = selectedClipForSheets {
            NavigationStack {
                IOSKeyframeEditorView(
                    clip: clip,
                    playheadTime: viewModel.playheadTime,
                    selectedKeyframeId: nil,
                    onSelect: { _ in },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )
                .navigationTitle("Keyframes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    @MainActor
    private func startExport() async {
        guard !viewModel.isExporting else { return }

        didCancelExport = false
        isExportProgressPresented = true
        exportErrorMessage = nil

        do {
            _ = try await viewModel.exportProject()
            isExportProgressPresented = false
            isExportResultPresented = viewModel.lastExportURL != nil
        } catch {
            isExportProgressPresented = false

            guard !didCancelExport else {
                return
            }

            exportErrorMessage = error.localizedDescription
            isExportErrorPresented = true
        }
    }

    private var playheadBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(timeString(viewModel.playheadTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)

                Spacer()

                Text(timeString(viewModel.currentProject.timeline.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: Binding(
                    get: { viewModel.playheadTime },
                    set: { viewModel.playheadTime = clampedPlayhead($0) }
                ),
                in: 0...max(viewModel.currentProject.timeline.duration, 0.1)
            )
            .tint(.primary)
            .frame(minHeight: 32)
            .accessibilityLabel("Playhead")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    /// Phase-1 (review #3): export presets — resolution + container, applied
    /// through SetProjectExportSettingsCommand (the engine's actual inputs).
    @ViewBuilder
    private var exportSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("Resolution") {
                    exportResolutionPicker
                }
                Section("Container") {
                    exportContainerPicker
                }
            }
            .navigationTitle("Export Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
        .presentationDetents([.medium])
    }

    private var exportResolutionPicker: some View {
        IOSExportOptionRow(
            options: ExportResolution.allCases,
            current: viewModel.currentProject.exportSettings.resolution
        ) { resolution in
            Task { await viewModel.updateExportSettings(resolution: resolution) }
        }
    }

    private var exportContainerPicker: some View {
        IOSExportOptionRow(
            options: ExportContainerFormat.allCases,
            current: viewModel.currentProject.exportSettings.containerFormat
        ) { format in
            Task { await viewModel.updateExportSettings(containerFormat: format) }
        }
    }

    /// Phase-1 (review #3): track management — add video/audio tracks, per
    /// track mute/lock, delete. All through real Core commands (undoable).
    @ViewBuilder
    private var trackManagerSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await viewModel.addTrack(kind: .video) }
                    } label: {
                        Label("Add Video Track", systemImage: "rectangle.stack.badge.plus")
                    }
                    Button {
                        Task { await viewModel.addTrack(kind: .audio) }
                    } label: {
                        Label("Add Audio Track", systemImage: "waveform.badge.plus")
                    }
                }
                Section("Tracks") {
                    ForEach(viewModel.currentProject.timeline.tracks) { track in
                        HStack {
                            Image(systemName: trackIconName(for: track.kind))
                                .foregroundStyle(.secondary)
                            Text(track.name)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                Task { await viewModel.setTrackMuted(track.id, !track.isMuted) }
                            } label: {
                                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(track.isMuted ? "Unmute track" : "Mute track")
                            Button {
                                Task { await viewModel.setTrackLocked(track.id, !track.isLocked) }
                            } label: {
                                Image(systemName: track.isLocked ? "lock.fill" : "lock.open")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(track.isLocked ? "Unlock track" : "Lock track")
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteTrack(track.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
        }
    }

    private func trackIconName(for kind: TrackKind) -> String {
        switch kind {
        case .video: "rectangle.on.rectangle"
        case .audio: "waveform"
        case .text: "textformat"
        }
    }

    private var bottomToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                toolbarButton(title: "Media", systemImage: "plus.rectangle.on.rectangle") {
                    isMediaBrowserPresented = true
                }

                toolbarButton(title: "Text", systemImage: "textformat") {
                    isTextClipPresented = true
                }

                toolbarButton(title: "Sticker", systemImage: "face.smiling") {
                    isStickerPickerPresented = true
                }

                toolbarButton(title: "Music", systemImage: "music.note") {
                    isMusicLibraryPresented = true
                }

                toolbarButton(title: "SFX", systemImage: "speaker.wave.2") {
                    isSFXPickerPresented = true
                }

                toolbarButton(title: "Voice", systemImage: "mic") {
                    isVoiceoverPresented = true
                }

                // CA-14: beat detection on the selected audio/video clip —
                // markers become drag snap targets (Mac parity).
                toolbarButton(title: "Beats", systemImage: "waveform") {
                    isBeatActionPresented = true
                }
                .disabled(!viewModel.canDetectBeats)

                // Phase-1 (review #3): track management (add/mute/lock/delete).
                toolbarButton(title: "Tracks", systemImage: "rectangle.stack") {
                    isTrackManagerPresented = true
                }

                Divider().frame(height: 28)

                toolbarButton(title: "Subtitles", systemImage: "captions.bubble") {
                    isSubtitleFormatPickerPresented = true
                }
                .disabled(!hasExportableSubtitles)

                toolbarButton(title: "Filter", systemImage: "wand.and.stars") {
                    isFilterPickerPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Effects", systemImage: "sparkles") {
                    isEffectsInspectorPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Chroma", systemImage: "paintpalette") {
                    isChromaKeyPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Mask", systemImage: "circle.dashed") {
                    isMaskCanvasPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                Divider().frame(height: 28)

                toolbarButton(title: "Keyframe", systemImage: "diamond") {
                    isKeyframeEditorPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Subtitles", systemImage: "captions.bubble") {
                    isAutoSubtitlesPresented = true
                }

                toolbarButton(title: "AI", systemImage: "brain") {
                    isAutoAssistantPresented = true
                }

                toolbarButton(title: "Split", systemImage: "scissors") {
                    Task { await viewModel.splitClip() }
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Trim", systemImage: "crop") {
                    isTrimActionPresented = true
                }
                .disabled(viewModel.selectedClipId == nil)

                toolbarButton(title: "Template", systemImage: "square.grid.2x2") {
                    isTemplatePickerPresented = true
                }

                toolbarButton(title: "Canvas", systemImage: "rectangle.expand.vertical") {
                    isCanvasSettingsPresented = true
                }

                toolbarButton(title: "Delete", systemImage: "trash") {
                    Task { await viewModel.deleteClip() }
                }
                .disabled(viewModel.selectedClipId == nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .frame(width: 36, height: 28)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
    }

    private func importPhotosItem(_ item: PhotosPickerItem) async {
        // BUG-IOS-06: the single shared file-based importer (on the view
        // model) — both picker surfaces route through it.
        await viewModel.importFromPhotosPicker(item)
    }

    private func clampedPlayhead(_ time: TimeInterval) -> TimeInterval {
        let duration = max(viewModel.currentProject.timeline.duration, 0)
        return min(max(0, time.isFinite ? time : 0), duration)
    }

    private func timeString(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct IOSExportProgressSheet: View {
    var progress: Double
    var cancelAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exporting")
                        .font(.headline)

                    ProgressView(value: min(max(progress, 0), 1))
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Export progress")
                        .accessibilityValue(exportProgressAccessibilityValue)
                        .accessibilityHint("This progress alone does not verify an export golden file or playback result.")

                    Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                Button("Cancel Export", role: .destructive, action: cancelAction)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Stops the running export. It does not delete previously exported files.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var exportProgressAccessibilityValue: String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded())) percent"
    }
}

private struct IOSExportResultSheet: View {
    @Environment(\.dismiss) private var dismiss

    var exportURL: URL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Label("Export Complete", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Export complete")
                    .accessibilityValue(exportURL.lastPathComponent)
                    .accessibilityHint("The file was written by the export engine. Share it after playback review if you need export golden evidence.")

                Text(exportURL.lastPathComponent)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityHidden(true)

                ShareLink(item: exportURL) {
                    Label("Share Movie", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Share exported movie")
                .accessibilityValue(exportURL.lastPathComponent)
                .accessibilityHint("Opens the iOS share sheet for the latest export file. This does not confirm playback sync or export golden verification.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DismissButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Done") { dismiss() }
    }
}

/// Phase-1 (review #3): a bordered option row for the export settings sheet
/// (resolution / container). A standalone generic view keeps the big content
/// view's type-checking flat — inline modifier chains timed out the checker.
private struct IOSExportOptionRow<Option: Hashable>: View {
    let options: [Option]
    let current: Option
    let onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(label(for: option)) {
                    onSelect(option)
                }
                .buttonStyle(.bordered)
                .tint(current == option ? .accentColor : .gray)
                .accessibilityAddTraits(current == option ? .isSelected : [])
            }
        }
    }

    private func label(for option: Option) -> String {
        if let resolution = option as? ExportResolution {
            return resolution.displayName
        }
        if let format = option as? ExportContainerFormat {
            return format.displayName
        }
        return String(describing: option)
    }
}

/// Phase-1 (review #3): the `.moviecut` document the fileExporter writes.
/// Encodes with the SAME codec discipline as ProjectStore.save (ISO8601
/// dates, pretty-printed sorted keys) so saved files load on both platforms
/// and round-trip through the migration chain.
struct MovieCutProjectDocument: FileDocument {
    static var readableContentTypes: [UTType] { [moviecutType] }

    let project: Project

    init(project: Project) {
        self.project = project
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        project = try decoder.decode(Project.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(project))
    }
}

let moviecutType = UTType(filenameExtension: "moviecut") ?? .json


#Preview {
    IOSContentView()
}
#endif
