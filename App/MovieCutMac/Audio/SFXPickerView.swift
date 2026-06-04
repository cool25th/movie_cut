import AVFoundation
import SwiftUI
import MovieCutCore

struct SFXPickerView: View {
    var viewModel: EditorViewModel

    @State private var searchText = ""
    @State private var previewItemId: UUID?
    @State private var previewPlayer: AVAudioPlayer?

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search SFX", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            if groupedItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No matching SFX")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(groupedItems) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(categoryTitle(group.category))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 2)

                                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                                    ForEach(group.items) { item in
                                        SFXItemButton(
                                            item: item,
                                            isPreviewing: isPreviewing(item),
                                            previewAction: { togglePreview(for: item) },
                                            addAction: {
                                                Task { await viewModel.addSFXToTimeline(item) }
                                            }
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .onDisappear {
            stopPreview()
        }
    }

    private var filteredItems: [SFXItem] {
        SFXLibrary.search(query: searchText)
    }

    private var groupedItems: [SFXCategoryGroup] {
        let grouped = Dictionary(grouping: filteredItems, by: \.category)
        return categoryOrder.compactMap { category in
            guard let items = grouped[category], !items.isEmpty else {
                return nil
            }
            return SFXCategoryGroup(category: category, items: items)
        }
    }

    private var categoryOrder: [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for item in SFXLibrary.all where !seen.contains(item.category) {
            seen.insert(item.category)
            ordered.append(item.category)
        }
        return ordered
    }

    private func togglePreview(for item: SFXItem) {
        if previewItemId == item.id, let player = previewPlayer, player.isPlaying {
            player.pause()
            return
        }

        stopPreview()

        guard let url = viewModel.sfxURL(for: item) else {
            viewModel.lastErrorMessage = "Missing bundled sound effect: \(item.fileName)"
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.prepareToPlay()
            player.play()
            previewPlayer = player
            previewItemId = item.id
        } catch {
            previewPlayer = nil
            previewItemId = nil
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewItemId = nil
    }

    private func isPreviewing(_ item: SFXItem) -> Bool {
        previewItemId == item.id && (previewPlayer?.isPlaying ?? false)
    }

    private func categoryTitle(_ category: String) -> String {
        category.localizedCapitalized
    }
}

private struct SFXCategoryGroup: Identifiable {
    let category: String
    let items: [SFXItem]

    var id: String { category }
}

private struct SFXItemButton: View {
    let item: SFXItem
    let isPreviewing: Bool
    let previewAction: () -> Void
    let addAction: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: addAction) {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(item.name)
                        .font(.caption)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(8)
                .padding(.trailing, 24)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
                .background(Color(nsColor: .separatorColor).opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name)
            .accessibilityHint("Adds this sound effect to the timeline.")

            Button(action: previewAction) {
                Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                    .font(.caption)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isPreviewing ? "Pause \(item.name)" : "Preview \(item.name)")
        }
    }

    private var iconName: String {
        switch item.category {
        case "whoosh":
            return "wind"
        case "click":
            return "cursorarrow.click"
        case "pop":
            return "circle.circle"
        case "ding":
            return "bell"
        case "boom":
            return "speaker.wave.3"
        case "notification":
            return "app.badge"
        default:
            return "waveform"
        }
    }
}
