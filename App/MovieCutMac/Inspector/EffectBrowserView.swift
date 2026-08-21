import AppKit
import SwiftUI
import MovieCutCore

/// G-28 Inc 2b — searchable, cost-aware effect discovery with real before /
/// after preview and renderer-compatible parameter drafting before commit.
struct EffectBrowserView: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    /// `measureAllBuiltIns` is intentionally a process-wide single flight.
    /// A sheet dismissal cancels the view's `.task`, but detached work does not
    /// inherit that cancellation. Sharing one task prevents a quick reopen from
    /// starting a second expensive Core Image + process-memory measurement run,
    /// and the completed Task value acts as the browser's process-local cache.
    private static let profileMeasurementTask = Task.detached(priority: .utility) {
        EffectCostProfiler.measureAllBuiltIns(iterations: 3)
    }

    @State private var searchText = ""
    @State private var favoriteIds: Set<String> = []
    @State private var selectedEffectType: EffectType?
    @State private var profiles: [EffectType: EffectCostProfile] = [:]
    @State private var draftParameters: [String: Double] = [:]
    @State private var previewSourceData: Data?
    @State private var sourcePreviewImage: NSImage?
    @State private var effectPreviewImage: NSImage?
    @State private var previewGeneration = 0
    @State private var appliedMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchField
                Divider()
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 150))],
                        spacing: MovieCutSpacing.small
                    ) {
                        ForEach(filteredEffects) { item in
                            effectCard(item)
                        }
                    }
                    .padding(MovieCutSpacing.medium)
                }
            }
            .frame(minWidth: 460)

            Divider()

            detailPanel
                .frame(width: 330)
        }
        .frame(minWidth: 800, minHeight: 480)
        .background(MovieCutTheme.editorBackground)
        .task { await loadProfiles() }
        .onAppear {
            loadPreviewSource()
            if selectedEffectType == nil, let first = EffectBrowserCatalog.items.first {
                selectEffect(first)
            }
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search effects…", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search effects")
        }
        .padding(MovieCutSpacing.small)
        .padding(.horizontal, MovieCutSpacing.medium)
        .background(MovieCutTheme.cardBackground)
    }

    private var filteredEffects: [EffectBrowserCatalogItem] {
        let matching = EffectBrowserCatalog.items.filter { item in
            searchText.isEmpty
                || displayName(for: item.type).localizedCaseInsensitiveContains(searchText)
                || tags(for: item.type).contains { $0.localizedCaseInsensitiveContains(searchText) }
        }

        // Favorites first, then by measured cost (cheapest first), then name so
        // the list remains deterministic before profiling finishes.
        return matching.sorted { lhs, rhs in
            let lhsFavorite = favoriteIds.contains(lhs.type.rawValue)
            let rhsFavorite = favoriteIds.contains(rhs.type.rawValue)
            if lhsFavorite != rhsFavorite { return lhsFavorite }

            let lhsCost = profiles[lhs.type]?.millisecondsPerFrame
            let rhsCost = profiles[rhs.type]?.millisecondsPerFrame
            switch (lhsCost, rhsCost) {
            case let (.some(left), .some(right)) where left != right:
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return displayName(for: lhs.type) < displayName(for: rhs.type)
            }
        }
    }

    // MARK: - Card

    private func effectCard(_ item: EffectBrowserCatalogItem) -> some View {
        let profile = profiles[item.type]
        let isSelected = selectedEffectType == item.type

        return VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack {
                Text(displayName(for: item.type))
                    .font(MovieCutTypography.cardTitle)
                    .lineLimit(1)
                Spacer()
                Button {
                    toggleFavorite(item.type)
                } label: {
                    Image(systemName: favoriteIds.contains(item.type.rawValue) ? "star.fill" : "star")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    favoriteIds.contains(item.type.rawValue)
                        ? "Remove \(displayName(for: item.type)) from favorites"
                        : "Add \(displayName(for: item.type)) to favorites"
                )
            }

            Text(tags(for: item.type).prefix(2).joined(separator: " · "))
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            HStack(spacing: 4) {
                if let tier = profile?.costTier {
                    costBadge(tier)
                }
                if let milliseconds = profile?.millisecondsPerFrame {
                    Text(String(format: "%.1fms", milliseconds))
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Measuring…")
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(MovieCutSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium)
                .fill(isSelected ? MovieCutTheme.accentCyan.opacity(0.15) : MovieCutTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium)
                .strokeBorder(isSelected ? MovieCutTheme.accentCyan : MovieCutTheme.border.opacity(0.25), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectEffect(item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Selects this effect for preview and parameter editing before applying it.")
    }

    private func costBadge(_ tier: EffectCostProfile.CostTier) -> some View {
        HStack(spacing: 2) {
            Circle()
                .fill(badgeColor(tier))
                .frame(width: 6, height: 6)
            Text(tier.rawValue)
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }

    private func badgeColor(_ tier: EffectCostProfile.CostTier) -> Color {
        switch tier {
        case .instant: return .green
        case .moderate: return .yellow
        case .heavy: return .orange
        }
    }

    // MARK: - Preview + parameters

    @ViewBuilder
    private var detailPanel: some View {
        if let selectedEffectType,
           let item = EffectBrowserCatalog.item(for: selectedEffectType) {
            ScrollView {
                VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
                    VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                        Text(displayName(for: item.type))
                            .font(.headline)
                        Text("Preview and tune before adding this effect to the selected clip.")
                            .font(MovieCutTypography.cardBody)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: MovieCutSpacing.small) {
                        previewTile(title: "Original", image: sourcePreviewImage)
                        previewTile(title: "Preview", image: effectPreviewImage)
                    }

                    VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                        Text("Parameters")
                            .font(MovieCutTypography.cardTitle)

                        ForEach(item.parameters) { definition in
                            parameterRow(definition, item: item)
                        }
                    }
                    .movieCutCard(
                        background: MovieCutTheme.elevatedCardBackground,
                        border: MovieCutTheme.border.opacity(0.28)
                    )

                    Button {
                        applyEffect(item.type)
                    } label: {
                        Label("Apply to Clip", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MovieCutTheme.accentCyan)
                    .accessibilityHint("Adds the previewed effect with the drafted parameters to the selected clip.")

                    if let appliedMessage {
                        Label(appliedMessage, systemImage: "checkmark.circle.fill")
                            .font(MovieCutTypography.cardBody)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(MovieCutSpacing.medium)
            }
            .background(MovieCutTheme.panelBackground)
        } else {
            VStack(spacing: MovieCutSpacing.small) {
                Image(systemName: "sparkles.rectangle.stack")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Choose an effect")
                    .font(MovieCutTypography.cardTitle)
                Text("Select a card to preview and tune it before applying.")
                    .font(MovieCutTypography.cardBody)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(MovieCutSpacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MovieCutTheme.panelBackground)
        }
    }

    private func previewTile(title: String, image: NSImage?) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            Text(title)
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.secondary)

            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    VStack(spacing: MovieCutSpacing.xSmall) {
                        Image(systemName: "photo")
                        Text("No thumbnail")
                            .font(MovieCutTypography.micro)
                    }
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 104)
            .background(MovieCutTheme.previewWellBackground)
            .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small))
        }
        .frame(maxWidth: .infinity)
    }

    private func parameterRow(
        _ definition: EffectBrowserParameter,
        item: EffectBrowserCatalogItem
    ) -> some View {
        let value = draftParameters[definition.key] ?? definition.previewValue

        return VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
            HStack {
                Text(definition.title)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: definition.valueFormat, value))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { draftParameters[definition.key] ?? definition.previewValue },
                    set: { newValue in
                        draftParameters[definition.key] = definition.clamped(newValue)
                        refreshPreview(for: item)
                    }
                ),
                in: definition.range
            )
            .accessibilityLabel(definition.title)
            .accessibilityValue(String(format: definition.valueFormat, value))
        }
    }

    private func loadPreviewSource() {
        guard previewSourceData == nil,
              let data = viewModel.thumbnailData(for: clip),
              let image = NSImage(data: data)
        else {
            return
        }

        previewSourceData = data
        sourcePreviewImage = image

        if let selectedEffectType,
           let item = EffectBrowserCatalog.item(for: selectedEffectType) {
            refreshPreview(for: item)
        }
    }

    private var currentBrowserClip: Clip {
        if let selectedClip = viewModel.selectedClip, selectedClip.id == clip.id {
            return selectedClip
        }
        return clip
    }

    private var currentBrowserClipEffects: [Effect] {
        currentBrowserClip.effects
    }

    private func refreshPreview(for item: EffectBrowserCatalogItem) {
        guard let data = previewSourceData else {
            effectPreviewImage = nil
            return
        }

        let clipSnapshot = currentBrowserClip
        let previewEffects = item.previewEffects(
            existingEffects: clipSnapshot.effects,
            parameters: draftParameters
        )
        previewGeneration += 1
        let generation = previewGeneration

        Task {
            let renderedData = await Task.detached(priority: .userInitiated) {
                EffectBrowserPreviewRenderer.render(
                    sourceData: data,
                    clip: clipSnapshot,
                    effects: previewEffects
                )
            }.value

            guard generation == previewGeneration else { return }
            effectPreviewImage = renderedData.flatMap(NSImage.init(data:))
        }
    }

    // MARK: - Actions

    private func selectEffect(_ item: EffectBrowserCatalogItem) {
        selectedEffectType = item.type
        draftParameters = item.initialParameters
        appliedMessage = nil
        refreshPreview(for: item)
    }

    private func applyEffect(_ type: EffectType) {
        guard let item = EffectBrowserCatalog.item(for: type) else { return }
        let effect = item.makeEffect(parameters: draftParameters)
        let currentEffects = currentBrowserClipEffects

        Task {
            await viewModel.updateSelectedEffects(currentEffects + [effect])
            appliedMessage = "Applied \(displayName(for: type))"
        }
    }

    private func toggleFavorite(_ type: EffectType) {
        if favoriteIds.contains(type.rawValue) {
            favoriteIds.remove(type.rawValue)
        } else {
            favoriteIds.insert(type.rawValue)
        }
    }

    // MARK: - Data

    /// The synchronous profiler executes outside MainActor and is shared by
    /// every browser instance. Cancelling this view only suppresses its state
    /// update; a later browser instance reuses the same in-flight/completed
    /// measurement instead of launching duplicate profiling work.
    private func loadProfiles() async {
        let all = await Self.profileMeasurementTask.value
        guard !Task.isCancelled else { return }

        var map: [EffectType: EffectCostProfile] = [:]
        for profile in all {
            map[profile.effectType] = profile
        }
        profiles = map
    }

    private func displayName(for type: EffectType) -> String {
        type.displayName
    }

    private func tags(for type: EffectType) -> [String] {
        EffectBrowserCatalog.item(for: type)?.tags ?? []
    }
}
