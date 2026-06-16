import Foundation
import Testing

/// R1-03/R3-03 exposes canvas ratio and computed export render size in the
/// toolbar and preview transport without changing export/render semantics.
@Suite("R1-03/R3-03 Canvas Resolution Badge StaticContract")
struct R103R303CanvasResolutionBadgeStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R103R303CanvasResolutionBadgeStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R103R303CanvasResolutionBadgeStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("ContentView toolbar shows compact canvas resolution badge near canvas controls")
    func contentViewToolbarShowsCompactCanvasResolutionBadgeNearCanvasControls() throws {
        let content = try source("App/MovieCutMac/ContentView.swift")
        let canvasControls = try section(
            in: content,
            from: #"Picker("Canvas", selection: $viewModel.canvasSelection)"#,
            to: #"Button(action: { isCanvasSettingsPresented.toggle() })"#
        )
        let badge = try section(
            in: content,
            from: "private var toolbarCanvasResolutionBadge: some View",
            to: "    private var exportToolbarControl"
        )

        #expect(canvasControls.contains("toolbarCanvasResolutionBadge"))
        #expect(badge.contains("Label {"))
        #expect(badge.contains("Text(viewModel.canvasResolutionBadgeText)"))
        #expect(badge.contains(#"Image(systemName: "rectangle.ratio")"#))
        #expect(badge.contains("Capsule()"))
        #expect(badge.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(badge.contains(#"accessibilityLabel(NSLocalizedString("Canvas and export resolution", comment: ""))"#))
        #expect(badge.contains("accessibilityValue(viewModel.canvasResolutionBadgeText)"))
        #expect(badge.contains(#"accessibilityHint(NSLocalizedString("Shows the current canvas aspect ratio and computed export render size.", comment: ""))"#))
    }

    @Test("PreviewPanel replaces ratio-only label with preview canvas export badge")
    func previewPanelReplacesRatioOnlyLabelWithPreviewCanvasExportBadge() throws {
        let preview = try source("App/MovieCutMac/PreviewPanel.swift")
        let transport = try section(
            in: preview,
            from: "private var previewTransportBar: some View",
            to: "    private var canvasAspectRatio"
        )
        let badge = try section(
            in: preview,
            from: "private var previewCanvasResolutionBadge: some View",
            to: "    @ViewBuilder"
        )

        #expect(transport.contains("previewCanvasResolutionBadge"))
        #expect(!transport.contains("Label(canvasRatioText, systemImage: \"rectangle.ratio\")"))
        #expect(!preview.contains("private var canvasRatioText: String"))
        #expect(badge.contains("Text(viewModel.canvasResolutionBadgeText)"))
        #expect(badge.contains(#"Image(systemName: "rectangle.ratio")"#))
        #expect(badge.contains("Capsule()"))
        #expect(badge.contains(#"accessibilityLabel(NSLocalizedString("Preview canvas and export resolution", comment: ""))"#))
        #expect(badge.contains("accessibilityValue(viewModel.canvasResolutionBadgeText)"))
        #expect(badge.contains(#"accessibilityHint(NSLocalizedString("Shows the preview canvas ratio and computed export render size.", comment: ""))"#))
    }

    @Test("EditorViewModel exposes read-only canvas and export badge helpers")
    func editorViewModelExposesReadOnlyCanvasAndExportBadgeHelpers() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let badgeProperties = try section(
            in: viewModel,
            from: "var canvasAspectBadgeText: String",
            to: "    var mediaAssets"
        )
        let helperProperties = try section(
            in: viewModel,
            from: "private static func aspectRatioBadgeText(for canvas: CanvasPreset) -> String",
            to: "    private static func ensureDefaultTracks"
        )

        #expect(badgeProperties.contains("var canvasAspectBadgeText: String"))
        #expect(badgeProperties.contains("Self.aspectRatioBadgeText(for: currentProject.canvas)"))
        #expect(badgeProperties.contains("var exportResolutionBadgeText: String"))
        #expect(badgeProperties.contains("ExportPlanner().renderSize("))
        #expect(badgeProperties.contains("for: currentProject.exportSettings.resolution"))
        #expect(badgeProperties.contains("canvas: currentProject.canvas"))
        #expect(badgeProperties.contains("var canvasResolutionBadgeText: String"))
        #expect(badgeProperties.contains(#""\(canvasAspectBadgeText) · \(exportResolutionBadgeText)""#))
        #expect(helperProperties.contains(#"return "16:9""#))
        #expect(helperProperties.contains(#"return "9:16""#))
        #expect(helperProperties.contains(#"return "4:5""#))
        #expect(helperProperties.contains(#"return "1:1""#))
        #expect(helperProperties.contains(#"return "21:9""#))
        #expect(helperProperties.contains("greatestCommonDivisor(width, height)"))

        for forbiddenMutation in [
            "updateExportSettings",
            "updateCanvas(",
            "session.dispatch",
            "dispatchCommand",
            "apply("
        ] {
            #expect(!badgeProperties.contains(forbiddenMutation))
            #expect(!helperProperties.contains(forbiddenMutation))
        }
    }

    @Test("R1-03 and R3-03 docs are implemented without overclaiming preview zoom or safe zones")
    func r103AndR303DocsAreImplementedWithoutOverclaimingPreviewZoomOrSafeZones() throws {
        let docs = try source("docs/CAPCUT_UI_PARITY_REQUIREMENTS.md")
        let r103Row = try section(
            in: docs,
            from: "| R1-03 | 비율/해상도 배지 |",
            to: "| R1-04 | undo/redo 좌측 클러스터 |"
        )
        let r303Row = try section(
            in: docs,
            from: "| R3-03 | 비율/해상도 배지 |",
            to: "| R3-04 | **빈 상태 CTA** |"
        )

        #expect(r103Row.contains("✅ 구현(2026-06-16, Codex R1-03/R3-03):"))
        #expect(r103Row.contains("`EditorViewModel.swift` read-only badge helpers"))
        #expect(r103Row.contains("`ExportPlanner().renderSize(for:canvas:)`"))
        #expect(r103Row.contains("`ContentView.swift` toolbar Canvas controls"))
        #expect(r103Row.contains("검증: `git diff --check`, `swift test --filter StaticContract`(181 tests / 46 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED"))
        #expect(r303Row.contains("✅ 구현(2026-06-16, Codex R1-03/R3-03):"))
        #expect(r303Row.contains("`PreviewPanel.swift` transport bar"))
        #expect(r303Row.contains("Current/Duration/playback/frame/volume controls는 유지"))
        #expect(r303Row.contains("R3-05 safe-zone toggle은 별도 잔여"))
        #expect(r303Row.contains("검증: `git diff --check`, `swift test --filter StaticContract`(181 tests / 46 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED"))
        #expect(docs.contains("| R3-02 | zoom-to-fit + 줌 | ✅ 구현(2026-06-16, Codex R3-01/R3-02):"))
        #expect(docs.contains("| R3-05 | 안전영역 토글 | 🟡 `SafeZoneGuide` |"))
        #expect(docs.contains("- **P2 완료** — R1-03, R3-02, R3-03."))
        #expect(docs.contains("- **P2 시각 폴리시** — R6-01 visual parity loop, R6-02, R2-01."))
        #expect(!docs.contains("R3-02/03"))
        #expect(!docs.contains("| R3-05 | 안전영역 토글 | ✅"))
    }
}

private enum R103R303CanvasResolutionBadgeStaticContractError: Error {
    case missingMarker(String)
}
