import Foundation
import Testing

/// R2-04 keeps hover preview/listen behavior presentation-scoped by reusing
/// existing preview players and adding visual-only affordances for library
/// effect, filter, and transition cards.
@Suite("R2-04 Library Hover Preview StaticContract")
struct R204LibraryHoverPreviewStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R204LibraryHoverPreviewStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R204LibraryHoverPreviewStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Music library hover listen reuses AVAudioPlayer without removing click toggle")
    func musicLibraryHoverListenReusesPlayerWithoutRemovingClickToggle() throws {
        let source = try source("App/MovieCutMac/Music/MusicLibraryView.swift")
        let togglePreview = try section(
            in: source,
            from: "private func togglePreview(for track: MovieCutCore.MusicTrack)",
            to: "    private func durationText"
        )

        #expect(source.contains("import AVFoundation"))
        #expect(source.contains("@State private var previewTrackId: UUID?"))
        #expect(source.contains("@State private var hoverPreviewTrackId: UUID?"))
        #expect(source.contains("@State private var previewPlayer: AVAudioPlayer?"))
        #expect(source.contains(".onHover { isHovering in"))
        #expect(source.contains("startHoverPreview(for: track)"))
        #expect(source.contains("stopHoverPreview(for: track)"))
        #expect(source.contains("Hover to listen. Use the preview button to toggle playback"))
        #expect(togglePreview.contains("private func togglePreview(for track: MovieCutCore.MusicTrack)"))
        #expect(togglePreview.contains("hoverPreviewTrackId = nil"))
        #expect(togglePreview.contains("private func startHoverPreview(for track: MovieCutCore.MusicTrack)"))
        #expect(togglePreview.contains("private func stopHoverPreview(for track: MovieCutCore.MusicTrack)"))
        #expect(togglePreview.contains("guard hoverPreviewTrackId == track.id else { return }"))
        #expect(togglePreview.contains("private func startPreview(for track: MovieCutCore.MusicTrack)"))
        #expect(togglePreview.contains("AVAudioPlayer(contentsOf: track.fileURL)"))
        #expect(togglePreview.contains("private func stopPreview()"))
        #expect(togglePreview.contains("private func isPreviewing(_ track: MovieCutCore.MusicTrack) -> Bool"))
    }

    @Test("SFX picker exposes hover preview closures while preserving preview and add actions")
    func sfxPickerExposesHoverPreviewClosuresWhilePreservingActions() throws {
        let source = try source("App/MovieCutMac/Audio/SFXPickerView.swift")
        let itemButton = try section(
            in: source,
            from: "private struct SFXItemButton: View",
            to: "    private var iconName: String"
        )

        #expect(source.contains("import AVFoundation"))
        #expect(source.contains("@State private var previewItemId: UUID?"))
        #expect(source.contains("@State private var hoverPreviewItemId: UUID?"))
        #expect(source.contains("@State private var previewPlayer: AVAudioPlayer?"))
        #expect(source.contains("previewAction: { togglePreview(for: item) }"))
        #expect(source.contains("hoverPreviewAction: { startHoverPreview(for: item) }"))
        #expect(source.contains("hoverStopAction: { stopHoverPreview(for: item) }"))
        #expect(source.contains("Task { await viewModel.addSFXToTimeline(item) }"))
        #expect(source.contains("private func startHoverPreview(for item: SFXItem)"))
        #expect(source.contains("private func stopHoverPreview(for item: SFXItem)"))
        #expect(source.contains("guard hoverPreviewItemId == item.id else { return }"))
        #expect(source.contains("AVAudioPlayer(contentsOf: url)"))
        #expect(itemButton.contains("let previewAction: () -> Void"))
        #expect(itemButton.contains("let hoverPreviewAction: () -> Void"))
        #expect(itemButton.contains("let hoverStopAction: () -> Void"))
        #expect(itemButton.contains("let addAction: () -> Void"))
        #expect(itemButton.contains(".onHover { isHovering in"))
        #expect(itemButton.contains("hoverPreviewAction()"))
        #expect(itemButton.contains("hoverStopAction()"))
        #expect(itemButton.contains("Button(action: previewAction)"))
        #expect(itemButton.contains("Button(action: addAction)"))
        #expect(itemButton.contains("Hover to listen"))
    }

    @Test("Effect filter and transition cards expose hover preview surface without applying on hover")
    func effectFilterAndTransitionCardsExposeHoverPreviewSurface() throws {
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
            to: "    @ViewBuilder\n    private var mediaContent"
        )

        #expect(source.contains("@State private var hoveredLibraryPreviewTitle: String?"))
        #expect(source.contains("@State private var hoveredLibraryPreviewKind: LibraryHoverPreviewKind?"))
        #expect(source.contains("previewKind: .effect"))
        #expect(source.contains("previewKind: .filter"))
        #expect(transitionContent.contains("previewKind: .transition"))
        #expect(effectGrid.contains(".onHover { isHovering in"))
        #expect(effectGrid.contains("setLibraryHoverPreview(isHovering, title: type.displayName, kind: previewKind)"))
        #expect(transitionContent.contains(".onHover { isHovering in"))
        #expect(transitionContent.contains("setLibraryHoverPreview(isHovering, title: type.displayName, kind: .transition)"))
        #expect(browserCard.contains("private func libraryHoverVisualPreview(title: String, kind: LibraryHoverPreviewKind) -> some View"))
        #expect(browserCard.contains("libraryPreviewPlaceholder(systemImage: systemImage, kind: previewKind, disabledReason: disabledReason)"))
        #expect(browserCard.contains("libraryHoverVisualPreview(title: title, kind: previewKind)"))
        #expect(!browserCard.contains("libraryHoverPreviewAffordance"))
        #expect(browserCard.contains("hoveredLibraryPreviewTitle == title"))
        #expect(browserCard.contains("hoveredLibraryPreviewKind == kind"))
        #expect(source.contains(#"NSLocalizedString("Preview effect: %@", comment: "")"#))
        #expect(source.contains(#"NSLocalizedString("Preview filter: %@", comment: "")"#))
        #expect(source.contains(#"NSLocalizedString("Preview transition: %@", comment: "")"#))
        #expect(source.contains("Hover shows a visual-only effect preview"))
        #expect(source.contains("Hover shows a visual-only A/B transition preview"))
        #expect(source.contains("private func setLibraryHoverPreview(_ isHovering: Bool, title: String, kind: LibraryHoverPreviewKind)"))
        #expect(source.contains("applyEffect(type)"))
        #expect(source.contains("applyTransition(type)"))
        #expect(!effectGrid.contains("updateSelectedEffects"))
        #expect(!transitionContent.contains("updateSelectedTransition"))
    }
}

private enum R204LibraryHoverPreviewStaticContractError: Error {
    case missingMarker(String)
}
