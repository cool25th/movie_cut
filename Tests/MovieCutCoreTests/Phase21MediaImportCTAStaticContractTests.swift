import Foundation
import Testing

/// Phase 2-1 makes the true empty Media tab a large import/drop call-to-action
/// while preserving the existing panel drop path and filtered-search empty state.
@Suite("Phase 2-1 Media Import CTA StaticContract")
struct Phase21MediaImportCTAStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw Phase21MediaImportCTAStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw Phase21MediaImportCTAStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Media tab true empty state uses the large import CTA helper")
    func mediaTabTrueEmptyStateUsesImportCTAHelper() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let mediaContent = try section(
            in: source,
            from: "private var mediaContent: some View",
            to: "    private func assetGridCard"
        )
        let importCTA = try section(
            in: source,
            from: "private var mediaImportCTAEmptyState: some View",
            to: "    private func assetGridCard"
        )

        #expect(source.contains("private var mediaImportCTAEmptyState: some View"))
        #expect(mediaContent.contains("if viewModel.mediaAssets.isEmpty {\n            mediaImportCTAEmptyState"))
        #expect(!mediaContent.contains("Image(systemName: \"photo.on.rectangle.angled\")"))
        #expect(!mediaContent.contains(#"Text(NSLocalizedString("Drop media files here", comment: ""))"#))
        #expect(!mediaContent.contains(".frame(maxWidth: 220)"))

        for marker in [
            "Image(systemName: \"square.and.arrow.down\")",
            ".font(.system(size: 44, weight: .semibold))",
            "MovieCutTheme.accentCyan",
            #"Text(NSLocalizedString("Import media", comment: ""))"#,
            #"Drag media files here or choose files to start editing"#,
            #"Label(NSLocalizedString("Import Media", comment: ""), systemImage: "square.and.arrow.down")"#,
            "openImportPanel()",
            ".buttonStyle(.borderedProminent)",
            ".controlSize(.large)",
            #"Accepted: video, audio, images"#,
            ".frame(maxWidth: .infinity, minHeight: 220)",
            "padding: MovieCutSpacing.large"
        ] {
            #expect(importCTA.contains(marker))
        }
    }

    @Test("Media import CTA exposes accessible labels and drop hints")
    func mediaImportCTAExposesAccessibleLabelsAndDropHints() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let importCTA = try section(
            in: source,
            from: "private var mediaImportCTAEmptyState: some View",
            to: "    private func assetGridCard"
        )

        #expect(importCTA.contains(#".accessibilityLabel(NSLocalizedString("Import media", comment: ""))"#))
        #expect(importCTA.contains(#".accessibilityHint(NSLocalizedString("Opens a file picker for video, audio, or image assets.", comment: ""))"#))
        #expect(importCTA.contains("Drop media files here to import them, or use the Import Media button."))
        #expect(importCTA.contains(".accessibilityElement(children: .contain)"))
    }

    @Test("Panel drop import and filtered-search empty state remain separate")
    func panelDropImportAndFilteredSearchEmptyStateRemainSeparate() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")
        let body = try section(
            in: source,
            from: "var body: some View",
            to: "    @ViewBuilder\n    private var headerActions"
        )
        let mediaContent = try section(
            in: source,
            from: "private var mediaContent: some View",
            to: "    private func assetGridCard"
        )

        #expect(body.contains(".onDrop(of: [.fileURL, .movie, .image], isTargeted: nil)"))
        #expect(body.contains("handleDrop(providers)"))
        #expect(body.contains("return true"))
        #expect(body.contains(#".accessibilityHint(NSLocalizedString("Drop media files here to import them.", comment: ""))"#))
        #expect(mediaContent.contains("} else if assets.isEmpty {\n            librarySearchEmptyState()"))
        #expect(mediaContent.contains("let assets = filteredMediaAssets"))
    }

    @Test("Handoff marks only Phase 2-1 implemented")
    func handoffKeepsPhase21ImplementedAfterPhase22Completion() throws {
        let handoff = try source("docs/CAPCUT_UI_SHOWCASE_HANDOFF.md")

        #expect(handoff.contains("Phase 2-1 implemented"))
        #expect(handoff.contains("Phase21MediaImportCTAStaticContractTests"))
        #expect(handoff.contains("Phase 2-2 implemented"))
        #expect(handoff.contains("Phase 2-3 and Phase 2-4 remain pending"))
        #expect(!handoff.contains("Phase 2 complete"))
    }
}

private enum Phase21MediaImportCTAStaticContractError: Error {
    case missingMarker(String)
}
