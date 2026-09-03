import Foundation
import Testing

/// R4-01 keeps the macOS Inspector context-sensitive at the presentation layer:
/// selected clip kind chooses the first inspector card without changing core
/// commands, export, or rendering behavior.
@Suite("R4-01 Inspector Context StaticContract")
struct R401InspectorContextStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R401InspectorContextStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R401InspectorContextStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("Vocal separation section is hosted for audio clips only")
    func vocalSectionHostedForAudioClipsOnly() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")

        // The audio helper hosts the basic section plus the vocal section.
        let audioHelper = try section(
            in: panel,
            from: "private func audioClipInspectorSections(for clip: Clip) -> some View",
            to: "    }\n"
        )
        #expect(audioHelper.contains("mode: InspectorBasicMode.audio"))
        #expect(audioHelper.contains("InspectorVocalSection(viewModel: viewModel, clip: clip)"))

        // No other clip kind surfaces the vocal section.
        let textBranch = try section(in: panel, from: "case .text:", to: "case .video, .image:")
        #expect(!textBranch.contains("InspectorVocalSection"))
        let visualBranch = try section(
            in: panel,
            from: "case .video, .image:",
            to: "    }\n\n    /// Audio clips"
        )
        #expect(!visualBranch.contains("InspectorVocalSection"))
    }

    @Test("InspectorPanel swaps selected clip sections by ClipKind")
    func inspectorPanelSwapsSelectedClipSectionsByClipKind() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")

        #expect(panel.contains("private func selectedClipInspectorSections(for clip: Clip) -> some View"))
        #expect(panel.contains("switch clip.kind"))
        #expect(panel.contains("case .audio:"))
        #expect(panel.contains("case .text:"))
        #expect(panel.contains("case .video, .image:"))

        let audioBranch = try section(in: panel, from: "case .audio:", to: "case .text:")
        #expect(audioBranch.contains("audioClipInspectorSections(for: clip)"))
        #expect(!audioBranch.contains("InspectorEffectsSection"))
        #expect(!audioBranch.contains("InspectorAnalysisSection"))

        let textBranch = try section(in: panel, from: "case .text:", to: "case .video, .image:")
        #expect(textBranch.contains("mode: InspectorBasicMode.text"))
        #expect(!textBranch.contains("InspectorEffectsSection"))
        #expect(!textBranch.contains("InspectorAnalysisSection"))

        let visualBranch = try section(
            in: panel,
            from: "case .video, .image:",
            to: "    }\n\n    /// R4-02"
        )
        #expect(visualBranch.contains("visualClipInspectorSections(for: clip)"))

        let visualHelper = try section(
            in: panel,
            from: "private func visualClipInspectorSections(for clip: Clip) -> some View",
            to: "    }\n\n    /// Project-wide tools"
        )
        #expect(visualHelper.contains("mode: InspectorBasicMode.visual"))
        #expect(visualHelper.contains("mode: InspectorBasicMode.speed"))
        #expect(visualHelper.contains("mode: InspectorEffectsMode.adjustment"))
        #expect(visualHelper.contains("mode: InspectorEffectsMode.mask"))
        #expect(visualHelper.contains("mode: InspectorEffectsMode.animation"))
        #expect(visualHelper.contains("InspectorAnalysisSection(viewModel: viewModel, clip: clip)"))
    }

    @Test("InspectorBasicMode.audio routes to volume fade denoise and equalizer controls")
    func inspectorBasicAudioModeRoutesToAudioControls() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")

        #expect(inspector.contains("enum InspectorBasicMode"))
        #expect(inspector.contains("case visual"))
        #expect(inspector.contains("case audio"))
        #expect(inspector.contains("case text"))
        #expect(inspector.contains("case .audio:"))
        #expect(inspector.contains("audioSections"))

        let audioMode = try section(in: inspector, from: "private var audioSections", to: "private var textSections")
        #expect(audioMode.contains("clipInfoSection"))
        #expect(audioMode.contains("volumeSection"))
        #expect(audioMode.contains("fadeDurationSection"))
        #expect(audioMode.contains("equalizerSection"))
        #expect(audioMode.contains("autoCutSection"))
        #expect(audioMode.contains("speedSection"))
        #expect(!audioMode.contains("transformSection"))
        #expect(!audioMode.contains("InspectorEffectsSection"))

        let volume = try section(in: inspector, from: "private var volumeSection", to: "private var fadeDurationSection")
        #expect(volume.contains("Text(\"Volume\")"))
        #expect(volume.contains("Button(\"Noise Reduction\")"))
        #expect(volume.contains("viewModel.applyNoiseReduction(for: clipId)"))

        let fade = try section(in: inspector, from: "private var fadeDurationSection", to: "private var equalizerSection")
        #expect(fade.contains("AudioFadeDurationEditor(viewModel: viewModel, clip: clip)"))
        #expect(inspector.contains("Text(\"Fade Duration\")"))

        let equalizer = try section(in: inspector, from: "private var equalizerSection", to: "private var speedSection")
        #expect(equalizer.contains("Section(\"Equalizer\")"))
        #expect(equalizer.contains("viewModel.applyEQPreset(newValue)"))
    }

    @Test("InspectorBasicMode.text makes style controls the prominent text surface")
    func inspectorBasicTextModeMakesStyleControlsProminent() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")

        let textMode = try section(in: inspector, from: "private var textSections", to: "/// Subject-tracking")
        #expect(textMode.contains("textContentSection(textContent)"))
        #expect(textMode.contains("clipInfoSection"))
        #expect(textMode.contains("transformSection"))
        #expect(textMode.contains("opacitySection"))
        #expect(!textMode.contains("volumeSection"))
        #expect(!textMode.contains("InspectorEffectsSection"))

        let textContentRange = try #require(textMode.range(of: "textContentSection(textContent)"))
        let clipInfoRange = try #require(textMode.range(of: "clipInfoSection"))
        #expect(textContentRange.lowerBound < clipInfoRange.lowerBound)

        let textSection = try section(
            in: inspector,
            from: "private func textContentSection",
            to: "private func normalTextStyleEditor"
        )
        #expect(textSection.contains("Text(isStickerClip ? \"Sticker\" : \"Style\")"))
        #expect(textSection.contains("normalTextStyleEditor(textContent)"))

        let styleEditor = try section(
            in: inspector,
            from: "private func normalTextStyleEditor",
            to: "/// Generates a spoken audio clip"
        )
        #expect(styleEditor.contains("fontPicker(textContent)"))
        #expect(styleEditor.contains("fontSizeControl(textContent)"))
        #expect(styleEditor.contains("alignmentPicker(textContent)"))
        #expect(styleEditor.contains("foregroundColorPicker(textContent)"))
        #expect(styleEditor.contains("textBackgroundControls(textContent)"))
        #expect(styleEditor.contains("textQuickStylePresets(textContent)"))
    }
}

private enum R401InspectorContextStaticContractError: Error {
    case missingMarker(String)
}
