import Foundation
import Testing

/// R2-05 keeps media-library clip creation presentation-scoped while exposing
/// CapCut-style drag, double-click, and explicit per-card add interactions.
@Suite("R2-05 Library Add Interaction StaticContract")
struct R205LibraryAddInteractionStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R205LibraryAddInteractionStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R205LibraryAddInteractionStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Media asset cards keep drag while adding double click and explicit add")
    func mediaAssetCardsKeepDragWhileAddingDoubleClickAndExplicitAdd() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let assetCard = try section(
            in: source,
            from: "private func assetGridCard(_ asset: MediaAsset) -> some View",
            to: "    private func assetAddButton"
        )
        let doubleClick = try section(
            in: assetCard,
            from: ".onTapGesture(count: 2) {",
            to: "        .onDrag {"
        )
        let drag = try section(
            in: assetCard,
            from: ".onDrag {",
            to: "        .accessibilityElement(children: .contain)"
        )

        #expect(assetCard.contains("assetGridThumbnailView(asset)"))
        #expect(assetCard.contains("assetAddButton(asset)"))
        #expect(assetCard.contains("proxyButton(asset)"))
        #expect(assetCard.contains(".onTapGesture {"))
        #expect(doubleClick.contains("viewModel.selectedAssetId = asset.id"))
        #expect(doubleClick.contains("Task { await viewModel.addClipToTimeline() }"))
        #expect(drag.contains("viewModel.selectedAssetId = asset.id"))
        #expect(drag.contains("return assetDragProvider(for: asset)"))
        #expect(assetCard.contains("viewModel.generateProxy(for: asset.id)"))
        #expect(assetCard.contains("Selects this asset. Drag it to the timeline to create a clip, double-click it, or use its Add button."))
    }

    @Test("Explicit media add button selects asset before adding to timeline")
    func explicitMediaAddButtonSelectsAssetBeforeAddingToTimeline() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let addButton = try section(
            in: source,
            from: "private func assetAddButton(_ asset: MediaAsset) -> some View",
            to: "    private func assetInfoView"
        )

        #expect(addButton.contains("Button {"))
        #expect(addButton.contains("viewModel.selectedAssetId = asset.id"))
        #expect(addButton.contains("Task { await viewModel.addClipToTimeline() }"))
        #expect(addButton.contains(#"Image(systemName: "plus.circle.fill")"#))
        #expect(addButton.contains(#".accessibilityLabel(String(format: NSLocalizedString("Add %@ to timeline", comment: ""), asset.originalURL.lastPathComponent))"#))
        #expect(addButton.contains(#".accessibilityHint(NSLocalizedString("Adds this asset to the timeline.", comment: ""))"#))

        let selection = try #require(addButton.range(of: "viewModel.selectedAssetId = asset.id"))
        let add = try #require(addButton.range(of: "Task { await viewModel.addClipToTimeline() }"))
        #expect(selection.lowerBound < add.lowerBound)
    }

    @Test("Browser grid cards keep plus affordance and add apply hints")
    func browserGridCardsKeepPlusAffordanceAndAddApplyHints() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let browserCard = try section(
            in: source,
            from: "private func browserGridCard(title: String, subtitle: String, systemImage: String) -> some View",
            to: "    @ViewBuilder\n    private var mediaContent"
        )

        #expect(browserCard.contains(#"Image(systemName: "plus.circle.fill")"#))
        #expect(source.contains("Task { await viewModel.addTextTemplateClip(template) }"))
        #expect(source.contains("applyEffect(type)"))
        #expect(source.contains("applyTransition(type)"))
        #expect(source.contains(#".accessibilityHint(NSLocalizedString("Adds this text template to the timeline.", comment: ""))"#))
        #expect(source.contains(#".accessibilityHint(String(format: NSLocalizedString("Applies the %@ effect to the selected clip.", comment: ""), type.displayName))"#))
        #expect(source.contains(#".accessibilityHint(NSLocalizedString("Applies this transition to the selected clip.", comment: ""))"#))
    }

    @Test("R2-05 docs are complete without overclaiming R2-04")
    func r205DocsAreCompleteWithoutOverclaimingR204() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let r205Row = try section(
            in: docs,
            from: "| R2-05 | 드래그 **또는** ＋/더블클릭 추가 |",
            to: "\n\n### R3."
        )

        #expect(docs.contains("| R2-04 | hover 미리듣기/미리보기 | ❌ |"))
        #expect(r205Row.contains("✅ 구현(2026-06-16, Codex R2-05):"))
        #expect(r205Row.contains("`addClipToTimeline()`"))
        #expect(r205Row.contains("검증: `git diff --check`, `swift test --filter StaticContract`(177 tests / 45 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED"))
        #expect(docs.contains("- **P1 완료** — R1-02, R2-02, R2-03, R2-05, R4-02, R5-02, R5-03."))
        #expect(docs.contains("- **P1 인터랙션** — R2-04, R3-01 세부 마감."))
        #expect(!docs.contains("| R2-04 | hover 미리듣기/미리보기 | ✅"))
    }
}

private enum R205LibraryAddInteractionStaticContractError: Error {
    case missingMarker(String)
}
