#if os(iOS)
import SwiftUI
import MovieCutCore

struct IOSEffectsInspectorView: View {
    @Bindable var viewModel: IOSEditorViewModel
    let clip: Clip

    @State private var selectedTab: InspectorTab = .basic

    private enum InspectorTab: String, CaseIterable {
        case basic = "Basic"
        case effects = "Effects"
        case audio = "Audio"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedTab) {
                ForEach(InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .basic:
                        basicSection
                    case .effects:
                        effectsSection
                    case .audio:
                        audioSection
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Basic Section

    private var basicSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            clipInfoSection
            transformSection
            opacitySection
            speedSection
        }
    }

    private var clipInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("클립 정보")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Text("타입")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(clip.kind.rawValue)
                    .font(.caption)
            }
            HStack {
                Text("길이")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2fs", clip.timelineRange.duration))
                    .font(.caption)
            }
        }
    }

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("변형")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Text("X")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", clip.transform.position.x))
                    .font(.caption)
            }
            HStack {
                Text("Y")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f", clip.transform.position.y))
                    .font(.caption)
            }
            HStack {
                Text("배율")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", clip.transform.scale.width))
                    .font(.caption)
            }
            HStack {
                Text("회전")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f°", clip.transform.rotation))
                    .font(.caption)
            }
        }
    }

    private var opacitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("불투명도")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.0f%%", clip.opacity * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { clip.opacity },
                set: { newValue in Task { await viewModel.updateSelectedOpacity(newValue) } }
            ), in: 0...1)
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("속도")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.2gx", clip.playbackRate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { clip.playbackRate },
                set: { newValue in Task { await viewModel.updateSelectedPlaybackRate(newValue) } }
            ), in: 0.25...4.0)
        }
    }

    // MARK: - Effects Section

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            colorCorrectionSection
            colorGradeSection
            maskSection
            effectsListSection
        }
    }

    private var colorCorrectionSection: some View {
        let cc = clip.colorCorrection ?? ColorCorrection()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("색 보정")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("초기화") {
                    Task { await viewModel.updateSelectedColorCorrection(nil) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(clip.colorCorrection == nil)
            }

            inspectorSlider(title: "밝기", value: cc.brightness, range: -1...1, binding: colorCorrectionBinding(keyPath: \.brightness))
            inspectorSlider(title: "대비", value: cc.contrast, range: 0...2, binding: colorCorrectionBinding(keyPath: \.contrast))
            inspectorSlider(title: "채도", value: cc.saturation, range: 0...2, binding: colorCorrectionBinding(keyPath: \.saturation))
            inspectorSlider(title: "색온도", value: cc.warmth, range: -1...1, binding: colorCorrectionBinding(keyPath: \.warmth))
            inspectorSlider(title: "색조", value: cc.tint, range: -1...1, binding: colorCorrectionBinding(keyPath: \.tint))
        }
    }

    private var colorGradeSection: some View {
        let grade = clip.colorGrade ?? ColorGrade()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("컬러 그레이드")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("초기화") {
                    Task { await viewModel.updateSelectedColorGrade(nil) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(clip.colorGrade == nil)
            }

            Text("리프트 · 그림자")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "R", value: grade.lift.red, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.red))
            inspectorSlider(title: "G", value: grade.lift.green, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.green))
            inspectorSlider(title: "B", value: grade.lift.blue, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.blue))

            Text("감마 · 중간톤")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "감마", value: grade.gamma, range: 0.2...2.0, binding: colorGradeBinding(keyPath: \.gamma))

            Text("게인 · 하이라이트")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "R", value: grade.gain.red, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.red))
            inspectorSlider(title: "G", value: grade.gain.green, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.green))
            inspectorSlider(title: "B", value: grade.gain.blue, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.blue))
        }
    }

    private var maskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("마스크")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let mask = clip.mask {
                HStack {
                    Text("형태")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mask.shape.displayName)
                        .font(.caption)
                }
                inspectorSlider(title: "페더", value: mask.feather, range: 0...1, binding: maskFeatherBinding())
            } else {
                Text("마스크 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var effectsListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("이펙트")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Menu {
                    ForEach(EffectType.allCases, id: \.self) { type in
                        Button(type.displayName) { addEffect(type) }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.accentColor)
                }
            }

            if clip.effects.isEmpty {
                Text("이펙트 없음")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(clip.effects) { effect in
                HStack {
                    Image(systemName: effectIcon(for: effect.type))
                        .foregroundStyle(.accentColor)
                    Text(effect.type.displayName)
                        .font(.caption)
                    Spacer()
                    Button {
                        removeEffect(effect.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Audio Section

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            volumeSection
            fadeSection
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("볼륨")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(String(format: "%.0f%%", clip.volume * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { clip.volume },
                set: { newValue in Task { await viewModel.updateSelectedVolume(newValue) } }
            ), in: 0...2)
        }
    }

    private var fadeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("페이드")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("페이드 인")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", clip.fadeInDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { clip.fadeInDuration },
                    set: { newValue in Task { await viewModel.updateSelectedAudioFade(fadeInDuration: newValue) } }
                ), in: 0...5)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("페이드 아웃")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1fs", clip.fadeOutDuration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(
                    get: { clip.fadeOutDuration },
                    set: { newValue in Task { await viewModel.updateSelectedAudioFade(fadeOutDuration: newValue) } }
                ), in: 0...5)
            }
        }
    }

    // MARK: - Helpers

    private func inspectorSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        binding: Binding<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }
            Slider(value: binding, in: range, step: 0.01)
        }
    }

    // MARK: - Bindings

    private func colorCorrectionBinding(
        keyPath: WritableKeyPath<ColorCorrection, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let correction = clip.colorCorrection ?? ColorCorrection()
                return correction[keyPath: keyPath]
            },
            set: { newValue in
                var correction = clip.colorCorrection ?? ColorCorrection()
                correction[keyPath: keyPath] = newValue
                Task { await viewModel.updateSelectedColorCorrection(correction) }
            }
        )
    }

    private func colorGradeBinding(
        keyPath: WritableKeyPath<ColorGrade, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let grade = clip.colorGrade ?? ColorGrade()
                return grade[keyPath: keyPath]
            },
            set: { newValue in
                var grade = clip.colorGrade ?? ColorGrade()
                grade[keyPath: keyPath] = newValue
                // Re-init so ColorGrade's clamping invariants are enforced.
                let clamped = ColorGrade(lift: grade.lift, gamma: grade.gamma, gain: grade.gain)
                Task { await viewModel.updateSelectedColorGrade(clamped) }
            }
        )
    }

    private func maskFeatherBinding() -> Binding<Double> {
        Binding(
            get: { clip.mask?.feather ?? 0 },
            set: { feather in
                guard var mask = clip.mask else { return }
                mask.feather = feather
                Task { await viewModel.updateSelectedMask(mask) }
            }
        )
    }

    // MARK: - Effects

    private func addEffect(_ type: EffectType) {
        var effects = clip.effects
        effects.append(Effect(type: type))
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func removeEffect(_ effectId: UUID) {
        let effects = clip.effects.filter { $0.id != effectId }
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func effectIcon(for type: EffectType) -> String {
        switch type {
        case .brightness: return "sun.max"
        case .contrast: return "circle.lefthalf"
        case .saturation: return "paintpalette"
        case .temperature: return "thermometer"
        case .exposure: return "camera.aperture"
        case .fadeIn: return "arrow.down.right"
        case .fadeOut: return "arrow.up.right"
        case .crossDissolve: return "arrow.left.arrow.right"
        case .grayscale: return "moon"
        case .sepia: return "paintbrush"
        case .blur: return "drop"
        case .styleTransfer: return "sparkles"
        case .cinematicLUT: return "film"
        case .vintageLUT: return "camera.filters"
        case .noirLUT: return "moon"
        case .vividLUT: return "wand.and.stars"
        case .coolLUT: return "snowflake"
        case .externalLUT: return "square.stack.3d.forward.dottedline"
        }
    }
}
#endif
