import Foundation
import Testing

/// Phase 2-2 upgrades effect/filter/adjustment/transition hover previews from
/// text-only affordances into deterministic local visual preview surfaces.
@Suite("Phase 2-2 Hover Visual Preview StaticContract")
struct Phase22HoverVisualPreviewStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase22HoverVisualPreviewStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase22HoverVisualPreviewStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Browser cards render visual preview helpers under hover state")
    func browserCardsRenderVisualPreviewHelpersUnderHoverState() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let browserCard = try section(
            in: source,
            from: "private func browserGridCard(",
            to: "    private func stickerGridCard"
        )
        let previewHelpers = try section(
            in: source,
            from: "private func libraryPreviewPlaceholder(",
            to: "    @ViewBuilder\n    private var mediaContent"
        )

        #expect(source.contains("private func libraryHoverVisualPreview(title: String, kind: LibraryHoverPreviewKind) -> some View"))
        #expect(browserCard.contains("let isPreviewHovered = previewKind.map"))
        #expect(browserCard.contains("hoveredLibraryPreviewTitle == title"))
        #expect(browserCard.contains("hoveredLibraryPreviewKind == kind"))
        #expect(browserCard.contains("if isPreviewHovered"))
        #expect(browserCard.contains("libraryHoverVisualPreview(title: title, kind: previewKind)"))
        #expect(browserCard.contains(".frame(height: 64)"))
        #expect(browserCard.contains(".help(libraryPreviewHelp(title: title, kind: previewKind, disabledReason: disabledReason))"))
        #expect(!browserCard.contains("libraryHoverPreviewAffordance"))

        for marker in [
            "private func effectFilterPreviewSwatch(title: String, kind: LibraryHoverPreviewKind) -> some View",
            "private func transitionPreviewSwatch(title: String) -> some View",
            "LinearGradient(",
            "RoundedRectangle(cornerRadius: MovieCutRadius.small",
            "MovieCutTheme.accentCyan",
            #"Text(NSLocalizedString("Before", comment: ""))"#,
            #"Text(NSLocalizedString("After", comment: ""))"#,
            #"Text(NSLocalizedString("A", comment: ""))"#,
            #"Text(NSLocalizedString("B", comment: ""))"#,
            #"Image(systemName: "arrow.right")"#
        ] {
            #expect(previewHelpers.contains(marker))
        }
    }

    @Test("Effect filter adjustment and transition cards keep browse hover and click apply separate")
    func cardsKeepBrowseHoverAndClickApplySeparate() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let transitionContent = try section(
            in: source,
            from: "private var transitionsTabContent: some View",
            to: "    @ViewBuilder\n    private var embeddedLibrarySearchNote"
        )
        let effectGrid = try section(
            in: source,
            from: "private func effectGrid(",
            to: "    @ViewBuilder\n    private func librarySearchEmptyState"
        )
        let hoverBodies = ([effectGrid, transitionContent].joined(separator: "\n"))
            .components(separatedBy: ".onHover { isHovering in")
            .dropFirst()
            .map { String($0.prefix(220)) }
            .joined(separator: "\n")

        #expect(source.contains("previewKind: .effect"))
        #expect(source.contains("previewKind: .filter"))
        #expect(source.contains("previewKind: .adjustment"))
        #expect(effectGrid.contains("previewKind: previewKind"))
        #expect(transitionContent.contains("previewKind: .transition"))
        #expect(effectGrid.contains("setLibraryHoverPreview(isHovering, title: type.displayName, kind: previewKind)"))
        #expect(transitionContent.contains("setLibraryHoverPreview(isHovering, title: type.displayName, kind: .transition)"))
        #expect(effectGrid.contains("applyEffect(type)"))
        #expect(transitionContent.contains("applyTransition(type)"))
        #expect(hoverBodies.contains("setLibraryHoverPreview"))

        for forbidden in [
            "applyEffect(type)",
            "applyTransition(type)",
            "updateSelectedEffects",
            "updateSelectedTransition",
            "dispatch",
            "render",
            "export"
        ] {
            #expect(!hoverBodies.contains(forbidden))
        }
    }

    @Test("Preview help distinguishes visual hover from click apply and disabled state")
    func previewHelpDistinguishesHoverFromClickApplyAndDisabledState() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let transitionContent = try section(
            in: source,
            from: "private var transitionsTabContent: some View",
            to: "    @ViewBuilder\n    private var embeddedLibrarySearchNote"
        )
        let effectGrid = try section(
            in: source,
            from: "private func effectGrid(",
            to: "    @ViewBuilder\n    private func librarySearchEmptyState"
        )
        let browserCard = try section(
            in: source,
            from: "private func browserGridCard(",
            to: "    private func stickerGridCard"
        )

        #expect(source.contains("func previewHelp(for title: String, disabledReason: String? = nil) -> String"))
        #expect(source.contains("Hover shows a visual-only effect preview"))
        #expect(source.contains("Hover shows a visual-only filter preview"))
        #expect(source.contains("Hover shows a visual-only adjustment preview"))
        #expect(source.contains("Hover shows a visual-only A/B transition preview"))
        #expect(source.contains("disabledReason ?? applyMessage"))
        #expect(effectGrid.contains(".accessibilityHint(previewKind.previewHelp(for: type.displayName, disabledReason: disabledReason))"))
        #expect(transitionContent.contains(".accessibilityHint(LibraryHoverPreviewKind.transition.previewHelp(for: type.displayName, disabledReason: disabledReason))"))
        #expect(effectGrid.contains(".help(previewKind.previewHelp(for: type.displayName, disabledReason: disabledReason))"))
        #expect(transitionContent.contains(".help(LibraryHoverPreviewKind.transition.previewHelp(for: type.displayName, disabledReason: disabledReason))"))
        #expect(browserCard.contains("Label(disabledReason, systemImage: \"info.circle\")"))
    }

    @Test("Handoff marks Phase 2-2 implemented without claiming Phase 2 complete")
    func handoffMarksPhase22ImplementedWithoutClaimingPhase2Complete() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 2-1 implemented"))
        #expect(handoff.contains("Phase 2-2 implemented"))
        #expect(handoff.contains("Phase22HoverVisualPreviewStaticContractTests"))
        #expect(handoff.contains("Phase 2-3 and Phase 2-4 remain pending"))
        #expect(!handoff.contains("Phase 2 complete"))
    }
}

private enum Phase22HoverVisualPreviewStaticContractError: Error {
    case missingMarker(String)
}
