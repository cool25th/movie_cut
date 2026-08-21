import SwiftUI
import MovieCutCore

/// G-28 Inc 2 — the effect browser: searchable, cost-aware, favoritable.
/// EffectCostProfile's measured tiers drive the badges; search filters by
/// name and tag; favorites pin to the top. The browser is the plan's
/// "검색 성공률·재사용률 KPI" surface.
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

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: MovieCutSpacing.small) {
                    ForEach(filteredEffects, id: \.rawValue) { effectType in
                        effectCard(effectType)
                    }
                }
                .padding(MovieCutSpacing.medium)
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .background(MovieCutTheme.editorBackground)
        .task { await loadProfiles() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search effects…", text: $searchText)
                .textFieldStyle(.plain)
        }
        .padding(MovieCutSpacing.small)
        .padding(.horizontal, MovieCutSpacing.medium)
        .background(MovieCutTheme.cardBackground)
    }

    private var filteredEffects: [EffectType] {
        let all = EffectType.allCases
        let matching = all.filter { type in
            searchText.isEmpty
                || type.rawValue.localizedCaseInsensitiveContains(searchText)
                || tags(for: type).contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
        // Favorites first, then by cost (cheapest first).
        return matching.sorted { a, b in
            let aFav = favoriteIds.contains(a.rawValue)
            let bFav = favoriteIds.contains(b.rawValue)
            if aFav != bFav { return aFav }
            let aCost = profiles[a]?.millisecondsPerFrame ?? 0
            let bCost = profiles[b]?.millisecondsPerFrame ?? 0
            return aCost < bCost
        }
    }

    // MARK: - Card

    private func effectCard(_ type: EffectType) -> some View {
        let profile = profiles[type]
        let isSelected = selectedEffectType == type
        return VStack(spacing: MovieCutSpacing.small) {
            HStack {
                Text(displayName(for: type))
                    .font(MovieCutTypography.cardTitle)
                    .lineLimit(1)
                Spacer()
                Button {
                    toggleFavorite(type)
                } label: {
                    Image(systemName: favoriteIds.contains(type.rawValue) ? "star.fill" : "star")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                if let tier = profile?.costTier {
                    costBadge(tier)
                }
                if let ms = profile?.millisecondsPerFrame {
                    Text(String(format: "%.1fms", ms))
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(MovieCutSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? MovieCutTheme.accentCyan.opacity(0.15) : MovieCutTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? MovieCutTheme.accentCyan : .clear, lineWidth: 1)
        )
        .onTapGesture {
            selectedEffectType = type
            applyEffect(type)
        }
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

    // MARK: - Actions

    private func applyEffect(_ type: EffectType) {
        let effect = Effect(type: type, parameters: ["intensity": 0.5])
        Task {
            await viewModel.updateSelectedEffects(clip.effects + [effect])
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
        type.rawValue
            .replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .capitalized
    }

    private func tags(for type: EffectType) -> [String] {
        switch type {
        case .brightness, .contrast, .exposure, .temperature, .saturation:
            return ["color", "adjustment"]
        case .fadeIn, .fadeOut, .crossDissolve:
            return ["transition", "timing"]
        case .grayscale, .sepia:
            return ["color", "vintage"]
        case .blur:
            return ["focus", "soft"]
        case .styleTransfer:
            return ["ai", "style"]
        case .cinematicLUT, .vintageLUT, .noirLUT, .vividLUT, .coolLUT:
            return ["lut", "color", "cinematic"]
        case .externalLUT:
            return ["lut", "custom", "import"]
        }
    }
}
