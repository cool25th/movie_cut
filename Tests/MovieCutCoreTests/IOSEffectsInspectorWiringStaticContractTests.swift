import Foundation
import Testing

/// Locks the iOS effects-inspector slider wiring. The inspector sliders used to
/// render `Slider(value: .constant(value))` (read-only) and the Reset buttons
/// were empty closures, so iOS users could see but not adjust brightness /
/// contrast / saturation / color-temperature, color grade, mask feather, and the
/// basic opacity / speed / volume / fade controls. This contract pins each
/// slider to a real `Binding` routed through `IOSEditorViewModel`.
///
/// The iOS app target can't be built on every host (no iOS platform installed),
/// so this is a static-source regression net, NOT a runtime/device verification.
/// It proves the wiring is *present in source*; it does not prove on-device
/// behavior. On-device adjustment still needs a separate iOS build + manual pass.
@Suite("iOS Effects Inspector Wiring Static Contract")
struct IOSEffectsInspectorWiringStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func inspectorSource() throws -> String {
        try source("App/MovieCutiOS/Views/IOSEffectsInspectorView.swift")
    }

    private func viewModelSource() throws -> String {
        try source("App/MovieCutiOS/IOSEditorViewModel.swift")
    }

    @Test("inspectorSlider drives a real Binding, never a constant")
    func sliderUsesBinding() throws {
        let source = try inspectorSource()
        #expect(source.contains("binding: Binding<Double>"))
        #expect(source.contains("Slider(value: binding, in: range"))
        // No read-only sliders anywhere in the inspector.
        #expect(!source.contains(".constant("))
        #expect(!source.contains("set: { _ in }"))
    }

    @Test("view binds the @Observable view model with @Bindable")
    func usesBindableViewModel() throws {
        let source = try inspectorSource()
        #expect(source.contains("@Bindable var viewModel: IOSEditorViewModel"))
        #expect(!source.contains("@ObservedObject"))
    }

    @Test("color-correction sliders and Reset are wired")
    func colorCorrectionWired() throws {
        let source = try inspectorSource()
        #expect(source.contains("colorCorrectionBinding(keyPath: \\.brightness)"))
        #expect(source.contains("colorCorrectionBinding(keyPath: \\.contrast)"))
        #expect(source.contains("colorCorrectionBinding(keyPath: \\.saturation)"))
        #expect(source.contains("colorCorrectionBinding(keyPath: \\.warmth)"))
        #expect(source.contains("updateSelectedColorCorrection(correction)"))
        // Reset is a real action, not an empty closure.
        #expect(source.contains("await viewModel.updateSelectedColorCorrection(nil)"))
    }

    @Test("adjustable color-grade UI is wired to the shared grade model")
    func colorGradeWired() throws {
        let source = try inspectorSource()
        #expect(source.contains("private var colorGradeSection"))
        #expect(source.contains("colorGradeBinding(keyPath: \\.lift.red)"))
        #expect(source.contains("colorGradeBinding(keyPath: \\.gamma)"))
        #expect(source.contains("colorGradeBinding(keyPath: \\.gain.blue)"))
        #expect(source.contains("updateSelectedColorGrade(clamped)"))
        #expect(source.contains("await viewModel.updateSelectedColorGrade(nil)"))
        // Grade keypath mutations re-init ColorGrade so its clamps hold.
        #expect(source.contains("ColorGrade("))
        #expect(source.contains("hslBands: grade.hslBands"))
        #expect(source.contains("curves: grade.curves"))
    }

    @Test("mask feather slider is wired")
    func maskFeatherWired() throws {
        let source = try inspectorSource()
        #expect(source.contains("maskFeatherBinding()"))
        #expect(source.contains("updateSelectedMask(mask)"))
    }

    @Test("basic sliders (opacity / speed / volume / fade) are wired")
    func basicSlidersWired() throws {
        let source = try inspectorSource()
        #expect(source.contains("updateSelectedOpacity(newValue)"))
        #expect(source.contains("updateSelectedPlaybackRate(newValue)"))
        #expect(source.contains("updateSelectedVolume(newValue)"))
        #expect(source.contains("updateSelectedAudioFade(fadeInDuration: newValue)"))
        #expect(source.contains("updateSelectedAudioFade(fadeOutDuration: newValue)"))
    }

    @Test("effect add/remove menu buttons are wired")
    func effectListWired() throws {
        let source = try inspectorSource()
        #expect(source.contains("addEffect(type)"))
        #expect(source.contains("removeEffect(effect.id)"))
        #expect(source.contains("updateSelectedEffects(effects)"))
    }

    @Test("view model exposes the grade and fade update methods the UI calls")
    func viewModelExposesUpdaters() throws {
        let source = try viewModelSource()
        #expect(source.contains("func updateSelectedColorGrade(_ colorGrade: ColorGrade?) async"))
        #expect(source.contains(".colorGrade(colorGrade)"))
        #expect(source.contains("func updateSelectedAudioFade("))
        #expect(source.contains("AudioFadeCommand("))
    }
}
