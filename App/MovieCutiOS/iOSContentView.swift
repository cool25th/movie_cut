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
    @State private var isExportUnavailablePresented = false
    @State private var isImporting = false

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
                        Task {
                            await viewModel.exportProject()
                            isExportUnavailablePresented = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export")

                    ShareLink(item: sharePlaceholderText) {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .accessibilityLabel("Share")
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
            .alert("Export is not available yet", isPresented: $isExportUnavailablePresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The iOS editor can preview and edit the timeline, but export has not been connected in this target.")
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
        HStack(spacing: 8) {
            toolbarButton(title: "Media", systemImage: "plus.rectangle.on.rectangle") {
                isMediaBrowserPresented = true
            }

            toolbarButton(title: "Inspect", systemImage: "slider.horizontal.3") {
                isInspectorPresented = true
            }
            .disabled(viewModel.selectedClipId == nil)

            toolbarButton(title: "Split", systemImage: "scissors") {
                Task { await viewModel.splitClip() }
            }
            .disabled(viewModel.selectedClipId == nil)

            toolbarButton(title: "Delete", systemImage: "trash") {
                Task { await viewModel.deleteClip() }
            }
            .disabled(viewModel.selectedClipId == nil)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var sharePlaceholderText: String {
        "MovieCut project: \(viewModel.currentProject.name)"
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

#Preview {
    IOSContentView()
}
#endif
