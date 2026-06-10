import Foundation
import Testing

/// The macOS Inspector lives in the app target. These checks keep the P1 audio
/// fade duration editing contract visible in SwiftPM's faster static loop.
@Suite("Audio Fade Inspector StaticContract")
struct AudioFadeInspectorStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw AudioFadeInspectorStaticContractError.missingMarker(start)
        }

        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw AudioFadeInspectorStaticContractError.missingMarker(end)
        }

        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    private func tail(in source: String, from start: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw AudioFadeInspectorStaticContractError.missingMarker(start)
        }

        return String(source[startRange.lowerBound...])
    }

    @Test("Inspector exposes an explicit precise fade duration editor")
    func inspectorExposesExplicitPreciseFadeDurationEditor() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let body = try section(
            in: inspector,
            from: "var body: some View",
            to: "private var clipInfoSection"
        )
        let volume = try section(
            in: inspector,
            from: "private var volumeSection",
            to: "private var fadeDurationSection"
        )
        let fadeSection = try section(
            in: inspector,
            from: "private var fadeDurationSection",
            to: "private var equalizerSection"
        )
        let editor = try tail(in: inspector, from: "private struct AudioFadeDurationEditor")

        #expect(body.contains("volumeSection"))
        #expect(body.contains("fadeDurationSection"))
        #expect(volume.contains("updateSelectedVolume"))
        #expect(!volume.contains("updateSelectedAudioFade"))
        #expect(fadeSection.contains("AudioFadeDurationEditor(viewModel: viewModel, clip: clip)"))

        #expect(editor.contains("Text(\"Fade Duration\")"))
        #expect(editor.contains("title: \"Fade In\""))
        #expect(editor.contains("title: \"Fade Out\""))
        #expect(editor.contains("TextField(\"Seconds\""))
        #expect(editor.contains("Stepper(\"Step \\(title)\""))
        #expect(editor.contains("Slider(value: binding, in: fadeControlRange, step: fineStep)"))
        #expect(editor.contains("String(format: \"%.2fs\""))
        #expect(editor.contains("max(0, min(10, clip.timelineRange.duration))"))
        #expect(editor.contains("min(max(value, 0), fadeDurationMaximum)"))
    }

    @Test("Fade duration editor exposes accessibility labels values and hints")
    func fadeDurationEditorExposesAccessibilityContract() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let editor = try tail(in: inspector, from: "private struct AudioFadeDurationEditor")

        #expect(editor.contains("accessibilityLabel: \"Fade In duration\""))
        #expect(editor.contains("accessibilityLabel: \"Fade Out duration\""))
        #expect(editor.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(editor.contains(".accessibilityValue(formattedSeconds(clampedValue))"))
        #expect(editor.contains(".accessibilityHint(accessibilityHint)"))
        #expect(editor.contains(".accessibilityLabel(\"\\(accessibilityLabel) value\")"))
        #expect(editor.contains(".accessibilityLabel(\"\\(accessibilityLabel) fine adjustment\")"))
        #expect(editor.contains(".accessibilityHint(\"Enter a non-negative duration in seconds.\")"))
        #expect(editor.contains(".accessibilityHint(\"Adjusts the duration in 0.05 second increments.\")"))
        #expect(editor.contains(".accessibilityLabel(\"Reset audio fades\")"))
        #expect(editor.contains(".accessibilityLabel(\"No audio fade preset\")"))
        #expect(editor.contains(".accessibilityLabel(\"Soft audio fade preset\")"))
        #expect(editor.contains(".accessibilityLabel(\"Long audio fade preset\")"))
    }

    @Test("Fade edits presets and reset use updateSelectedAudioFade only")
    func fadeEditsPresetsAndResetUseAudioFadeViewModelPathOnly() throws {
        let inspector = try source("App/MovieCutMac/Inspector/InspectorBasicSection.swift")
        let editor = try tail(in: inspector, from: "private struct AudioFadeDurationEditor")
        let fadeInUpdate = try section(
            in: editor,
            from: "private func updateFadeInDuration",
            to: "private func updateFadeOutDuration"
        )
        let fadeOutUpdate = try section(
            in: editor,
            from: "private func updateFadeOutDuration",
            to: "private func resetAudioFades"
        )
        let reset = try section(
            in: editor,
            from: "private func resetAudioFades",
            to: "private func applyAudioFadePreset"
        )
        let preset = try section(
            in: editor,
            from: "private func applyAudioFadePreset",
            to: "private func formattedSeconds"
        )

        #expect(fadeInUpdate.contains("viewModel.updateSelectedAudioFade(fadeInDuration: clampedFadeDuration(newValue))"))
        #expect(fadeOutUpdate.contains("viewModel.updateSelectedAudioFade(fadeOutDuration: clampedFadeDuration(newValue))"))
        #expect(reset.contains("viewModel.updateSelectedAudioFade(fadeInDuration: zero, fadeOutDuration: zero)"))
        #expect(preset.contains("viewModel.updateSelectedAudioFade("))
        #expect(preset.contains("fadeInDuration: clampedDuration"))
        #expect(preset.contains("fadeOutDuration: clampedDuration"))
        #expect(editor.contains("Button(\"Reset Fades\")"))
        #expect(editor.contains("Button(\"None\")"))
        #expect(editor.contains("Button(\"Soft\")"))
        #expect(editor.contains("Button(\"Long\")"))
        #expect(!editor.contains("AudioFadeCommand("))
        #expect(!editor.contains("fadeInDuration ="))
        #expect(!editor.contains("fadeOutDuration ="))
    }

    @Test("EditorViewModel routes selected audio fade edits to AudioFadeCommand")
    func editorViewModelRoutesSelectedAudioFadeEditsToAudioFadeCommand() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let update = try section(
            in: viewModel,
            from: "func updateSelectedAudioFade",
            to: "func applyEQPreset"
        )
        let command = try source("Sources/MovieCutCore/Commands/AudioFadeCommand.swift")

        #expect(update.contains("guard let selectedClipId, let selectedClip else { return }"))
        #expect(update.contains("await apply(AudioFadeCommand("))
        #expect(update.contains("clipId: selectedClipId"))
        #expect(update.contains("fadeInDuration: fadeInDuration ?? selectedClip.fadeInDuration"))
        #expect(update.contains("fadeOutDuration: fadeOutDuration ?? selectedClip.fadeOutDuration"))
        #expect(command.contains("public struct AudioFadeCommand"))
        #expect(command.contains("Audio fade durations cannot be negative."))
        #expect(command.contains("fadeInDuration >= 0"))
        #expect(command.contains("fadeOutDuration >= 0"))
    }

    @Test("Backlog marks fade duration UI complete and advances next P1")
    func backlogMarksFadeDurationUICompleteAndAdvancesNextP1() throws {
        let backlog = try source("docs/CAPCUT_FEATURE_BACKLOG.md")
        let handoff = try source("docs/SESSION_HANDOFF.md")

        #expect(backlog.contains("- [x] ✅ 페이드 duration 편집 UI (P1)"))
        #expect(backlog.contains("Mac Inspector `Fade Duration`"))
        #expect(backlog.contains("Fade In/Fade Out"))
        #expect(backlog.contains("Seconds `TextField`"))
        #expect(backlog.contains("Reset Fades/None/Soft/Long"))
        #expect(backlog.contains("`updateSelectedAudioFade` → `AudioFadeCommand`"))
        #expect(backlog.contains("다음 1순위는 텍스트 템플릿/타이틀 프리셋"))
        #expect(!backlog.contains("- [ ] 🟡 페이드 duration 편집 UI"))
        #expect(!backlog.contains("다음 1순위는 페이드 duration 편집 UI"))

        #expect(handoff.contains("페이드 duration 편집 UI 배치"))
        #expect(handoff.contains("Fade Duration"))
        #expect(handoff.contains("Reset Fades/None/Soft/Long"))
        #expect(handoff.contains("`updateSelectedAudioFade` → `AudioFadeCommand`"))
        #expect(handoff.contains("| 1 | **텍스트 템플릿/타이틀 프리셋**"))
        #expect(handoff.contains("| 완료 | ✅ **페이드 duration 편집 UI**"))
    }
}

private enum AudioFadeInspectorStaticContractError: Error {
    case missingMarker(String)
}
