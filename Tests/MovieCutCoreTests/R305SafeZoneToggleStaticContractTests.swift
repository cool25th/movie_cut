import Foundation
import Testing

/// R3-05 exposes presentation-only title/action safe guides in the Preview panel
/// without touching render, export, playback, or session behavior.
@Suite("R3-05 Safe Zone Toggle StaticContract")
struct R305SafeZoneToggleStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R305SafeZoneToggleStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R305SafeZoneToggleStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func assertContainsInOrder(_ source: String, _ markers: [String]) throws {
        var cursor = source.startIndex
        for marker in markers {
            guard let range = source.range(of: marker, range: cursor..<source.endIndex) else {
                throw R305SafeZoneToggleStaticContractError.missingMarker(marker)
            }
            cursor = range.upperBound
        }
    }

    @Test("Preview transport exposes safe-zone toggle in horizontal and fallback layouts")
    func previewTransportExposesSafeZoneToggleInBothLayouts() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let transport = try section(
            in: preview,
            from: "private var previewTransportBar: some View",
            to: "    private var playbackTransportCapsule"
        )
        let toggle = try section(
            in: preview,
            from: "private var previewSafeZoneToggle: some View",
            to: "    private var previewZoomDisplay"
        )

        #expect(preview.contains("@State private var showsSafeZoneGuides = false"))
        #expect(transport.contains("ViewThatFits(in: .horizontal)"))
        #expect(transport.contains("previewCanvasResolutionBadge"))
        #expect(transport.components(separatedBy: "previewSafeZoneToggle").count - 1 == 2)
        #expect(transport.contains("previewZoomControls"))
        #expect(transport.contains("previewVolumeControl"))
        #expect(toggle.contains("Button(action: { showsSafeZoneGuides.toggle() })"))
        #expect(toggle.contains(#"Image(systemName: showsSafeZoneGuides ? "rectangle.inset.filled" : "rectangle.dashed")"#))
        #expect(toggle.contains(#"accessibilityLabel(NSLocalizedString("Safe zone guides", comment: ""))"#))
        #expect(toggle.contains(#"accessibilityValue(showsSafeZoneGuides ? NSLocalizedString("On", comment: "") : NSLocalizedString("Off", comment: ""))"#))
        #expect(toggle.contains(#"accessibilityHint(NSLocalizedString("Shows or hides non-exporting title and action safe guides on the preview canvas.", comment: ""))"#))
    }

    @Test("Preview surface keeps fitted canvas overlay before presentation zoom")
    func previewSurfaceKeepsFittedCanvasOverlayBeforePresentationZoom() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let surface = try section(
            in: preview,
            from: "private var previewSurface: some View",
            to: "    private var canvasAspectRatio"
        )

        try assertContainsInOrder(surface, [
            "VideoPreviewView(player: playbackEngine.player)",
            ".aspectRatio(canvasAspectRatio, contentMode: .fit)",
            ".overlay {",
            "previewOverlay(for: clip)",
            ".scaleEffect(previewZoom)"
        ])
    }

    @Test("Safe-zone overlay draws standard guides from guide insets without hit testing")
    func safeZoneOverlayDrawsStandardGuidesFromInsetsWithoutHitTesting() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let overlay = try section(
            in: preview,
            from: "private func previewOverlay(for clip: Clip) -> some View",
            to: "    private func maskBinding"
        )

        #expect(overlay.contains("if showsSafeZoneGuides"))
        #expect(overlay.contains("safeZoneGuideOverlay(guides: SafeZoneGuide.standard)"))
        #expect(overlay.contains("private func safeZoneGuideOverlay(guides: [SafeZoneGuide]) -> some View"))
        #expect(overlay.contains("GeometryReader { proxy in"))
        #expect(overlay.contains("ForEach(Array(guides.enumerated()), id: \\.offset)"))
        #expect(overlay.contains("let rect = safeZoneRect(for: guide, in: proxy.size)"))
        #expect(overlay.contains("RoundedRectangle(cornerRadius: 3, style: .continuous)"))
        #expect(overlay.contains("StrokeStyle(lineWidth: 1, dash: index == 0 ? [5, 4] : [3, 3])"))
        #expect(overlay.contains("Text(guide.name)"))
        #expect(overlay.contains(".allowsHitTesting(false)"))
        #expect(overlay.contains(".accessibilityHidden(true)"))
        #expect(overlay.contains("let insets = guide.insets"))
        #expect(overlay.contains("CGFloat(insets.leading)"))
        #expect(overlay.contains("CGFloat(insets.top)"))
        #expect(overlay.contains("CGFloat(insets.trailing)"))
        #expect(overlay.contains("CGFloat(insets.bottom)"))
        #expect(overlay.contains("Color(hex: guide.colorHex)"))
        #expect(preview.contains("private extension Color"))
        #expect(preview.contains("init(hex: String)"))
    }

    @Test("Preview overlay preserves existing canvas overlays around safe-zone layer")
    func previewOverlayPreservesExistingCanvasOverlaysAroundSafeZoneLayer() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let overlay = try section(
            in: preview,
            from: "private func previewOverlay(for clip: Clip) -> some View",
            to: "    private func safeZoneGuideOverlay"
        )

        #expect(overlay.contains("clipPlaceholder(for: clip)"))
        #expect(overlay.contains("ReframeCropPathOverlay"))
        #expect(overlay.contains("ChromaKeyEyedropperOverlay"))
        #expect(overlay.contains("MaskCanvasView"))
        #expect(overlay.contains("CanvasMultiSelectionOverlay"))
        #expect(overlay.contains("CanvasTransformOverlay"))
    }

    @Test("Safe-zone UI is presentation-only and does not spread into core services")
    func safeZoneUIIsPresentationOnlyAndDoesNotSpreadIntoCoreServices() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let toggle = try section(
            in: preview,
            from: "private var previewSafeZoneToggle: some View",
            to: "    private var previewZoomDisplay"
        )
        let overlay = try section(
            in: preview,
            from: "private func safeZoneGuideOverlay(guides: [SafeZoneGuide]) -> some View",
            to: "    private func maskBinding"
        )

        for forbiddenCall in [
            "updateCanvas(",
            "updateExportSettings(",
            "EditorSession",
            "session.dispatch",
            "dispatchCommand",
            "ExportEngine",
            "PlaybackEngine",
            "playbackEngine.",
            "viewModel."
        ] {
            #expect(!toggle.contains(forbiddenCall))
            #expect(!overlay.contains(forbiddenCall))
        }

        for path in [
            "App/MovieCutMac/EditorViewModel.swift",
            "App/MovieCutMac/Export/ExportEngine.swift",
            "App/MovieCutMac/Playback/PlaybackEngine.swift"
        ] {
            let serviceSource = try source(path)
            for uiMarker in [
                "showsSafeZoneGuides",
                "previewSafeZoneToggle",
                "safeZoneGuideOverlay",
                "Safe zone guides"
            ] {
                #expect(!serviceSource.contains(uiMarker))
            }
        }
    }
}

private enum R305SafeZoneToggleStaticContractError: Error {
    case missingMarker(String)
}
