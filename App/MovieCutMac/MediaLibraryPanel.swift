import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct MediaLibraryPanel: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Media")
                    .font(.headline)
                Spacer()
                Button(action: openImportPanel) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            if viewModel.mediaAssets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Drop media files here")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(viewModel.mediaAssets) { asset in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 48, height: 36)
                                    .overlay {
                                        Image(systemName: iconForKind(asset.kind))
                                            .foregroundStyle(.secondary)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(asset.originalURL.lastPathComponent)
                                        .lineLimit(1)
                                        .font(.caption)
                                    if let duration = asset.duration {
                                        Text(String(format: "%.1fs", duration))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(6)
                            .background(asset.id == viewModel.selectedAssetId ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectedAssetId = asset.id
                            }
                        }
                    }
                    .padding(4)
                }
            }

            if viewModel.selectedAsset != nil {
                Button("Add to Timeline") {
                    Task { await viewModel.addClipToTimeline() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    private func openImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        let types = [UTType.movie, UTType.video, UTType.audio, UTType.image]
        panel.allowedContentTypes = types
        if panel.runModal() == .OK {
            let urls = panel.urls
            Task { @MainActor in
                await viewModel.importMedia(urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    await viewModel.importMedia([url])
                }
            }
        }
    }

    private func iconForKind(_ kind: MediaKind) -> String {
        switch kind {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }
}
