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
        // The computed badge properties stay on the VM (views bind to them);
        // the compact ratio token now lives on `AspectRatio.shortDisplayName`
        // in Core (Sources/MovieCutCore/Models/CanvasPreset.swift), shared by
        // Mac and iOS so the ratio→string table is no longer duplicated.
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let coreModel = try source("Sources/MovieCutCore/Models/CanvasPreset.swift")
        let badgeProperties = try section(
            in: viewModel,
            from: "var canvasAspectBadgeText: String",
            to: "    var mediaAssets"
        )
        let ratioHelpers = try section(
            in: coreModel,
            from: "public var shortDisplayName: String {",
            to: "private static func greatestCommonDivisor"
        )

        #expect(badgeProperties.contains("var canvasAspectBadgeText: String"))
        #expect(badgeProperties.contains("shortDisplayName(forSize:"))
        #expect(badgeProperties.contains("var exportResolutionBadgeText: String"))
        #expect(badgeProperties.contains("ExportPlanner().renderSize("))
        #expect(badgeProperties.contains("for: currentProject.exportSettings.resolution"))
        #expect(badgeProperties.contains("canvas: currentProject.canvas"))
        #expect(badgeProperties.contains("var canvasResolutionBadgeText: String"))
        #expect(badgeProperties.contains(#""\(canvasAspectBadgeText) · \(exportResolutionBadgeText)""#))
        #expect(ratioHelpers.contains(#"return "16:9""#))
        #expect(ratioHelpers.contains(#"return "9:16""#))
        #expect(ratioHelpers.contains(#"return "4:5""#))
        #expect(ratioHelpers.contains(#"return "1:1""#))
        #expect(ratioHelpers.contains(#"return "21:9""#))
        #expect(coreModel.contains("greatestCommonDivisor(width, height)"))

        for forbiddenMutation in [
            "updateExportSettings",
            "updateCanvas(",
            "session.dispatch",
            "dispatchCommand",
            "apply("
        ] {
            #expect(!badgeProperties.contains(forbiddenMutation))
        }
    }
}

private enum R103R303CanvasResolutionBadgeStaticContractError: Error {
    case missingMarker(String)
}
