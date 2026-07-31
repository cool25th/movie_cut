import Foundation
import Testing

/// R3-01/R3-02 keeps the preview transport complete while adding
/// presentation-only zoom-to-fit controls.
@Suite("R3-01/R3-02 Preview Transport Zoom StaticContract")
struct R301R302PreviewTransportZoomStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R301R302PreviewTransportZoomStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R301R302PreviewTransportZoomStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Preview panel exposes presentation-only zoom state and surface scale")
    func previewPanelExposesPresentationOnlyZoomStateAndSurfaceScale() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let surface = try section(
            in: preview,
            from: "private var previewSurface: some View",
            to: "    private var canvasAspectRatio"
        )

        #expect(preview.contains("@State private var previewZoom: Double = 1"))
        #expect(preview.contains("@State private var isPreviewZoomFit = true"))
        #expect(preview.contains("private let previewZoomRange: ClosedRange<Double> = 0.5...2"))
        #expect(preview.contains("private let previewZoomStep: Double = 0.25"))
        #expect(surface.contains("VideoPreviewView(player: playbackEngine.player)"))
        #expect(surface.contains(".aspectRatio(canvasAspectRatio, contentMode: .fit)"))
        #expect(surface.contains(".scaleEffect(previewZoom)"))
        #expect(surface.contains(".accessibilityValue(previewZoomAccessibilityValue)"))
        #expect(!surface.contains("updateCanvas("))
        #expect(!surface.contains("updateExportSettings("))
        #expect(!surface.contains("exportEngine"))
    }

    @Test("Preview transport keeps timecodes frame buttons and adaptive layout")
    func previewTransportKeepsTimecodesFrameButtonsAndAdaptiveLayout() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let transport = try section(
            in: preview,
            from: "private var previewTransportBar: some View",
            to: "    private var playbackTransportCapsule"
        )
        let capsule = try section(
            in: preview,
            from: "private var playbackTransportCapsule: some View",
            to: "    private var previewVolumeControl"
        )

        #expect(transport.contains("ViewThatFits(in: .horizontal)"))
        #expect(transport.contains("previewTimeBadge("))
        #expect(transport.contains("title: NSLocalizedString(\"Current\", comment: \"\")"))
        #expect(transport.contains("title: NSLocalizedString(\"Duration\", comment: \"\")"))
        #expect(transport.contains("playbackTransportCapsule"))
        #expect(transport.contains("previewCanvasResolutionBadge"))
        #expect(transport.contains("previewZoomControls"))
        #expect(transport.contains("previewVolumeControl"))
        #expect(capsule.contains("Image(systemName: \"backward.frame\")"))
        #expect(capsule.contains("Image(systemName: playbackEngine.isPlaying ? \"pause.fill\" : \"play.fill\")"))
        #expect(capsule.contains("Image(systemName: \"forward.frame\")"))
        #expect(capsule.contains("accessibilityLabel(NSLocalizedString(\"Seek Back One Frame\", comment: \"\"))"))
        #expect(capsule.contains("accessibilityLabel(playbackEngine.isPlaying ? NSLocalizedString(\"Pause\", comment: \"\") : NSLocalizedString(\"Play\", comment: \"\"))"))
        #expect(capsule.contains("accessibilityLabel(NSLocalizedString(\"Seek Forward One Frame\", comment: \"\"))"))
        #expect(capsule.contains("accessibilityLabel(NSLocalizedString(\"Playback transport\", comment: \"\"))"))
    }

    @Test("Preview zoom controls expose fit percentage slider plus minus and accessibility")
    func previewZoomControlsExposeFitPercentageSliderPlusMinusAndAccessibility() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let zoom = try section(
            in: preview,
            from: "private var previewZoomControls: some View",
            to: "    private var previewZoomDisplay"
        )
        let helpers = try section(
            in: preview,
            from: "private var previewZoomDisplay: String",
            to: "    private var previewSurface"
        )

        #expect(zoom.contains("Button(action: resetPreviewZoomToFit)"))
        #expect(zoom.contains("Label(NSLocalizedString(\"Fit\", comment: \"\"), systemImage: \"arrow.up.left.and.down.right\")"))
        #expect(zoom.contains("Button(action: { adjustPreviewZoom(by: -previewZoomStep) })"))
        #expect(zoom.contains("Image(systemName: \"minus.magnifyingglass\")"))
        #expect(zoom.contains("Text(previewZoomDisplay)"))
        #expect(zoom.contains("Slider(value: Binding("))
        #expect(zoom.contains("setManualPreviewZoom(newValue)"))
        #expect(zoom.contains("Button(action: { adjustPreviewZoom(by: previewZoomStep) })"))
        #expect(zoom.contains("Image(systemName: \"plus.magnifyingglass\")"))
        #expect(zoom.contains("accessibilityLabel(NSLocalizedString(\"Preview zoom controls\", comment: \"\"))"))
        #expect(zoom.contains("accessibilityLabel(NSLocalizedString(\"Fit Preview\", comment: \"\"))"))
        #expect(zoom.contains("accessibilityLabel(NSLocalizedString(\"Preview zoom slider\", comment: \"\"))"))
        #expect(helpers.contains("String(format: NSLocalizedString(\"%.0f%%\", comment: \"\"), clampedPreviewZoom(previewZoom) * 100)"))
        #expect(helpers.contains("previewZoom = 1"))
        #expect(helpers.contains("isPreviewZoomFit = true"))
        #expect(helpers.contains("isPreviewZoomFit = false"))
        #expect(helpers.contains("min(previewZoomRange.upperBound, max(previewZoomRange.lowerBound, zoom))"))
    }
}

private enum R301R302PreviewTransportZoomStaticContractError: Error {
    case missingMarker(String)
}
