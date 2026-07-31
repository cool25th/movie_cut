import Foundation
import Testing

/// Phase 0-3 keeps Effects, Filters, Transitions, and Stickers browseable in
/// the left library before clip selection while leaving apply/add paths intact.
@Suite("Phase 0-3 Browseable Cards StaticContract")
struct Phase03BrowseableCardsStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase03BrowseableCardsStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase03BrowseableCardsStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    @Test("Effects and filters keep catalog grids visible without selected clip")
    func effectsAndFiltersKeepCatalogGridsVisibleWithoutSelectedClip() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let effectGrid = try section(
            in: source,
            from: "private func effectGrid(",
            to: "    @ViewBuilder\n    private func librarySearchEmptyState"
        )

        #expect(source.contains("private var effectsTabContent: some View"))
        #expect(source.contains("private var filtersTabContent: some View"))
        #expect(effectGrid.contains("let disabledReason = viewModel.selectedClip == nil ? emptyMessage : nil"))
        #expect(effectGrid.contains("if viewModel.selectedClip == nil"))
        #expect(effectGrid.contains("selectClipEmptyState(message: emptyMessage)"))
        #expect(effectGrid.contains("LazyVGrid(columns: libraryGridColumns"))
        #expect(effectGrid.contains("ForEach(effects, id: \\.self) { type in"))
        #expect(effectGrid.contains("browserGridCard("))
        #expect(effectGrid.contains("disabledReason: disabledReason"))
        #expect(effectGrid.contains("applyEffect(type)"))
        #expect(!effectGrid.contains(".disabled(viewModel.selectedClip == nil)"))
        #expect(!effectGrid.contains("updateSelectedEffects"))
    }

    @Test("Transitions keep catalog grid visible without selected clip")
    func transitionsKeepCatalogGridVisibleWithoutSelectedClip() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let transitions = try section(
            in: source,
            from: "private var transitionsTabContent: some View",
            to: "    @ViewBuilder\n    private var embeddedLibrarySearchNote"
        )

        #expect(transitions.contains("let transitions = filteredTransitionTypes"))
        #expect(transitions.contains("let disabledReason = viewModel.selectedClip == nil"))
        #expect(transitions.contains(#"NSLocalizedString("Select a clip to apply a transition.", comment: "")"#))
        #expect(transitions.contains("if viewModel.selectedClip == nil"))
        #expect(transitions.contains("selectClipEmptyState(message: NSLocalizedString(\"Select a clip to apply a transition.\", comment: \"\"))"))
        #expect(transitions.contains("LazyVGrid(columns: libraryGridColumns"))
        #expect(transitions.contains("ForEach(transitions, id: \\.self) { type in"))
        #expect(transitions.contains("browserGridCard("))
        #expect(transitions.contains("disabledReason: disabledReason"))
        #expect(transitions.contains("applyTransition(type)"))
        #expect(!transitions.contains(".disabled(viewModel.selectedClip == nil)"))
        #expect(!transitions.contains("updateSelectedTransition"))
    }

    @Test("Stickers expose direct MediaLibraryPanel cards from built-in definitions")
    func stickersExposeDirectMediaLibraryPanelCards() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let stickers = try section(
            in: source,
            from: "private var stickersTabContent: some View",
            to: "    private var effectsTabContent"
        )
        let stickerCard = try section(
            in: source,
            from: "private func stickerGridCard(_ sticker: StickerAsset) -> some View",
            to: "    @ViewBuilder\n    private func stickerPreviewGlyph"
        )

        #expect(stickers.contains("let stickers = filteredStickerAssets"))
        #expect(stickers.contains("LazyVGrid(columns: libraryGridColumns"))
        #expect(stickers.contains("ForEach(stickers) { sticker in"))
        #expect(stickers.contains("stickerGridCard(sticker)"))
        #expect(stickers.contains("Task { await viewModel.addSticker(sticker) }"))
        #expect(!stickers.contains("StickerPickerView"))
        #expect(!stickers.contains("viewModel.selectedClip"))
        #expect(source.contains("private var filteredStickerAssets: [StickerAsset]"))
        #expect(source.contains("StickerLibrary.builtIn().stickers.filter(stickerMatchesLibrarySearch)"))
        #expect(source.contains("private func stickerMatchesLibrarySearch(_ sticker: StickerAsset) -> Bool"))
        #expect(stickerCard.contains("stickerPreviewGlyph(sticker)"))
        #expect(stickerCard.contains("Text(sticker.name)"))
        #expect(stickerCard.contains("Label(stickerCategoryName(sticker), systemImage: stickerSystemImage(sticker))"))
        #expect(stickerCard.contains("Text(stickerDescription(sticker))"))
        #expect(stickerCard.contains(#"Text(NSLocalizedString("Add", comment: ""))"#))
        #expect(stickerCard.contains(#"Image(systemName: "plus.circle.fill")"#))
        #expect(source.contains("StickerImageProvider.previewImage(for: sticker)"))
    }

    @Test("Apply and add actions keep existing presentation-layer call paths")
    func applyAndAddActionsKeepExistingCallPaths() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let applyEffect = try section(
            in: source,
            from: "private func applyEffect(_ type: EffectType)",
            to: "    private func applyTransition"
        )
        let applyTransition = try section(
            in: source,
            from: "private func applyTransition(_ type: TransitionType)",
            to: "    private func parameterDefinitions"
        )

        #expect(occurrences(of: "applyEffect(type)", in: source) == 1)
        #expect(occurrences(of: "applyTransition(type)", in: source) == 1)
        #expect(occurrences(of: "Task { await viewModel.addSticker(sticker) }", in: source) == 1)
        #expect(!source.contains("addStickerClip(sticker)"))
        #expect(applyEffect.contains("guard let clip = viewModel.selectedClip else { return }"))
        #expect(applyEffect.contains("Task { await viewModel.updateSelectedEffects(effects) }"))
        #expect(applyTransition.contains("guard let clip = viewModel.selectedClip else { return }"))
        #expect(applyTransition.contains("Task { await viewModel.updateSelectedTransition(transition) }"))
    }
}

private enum Phase03BrowseableCardsStaticContractError: Error {
    case missingMarker(String)
}
