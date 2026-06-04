import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct MediaLibraryPanel: View {
    var viewModel: EditorViewModel
    @State private var isAddingText = false
    @State private var textClipText = NSLocalizedString("Text", comment: "")
    @State private var selectedLibraryTab: LibraryTab = .media

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("Library", comment: ""))
                    .font(.headline)
                Spacer()
                if selectedLibraryTab == .media {
                    Button(action: openImportPanel) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(NSLocalizedString("Import", comment: ""))
                    .accessibilityHint(NSLocalizedString("Opens a file picker to import media.", comment: ""))
                    Button(action: openTextSheet) {
                        Image(systemName: "textformat")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(NSLocalizedString("Add Text", comment: ""))
                    .accessibilityHint(NSLocalizedString("Creates a new text clip.", comment: ""))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Picker(NSLocalizedString("Library", comment: ""), selection: $selectedLibraryTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .accessibilityLabel(NSLocalizedString("Library", comment: ""))

            switch selectedLibraryTab {
            case .media:
                mediaContent

                if viewModel.selectedAsset != nil {
                    Button(NSLocalizedString("Add to Timeline", comment: "")) {
                        Task { await viewModel.addClipToTimeline() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .accessibilityLabel(NSLocalizedString("Add to Timeline", comment: ""))
                    .accessibilityHint(NSLocalizedString("Adds the selected library asset to the timeline.", comment: ""))
                }
            case .stickers:
                StickerPickerView { sticker in
                    Task { await viewModel.addSticker(sticker) }
                }
            case .music:
                MusicLibraryView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 200)
        .background(Color(nsColor: .controlBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Library", comment: ""))
        .accessibilityHint(NSLocalizedString("Drop media files here to import them.", comment: ""))
        .sheet(isPresented: $isAddingText) {
            VStack(alignment: .leading, spacing: 12) {
                Text(NSLocalizedString("Add Text", comment: ""))
                    .font(.headline)
                TextField(NSLocalizedString("Text", comment: ""), text: $textClipText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .accessibilityLabel(NSLocalizedString("Text", comment: ""))
                HStack {
                    Spacer()
                    Button(NSLocalizedString("Cancel", comment: "")) {
                        isAddingText = false
                    }
                    .accessibilityLabel(NSLocalizedString("Cancel", comment: ""))
                    Button(NSLocalizedString("Add", comment: "")) {
                        let text = textClipText
                        isAddingText = false
                        Task { await viewModel.addTextClip(text: text) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(NSLocalizedString("Add", comment: ""))
                    .accessibilityHint(NSLocalizedString("Adds the text clip to the timeline.", comment: ""))
                }
            }
            .padding(16)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.mediaAssets.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("Drop media files here", comment: ""))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(NSLocalizedString("Drop media files here", comment: ""))
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
                                    Text(String(format: NSLocalizedString("%.1fs", comment: ""), duration))
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
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(asset.originalURL.lastPathComponent)
                        .accessibilityValue(assetAccessibilityValue(asset))
                        .accessibilityHint(NSLocalizedString("Selects this asset in the media library.", comment: ""))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction {
                            viewModel.selectedAssetId = asset.id
                        }
                    }
                }
                .padding(4)
            }
            .accessibilityLabel(NSLocalizedString("Asset List", comment: ""))
        }
    }

    private func openTextSheet() {
        textClipText = NSLocalizedString("Text", comment: "")
        isAddingText = true
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

    private func assetAccessibilityValue(_ asset: MediaAsset) -> String {
        let kindName = String(describing: asset.kind)
        if let duration = asset.duration {
            return String(format: NSLocalizedString("%@, duration %@", comment: ""), kindName, String(format: NSLocalizedString("%.1fs", comment: ""), duration))
        }
        return kindName
    }
}

private enum LibraryTab: CaseIterable, Identifiable {
    case media
    case stickers
    case music

    var id: Self { self }

    var displayName: String {
        switch self {
        case .media:
            return NSLocalizedString("Media", comment: "")
        case .stickers:
            return NSLocalizedString("Stickers", comment: "")
        case .music:
            return NSLocalizedString("Music", comment: "")
        }
    }
}
