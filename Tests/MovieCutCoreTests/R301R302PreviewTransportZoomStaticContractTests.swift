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
            from: "private func previewSurface(for clip: Clip) -> some View",
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
            to: "    private func previewSurface"
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

    @Test("R3-01 and R3-02 docs complete without overclaiming safe zones")
    func r301AndR302DocsCompleteWithoutOverclaimingSafeZones() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")

        #expect(docs.contains("| R3-01 | 트랜스포트 정렬 + 타임코드(현재/전체) | ✅ 구현(2026-06-16, Codex R3-01/R3-02):"))
        #expect(docs.contains("| R3-02 | zoom-to-fit + 줌 | ✅ 구현(2026-06-16, Codex R3-01/R3-02):"))
        #expect(docs.contains("`.scaleEffect(previewZoom)`만 적용해 export/render/canvas semantics를 변경하지 않음"))
        #expect(docs.contains("| R3-05 | 안전영역 토글 | 🟡 `SafeZoneGuide` |"))
        #expect(docs.contains("- **P1 완료** — R1-02, R2-02, R2-03, R2-05, R3-01, R4-02, R5-02, R5-03."))
        #expect(docs.contains("- **P1 인터랙션** — R2-04."))
        #expect(docs.contains("- **P2 완료** — R1-03, R3-02, R3-03."))
        #expect(docs.contains("- **P2 시각 폴리시** — R6-01 visual parity loop, R6-02, R2-01."))
        #expect(!docs.contains("| R3-05 | 안전영역 토글 | ✅"))
    }
}

private enum R301R302PreviewTransportZoomStaticContractError: Error {
    case missingMarker(String)
}
