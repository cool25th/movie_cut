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
    @State private var hoveredLibraryPreviewTitle: String?
    @State private var hoveredLibraryPreviewKind: LibraryHoverPreviewKind?
    @State private var runningSmartTool: SmartLibraryTool?

    private let libraryRailWidth: CGFloat = 60
    private let libraryRailItemHeight: CGFloat = 32
    private let libraryRailItemSpacing: CGFloat = MovieCutSpacing.xxSmall
    private let libraryRailTopInset: CGFloat = 112

    private let libraryGridColumns = [
        GridItem(.flexible(minimum: 112), spacing: MovieCutSpacing.small),
        GridItem(.flexible(minimum: 112), spacing: MovieCutSpacing.small)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            MovieCutPanelHeader(
                title: NSLocalizedString("Library", comment: ""),
                systemImage: "rectangle.stack",
                subtitle: selectedLibraryTab.subtitle
            ) {
                headerActions
            }

            HStack(spacing: 0) {
                libraryTabRail

                Divider()
                    .overlay(MovieCutTheme.divider)

                libraryContentWell
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 360)
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
                    .font(MovieCutTypography.panelTitle)
                TextField(NSLocalizedString("Text", comment: ""), text: $textClipText)
                    .movieCutInputField()
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
            .background(MovieCutTheme.panelBackground)
            .accessibilityElement(children: .contain)
        }
    }

    private var libraryContentWell: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            librarySearchField
            selectedLibraryTabContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .fill(MovieCutTheme.libraryWellBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.58), lineWidth: 0.5)
        )
        .padding(MovieCutSpacing.small)
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

    @ViewBuilder
    private var selectedLibraryTabContent: some View {
        switch selectedLibraryTab {
        case .media:
            mediaTabContent
        case .audio:
            audioTabContent
        case .text:
            textTabContent
        case .captions:
            captionsTabContent
        case .stickers:
            stickersTabContent
        case .effects:
            effectsTabContent
        case .transitions:
            transitionsTabContent
        case .filters:
            filtersTabContent
        case .adjustment:
            adjustmentTabContent
        case .smart:
            smartTabContent
        }
    }

    private var libraryTabRail: some View {
        VStack(spacing: libraryRailItemSpacing) {
            ForEach(LibraryTab.allCases) { tab in
                libraryRailButton(for: tab)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, libraryRailTopInset)
        .padding(.bottom, MovieCutSpacing.xSmall)
        .frame(width: libraryRailWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(MovieCutTheme.panelBackgroundRaised)
        .accessibilityLabel(NSLocalizedString("Library browser tabs", comment: ""))
    }

    private func libraryRailButton(for tab: LibraryTab) -> some View {
        Button {
            selectLibraryTab(tab)
        } label: {
            VStack(spacing: MovieCutSpacing.xxSmall) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(height: 16)
                    .accessibilityHidden(true)

                Text(tab.railLabel)
                    .font(selectedLibraryTab == tab ? MovieCutTypography.micro.weight(.semibold) : MovieCutTypography.micro)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: libraryRailWidth - MovieCutSpacing.small, height: libraryRailItemHeight)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(selectedLibraryTab == tab ? MovieCutTheme.selectedFill : MovieCutTheme.libraryRailButtonBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .stroke(
                        selectedLibraryTab == tab ? MovieCutTheme.accentCyan.opacity(0.62) : MovieCutTheme.border.opacity(0.46),
                        lineWidth: selectedLibraryTab == tab ? 1 : 0.5
                    )
            )
            .foregroundStyle(selectedLibraryTab == tab ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText)
            .contentShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.displayName)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityValue(selectedLibraryTab == tab ? NSLocalizedString("Selected", comment: "") : NSLocalizedString("Not selected", comment: ""))
    }

    private func selectLibraryTab(_ tab: LibraryTab) {
        if selectedLibraryTab != tab {
            librarySearchText = ""
            hoveredLibraryPreviewTitle = nil
            hoveredLibraryPreviewKind = nil
        }
        selectedLibraryTab = tab
    }

    private var librarySearchField: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(MovieCutTypography.toolbar)
                .foregroundStyle(.secondary)

            TextField(librarySearchPlaceholder, text: $librarySearchText)
                .textFieldStyle(.plain)
                .font(MovieCutTypography.cardBody)
                .foregroundStyle(.primary)
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
                .fill(MovieCutTheme.libraryRailButtonBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.72), lineWidth: 0.5)
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
            .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
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
                .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
            }
        }
        .accessibilityLabel(NSLocalizedString("Text template browser", comment: ""))
    }

    private var captionsTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
                librarySection(title: NSLocalizedString("Captions", comment: ""), systemImage: "captions.bubble") {
                    AutoSubtitlesView(viewModel: viewModel)
                        .tint(MovieCutTheme.accentCyan)
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
        .accessibilityLabel(NSLocalizedString("Captions browser", comment: ""))
    }

    private var stickersTabContent: some View {
        let stickers = filteredStickerAssets

        return Group {
            if stickers.isEmpty {
                librarySearchEmptyState()
                    .padding(MovieCutSpacing.medium)
            } else {
                ScrollView {
                    LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                        ForEach(stickers) { sticker in
                            Button {
                                Task { await viewModel.addSticker(sticker) }
                            } label: {
                                stickerGridCard(sticker)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: NSLocalizedString("Add %@ sticker", comment: ""), sticker.name))
                            .accessibilityValue(stickerCategoryName(sticker))
                            .accessibilityHint(NSLocalizedString("Adds this sticker to the timeline.", comment: ""))
                        }
                    }
                    .padding(MovieCutSpacing.medium)
                }
                .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
            }
        }
        .accessibilityLabel(NSLocalizedString("Sticker browser", comment: ""))
    }

    private var effectsTabContent: some View {
        effectGrid(
            title: NSLocalizedString("Effects", comment: ""),
            systemImage: "sparkles",
            previewKind: .effect,
            types: EffectType.allCases.filter { $0 != .externalLUT },
            emptyMessage: NSLocalizedString("Select a clip to apply effects.", comment: "")
        )
    }

    private var filtersTabContent: some View {
        effectGrid(
            title: NSLocalizedString("Filters", comment: ""),
            systemImage: "camera.filters",
            previewKind: .filter,
            types: filterEffectTypes,
            emptyMessage: NSLocalizedString("Select a clip to apply filters.", comment: "")
        )
    }

    private var adjustmentTabContent: some View {
        effectGrid(
            title: NSLocalizedString("Adjustments", comment: ""),
            systemImage: "slider.horizontal.3",
            previewKind: .adjustment,
            types: adjustmentEffectTypes,
            emptyMessage: NSLocalizedString("Select a clip to apply adjustment presets.", comment: "")
        )
    }

    private var smartTabContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
                smartFeedbackView

                LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
                    ForEach(SmartLibraryTool.allCases) { tool in
                        smartToolButton(tool)
                    }
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
        .accessibilityLabel(NSLocalizedString("Smart tools browser", comment: ""))
    }

    @ViewBuilder
    private var smartFeedbackView: some View {
        if let message = viewModel.quickToolProgressMessage {
            smartFeedbackLabel(message, systemImage: "hourglass", color: .secondary)
        } else if let message = viewModel.lastStatusMessage {
            smartFeedbackLabel(message, systemImage: "checkmark.circle", color: .secondary)
        } else if let message = viewModel.lastErrorMessage {
            smartFeedbackLabel(message, systemImage: "exclamationmark.triangle", color: .red)
        }
    }

    private func smartFeedbackLabel(_ message: String, systemImage: String, color: Color) -> some View {
        Label(message, systemImage: systemImage)
            .font(MovieCutTypography.metadata)
            .foregroundStyle(color)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .movieCutLibraryBrowserCard(
                padding: MovieCutSpacing.small,
                background: MovieCutTheme.libraryCardBackground,
                border: MovieCutTheme.border.opacity(0.52)
            )
            .accessibilityElement(children: .combine)
    }

    private func smartToolButton(_ tool: SmartLibraryTool) -> some View {
        let isEnabled = isSmartToolEnabled(tool)
        let isRunning = runningSmartTool == tool
        let isBlockedByRunningTool = runningSmartTool != nil && !isRunning

        return Button {
            runSmartTool(tool)
        } label: {
            smartToolCard(
                tool,
                isEnabled: isEnabled,
                isRunning: isRunning,
                isBlockedByRunningTool: isBlockedByRunningTool
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isBlockedByRunningTool)
        .help(isEnabled ? tool.title : tool.disabledReason)
        .accessibilityLabel(tool.title)
        .accessibilityHint(isEnabled ? NSLocalizedString("Runs this Smart tool.", comment: "") : tool.disabledReason)
    }

    private func smartToolCard(
        _ tool: SmartLibraryTool,
        isEnabled: Bool,
        isRunning: Bool,
        isBlockedByRunningTool: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack(alignment: .top, spacing: MovieCutSpacing.small) {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isEnabled ? MovieCutTheme.accentCyan : MovieCutTheme.mutedText)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                    Text(tool.title)
                        .font(MovieCutTypography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(tool.description)
                        .font(MovieCutTypography.cardBody)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 0)

            smartToolAffordance(
                tool,
                isEnabled: isEnabled,
                isRunning: isRunning,
                isBlockedByRunningTool: isBlockedByRunningTool
            )
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: MovieCutTheme.libraryCardBackground,
            border: isEnabled ? MovieCutTheme.border.opacity(0.52) : MovieCutTheme.border.opacity(0.32)
        )
        .opacity(isEnabled || isRunning ? 1 : 0.68)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func smartToolAffordance(
        _ tool: SmartLibraryTool,
        isEnabled: Bool,
        isRunning: Bool,
        isBlockedByRunningTool: Bool
    ) -> some View {
        if isRunning {
            HStack(spacing: MovieCutSpacing.xSmall) {
                ProgressView()
                    .controlSize(.small)
                Text(tool.progressMessage)
                    .font(MovieCutTypography.metadata.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else if !isEnabled {
            Label(tool.disabledReason, systemImage: "info.circle")
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else if isBlockedByRunningTool {
            Label(NSLocalizedString("Waiting for current Smart tool.", comment: ""), systemImage: "hourglass")
                .font(MovieCutTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        } else {
            HStack(spacing: MovieCutSpacing.xSmall) {
                Text(NSLocalizedString("Execute", comment: ""))
                    .font(MovieCutTypography.metadata.weight(.semibold))
                Image(systemName: "play.circle.fill")
            }
            .foregroundStyle(MovieCutTheme.accentCyan)
        }
    }

    private func isSmartToolEnabled(_ tool: SmartLibraryTool) -> Bool {
        switch tool {
        case .autoCut:
            return viewModel.canRunAutoCutOnSelection
        case .sceneDetect:
            return viewModel.canDetectSceneChangesForSelection
        case .beatDetect:
            return viewModel.canDetectBeats
        case .reframe:
            return viewModel.canAutoReframeSelection
        case .noiseReduction:
            return viewModel.canApplyNoiseReductionToSelection
        case .extractAudio:
            return viewModel.canExtractAudioFromSelection
        }
    }

    private func runSmartTool(_ tool: SmartLibraryTool) {
        guard runningSmartTool == nil else { return }
        runningSmartTool = tool
        viewModel.quickToolProgressMessage = tool.progressMessage
        Task { @MainActor in
            await performSmartTool(tool)
            if viewModel.quickToolProgressMessage == tool.progressMessage {
                viewModel.quickToolProgressMessage = nil
            }
            runningSmartTool = nil
        }
    }

    @MainActor
    private func performSmartTool(_ tool: SmartLibraryTool) async {
        switch tool {
        case .autoCut:
            await viewModel.runAutoCutOnSelection()
        case .sceneDetect:
            await viewModel.detectSceneChangesForSelection()
        case .beatDetect:
            await viewModel.detectBeats()
        case .reframe:
            await viewModel.autoReframeSelection()
        case .noiseReduction:
            await viewModel.applyNoiseReductionToSelection()
        case .extractAudio:
            await viewModel.extractAudioFromSelection()
        }
    }

    @ViewBuilder
    private var transitionsTabContent: some View {
        let transitions = filteredTransitionTypes
        let disabledReason = viewModel.selectedClip == nil
            ? NSLocalizedString("Select a clip to apply a transition.", comment: "")
            : nil

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
                                    systemImage: type == .none ? "nosign" : "rectangle.2.swap",
                                    previewKind: .transition,
                                    disabledReason: disabledReason
                                )
                                .onHover { isHovering in
                                    setLibraryHoverPreview(isHovering, title: type.displayName, kind: .transition)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type.displayName)
                            .accessibilityHint(LibraryHoverPreviewKind.transition.previewHelp(for: type.displayName, disabledReason: disabledReason))
                            .help(LibraryHoverPreviewKind.transition.previewHelp(for: type.displayName, disabledReason: disabledReason))
                        }
                    }
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
        .accessibilityLabel(NSLocalizedString("Transition browser", comment: ""))
    }

    @ViewBuilder
    private var embeddedLibrarySearchNote: some View {
        if !librarySearchQuery.isEmpty {
            HStack(spacing: MovieCutSpacing.xSmall) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(embeddedLibrarySearchNoteText)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, MovieCutSpacing.medium)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func effectGrid(
        title: String,
        systemImage: String,
        previewKind: LibraryHoverPreviewKind,
        types: [EffectType],
        emptyMessage: String
    ) -> some View {
        let effects = filteredEffectTypes(types)
        let disabledReason = viewModel.selectedClip == nil ? emptyMessage : nil

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
                                    systemImage: systemImage,
                                    previewKind: previewKind,
                                    disabledReason: disabledReason
                                )
                                .onHover { isHovering in
                                    setLibraryHoverPreview(isHovering, title: type.displayName, kind: previewKind)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(type.displayName)
                            .accessibilityHint(previewKind.previewHelp(for: type.displayName, disabledReason: disabledReason))
                            .help(previewKind.previewHelp(for: type.displayName, disabledReason: disabledReason))
                        }
                    }
                }
            }
            .padding(MovieCutSpacing.medium)
        }
        .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func librarySearchEmptyState() -> some View {
        VStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(format: NSLocalizedString("No results for \"%@\"", comment: ""), librarySearchQuery))
                .font(MovieCutTypography.cardBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .movieCutLibraryBrowserCard(background: MovieCutTheme.libraryCardBackground)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func selectClipEmptyState(message: String) -> some View {
        VStack(spacing: MovieCutSpacing.small) {
            Image(systemName: "cursorarrow.click.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(MovieCutTypography.cardBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .movieCutLibraryBrowserCard(background: MovieCutTheme.libraryCardBackground)
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

    private func browserGridCard(
        title: String,
        subtitle: String,
        systemImage: String,
        previewKind: LibraryHoverPreviewKind? = nil,
        affordanceSystemImage: String = "plus.circle.fill",
        affordanceText: String? = nil,
        disabledReason: String? = nil
    ) -> some View {
        let isPreviewHovered = previewKind.map { kind in
            hoveredLibraryPreviewTitle == title && hoveredLibraryPreviewKind == kind
        } ?? false

        return VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            if let previewKind {
                ZStack {
                    libraryPreviewPlaceholder(systemImage: systemImage, kind: previewKind, disabledReason: disabledReason)

                    if isPreviewHovered {
                        libraryHoverVisualPreview(title: title, kind: previewKind)
                    }
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
                .accessibilityLabel(previewKind.previewLabel(for: title))
                .accessibilityHint(previewKind.previewHelp(for: title, disabledReason: disabledReason))
            } else {
                libraryStaticThumbnailWell(systemImage: systemImage, disabledReason: disabledReason)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(MovieCutTypography.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(subtitle)
                .font(MovieCutTypography.cardBody)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            if let disabledReason {
                Label(disabledReason, systemImage: "info.circle")
                    .font(MovieCutTypography.metadata.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                HStack(spacing: MovieCutSpacing.xSmall) {
                    Spacer()
                    if let affordanceText {
                        Text(affordanceText)
                            .font(MovieCutTypography.metadata.weight(.semibold))
                            .lineLimit(1)
                    }
                    Image(systemName: affordanceSystemImage)
                }
                .foregroundStyle(MovieCutTheme.accentCyan.opacity(0.82))
            }
        }
        .frame(maxWidth: .infinity, minHeight: previewKind == nil ? 104 : 148, alignment: .topLeading)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: MovieCutTheme.libraryCardBackground
        )
        .help(libraryPreviewHelp(title: title, kind: previewKind, disabledReason: disabledReason))
        .contentShape(Rectangle())
    }

    private func libraryStaticThumbnailWell(systemImage: String, disabledReason: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.libraryThumbnailBackground.opacity(disabledReason == nil ? 1 : 0.72))

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MovieCutTheme.libraryThumbnailStripe.opacity(index == 1 ? 0.72 : 0.42))
                        .frame(width: 14 + CGFloat(index * 5), height: 34 - CGFloat(index * 4))
                }
            }
            .offset(x: 18, y: 8)

            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(disabledReason == nil ? MovieCutTheme.accentCyan.opacity(0.88) : MovieCutTheme.mutedText)
        }
    }

    private func stickerGridCard(_ sticker: StickerAsset) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack(alignment: .top, spacing: MovieCutSpacing.small) {
                stickerPreviewGlyph(sticker)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                    Text(sticker.name)
                        .font(MovieCutTypography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Label(stickerCategoryName(sticker), systemImage: stickerSystemImage(sticker))
                        .font(MovieCutTypography.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text(stickerDescription(sticker))
                .font(MovieCutTypography.cardBody)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack(spacing: MovieCutSpacing.xSmall) {
                Spacer()
                Text(NSLocalizedString("Add", comment: ""))
                    .font(MovieCutTypography.metadata.weight(.semibold))
                Image(systemName: "plus.circle.fill")
            }
            .foregroundStyle(MovieCutTheme.accentCyan.opacity(0.82))
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: MovieCutTheme.libraryCardBackground
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func stickerPreviewGlyph(_ sticker: StickerAsset) -> some View {
        if let emoji = sticker.emoji, !sticker.isImageBacked {
            Text(emoji)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = StickerImageProvider.previewImage(for: sticker) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.libraryThumbnailBackground)
                Image(systemName: stickerSystemImage(sticker))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func libraryPreviewPlaceholder(
        systemImage: String,
        kind: LibraryHoverPreviewKind,
        disabledReason: String?
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.libraryThumbnailBackground.opacity(disabledReason == nil ? 1 : 0.62))
            LinearGradient(
                colors: [
                    kind.previewAccent.opacity(disabledReason == nil ? 0.16 : 0.08),
                    MovieCutTheme.libraryCardBackground.opacity(0.68)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(disabledReason == nil ? kind.previewAccent.opacity(0.82) : MovieCutTheme.mutedText)
        }
    }

    @ViewBuilder
    private func libraryHoverVisualPreview(title: String, kind: LibraryHoverPreviewKind) -> some View {
        switch kind {
        case .transition:
            transitionPreviewSwatch(title: title)
        case .effect, .filter, .adjustment:
            effectFilterPreviewSwatch(title: title, kind: kind)
        }
    }

    private func effectFilterPreviewSwatch(title: String, kind: LibraryHoverPreviewKind) -> some View {
        ZStack {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        MovieCutTheme.libraryThumbnailBackground,
                        MovieCutTheme.libraryCardBackground,
                        Color.gray.opacity(0.2)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        kind.previewAccent.opacity(0.34),
                        MovieCutTheme.accentCyan.opacity(kind == .filter ? 0.3 : 0.16),
                        MovieCutTheme.libraryRaisedCardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            Rectangle()
                .fill(Color.white.opacity(0.38))
                .frame(width: 1)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(NSLocalizedString("Before", comment: ""))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(kind.previewToken)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(kind.previewAccent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(MovieCutTheme.libraryRaisedCardBackground.opacity(0.86))
                        )
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    Text(title)
                        .font(MovieCutTypography.micro.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Spacer()
                    Text(NSLocalizedString("After", comment: ""))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(kind.previewAccent)
                }
            }
            .padding(6)

            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(kind.previewAccent.opacity(0.46), lineWidth: 1)
        }
    }

    private func transitionPreviewSwatch(title: String) -> some View {
        ZStack {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        MovieCutTheme.libraryThumbnailBackground,
                        Color.blue.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                LinearGradient(
                    colors: [
                        MovieCutTheme.accentCyan.opacity(0.28),
                        MovieCutTheme.libraryRaisedCardBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            HStack(spacing: 0) {
                Text(NSLocalizedString("A", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.78))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                ZStack {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(MovieCutTheme.accentCyan.opacity(0.28))
                        .frame(width: 14)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MovieCutTheme.accentCyan)
                }
                .frame(width: 22)

                Text(NSLocalizedString("B", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MovieCutTheme.accentCyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: LibraryHoverPreviewKind.transition.systemImage)
                        .font(.system(size: 8, weight: .bold))
                    Text(title)
                        .font(MovieCutTypography.micro.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MovieCutTheme.libraryRaisedCardBackground.opacity(0.72))
            }

            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.accentCyan.opacity(0.48), lineWidth: 1)
        }
    }

    private func libraryPreviewHelp(
        title: String,
        kind: LibraryHoverPreviewKind?,
        disabledReason: String?
    ) -> String {
        guard let kind else {
            return disabledReason ?? ""
        }

        return kind.previewHelp(for: title, disabledReason: disabledReason)
    }

    @ViewBuilder
    private var mediaContent: some View {
        let assets = filteredMediaAssets

        if viewModel.mediaAssets.isEmpty {
            mediaImportCTAEmptyState
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
            .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
            .accessibilityLabel(NSLocalizedString("Asset Grid", comment: ""))
        }
    }

    private var mediaImportCTAEmptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                mediaCompactImportSourceRow
                mediaCompactDropTile
                mediaEmptyGridRhythm
            }
            .padding(MovieCutSpacing.medium)
        }
        .movieCutScrollBackground(MovieCutTheme.libraryWellBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(NSLocalizedString("Import media", comment: ""))
        .accessibilityHint(NSLocalizedString("Drop media files here to import them, or use the Import Media button.", comment: ""))
    }

    private var mediaCompactImportSourceRow: some View {
        HStack(spacing: MovieCutSpacing.small) {
            Label(NSLocalizedString("Local media", comment: ""), systemImage: "folder")
                .font(MovieCutTypography.metadata.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: MovieCutSpacing.small)

            Button {
                openImportPanel()
            } label: {
                Label(NSLocalizedString("Import", comment: ""), systemImage: "square.and.arrow.down")
                    .font(MovieCutTypography.metadata.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(MovieCutTheme.accentCyan)
            .accessibilityLabel(NSLocalizedString("Import media", comment: ""))
            .accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))
        }
        .padding(.horizontal, MovieCutSpacing.small)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.librarySourceRowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.border.opacity(0.22), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var mediaCompactDropTile: some View {
        Button {
            openImportPanel()
        } label: {
            HStack(alignment: .center, spacing: MovieCutSpacing.medium) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(MovieCutTheme.accentCyan)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(MovieCutTheme.accentCyan.opacity(0.12))
                    )
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                    Text(NSLocalizedString("Drop files to import", comment: ""))
                        .font(MovieCutTypography.cardTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(NSLocalizedString("Video, audio, and image assets appear in this grid.", comment: ""))
                        .font(MovieCutTypography.cardBody)
                        .foregroundStyle(MovieCutTheme.mutedText)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        }
        .buttonStyle(.plain)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: MovieCutTheme.libraryRaisedCardBackground,
            border: MovieCutTheme.accentCyan.opacity(0.24)
        )
        .accessibilityLabel(NSLocalizedString("Import media", comment: ""))
        .accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))
    }

    private var mediaEmptyGridRhythm: some View {
        LazyVGrid(columns: libraryGridColumns, alignment: .leading, spacing: MovieCutSpacing.small) {
            ForEach(0..<6, id: \.self) { index in
                mediaEmptySkeletonCard(index: index)
            }
        }
        .accessibilityHidden(true)
    }

    private func mediaEmptySkeletonCard(index: Int) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.libraryThumbnailBackground.opacity(0.72))
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(MovieCutTheme.librarySkeletonFill.opacity(column == index % 3 ? 0.86 : 0.54))
                            .frame(width: 16 + CGFloat(column * 4), height: 24 + CGFloat((index + column) % 3) * 6)
                    }
                }
                .padding(MovieCutSpacing.small)
            }
            .frame(height: 64)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MovieCutTheme.librarySkeletonFill)
                .frame(width: index.isMultiple(of: 2) ? 72 : 96, height: 6)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(MovieCutTheme.librarySkeletonFill.opacity(0.56))
                .frame(width: 52, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: MovieCutTheme.libraryCardBackground.opacity(0.72),
            border: MovieCutTheme.border.opacity(0.10)
        )
    }

    private func assetGridCard(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            ZStack(alignment: .topTrailing) {
                assetGridThumbnailView(asset)

                HStack(spacing: MovieCutSpacing.xSmall) {
                    assetAddButton(asset)
                    proxyButton(asset)
                }
                .padding(MovieCutSpacing.xSmall)
            }

            assetInfoView(asset)
                .frame(maxWidth: .infinity, alignment: .leading)

            assetStateText(asset)
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .movieCutLibraryBrowserCard(
            padding: MovieCutSpacing.small,
            background: asset.id == viewModel.selectedAssetId ? MovieCutTheme.libraryRaisedCardBackground : MovieCutTheme.libraryCardBackground,
            border: asset.id == viewModel.selectedAssetId ? MovieCutTheme.accentCyan.opacity(0.45) : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectedAssetId = asset.id
        }
        .onTapGesture(count: 2) {
            viewModel.selectedAssetId = asset.id
            Task { await viewModel.addClipToTimeline() }
        }
        .onDrag {
            viewModel.selectedAssetId = asset.id
            return assetDragProvider(for: asset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(asset.originalURL.lastPathComponent)
        .accessibilityValue(assetAccessibilityValue(asset))
        .accessibilityHint(NSLocalizedString("Selects this asset. Drag it to the timeline to create a clip, double-click it, or use its Add button.", comment: ""))
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

    private func assetAddButton(_ asset: MediaAsset) -> some View {
        Button {
            viewModel.selectedAssetId = asset.id
            Task { await viewModel.addClipToTimeline() }
        } label: {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(MovieCutTheme.accentCyan)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .frame(width: 24, height: 24)
        .background(
            Circle()
                .fill(MovieCutTheme.libraryRaisedCardBackground.opacity(0.85))
        )
        .help(NSLocalizedString("Add to Timeline", comment: ""))
        .accessibilityLabel(String(format: NSLocalizedString("Add %@ to timeline", comment: ""), asset.originalURL.lastPathComponent))
        .accessibilityHint(NSLocalizedString("Adds this asset to the timeline.", comment: ""))
    }

    private func assetInfoView(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(asset.originalURL.lastPathComponent)
                .lineLimit(1)
                .font(MovieCutTypography.cardTitle)
            if let detail = assetDetailSummary(asset) {
                Text(detail)
                    .lineLimit(1)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
            }
            assetStateText(asset)
        }
    }

    @ViewBuilder
    private func assetStateText(_ asset: MediaAsset) -> some View {
        if asset.kind == .video {
            Text(proxyStateText(asset))
                .font(MovieCutTypography.metadata)
                .foregroundStyle(asset.proxy?.proxyURL == nil ? Color.secondary : Color.green)
        } else if asset.kind == .image {
            Text(thumbnailStateText(asset))
                .font(MovieCutTypography.metadata)
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
            .controlSize(.small)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(MovieCutTheme.libraryRaisedCardBackground.opacity(0.85))
            )
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

    private var filteredStickerAssets: [StickerAsset] {
        StickerLibrary.builtIn().stickers.filter(stickerMatchesLibrarySearch)
    }

    private var embeddedLibrarySearchNoteText: String {
        switch selectedLibraryTab {
        case .audio:
            return NSLocalizedString("Use the Music and Sound Effects search fields below to filter audio.", comment: "")
        case .media, .text, .captions, .stickers, .effects, .transitions, .filters, .adjustment, .smart:
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

    private func stickerMatchesLibrarySearch(_ sticker: StickerAsset) -> Bool {
        librarySearchMatches([
            sticker.name,
            stickerCategoryName(sticker),
            stickerDescription(sticker),
            sticker.emoji ?? "",
            NSLocalizedString("Sticker", comment: "")
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

    private var adjustmentEffectTypes: [EffectType] {
        [.brightness, .contrast, .saturation, .temperature, .exposure]
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

    private func stickerCategoryName(_ sticker: StickerAsset) -> String {
        sticker.isImageBacked
            ? NSLocalizedString("Badge/Image", comment: "")
            : NSLocalizedString("Emoji", comment: "")
    }

    private func stickerDescription(_ sticker: StickerAsset) -> String {
        sticker.isImageBacked
            ? NSLocalizedString("Image-backed badge overlay that can be placed on the timeline.", comment: "")
            : NSLocalizedString("Emoji sticker overlay that can be placed on the timeline.", comment: "")
    }

    private func stickerSystemImage(_ sticker: StickerAsset) -> String {
        sticker.isImageBacked ? "photo.on.rectangle" : "face.smiling"
    }

    private func setLibraryHoverPreview(_ isHovering: Bool, title: String, kind: LibraryHoverPreviewKind) {
        if isHovering {
            hoveredLibraryPreviewTitle = title
            hoveredLibraryPreviewKind = kind
        } else if hoveredLibraryPreviewTitle == title && hoveredLibraryPreviewKind == kind {
            hoveredLibraryPreviewTitle = nil
            hoveredLibraryPreviewKind = nil
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
                .fill(MovieCutTheme.libraryThumbnailBackground)

            if let image = thumbnailImage(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .overlay(Color.black.opacity(0.10))
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
                .fill(MovieCutTheme.libraryThumbnailBackground)

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

private enum SmartLibraryTool: CaseIterable, Identifiable, Equatable {
    case autoCut
    case sceneDetect
    case beatDetect
    case reframe
    case noiseReduction
    case extractAudio

    var id: Self { self }

    var title: String {
        switch self {
        case .autoCut:
            return NSLocalizedString("Auto Cut", comment: "")
        case .sceneDetect:
            return NSLocalizedString("Detect Scenes", comment: "")
        case .beatDetect:
            return NSLocalizedString("Detect Beats", comment: "")
        case .reframe:
            return NSLocalizedString("Auto Reframe", comment: "")
        case .noiseReduction:
            return NSLocalizedString("Noise Reduce", comment: "")
        case .extractAudio:
            return NSLocalizedString("Extract Audio", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .autoCut:
            return "speaker.slash"
        case .sceneDetect:
            return "film.stack"
        case .beatDetect:
            return "metronome"
        case .reframe:
            return "viewfinder"
        case .noiseReduction:
            return "waveform.badge.minus"
        case .extractAudio:
            return "waveform"
        }
    }

    var description: String {
        switch self {
        case .autoCut:
            return NSLocalizedString("Analyze silence and prepare automatic cuts for the selected clip.", comment: "")
        case .sceneDetect:
            return NSLocalizedString("Find visual scene changes and add cut markers for review.", comment: "")
        case .beatDetect:
            return NSLocalizedString("Detect beats and add timeline markers for music edits.", comment: "")
        case .reframe:
            return NSLocalizedString("Track the subject and write crop keyframes for the canvas.", comment: "")
        case .noiseReduction:
            return NSLocalizedString("Render a denoised audio version for the selected clip.", comment: "")
        case .extractAudio:
            return NSLocalizedString("Extract the selected video clip's audio onto the timeline.", comment: "")
        }
    }

    var disabledReason: String {
        switch self {
        case .autoCut, .beatDetect, .noiseReduction:
            return NSLocalizedString("Select an audio or video clip.", comment: "")
        case .sceneDetect, .reframe, .extractAudio:
            return NSLocalizedString("Select a video clip.", comment: "")
        }
    }

    var progressMessage: String {
        switch self {
        case .autoCut:
            return NSLocalizedString("Analyzing silence...", comment: "")
        case .sceneDetect:
            return NSLocalizedString("Detecting scene changes...", comment: "")
        case .beatDetect:
            return NSLocalizedString("Detecting beats...", comment: "")
        case .reframe:
            return NSLocalizedString("Tracking crop frames...", comment: "")
        case .noiseReduction:
            return NSLocalizedString("Rendering denoised audio...", comment: "")
        case .extractAudio:
            return NSLocalizedString("Extracting audio...", comment: "")
        }
    }
}

private enum LibraryHoverPreviewKind {
    case effect
    case filter
    case adjustment
    case transition

    var systemImage: String {
        switch self {
        case .effect:
            return "sparkles"
        case .filter:
            return "camera.filters"
        case .adjustment:
            return "slider.horizontal.3"
        case .transition:
            return "rectangle.2.swap"
        }
    }

    var previewAccent: Color {
        switch self {
        case .effect:
            return MovieCutTheme.accentCyan
        case .filter:
            return Color.purple
        case .adjustment:
            return Color.orange
        case .transition:
            return MovieCutTheme.accentCyan
        }
    }

    var previewToken: String {
        switch self {
        case .effect:
            return NSLocalizedString("FX", comment: "")
        case .filter:
            return NSLocalizedString("Filter", comment: "")
        case .adjustment:
            return NSLocalizedString("Adjust", comment: "")
        case .transition:
            return NSLocalizedString("A/B", comment: "")
        }
    }

    func previewLabel(for title: String) -> String {
        switch self {
        case .effect:
            return String(format: NSLocalizedString("Preview effect: %@", comment: ""), title)
        case .filter:
            return String(format: NSLocalizedString("Preview filter: %@", comment: ""), title)
        case .adjustment:
            return String(format: NSLocalizedString("Preview adjustment: %@", comment: ""), title)
        case .transition:
            return String(format: NSLocalizedString("Preview transition: %@", comment: ""), title)
        }
    }

    func previewHelp(for title: String, disabledReason: String? = nil) -> String {
        let previewMessage: String
        let applyMessage: String

        switch self {
        case .effect:
            previewMessage = String(format: NSLocalizedString("Hover shows a visual-only effect preview for %@.", comment: ""), title)
            applyMessage = String(format: NSLocalizedString("Click applies the %@ effect to the selected clip.", comment: ""), title)
        case .filter:
            previewMessage = String(format: NSLocalizedString("Hover shows a visual-only filter preview for %@.", comment: ""), title)
            applyMessage = String(format: NSLocalizedString("Click applies the %@ filter to the selected clip.", comment: ""), title)
        case .adjustment:
            previewMessage = String(format: NSLocalizedString("Hover shows a visual-only adjustment preview for %@.", comment: ""), title)
            applyMessage = String(format: NSLocalizedString("Click applies the %@ adjustment to the selected clip.", comment: ""), title)
        case .transition:
            previewMessage = String(format: NSLocalizedString("Hover shows a visual-only A/B transition preview for %@.", comment: ""), title)
            applyMessage = NSLocalizedString("Click applies this transition to the selected clip.", comment: "")
        }

        return [previewMessage, disabledReason ?? applyMessage].joined(separator: " ")
    }
}

private enum LibraryTab: CaseIterable, Identifiable {
    case media
    case audio
    case text
    case captions
    case stickers
    case effects
    case transitions
    case filters
    case adjustment
    case smart

    var id: Self { self }

    var displayName: String {
        switch self {
        case .media:
            return NSLocalizedString("Media", comment: "")
        case .audio:
            return NSLocalizedString("Audio", comment: "")
        case .text:
            return NSLocalizedString("Text", comment: "")
        case .captions:
            return NSLocalizedString("Captions", comment: "")
        case .stickers:
            return NSLocalizedString("Stickers", comment: "")
        case .effects:
            return NSLocalizedString("Effects", comment: "")
        case .transitions:
            return NSLocalizedString("Transitions", comment: "")
        case .filters:
            return NSLocalizedString("Filters", comment: "")
        case .adjustment:
            return NSLocalizedString("Adjust", comment: "")
        case .smart:
            return NSLocalizedString("Smart", comment: "")
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
        case .captions:
            return NSLocalizedString("Auto subtitles and SRT", comment: "")
        case .stickers:
            return NSLocalizedString("Emoji and visual stickers", comment: "")
        case .effects:
            return NSLocalizedString("Clip effects", comment: "")
        case .transitions:
            return NSLocalizedString("Clip boundary motion", comment: "")
        case .filters:
            return NSLocalizedString("Looks and LUT-style filters", comment: "")
        case .adjustment:
            return NSLocalizedString("Color and look controls", comment: "")
        case .smart:
            return NSLocalizedString("AI tools and automation", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .media: return "photo.on.rectangle.angled"
        case .audio: return "waveform"
        case .text: return "textformat"
        case .captions: return "captions.bubble"
        case .stickers: return "face.smiling"
        case .effects: return "sparkles"
        case .transitions: return "rectangle.2.swap"
        case .filters: return "camera.filters"
        case .adjustment: return "slider.horizontal.3"
        case .smart: return "wand.and.stars"
        }
    }

    var railLabel: String {
        switch self {
        case .media:
            return NSLocalizedString("Media", comment: "")
        case .audio:
            return NSLocalizedString("Audio", comment: "")
        case .text:
            return NSLocalizedString("Text", comment: "")
        case .captions:
            return NSLocalizedString("Caps", comment: "")
        case .stickers:
            return NSLocalizedString("Sticker", comment: "")
        case .effects:
            return NSLocalizedString("FX", comment: "")
        case .transitions:
            return NSLocalizedString("Trans", comment: "")
        case .filters:
            return NSLocalizedString("Filter", comment: "")
        case .adjustment:
            return NSLocalizedString("Adjust", comment: "")
        case .smart:
            return NSLocalizedString("Smart", comment: "")
        }
    }

    var accessibilityHint: String {
        String(format: NSLocalizedString("Shows the %@ library browser.", comment: ""), displayName)
    }
}
