import Foundation
import Testing

/// R2-02/R2-03 keeps the left library browser presentation-scoped while adding
/// CapCut-style tab search and compact thumbnail/card grids.
@Suite("R2-02/R2-03 Library Search Grid StaticContract")
struct R202R203LibrarySearchGridStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R202R203LibrarySearchGridStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R202R203LibrarySearchGridStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Library panel exposes tab-aware search field")
    func libraryPanelExposesTabAwareSearchField() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let search = try section(
            in: source,
            from: "private var librarySearchField: some View",
            to: "    @ViewBuilder\n    private var mediaTabContent"
        )

        #expect(source.contains("@State private var librarySearchText = \"\""))
        #expect(source.contains("librarySearchField"))
        #expect(source.contains("librarySearchText = \"\""))
        #expect(search.contains("TextField(librarySearchPlaceholder, text: $librarySearchText)"))
        #expect(search.contains("Image(systemName: \"magnifyingglass\")"))
        #expect(search.contains("Image(systemName: \"xmark.circle.fill\")"))
        #expect(search.contains(#"accessibilityLabel(String(format: NSLocalizedString("Search %@", comment: ""), selectedLibraryTab.displayName))"#))
        #expect(search.contains(#"accessibilityHint(NSLocalizedString("Filters the selected library tab.", comment: ""))"#))
        #expect(source.contains("private var librarySearchPlaceholder: String"))
        #expect(source.contains(#"String(format: NSLocalizedString("Search %@", comment: ""), selectedLibraryTab.displayName)"#))
    }

    @Test("Library search filters each safe tab by visible labels and metadata")
    func librarySearchFiltersEachSafeTabByVisibleLabelsAndMetadata() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let filters = try section(
            in: source,
            from: "private var librarySearchPlaceholder: String",
            to: "    private var filterEffectTypes"
        )

        for marker in [
            "private var librarySearchQuery: String",
            "private var filteredMediaAssets: [MediaAsset]",
            "private var filteredTextTemplates: [MovieCutCore.TextTemplate]",
            "private var shouldShowCustomTextAction: Bool",
            "private func filteredEffectTypes(_ types: [EffectType]) -> [EffectType]",
            "private var filteredTransitionTypes: [TransitionType]",
            "private func assetMatchesLibrarySearch(_ asset: MediaAsset) -> Bool",
            "private func textTemplateMatchesLibrarySearch(_ template: MovieCutCore.TextTemplate) -> Bool",
            "private func effectTypeMatchesLibrarySearch(_ type: EffectType) -> Bool",
            "private func transitionTypeMatchesLibrarySearch(_ type: TransitionType) -> Bool",
            "private func librarySearchMatches(_ values: [String]) -> Bool"
        ] {
            #expect(filters.contains(marker))
        }

        #expect(filters.contains("asset.originalURL.lastPathComponent"))
        #expect(filters.contains("assetDetailSummary(asset)"))
        #expect(filters.contains("metadataSummary(asset)"))
        #expect(filters.contains("template.name"))
        #expect(filters.contains("template.content.text"))
        #expect(filters.contains("textTemplateSubtitle(template)"))
        #expect(filters.contains("type.displayName"))
        #expect(filters.contains("effectSubtitle(type)"))
        #expect(filters.contains("transitionSubtitle(type)"))
        #expect(filters.contains("transitionCategoryName(type.category)"))
        #expect(filters.contains(".caseInsensitive"))
        #expect(filters.contains(".diacriticInsensitive"))
    }

    @Test("Media text effects filters and transitions use grids and empty search state")
    func safeTabsUseGridsAndEmptySearchState() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        #expect(source.contains("private let libraryGridColumns = ["))
        #expect(source.contains("GridItem(.flexible(minimum: 120), spacing: MovieCutSpacing.small)"))
        #expect(source.contains("LazyVGrid(columns: libraryGridColumns"))
        #expect(source.contains("private func assetGridCard(_ asset: MediaAsset) -> some View"))
        #expect(source.contains("private func assetGridThumbnailView(_ asset: MediaAsset) -> some View"))
        #expect(source.contains("private func browserGridCard(title: String, subtitle: String, systemImage: String) -> some View"))
        #expect(source.contains("private func librarySearchEmptyState() -> some View"))
        #expect(source.contains(#"No results for \"%@\""#))
        #expect(source.contains(#"accessibilityLabel(NSLocalizedString("Asset Grid", comment: ""))"#))
        #expect(!source.contains("private func browserActionRow"))
        #expect(!source.contains("assetRow(asset)"))
    }

    @Test("Grid cards preserve existing actions and embedded browsers")
    func gridCardsPreserveExistingActionsAndEmbeddedBrowsers() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let assetCard = try section(
            in: source,
            from: "private func assetGridCard(_ asset: MediaAsset) -> some View",
            to: "    private func assetInfoView"
        )

        #expect(assetCard.contains("assetGridThumbnailView(asset)"))
        #expect(assetCard.contains("proxyButton(asset)"))
        #expect(assetCard.contains("viewModel.selectedAssetId = asset.id"))
        #expect(assetCard.contains("return assetDragProvider(for: asset)"))
        #expect(assetCard.contains("viewModel.generateProxy(for: asset.id)"))
        #expect(source.contains("Task { await viewModel.addTextTemplateClip(template) }"))
        #expect(source.contains("applyEffect(type)"))
        #expect(source.contains("applyTransition(type)"))
        #expect(source.contains("MusicLibraryView(viewModel: viewModel)"))
        #expect(source.contains("SFXPickerView(viewModel: viewModel)"))
        #expect(source.contains("StickerPickerView { sticker in"))
        #expect(source.contains("embeddedLibrarySearchNote"))
        #expect(source.contains("Use the Music and Sound Effects search fields below to filter audio."))
        #expect(source.contains("Use the sticker search field below to filter stickers."))
    }

    @Test("R2 search grid rows are marked implemented without overclaiming hover")
    func r2SearchGridRowsAreMarkedImplementedWithoutOverclaimingHover() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")

        #expect(docs.contains("| R2-02 | 탭별 검색바 | ✅ 구현(2026-06-16, Codex R2-02/R2-03):"))
        #expect(docs.contains("| R2-03 | 썸네일 그리드 | ✅ 구현(2026-06-16, Codex R2-02/R2-03):"))
        #expect(docs.contains("검증: `git diff --check`, `swift test --filter StaticContract`"))
        #expect(docs.contains("| R2-04 | hover 미리듣기/미리보기 | ❌ |"))
        #expect(docs.contains("| R2-05 | 드래그 **또는** ＋/더블클릭 추가 | ✅ 구현(2026-06-16, Codex R2-05):"))
        #expect(docs.contains("- **P1 완료** — R1-02, R2-02, R2-03, R2-05, R4-02, R5-02, R5-03."))
        #expect(docs.contains("- **P1 인터랙션** — R2-04, R3-01 세부 마감."))
        #expect(!docs.contains("| R2-04 | hover 미리듣기/미리보기 | ✅"))
    }
}

private enum R202R203LibrarySearchGridStaticContractError: Error {
    case missingMarker(String)
}
