#if os(iOS)
import AVFoundation
import MovieCutCore
import PhotosUI
import SwiftUI

struct IOSContentView: View {
    @State private var viewModel = IOSEditorViewModel()
    @State private var selectedPhotosItem: PhotosPickerItem?
    @State private var isMediaBrowserPresented = false
    @State private var isInspectorPresented = false
    @State private var isExportProgressPresented = false
    @State private var isExportResultPresented = false
    @State private var isExportErrorPresented = false
    @State private var didCancelExport = false
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
    @State private var isAutoSubtitlesPresented = false
    @State private var isAutoAssistantPresented = false
    @State private var isTemplatePickerPresented = false
    @State private var isCanvasSettingsPresented = false
    @State private var isEffectsInspectorPresented = false

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
                Text(exportErrorMessage ?? "MovieCut could not export this project.")
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
            // MARK: - New Sheet Integrations
            .sheet(isPresented: $isStickerPickerPresented) {
                NavigationStack {
                    IOSStickerPickerView(viewModel: viewModel)
                        .navigationTitle("Stickers")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isMusicLibraryPresented) {
                NavigationStack {
                    IOSMusicLibraryView(viewModel: viewModel)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isSFXPickerPresented) {
                NavigationStack {
                    IOSSFXPickerView(viewModel: viewModel)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isVoiceoverPresented) {
                NavigationStack {
                    IOSVoiceoverRecordingView(viewModel: viewModel)
                        .navigationTitle("Voiceover")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isAutoSubtitlesPresented) {
                NavigationStack {
                    IOSAutoSubtitlesView(viewModel: viewModel)
                        .navigationTitle("Auto Subtitles")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isAutoAssistantPresented) {
                NavigationStack {
                    IOSAutoAssistantView(viewModel: viewModel)
                        .navigationTitle("AI Assistant")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { DismissButton() } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isTemplatePickerPresented) {
                NavigationStack {
                    IOSTemplatePickerView(viewModel: viewModel)
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $isCanvasSettingsPresented) {
                NavigationStack {
                    IOSCanvasSettingsView(
                        canvas: viewModel.currentProject.canvas.preset,
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
            .sheet(isPresented: $isChromaKeyPresented) {
                if let clipId = viewModel.selectedClipId,
                   let clip = viewModel.currentProject.timeline.allClips.first(where: { $0.id == clipId }) {
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
            .sheet(isPresented: $isMaskCanvasPresented) {
                if let clipId = viewModel.selectedClipId,
                   let clip = viewModel.currentProject.timeline.allClips.first(where: { $0.id == clipId }) {
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
            .sheet(isPresented: $isEffectsInspectorPresented) {
                if let clipId = viewModel.selectedClipId,
                   let clip = viewModel.currentProject.timeline.allClips.first(where: { $0.id == clipId }) {
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
            .sheet(isPresented: $isKeyframeEditorPresented) {
                if let clipId = viewModel.selectedClipId,
                   let clip = viewModel.currentProject.timeline.allClips.first(where: { $0.id == clipId }) {
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

                Divider().frame(height: 28)

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
                    // Trim handle is inline in timeline
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
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }

        let fileExtension = item.supportedContentTypes.first?.preferredFilenameExtension ?? "mov"
        let folderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutiOSImports", isDirectory: true)
        let fileURL = folderURL
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            await viewModel.importMedia(from: fileURL, kind: mediaKind(for: fileExtension))

            if let importedAsset = viewModel.mediaAssets.first(where: { $0.originalURL == fileURL }) {
                await viewModel.addClipToTimeline(asset: importedAsset)
            }
        } catch {
            return
        }
    }

    private func mediaKind(for fileExtension: String) -> MediaKind {
        let imageExtensions = ["heic", "jpeg", "jpg", "png", "tif", "tiff", "webp"]
        return imageExtensions.contains(fileExtension.lowercased()) ? .image : .video
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

#Preview {
    IOSContentView()
}
#endif
