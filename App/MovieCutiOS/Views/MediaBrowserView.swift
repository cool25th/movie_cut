import SwiftUI
import PhotosUI
import MovieCutCore

struct MediaBrowserView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @State private var selectedItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $selectedItem, matching: .any(of: [.videos, .images])) {
                Label("Pick Media", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            List(viewModel.mediaAssets) { asset in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(asset.originalURL.lastPathComponent)
                            .font(.headline)
                            .lineLimit(1)
                        Text(durationText(asset.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Add to Timeline") {
                        Task {
                            await viewModel.addClipToTimeline(asset: asset)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            Task {
                await importItem(item)
                selectedItem = nil
            }
        }
    }

    private func importItem(_ item: PhotosPickerItem) async {
        // BUG-IOS-06: routes through the single shared file-based importer —
        // this view's private copy loaded the ENTIRE asset into memory and
        // swallowed failures.
        await viewModel.importFromPhotosPicker(item)
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else { return "Duration unknown" }
        return String(format: "%.1fs", duration)
    }
}
