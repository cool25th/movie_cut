import AppKit
import Foundation
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct MediaLibraryPanel: View {
    var viewModel: EditorViewModel
    @State private var isAddingText = false
    @State private var textClipText = NSLocalizedString("Text", comment: "")
    @State private var selectedLibraryTab: LibraryTab = .media
    @State private var librarySearchText = ""

    private let libraryGridColumns = [
        GridItem(.flexible(minimum: 120), spacing: MovieCutSpacing.small),
        GridItem(.flexible(minimum: 120), spacing: MovieCutSpacing.small)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            MovieCutPanelHeader(
                title: NSLocalizedString("Library", comment: ""),
                systemImage: "rectangle.stack",
                subtitle: selectedLibraryTab.subtitle
            ) {
                headerActions
            }

            libraryTabBar
            librarySearchField

            Group {
                switch selectedLibraryTab {
                case .media:
                    mediaTabContent
                case .audio:
                    audioTabContent
                case .text:
                    textTabContent
                case .stickers:
                    stickersTabContent
                case .effects:
                    effectsTabContent
                case .transitions:
                    transitionsTabContent
                case .filters:
                    filtersTabContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 320)
        .movieCutPanelBackground()
        .onDrop(of: [.fileURL, .movie, .image], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Library", comment: ""))
        .accessibilityHint(NSLocalizedString("Drop media files here to import them.", comment: ""))
        .sheet(isPresented: $isAddingText) {
            VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
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
            .padding(MovieCutSpacing.large)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        HStack(spacing: MovieCutSpacing.small) {
            if selectedLibraryTab == .media {
                Button(action: openImportPanel) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("Import", comment: ""))
                .accessibilityHint(NSLocalizedString("Opens a file picker to import media.", comment: ""))
            }

            if selectedLibraryTab == .text {
                Button(action: openTextSheet) {
                    Image(systemName: "textformat")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("Add Text", comment: ""))
                .accessibilityHint(NSLocalizedString("Creates a new text clip.", comment: ""))
            }
        }
    }

    private var libraryTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: MovieCutSpacing.small) {
                ForEach(LibraryTab.allCases) { tab in
                    Button {
                        if selectedLibraryTab != tab {
                            librarySearchText = ""
                        }
                        selectedLibraryTab = tab
                    } label: {
                        Label(tab.displayName, systemImage: tab.systemImage)
                            .font(.caption.weight(selectedLibraryTab == tab ? .semibold : .medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, MovieCutSpacing.medium)
                            .padding(.vertical, MovieCutSpacing.small)
                            .background(
                                RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                                    .fill(selectedLibraryTab == tab ? MovieCutTheme.selectedFill : MovieCutTheme.cardBackground)
                            )
                            .foregroundStyle(selectedLibraryTab == tab ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.displayName)
                    .accessibilityHint(tab.accessibilityHint)
                }
            }
            .padding(.horizontal, MovieCutSpacing.medium)
            .padding(.vertical, MovieCutSpacing.xSmall)
        }
        .accessibilityLabel(NSLocalizedString("Library browser tabs", comment: ""))
    }

    private var librarySearchField: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(librarySearchPlaceholder, text: $librarySearchText)
                .textFieldStyle(.plain)
                .accessibilityLabel(String(format: NSLocalizedString("Search %@", comment: ""), selectedLibraryTab.displayName))
                .accessibilityHint(NSLocalizedString("Filters the selected library tab.", comment: ""))

            if !librarySearchQuery.isEmpty {
                Button {
                    librarySearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(NSLocalizedString("Clear library search", comment: ""))
            }
        }
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.small)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.cardBackground)
        )
        .padding(.horizontal, MovieCutSpacing.medium)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var mediaTabContent: some View {
        VStack(spacing: MovieCutSpacing.small) {
            mediaContent

            if viewModel.selectedAsset != nil {
                Button(NSLocalizedString("Add to Timeline", comment: "")) {
                    Task { await viewModel.addClipToTimeline() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.horizontal, MovieCutSpacing.medium)
                .padding(.bottom, MovieCutSpacing.small)
                .accessibilityLabel(NSLocalizedString("Add to Timeline", comment: ""))
                .accessibilityHint(NSLocalizedString("Adds the selected library asset to the timeline.", comment: ""))
            }
        }
    }

    private var audioTabContent: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            embeddedLibrarySearchNote

            ScrollView {
                VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
                    librarySection(title: NSLocalizedString("Music", comment: ""), systemImage: "music.note.list") {
                        MusicLibraryView(viewModel: viewModel)
                    }

                    librarySection(title: NSLocalizedString("Sound Effects", comment: ""), systemImage: "waveform.badge.plus") {
                        SFXPickerView(viewModel: viewModel)
                    }
                }
                .padding(.horizontal, MovieCutSpacing.medium)
                .padding(.bottom, MovieCutSpacing.medium)
            }
        }
        .accessibilityLabel(NSLocalizedString("Audio browser", comment: ""))
    }

    @ViewBuilder
    private var textTabContent: some View {
        let templates = filteredTextTemplates
        let showsCustomTextAction = shouldShowCustomTextAction

        Group {
            if templates.isEmpty && !showsCustomTextAction {
                librarySearchEmptyState()
            } else {
                ScrollView {
                    LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                        if showsCustomTextAction {
                            Button {
                                openTextSheet()
                            } label: {
                                browserGridCard(
                                    title: NSLocalizedString("Custom Text", comment: ""),
                                    subtitle: NSLocalizedString("Type a custom text clip at the playhead", comment: ""),
                                    systemImage: "textformat"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(NSLocalizedString("Add custom text", comment: ""))
                            .accessibilityHint(NSLocalizedString("Opens the text clip creation sheet.", comment: ""))
                        }

                        ForEach(templates) { template in
                            Button {
                                Task { await viewModel.addTextTemplateClip(template) }
                            } label: {
                                browserGridCard(
                                    title: template.name,
                                    subtitle: textTemplateSubtitle(template),
                                    systemImage: "text.badge.plus"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: NSLocalizedString("Add %@ text template", comment: ""), template.name))
                            .accessibilityHint(NSLocalizedString("Adds this text template to the timeline.", comment: ""))
                        }
                    }
                    .padding(MovieCutSpacing.medium)
                }
            }
        }
        .accessibilityLabel(NSLocalizedString("Text template browser", comment: ""))
    }

    private var stickersTabContent: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            embeddedLibrarySearchNote

            StickerPickerView { sticker in
                Task { await viewModel.addSticker(sticker) }
            }
        }
        .accessibilityLabel(NSLocalizedString("Sticker browser", comment: ""))
    }

    private var effectsTabContent: some View {
        effectGrid(
            title: NSLocalizedString("Effects", comment: ""),
            systemImage: "sparkles",
            types: EffectType.allCases.filter { $0 != .externalLUT },
            emptyMessage: NSLocalizedString("Select a clip to apply effects.", comment: "")
        )
    }

    private var filtersTabContent: some View {
        effectGrid(
            title: NSLocalizedString("Filters", comment: ""),
            systemImage: "camera.filters",
            types: filterEffectTypes,
            emptyMessage: NSLocalizedString("Select a clip to apply filters.", comment: "")
        )
    }

    @ViewBuilder
    private var transitionsTabContent: some View {
        let transitions = filteredTransitionTypes

        ScrollView {
            LazyVStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                if viewModel.selectedClip == nil {
                    selectClipEmptyState(message: NSLocalizedString("Select a clip to apply a transition.", comment: ""))
                }

                if transitions.isEmpty {
                    librarySearchEmptyState()
                } else {
                    LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                        ForEach(transitions, id: \.self) { type in
                            Button {
                                applyTransition(type)
                            } label: {
                                browserGridCard(
                                    title: type.displayName,
                                    subtitle: transitionSubtitle(type),
                                    systemImage: type == .none ? "nosign" : "rectangle.2.swap"
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.selectedClip == nil)
                            .accessibilityLabel(type.displayName)
                            .accessibilityHint(NSLocalizedString("Applies this transition to the selected clip.", comment: ""))
                        }
                    }
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .accessibilityLabel(NSLocalizedString("Transition browser", comment: ""))
    }

    @ViewBuilder
    private var embeddedLibrarySearchNote: some View {
        if !librarySearchQuery.isEmpty {
            HStack(spacing: MovieCutSpacing.xSmall) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(embeddedLibrarySearchNoteText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MovieCutSpacing.medium)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func effectGrid(title: String, systemImage: String, types: [EffectType], emptyMessage: String) -> some View {
        let effects = filteredEffectTypes(types)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                if viewModel.selectedClip == nil {
                    selectClipEmptyState(message: emptyMessage)
                }

                if effects.isEmpty {
                    librarySearchEmptyState()
                } else {
                    LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                        ForEach(effects, id: \.self) { type in
                            Button {
                                applyEffect(type)
                            } label: {
                                browserGridCard(
                                    title: type.displayName,
                                    subtitle: effectSubtitle(type),
                                    systemImage: systemImage
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.selectedClip == nil)
                            .accessibilityLabel(type.displayName)
                            .accessibilityHint(String(format: NSLocalizedString("Applies the %@ effect to the selected clip.", comment: ""), type.displayName))
                        }
                    }
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func librarySearchEmptyState() -> some View {
        VStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("No results for \"%@\"", comment: ""), librarySearchQuery))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .movieCutCard(background: MovieCutTheme.elevatedCardBackground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func selectClipEmptyState(message: String) -> some View {
        VStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "cursorarrow.click.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .movieCutCard(background: MovieCutTheme.elevatedCardBackground)
        .accessibilityElement(children: .combine)
    }

    private func librarySection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MovieCutSectionCard(title: title, systemImage: systemImage) {
            content()
        }
    }

    private func browserGridCard(title: String, subtitle: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.cardBackground
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mediaContent: some View {
        let assets = filteredMediaAssets

        if viewModel.mediaAssets.isEmpty {
            VStack(spacing: MovieCutSpacing.small) {
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
        } else if assets.isEmpty {
            librarySearchEmptyState()
        } else {
            ScrollView {
                LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                    ForEach(assets) { asset in
                        assetGridCard(asset)
                    }
                }
                .padding(MovieCutSpacing.medium)
            }
            .accessibilityLabel(NSLocalizedString("Asset Grid", comment: ""))
        }
    }

    private func assetGridCard(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            ZStack(alignment: .topTrailing) {
                assetGridThumbnailView(asset)

                proxyButton(asset)
                    .padding(MovieCutSpacing.xSmall)
                    .background(
                        Circle()
                            .fill(MovieCutTheme.elevatedCardBackground.opacity(0.85))
                    )
            }

            assetInfoView(asset)
                .frame(maxWidth: .infinity, alignment: .leading)

            assetStateText(asset)
        }
        .frame(maxWidth: .infinity, minHeight: 152, alignment: .topLeading)
        .movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: asset.id == viewModel.selectedAssetId ? MovieCutTheme.selectedFill : MovieCutTheme.cardBackground,
            border: asset.id == viewModel.selectedAssetId ? Color.accentColor.opacity(0.35) : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedAssetId = asset.id
        }
        .onDrag {
            viewModel.selectedAssetId = asset.id
            return assetDragProvider(for: asset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(asset.originalURL.lastPathComponent)
        .accessibilityValue(assetAccessibilityValue(asset))
        .accessibilityHint(NSLocalizedString("Selects this asset. Drag it to the timeline to create a clip.", comment: ""))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            viewModel.selectedAssetId = asset.id
        }
        .contextMenu {
            if asset.kind == .video {
                Button(NSLocalizedString("Generate Proxy", comment: "")) {
                    viewModel.selectedAssetId = asset.id
                    Task { await viewModel.generateProxy(for: asset.id) }
                }
            }
        }
    }

    private func assetInfoView(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.originalURL.lastPathComponent)
                .lineLimit(1)
                .font(.caption)
            if let detail = assetDetailSummary(asset) {
                Text(detail)
                    .lineLimit(1)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            assetStateText(asset)
        }
    }

    @ViewBuilder
    private func assetStateText(_ asset: MediaAsset) -> some View {
        if asset.kind == .video {
            Text(proxyStateText(asset))
                .font(.caption2)
                .foregroundStyle(asset.proxy?.proxyURL == nil ? Color.secondary : Color.green)
        } else if asset.kind == .image {
            Text(thumbnailStateText(asset))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func proxyButton(_ asset: MediaAsset) -> some View {
        if asset.kind == .video {
            Button {
                viewModel.selectedAssetId = asset.id
                Task { await viewModel.generateProxy(for: asset.id) }
            } label: {
                Image(systemName: asset.proxy?.proxyURL == nil ? "film" : "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help(NSLocalizedString("Generate Proxy", comment: ""))
            .accessibilityLabel(NSLocalizedString("Generate Proxy", comment: ""))
            .accessibilityValue(proxyStateText(asset))
            .accessibilityHint(NSLocalizedString("Creates a lower-resolution proxy file for smoother editing.", comment: ""))
        }
    }

    private var librarySearchPlaceholder: String {
        String(format: NSLocalizedString("Search %@", comment: ""), selectedLibraryTab.displayName)
    }

    private var librarySearchQuery: String {
        librarySearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredMediaAssets: [MediaAsset] {
        viewModel.mediaAssets.filter(assetMatchesLibrarySearch)
    }

    private var filteredTextTemplates: [MovieCutCore.TextTemplate] {
        MovieCutCore.TextTemplate.builtIn.filter(textTemplateMatchesLibrarySearch)
    }

    private var shouldShowCustomTextAction: Bool {
        librarySearchMatches([
            NSLocalizedString("Custom Text", comment: ""),
            NSLocalizedString("custom", comment: ""),
            NSLocalizedString("text", comment: ""),
            NSLocalizedString("Type a custom text clip at the playhead", comment: "")
        ])
    }

    private func filteredEffectTypes(_ types: [EffectType]) -> [EffectType] {
        types.filter(effectTypeMatchesLibrarySearch)
    }

    private var filteredTransitionTypes: [TransitionType] {
        TransitionType.allCases.filter(transitionTypeMatchesLibrarySearch)
    }

    private var embeddedLibrarySearchNoteText: String {
        switch selectedLibraryTab {
        case .audio:
            return NSLocalizedString("Use the Music and Sound Effects search fields below to filter audio.", comment: "")
        case .stickers:
            return NSLocalizedString("Use the sticker search field below to filter stickers.", comment: "")
        case .media, .text, .effects, .transitions, .filters:
            return ""
        }
    }

    private func assetMatchesLibrarySearch(_ asset: MediaAsset) -> Bool {
        librarySearchMatches([
            asset.originalURL.lastPathComponent,
            String(describing: asset.kind),
            assetDetailSummary(asset) ?? "",
            metadataSummary(asset) ?? "",
            thumbnailStateText(asset),
            proxyStateText(asset)
        ])
    }

    private func textTemplateMatchesLibrarySearch(_ template: MovieCutCore.TextTemplate) -> Bool {
        librarySearchMatches([
            template.name,
            template.content.text,
            textTemplateSubtitle(template)
        ])
    }

    private func effectTypeMatchesLibrarySearch(_ type: EffectType) -> Bool {
        librarySearchMatches([
            type.displayName,
            effectSubtitle(type)
        ])
    }

    private func transitionTypeMatchesLibrarySearch(_ type: TransitionType) -> Bool {
        librarySearchMatches([
            type.displayName,
            transitionSubtitle(type),
            transitionCategoryName(type.category)
        ])
    }

    private func librarySearchMatches(_ values: [String]) -> Bool {
        let query = librarySearchQuery
        guard !query.isEmpty else { return true }

        return values.contains { value in
            value.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    private var filterEffectTypes: [EffectType] {
        [.cinematicLUT, .vintageLUT, .noirLUT, .vividLUT, .coolLUT, .grayscale, .sepia]
    }

    private func textTemplateSubtitle(_ template: MovieCutCore.TextTemplate) -> String {
        let animation = template.animation.map { textAnimationName($0.type) } ?? NSLocalizedString("No animation", comment: "")
        return String(format: NSLocalizedString("%@ · %.0f pt · %@", comment: ""), template.content.fontFamily, template.content.fontSize, animation)
    }

    private func effectSubtitle(_ type: EffectType) -> String {
        switch type {
        case .brightness, .contrast, .saturation, .temperature, .exposure:
            return NSLocalizedString("Color adjustment for the selected clip", comment: "")
        case .fadeIn, .fadeOut, .crossDissolve:
            return NSLocalizedString("Timing effect for the selected clip", comment: "")
        case .grayscale, .sepia, .cinematicLUT, .vintageLUT, .noirLUT, .vividLUT, .coolLUT:
            return NSLocalizedString("Visual look filter for the selected clip", comment: "")
        case .blur, .styleTransfer:
            return NSLocalizedString("Creative effect for the selected clip", comment: "")
        case .externalLUT:
            return NSLocalizedString("Imported LUT effect", comment: "")
        }
    }

    private func transitionSubtitle(_ type: TransitionType) -> String {
        if type == .none {
            return NSLocalizedString("Remove the selected clip transition", comment: "")
        }
        return String(format: NSLocalizedString("%@ transition · 0.5s default", comment: ""), transitionCategoryName(type.category))
    }

    private func textAnimationName(_ type: TextAnimationType) -> String {
        switch type {
        case .fadeIn: return NSLocalizedString("Fade In", comment: "")
        case .fadeOut: return NSLocalizedString("Fade Out", comment: "")
        case .typewriter: return NSLocalizedString("Typewriter", comment: "")
        case .bounce: return NSLocalizedString("Bounce", comment: "")
        case .slideUp: return NSLocalizedString("Slide Up", comment: "")
        case .slideDown: return NSLocalizedString("Slide Down", comment: "")
        case .scale: return NSLocalizedString("Scale", comment: "")
        }
    }

    private func transitionCategoryName(_ category: TransitionCategory) -> String {
        switch category {
        case .basic: return NSLocalizedString("Basic", comment: "")
        case .wipe: return NSLocalizedString("Wipe", comment: "")
        case .slide: return NSLocalizedString("Slide", comment: "")
        case .zoom: return NSLocalizedString("Zoom", comment: "")
        case .stylized: return NSLocalizedString("Stylized", comment: "")
        }
    }

    private func applyEffect(_ type: EffectType) {
        guard let clip = viewModel.selectedClip else { return }
        let parameters = Dictionary(
            uniqueKeysWithValues: parameterDefinitions(for: type).map { ($0.key, $0.defaultValue) }
        )
        var effects = clip.effects
        effects.append(Effect(type: type, parameters: parameters))
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func applyTransition(_ type: TransitionType) {
        guard let clip = viewModel.selectedClip else { return }
        let transition: MovieCutCore.Transition?
        if type == .none {
            transition = nil
        } else {
            transition = MovieCutCore.Transition(
                id: clip.transition?.id ?? UUID(),
                type: type,
                duration: clip.transition?.duration ?? 0.5
            )
        }
        Task { await viewModel.updateSelectedTransition(transition) }
    }

    private func parameterDefinitions(for type: EffectType) -> [EffectParameterDefinition] {
        switch type {
        case .brightness:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .contrast:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .saturation:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .temperature:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .exposure:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -2 ... 2, defaultValue: 0)]
        case .fadeIn, .fadeOut, .crossDissolve:
            return [EffectParameterDefinition(key: "duration", title: "Duration", range: 0.1 ... 3, defaultValue: 0.5, valueFormat: "%.1fs")]
        case .grayscale:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 1)]
        case .sepia:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.9)]
        case .blur:
            return [EffectParameterDefinition(key: "radius", title: "Radius", range: 1 ... 12, defaultValue: 1, valueFormat: "%.0f")]
        case .styleTransfer:
            return [
                EffectParameterDefinition(key: "styleIndex", title: "Style", range: 1 ... 5, defaultValue: 1, valueFormat: "%.0f"),
                EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.75)
            ]
        case .cinematicLUT, .vintageLUT, .vividLUT, .coolLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.8)]
        case .noirLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 0.9)]
        case .externalLUT:
            return [EffectParameterDefinition(key: "intensity", title: "Intensity", range: 0 ... 1, defaultValue: 1)]
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
        guard !providers.isEmpty else {
            Task { @MainActor in
                viewModel.reportInvalidMediaLibraryDrop()
            }
            return
        }

        DragDropHandler.loadExternalMediaURLs(from: providers) { urls in
            guard !urls.isEmpty else {
                Task { @MainActor in
                    viewModel.reportInvalidMediaLibraryDrop()
                }
                return
            }

            Task { @MainActor in
                await viewModel.importMedia(urls)
            }
        }
    }

    private func assetDragProvider(for asset: MediaAsset) -> NSItemProvider {
        let provider = NSItemProvider()
        let payload = Data(asset.id.uuidString.utf8)
        provider.suggestedName = asset.originalURL.lastPathComponent
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.movieCutMediaAssetID.identifier,
            visibility: .ownProcess
        ) { completion in
            completion(payload, nil)
            return nil
        }
        return provider
    }

    @ViewBuilder
    private func assetGridThumbnailView(_ asset: MediaAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.small)
                .fill(Color.secondary.opacity(0.2))

            if let image = thumbnailImage(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: iconForKind(asset.kind))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        .clipped()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func assetThumbnailView(_ asset: MediaAsset) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.small)
                .fill(Color.secondary.opacity(0.2))

            if let image = thumbnailImage(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small))
            } else {
                Image(systemName: iconForKind(asset.kind))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 48, height: 36)
        .clipped()
        .accessibilityHidden(true)
    }

    private func thumbnailImage(for asset: MediaAsset) -> NSImage? {
        guard
            asset.kind == .video || asset.kind == .image,
            let thumbnailData = asset.thumbnailData
        else {
            return nil
        }

        return NSImage(data: thumbnailData)
    }

    private func iconForKind(_ kind: MediaKind) -> String {
        switch kind {
        case .video: return "film"
        case .audio: return "waveform"
        case .image: return "photo"
        }
    }

    private func thumbnailStateText(_ asset: MediaAsset) -> String {
        if asset.kind == .video || asset.kind == .image {
            return asset.thumbnailData == nil
                ? NSLocalizedString("Thumbnail missing", comment: "")
                : NSLocalizedString("Thumbnail ready", comment: "")
        }

        return NSLocalizedString("No thumbnail", comment: "")
    }

    private func proxyStateText(_ asset: MediaAsset) -> String {
        asset.proxy?.proxyURL == nil
            ? NSLocalizedString("No proxy", comment: "")
            : NSLocalizedString("Proxy ready", comment: "")
    }

    private func assetDetailSummary(_ asset: MediaAsset) -> String? {
        var parts: [String] = []
        if let duration = asset.duration {
            parts.append(durationSummary(duration))
        }
        if let metadata = metadataSummary(asset) {
            parts.append(metadata)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func metadataSummary(_ asset: MediaAsset) -> String? {
        var parts: [String] = []
        let metadata = asset.metadata

        if let resolution = resolutionSummary(metadata) {
            parts.append(resolution)
        }

        switch asset.kind {
        case .video:
            if let frameRate = frameRateSummary(metadata.frameRate) {
                parts.append(frameRate)
            }
            if let codec = codecSummary(metadata.codec) {
                parts.append(codec)
            }
        case .audio:
            if let sampleRate = sampleRateSummary(metadata.sampleRate) {
                parts.append(sampleRate)
            }
            if let channelCount = channelCountSummary(metadata.channelCount) {
                parts.append(channelCount)
            }
            if let codec = codecSummary(metadata.codec) {
                parts.append(codec)
            }
        case .image:
            if let codec = codecSummary(metadata.codec) {
                parts.append(codec)
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func resolutionSummary(_ metadata: MediaMetadata) -> String? {
        guard let width = metadata.width,
              let height = metadata.height,
              width > 0,
              height > 0 else {
            return nil
        }

        return "\(width)×\(height)"
    }

    private func frameRateSummary(_ frameRate: Double?) -> String? {
        guard let frameRate, frameRate.isFinite, frameRate > 0 else {
            return nil
        }

        if abs(frameRate - frameRate.rounded()) < 0.01 {
            return String(format: NSLocalizedString("%.0f fps", comment: ""), frameRate)
        }

        return String(format: NSLocalizedString("%.2f fps", comment: ""), frameRate)
    }

    private func sampleRateSummary(_ sampleRate: Int?) -> String? {
        guard let sampleRate, sampleRate > 0 else {
            return nil
        }

        let kilohertz = Double(sampleRate) / 1_000
        if sampleRate % 1_000 == 0 {
            return String(format: NSLocalizedString("%.0f kHz", comment: ""), kilohertz)
        }

        return String(format: NSLocalizedString("%.1f kHz", comment: ""), kilohertz)
    }

    private func channelCountSummary(_ channelCount: Int?) -> String? {
        guard let channelCount, channelCount > 0 else {
            return nil
        }

        return String(format: NSLocalizedString("%d ch", comment: ""), channelCount)
    }

    private func codecSummary(_ codec: String?) -> String? {
        let trimmedCodec = codec?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCodec?.isEmpty == false ? trimmedCodec : nil
    }

    private func durationSummary(_ duration: TimeInterval) -> String {
        String(format: NSLocalizedString("%.1fs", comment: ""), duration)
    }

    private func assetAccessibilityValue(_ asset: MediaAsset) -> String {
        let kindName = String(describing: asset.kind)
        let detail: String
        if let duration = asset.duration {
            detail = String(format: NSLocalizedString("%@, duration %@", comment: ""), kindName, durationSummary(duration))
        } else {
            detail = kindName
        }

        var states = [detail]
        if let metadata = metadataSummary(asset) {
            states.append(metadata)
        }
        if asset.kind == .video || asset.kind == .image {
            states.append(thumbnailStateText(asset))
        }
        if asset.kind == .video {
            states.append(proxyStateText(asset))
        }
        states.append(NSLocalizedString("draggable to timeline", comment: ""))
        return states.joined(separator: ", ")
    }
}

private enum LibraryTab: CaseIterable, Identifiable {
    case media
    case audio
    case text
    case stickers
    case effects
    case transitions
    case filters

    var id: Self { self }

    var displayName: String {
        switch self {
        case .media:
            return NSLocalizedString("Media", comment: "")
        case .audio:
            return NSLocalizedString("Audio", comment: "")
        case .text:
            return NSLocalizedString("Text", comment: "")
        case .stickers:
            return NSLocalizedString("Stickers", comment: "")
        case .effects:
            return NSLocalizedString("Effects", comment: "")
        case .transitions:
            return NSLocalizedString("Transitions", comment: "")
        case .filters:
            return NSLocalizedString("Filters", comment: "")
        }
    }

    var subtitle: String {
        switch self {
        case .media:
            return NSLocalizedString("Import and drag clips", comment: "")
        case .audio:
            return NSLocalizedString("Music and sound effects", comment: "")
        case .text:
            return NSLocalizedString("Titles and captions", comment: "")
        case .stickers:
            return NSLocalizedString("Emoji and visual stickers", comment: "")
        case .effects:
            return NSLocalizedString("Clip effects", comment: "")
        case .transitions:
            return NSLocalizedString("Clip boundary motion", comment: "")
        case .filters:
            return NSLocalizedString("Looks and LUT-style filters", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .media: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .text: return "textformat"
        case .stickers: return "face.smiling"
        case .effects: return "sparkles"
        case .transitions: return "rectangle.2.swap"
        case .filters: return "camera.filters"
        }
    }

    var accessibilityHint: String {
        String(format: NSLocalizedString("Shows the %@ library browser.", comment: ""), displayName)
    }
}
