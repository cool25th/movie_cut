import Foundation
import Testing

/// The macOS Inspector lives in the app target. These checks keep the P1 text
/// style UI contract visible in SwiftPM's faster static test loop.
@Suite("Text Style Inspector StaticContract")
struct TextStyleInspectorStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw TextStyleInspectorStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw TextStyleInspectorStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Inspector exposes body, font, size, alignment, foreground, background, and preset controls")
    func inspectorExposesNormalTextStyleControls() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let normalEditor = try section(
            in: source,
            from: "private func normalTextStyleEditor",
            to: "private func textBodyEditor"
        )
        let controlBodies = try section(
            in: source,
            from: "private func textBodyEditor",
            to: "private func stickerMetadataSection"
        )

        #expect(normalEditor.contains("fontPicker(textContent)"))
        #expect(normalEditor.contains("fontSizeControl(textContent)"))
        #expect(normalEditor.contains("alignmentPicker(textContent)"))
        #expect(normalEditor.contains("foregroundColorPicker(textContent)"))
        #expect(normalEditor.contains("textBackgroundControls(textContent)"))
        #expect(normalEditor.contains("textQuickStylePresets(textContent)"))

        #expect(controlBodies.contains("TextField(isStickerClip ? \"Sticker\" : \"Text\""))
        #expect(controlBodies.contains("updated.text = newValue"))
        #expect(controlBodies.contains("Picker(\"Font\""))
        #expect(controlBodies.contains("updated.fontFamily = newValue"))
        #expect(controlBodies.contains("updated.fontSize = newValue"))
        #expect(controlBodies.contains("Picker(\"Alignment\""))
        #expect(controlBodies.contains("updated.alignment = newValue"))
        #expect(controlBodies.contains("ColorPicker(\"Foreground\""))
        #expect(controlBodies.contains("updated.fontColor = hexFromColor(newValue)"))
        #expect(controlBodies.contains("Toggle(\"Background\""))
        #expect(controlBodies.contains("ColorPicker(\"Background\""))
        #expect(controlBodies.contains("updated.backgroundColor = hexFromColor(newValue)"))
        #expect(controlBodies.contains("updated.backgroundColor = nil"))

        #expect(source.contains("name: \"Title\""))
        #expect(source.contains("name: \"Caption\""))
        #expect(source.contains("name: \"Lower Third\""))
        #expect(source.contains("name: \"BG Safe\""))
    }

    @Test("Inspector text edits use updateSelectedTextContent while preserving sticker metadata UI")
    func inspectorUsesTextContentCommandPathAndKeepsStickerMetadata() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")

        let textSection = try section(
            in: inspector,
            from: "private func textContentSection",
            to: "private func normalTextStyleEditor"
        )
        let bodyEditor = try section(
            in: inspector,
            from: "private func textBodyEditor",
            to: "private func fontPicker"
        )
        let presetMutation = try section(
            in: inspector,
            from: "private func applyTextStylePreset",
            to: "private func setTextBackgroundEnabled"
        )
        let stickerMetadata = try section(
            in: inspector,
            from: "private func stickerMetadataSection",
            to: "private var clipTypeLabel"
        )
        let updateCommand = try section(
            in: viewModel,
            from: "func updateSelectedTextContent",
            to: "func updateSelectedChromaKey"
        )

        #expect(textSection.contains("if isStickerClip"))
        #expect(textSection.contains("stickerMetadataSection(textContent)"))
        #expect(textSection.contains("normalTextStyleEditor(textContent)"))
        #expect(bodyEditor.contains("updated.contentKind = .sticker"))
        #expect(bodyEditor.contains("viewModel.updateSelectedTextContent(updated)"))
        #expect(presetMutation.contains("viewModel.updateSelectedTextContent(updated)"))
        #expect(!presetMutation.contains("stickerAssetID"))
        #expect(!presetMutation.contains("stickerImageURL"))
        #expect(stickerMetadata.contains("stickerAssetID"))
        #expect(stickerMetadata.contains("stickerImageURL"))
        #expect(updateCommand.contains("SetClipPropertyCommand"))
        #expect(updateCommand.contains("property: .textContent(textContent)"))
    }
}

private enum TextStyleInspectorStaticContractError: Error {
    case missingMarker(String)
}
