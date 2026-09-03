import Foundation
import Testing

/// Phase 2-4 centralizes compact typography and spacing aliases, then applies
/// them narrowly to the CapCut-style library and timeline presentation shell.
@Suite("Phase 2-4 Typography Density StaticContract")
struct Phase24TypographyDensityStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase24TypographyDensityStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase24TypographyDensityStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Shared helpers expose compact typography and density tokens")
    func sharedHelpersExposeCompactTypographyAndDensityTokens() throws {
        let shared = try source("App/MovieCutMac/Inspector/InspectorShared.swift")
        let iconTitle = try section(
            in: shared,
            from: "struct MovieCutIconTitle: View",
            to: "struct MovieCutPanelHeader"
        )
        let panelHeader = try section(
            in: shared,
            from: "struct MovieCutPanelHeader",
            to: "extension MovieCutPanelHeader"
        )
        let sectionCard = try section(
            in: shared,
            from: "struct MovieCutSectionCard",
            to: "private struct MovieCutCardModifier"
        )
        let viewExtension = try section(
            in: shared,
            from: "extension View",
            to: "struct EffectParameterDefinition"
        )

        for marker in [
            "static let xxSmall: CGFloat = 2",
            "enum MovieCutTypography",
            "static let panelTitle: Font = .caption.weight(.semibold)",
            "static let panelSubtitle: Font = .caption2",
            "static let cardTitle: Font = .caption.weight(.semibold)",
            "static let cardBody: Font = .caption2",
            "static let metadata: Font = .caption2",
            "static let toolbar: Font = .caption",
            "static let micro: Font = .system(size: 9, weight: .medium)"
        ] {
            #expect(shared.contains(marker))
        }

        for marker in [
            "var titleFont: Font = MovieCutTypography.panelTitle",
            ".font(MovieCutTypography.toolbar.weight(.semibold))",
            ".font(titleFont)",
            ".font(MovieCutTypography.panelSubtitle)",
            ".lineSpacing(0)"
        ] {
            #expect(iconTitle.contains(marker))
        }

        #expect(panelHeader.contains("MovieCutIconTitle(title: title, systemImage: systemImage, subtitle: subtitle)"))
        #expect(panelHeader.contains(".padding(.vertical, MovieCutSpacing.xSmall)"))
        #expect(sectionCard.contains("titleFont: MovieCutTypography.cardTitle"))
        #expect(sectionCard.contains(".movieCutCard()"))

        for marker in [
            "padding: CGFloat = MovieCutSpacing.small",
            "cornerRadius: CGFloat = MovieCutRadius.medium",
            "background: Color = MovieCutTheme.cardBackground",
            "border: Color = MovieCutTheme.border",
            ".font(MovieCutTypography.cardBody)"
        ] {
            #expect(viewExtension.contains(marker))
        }
    }

    @Test("Media library cards and CTA use shared tokens without changing actions")
    func mediaLibraryCardsAndCTAUseSharedTokensWithoutChangingActions() throws {
        let media = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let railButton = try section(
            in: media,
            from: "private func libraryRailButton(for tab: LibraryTab) -> some View",
            to: "    private func selectLibraryTab"
        )
        let searchField = try section(
            in: media,
            from: "private var librarySearchField: some View",
            to: "    @ViewBuilder\n    private var mediaTabContent"
        )
        let browserCard = try section(
            in: media,
            from: "private func browserGridCard(",
            to: "    private func stickerGridCard"
        )
        let importCTA = try section(
            in: media,
            from: "private var mediaImportCTAEmptyState: some View",
            to: "    private func assetGridCard"
        )
        let assetInfo = try section(
            in: media,
            from: "private func assetInfoView(_ asset: MediaAsset) -> some View",
            to: "    @ViewBuilder\n    private func proxyButton"
        )

        #expect(railButton.contains("MovieCutSpacing.xxSmall"))
        #expect(railButton.contains("MovieCutTypography.micro"))
        #expect(searchField.contains(".font(MovieCutTypography.toolbar)"))
        #expect(searchField.contains(".font(MovieCutTypography.cardBody)"))

        for marker in [
            ".font(MovieCutTypography.cardTitle)",
            ".font(MovieCutTypography.cardBody)",
            ".font(MovieCutTypography.metadata.weight(.semibold))",
            "libraryHoverVisualPreview(title: title, kind: previewKind)",
            "Label(disabledReason, systemImage: \"info.circle\")"
        ] {
            #expect(browserCard.contains(marker))
        }

        for marker in [
            #"Label(NSLocalizedString("Local media", comment: ""), systemImage: "folder")"#,
            #"Label(NSLocalizedString("Import", comment: ""), systemImage: "square.and.arrow.down")"#,
            #"Text(NSLocalizedString("Drop files to import", comment: ""))"#,
            ".font(MovieCutTypography.cardTitle)",
            ".font(MovieCutTypography.cardBody)",
            ".font(MovieCutTypography.metadata.weight(.semibold))",
            "mediaEmptyGuidanceCard",
            #"Text(NSLocalizedString("Your library is empty", comment: ""))"#,
            "openImportPanel()"
        ] {
            #expect(importCTA.contains(marker))
        }

        #expect(assetInfo.contains(".font(MovieCutTypography.cardTitle)"))
        #expect(assetInfo.contains(".font(MovieCutTypography.metadata)"))

        for marker in [
            ".onDrop(of: [.fileURL, .movie, .image], isTargeted: nil)",
            "handleDrop(providers)",
            "await viewModel.importMedia(urls)",
            "Task { await viewModel.addClipToTimeline() }",
            "Task { await viewModel.addTextTemplateClip(template) }",
            "Task { await viewModel.addSticker(sticker) }",
            "setLibraryHoverPreview(isHovering, title: type.displayName, kind: previewKind)",
            "setLibraryHoverPreview(isHovering, title: type.displayName, kind: .transition)",
            "applyEffect(type)",
            "applyTransition(type)"
        ] {
            #expect(media.contains(marker))
        }
    }

    @Test("Timeline toolbar uses typography tokens and preserves ViewModel calls")
    func timelineToolbarUsesTypographyTokensAndPreservesViewModelCalls() throws {
        let timeline = try source("App/MovieCutMac/TimelineView.swift")
        let helper = try section(
            in: timeline,
            from: "private func timelineToolbarIconButton(",
            to: "    private var selectedClipToolbar"
        )
        let selectedToolbar = try section(
            in: timeline,
            from: "private var selectedClipToolbar: some View",
            to: "    private var timelineMarkerControls"
        )
        let markerControls = try section(
            in: timeline,
            from: "private var timelineMarkerControls: some View",
            to: "    private var selectedClipSupportsVisualTimelineEffect"
        )
        let zoomControls = try section(
            in: timeline,
            from: "private var zoomControls: some View",
            to: "    private var timelineZoomDisplay"
        )

        for marker in [
            ".frame(width: 24, height: 24)",
            ".buttonStyle(.borderless)",
            ".controlSize(.small)",
            ".font(MovieCutTypography.toolbar)",
            ".help(localizedTitle)",
            ".accessibilityLabel(localizedAccessibilityLabel)",
            ".accessibilityHint(localizedHint)"
        ] {
            #expect(helper.contains(marker))
        }

        #expect(selectedToolbar.contains(".font(MovieCutTypography.toolbar)"))
        #expect(markerControls.contains(".font(MovieCutTypography.toolbar)"))
        #expect(zoomControls.contains(".font(MovieCutTypography.toolbar)"))
        #expect(zoomControls.contains(".font(MovieCutTypography.metadata.monospacedDigit())"))
        #expect(timeline.contains("Text(\"\\(sortedMarkers.count) markers\")\n                        .font(MovieCutTypography.metadata)"))

        for marker in [
            "Task { await viewModel.splitClip() }",
            "Task { await viewModel.deleteClip() }",
            "Task { await viewModel.rippleDeleteSelectedClip() }",
            "Task { await viewModel.duplicateSelectedClips() }",
            "viewModel.snapPlayheadToSelectedClipStart()",
            "viewModel.snapPlayheadToSelectedClipEnd()",
            "Task { viewModel.noteQuickToolUsed(); await viewModel.freezeSelectedFrame() }",
            "await viewModel.updateSelectedReversePlayback(!selectedClip.isReversed)",
            "viewModel.goToPreviousMarker()",
            "viewModel.addMarkerAtPlayhead()",
            "viewModel.goToNextMarker()",
            "viewModel.zoomTimelineOut()",
            "viewModel.zoomTimelineIn()",
            "fitTimelineToAvailableWidth(timelineViewportWidth)",
            "timelineToolbarIconButton("
        ] {
            #expect(timeline.contains(marker))
        }
    }
}

private enum Phase24TypographyDensityStaticContractError: Error {
    case missingMarker(String)
}
