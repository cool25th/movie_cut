#if os(iOS)
import MovieCutCore
import SwiftUI
import AVFoundation

struct IOSSFXPickerView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var selectedCategory: String?
    @State private var previewItemId: UUID?
    @State private var previewPlayer: AVAudioPlayer?

    private let columns = [
        GridItem(.adaptive(minimum: 124), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    TextField("Search SFX", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    categoryTabs
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground))

                if filteredItems.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(filteredItems) { item in
                                IOSSFXItemButton(
                                    item: item,
                                    isPreviewing: isPreviewing(item),
                                    previewAction: { togglePreview(for: item) },
                                    addAction: {
                                        Task {
                                            await viewModel.addSFXToTimeline(item)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Sound Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onDisappear {
                stopPreview()
            }
        }
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                IOSSFXCategoryTab(
                    title: "All",
                    isSelected: selectedCategory == nil,
                    action: { selectedCategory = nil }
                )

                ForEach(categoryOrder, id: \.self) { category in
                    IOSSFXCategoryTab(
                        title: categoryTitle(category),
                        isSelected: selectedCategory == category,
                        action: { selectedCategory = category }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("No matching SFX")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredItems: [SFXItem] {
        SFXLibrary.search(query: searchText).filter { item in
            guard let selectedCategory else { return true }
            return item.category == selectedCategory
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
        if isPreviewing(item) {
            stopPreview()
            return
        }

        stopPreview()

        guard let url = viewModel.sfxURL(for: item) else {
            viewModel.lastErrorMessage = "Missing bundled sound effect: \(item.fileName)"
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)

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

private struct IOSSFXCategoryTab: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct IOSSFXItemButton: View {
    let item: SFXItem
    let isPreviewing: Bool
    let previewAction: () -> Void
    let addAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                Spacer(minLength: 8)

                Text(item.category.localizedCapitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)

            HStack(spacing: 8) {
                Button(action: previewAction) {
                    Image(systemName: isPreviewing ? "pause.fill" : "play.fill")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(isPreviewing ? "Pause \(item.name)" : "Preview \(item.name)")

                Spacer(minLength: 8)

                Button(action: addAction) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add \(item.name) to timeline")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .background(Color.secondary.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
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
#endif
