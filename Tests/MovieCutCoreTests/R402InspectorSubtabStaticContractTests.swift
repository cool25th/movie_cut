import Foundation
import Testing

/// R4-02 keeps visual clip inspector sections behind a top segmented control
/// without changing editor commands, rendering, export, or core model behavior.
@Suite("R4-02 Inspector Subtab StaticContract")
struct R402InspectorSubtabStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw R402InspectorSubtabStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw R402InspectorSubtabStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("InspectorPanel exposes visual subtabs as an accessible segmented picker")
    func inspectorPanelExposesVisualSubtabsAsSegmentedPicker() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")
        let subtabEnum = try section(in: panel, from: "enum InspectorSubtab", to: "struct InspectorPanel")

        #expect(subtabEnum.contains("String, CaseIterable, Identifiable"))
        #expect(subtabEnum.contains("case basic = \"Basic\""))
        #expect(subtabEnum.contains("case speed = \"Speed\""))
        #expect(subtabEnum.contains("case animation = \"Animation\""))
        #expect(subtabEnum.contains("case adjustment = \"Adjustment\""))
        #expect(subtabEnum.contains("case mask = \"Mask\""))
        // The tab selection moved from panel @State to EditorViewModel so the
        // UI test harness can drive it (MOVIECUT_UITEST_INSPECTOR_TAB) — the
        // panel now binds the view model's property.
        #expect(panel.contains("Picker(\"Inspector section\", selection: $viewModel.selectedInspectorSubtab)"))
        #expect(panel.contains("ForEach(InspectorSubtab.allCases)"))
        #expect(panel.contains(".pickerStyle(.segmented)"))
        #expect(panel.contains(".accessibilityLabel(\"Inspector section\")"))
        #expect(panel.contains(".accessibilityHint(\"Switches between clip inspector sections.\")"))
    }

    @Test("InspectorPanel only routes video and image clips through subtabs")
    func inspectorPanelOnlyRoutesVisualClipsThroughSubtabs() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")

        let audioBranch = try section(in: panel, from: "case .audio:", to: "case .text:")
        #expect(audioBranch.contains("mode: InspectorBasicMode.audio"))
        #expect(!audioBranch.contains("visualClipInspectorSections"))
        #expect(!audioBranch.contains("Picker(\"Inspector section\""))

        let textBranch = try section(in: panel, from: "case .text:", to: "case .video, .image:")
        #expect(textBranch.contains("mode: InspectorBasicMode.text"))
        #expect(!textBranch.contains("visualClipInspectorSections"))
        #expect(!textBranch.contains("Picker(\"Inspector section\""))

        let visualBranch = try section(in: panel, from: "case .video, .image:", to: "    }\n\n    /// R4-02")
        #expect(visualBranch.contains("visualClipInspectorSections(for: clip)"))
    }

    @Test("Selected inspector subtab swaps the visual section body")
    func selectedInspectorSubtabSwapsVisualSectionBody() throws {
        let panel = try source("App/MovieCutMac/InspectorPanel.swift")
        let visualHelper = try section(
            in: panel,
            from: "private func visualClipInspectorSections(for clip: Clip) -> some View",
            to: "    }\n\n    /// Project-wide tools"
        )

        #expect(visualHelper.contains("switch viewModel.selectedInspectorSubtab"))
        #expect(visualHelper.contains("case .basic:"))
        #expect(visualHelper.contains("InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.visual)"))
        #expect(visualHelper.contains("case .speed:"))
        #expect(visualHelper.contains("InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.speed)"))
        #expect(visualHelper.contains("case .animation:"))
        #expect(visualHelper.contains("InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.animation)"))
        #expect(visualHelper.contains("case .adjustment:"))
        #expect(visualHelper.contains("InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.adjustment)"))
        #expect(visualHelper.contains("case .mask:"))
        #expect(visualHelper.contains("InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.mask)"))
        #expect(visualHelper.contains("InspectorAnalysisSection(viewModel: viewModel, clip: clip)"))
    }

    @Test("InspectorBasicMode.speed isolates speed controls from visual basics")
    func inspectorBasicModeSpeedIsolatesSpeedControlsFromVisualBasics() throws {
        let basic = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")

        #expect(basic.contains("case speed"))
        #expect(basic.contains("case .speed:"))
        #expect(basic.contains("speedSections"))

        let visualSections = try section(in: basic, from: "private var visualSections", to: "private var speedSections")
        #expect(visualSections.contains("clipInfoSection"))
        #expect(visualSections.contains("transformSection"))
        #expect(visualSections.contains("opacitySection"))
        #expect(visualSections.contains("autoReframeSection"))
        #expect(!visualSections.contains("speedSection"))

        let speedSections = try section(in: basic, from: "private var speedSections", to: "private var audioSections")
        #expect(speedSections.contains("clipInfoSection"))
        #expect(speedSections.contains("clip.kind.supportsSpeed"))
        #expect(speedSections.contains("speedSection"))
        #expect(speedSections.contains("speedUnavailableSection"))
    }

    @Test("InspectorEffectsMode routes adjustment mask and animation sections")
    func inspectorEffectsModeRoutesAdjustmentMaskAndAnimationSections() throws {
        let effects = try source("App/MovieCutMac/Inspector/InspectorEffectsSection.swift")

        #expect(effects.contains("enum InspectorEffectsMode"))
        #expect(effects.contains("case full"))
        #expect(effects.contains("case adjustment"))
        #expect(effects.contains("case mask"))
        #expect(effects.contains("case animation"))
        #expect(effects.contains("init(viewModel: EditorViewModel, clip: Clip, mode: InspectorEffectsMode = .full)"))
        #expect(effects.contains("switch mode"))

        let adjustment = try section(in: effects, from: "private var adjustmentSections", to: "private var maskSections")
        #expect(adjustment.contains("colorCorrectionSection"))
        #expect(adjustment.contains("backgroundRemovalSection"))
        #expect(adjustment.contains("styleTransferSection"))
        #expect(adjustment.contains("effectsSection"))
        #expect(adjustment.contains("chromaKeySection"))
        #expect(adjustment.contains("reverseFreezeSection"))
        #expect(!adjustment.contains("maskSection"))
        #expect(!adjustment.contains("animationSection"))

        let mask = try section(in: effects, from: "private var maskSections", to: "private var animationSections")
        #expect(mask.contains("maskSection"))
        #expect(!mask.contains("colorCorrectionSection"))
        #expect(!mask.contains("transitionSection"))

        let animation = try section(in: effects, from: "private var animationSections", to: "private var colorCorrectionSection")
        #expect(animation.contains("transitionSection"))
        #expect(animation.contains("animationSection"))
        #expect(!animation.contains("maskSection"))
        #expect(!animation.contains("effectsSection"))
    }
}

private enum R402InspectorSubtabStaticContractError: Error {
    case missingMarker(String)
}
