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
            Text("Clip Info")
                .font(.subheadline)
                .fontWeight(.semibold)
            HStack {
                Text("Type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(clip.kind.rawValue)
                    .font(.caption)
            }
            HStack {
                Text("Duration")
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
            Text("Transform")
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
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", clip.transform.scale.width))
                    .font(.caption)
            }
            HStack {
                Text("Rotation")
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
                Text(opacityTitle)
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
            .accessibilityLabel(Text(opacityTitle))
            .accessibilityValue(Text(String(format: "%.0f%%", clip.opacity * 100)))
        }
    }

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(speedTitle)
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
            .accessibilityLabel(Text(speedTitle))
            .accessibilityValue(Text(String(format: "%.2gx", clip.playbackRate)))
        }
    }

    // MARK: - Effects Section

    private var opacityTitle: String { "Opacity" }
    private var speedTitle: String { "Speed" }

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
                Text("Color Correction")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset") {
                    Task { await viewModel.updateSelectedColorCorrection(nil) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(clip.colorCorrection == nil)
            }

            inspectorSlider(title: "Brightness", value: cc.brightness, range: -1...1, binding: colorCorrectionBinding(keyPath: \.brightness))
            inspectorSlider(title: "Contrast", value: cc.contrast, range: 0...2, binding: colorCorrectionBinding(keyPath: \.contrast))
            inspectorSlider(title: "Saturation", value: cc.saturation, range: 0...2, binding: colorCorrectionBinding(keyPath: \.saturation))
            inspectorSlider(title: "Temperature", value: cc.warmth, range: -1...1, binding: colorCorrectionBinding(keyPath: \.warmth))
            inspectorSlider(title: "Tint", value: cc.tint, range: -1...1, binding: colorCorrectionBinding(keyPath: \.tint))
        }
    }

    private var colorGradeSection: some View {
        let grade = clip.colorGrade ?? ColorGrade()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color Grade")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset") {
                    Task { await viewModel.updateSelectedColorGrade(nil) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .disabled(clip.colorGrade == nil)
            }

            Text("Lift · Shadows")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "R", value: grade.lift.red, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.red))
            inspectorSlider(title: "G", value: grade.lift.green, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.green))
            inspectorSlider(title: "B", value: grade.lift.blue, range: -1...1, binding: colorGradeBinding(keyPath: \.lift.blue))

            Text("Gamma · Midtones")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "Gamma", value: grade.gamma, range: 0.2...2.0, binding: colorGradeBinding(keyPath: \.gamma))

            Text("Gain · Highlights")
                .font(.caption2)
                .foregroundStyle(.secondary)
            inspectorSlider(title: "R", value: grade.gain.red, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.red))
            inspectorSlider(title: "G", value: grade.gain.green, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.green))
            inspectorSlider(title: "B", value: grade.gain.blue, range: 0...2, binding: colorGradeBinding(keyPath: \.gain.blue))

            toneCurvesSection(grade: grade)
        }
    }

    // MARK: - Tone Curves (iOS curve editing — Mac Inc 6 parity, touch-first)

    private enum CurveChannel: String, CaseIterable, Identifiable {
        case master, red, green, blue
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .master: "Master"
            case .red: "Red"
            case .green: "Green"
            case .blue: "Blue"
            }
        }
    }

    @State private var selectedCurveChannel: CurveChannel = .master

    /// Common curve shapes as presets — the touch-first alternative to the
    /// Mac's draggable canvas. Each preset produces 3 control points
    /// (endpoints + a midpoint at x=0.5).
    private enum CurvePreset: String, CaseIterable, Identifiable {
        case linear = "Linear"
        case sCurve = "S-Curve"
        case fadeUp = "Fade Up"
        case fadeDown = "Fade Down"
        case boost = "Boost"
        case reduce = "Reduce"
        var id: String { rawValue }

        /// The midpoint's y value for this preset.
        var midpointY: Double {
            switch self {
            case .linear: 0.5
            case .sCurve: 0.5   // S-shape handled by a 3-point arrangement
            case .fadeUp: 0.65
            case .fadeDown: 0.35
            case .boost: 0.55
            case .reduce: 0.45
            }
        }

        func points() -> [CurvePoint] {
            let mid = midpointY
            switch self {
            case .linear:
                return ColorCurves.identityPoints
            case .sCurve:
                // An S: shadows darken, highlights brighten
                return [
                    CurvePoint(x: 0, y: 0),
                    CurvePoint(x: 0.25, y: 0.15),
                    CurvePoint(x: 0.75, y: 0.85),
                    CurvePoint(x: 1, y: 1),
                ]
            default:
                return [
                    CurvePoint(x: 0, y: 0),
                    CurvePoint(x: 0.5, y: mid),
                    CurvePoint(x: 1, y: 1),
                ]
            }
        }
    }

    private func toneCurvesSection(grade: ColorGrade) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tone Curves")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Channel", selection: $selectedCurveChannel) {
                ForEach(CurveChannel.allCases) { channel in
                    Text(channel.displayName).tag(channel)
                }
            }
            .pickerStyle(.segmented)

            // Mini curve preview — sampled through the SAME evaluator the
            // renderer consumes, so what you see is what renders.
            curvePreview(for: selectedCurveChannel, in: grade)
                .frame(height: 80)
                .aspectRatio(1.6, contentMode: .fit)

            // Preset chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(CurvePreset.allCases) { preset in
                        presetChip(preset, for: selectedCurveChannel, in: grade)
                    }
                }
            }
        }
    }

    /// A small curve visualization sampled through CurveEvaluator.
    private func curvePreview(for channel: CurveChannel, in grade: ColorGrade) -> some View {
        let curves = grade.curves ?? .identity
        let points: [CurvePoint]
        switch channel {
        case .master: points = curves.master
        case .red: points = curves.red
        case .green: points = curves.green
        case .blue: points = curves.blue
        }

        return Canvas { context, size in
            // Identity diagonal reference
            var diagonal = Path()
            diagonal.move(to: .zero)
            diagonal.addLine(to: CGPoint(x: size.width, y: size.height))
            context.stroke(diagonal, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

            // The curve
            var path = Path()
            let samples = 48
            for index in 0...samples {
                let x = Double(index) / Double(samples)
                let y = CurveEvaluator.evaluate(points: points, at: x)
                let point = CGPoint(x: size.width * x, y: size.height * (1 - y))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Tone curve preview, \(channel.displayName)")
        .accessibilityValue(
            points == ColorCurves.identityPoints ? "Identity" : "\(points.count - 2) control points"
        )
    }

    private func presetChip(_ preset: CurvePreset, for channel: CurveChannel, in grade: ColorGrade) -> some View {
        let curves = grade.curves ?? .identity
        let channelPoints: [CurvePoint]
        switch channel {
        case .master: channelPoints = curves.master
        case .red: channelPoints = curves.red
        case .green: channelPoints = curves.green
        case .blue: channelPoints = curves.blue
        }
        let isActive = channelPoints.map { CurvePoint(x: $0.x, y: $0.y) } == preset.points().map { CurvePoint(x: $0.x, y: $0.y) }

        return Button(preset.rawValue) {
            applyCurvePreset(preset, to: channel, in: grade)
        }
        .font(.caption2.weight(isActive ? .semibold : .regular))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            if isActive {
                Capsule().fill(Color.accentColor.opacity(0.2))
            } else {
                Capsule().fill(.quaternary)
            }
        }
        .accessibilityLabel("\(preset.rawValue) curve preset")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    /// Applies a curve preset to the selected channel, preserving the other
    /// channels. All-identity → nil commit keeps JSON byte-stable.
    private func applyCurvePreset(_ preset: CurvePreset, to channel: CurveChannel, in grade: ColorGrade) {
        var curves = grade.curves ?? .identity
        let points = preset.points()
        switch channel {
        case .master: curves.master = points
        case .red: curves.red = points
        case .green: curves.green = points
        case .blue: curves.blue = points
        }

        let updated = ColorGrade(
            lift: grade.lift,
            gamma: grade.gamma,
            gain: grade.gain,
            hslBands: grade.hslBands,
            curves: curves.isIdentity ? nil : curves
        )
        Task { await viewModel.updateSelectedColorGrade(updated) }
    }

    private var maskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mask")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let mask = clip.mask {
                HStack {
                    Text("Shape")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(mask.shape.displayName)
                        .font(.caption)
                }
                inspectorSlider(title: "Feather", value: mask.feather, range: 0...1, binding: maskFeatherBinding())
            } else {
                Text("No Mask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var effectsListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Effects")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Menu {
                    ForEach(EffectType.allCases, id: \.self) { type in
                        Button(type.displayName) { addEffect(type) }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }

            if clip.effects.isEmpty {
                Text("No Effects")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(clip.effects) { effect in
                HStack {
                    Image(systemName: effectIcon(for: effect.type))
                        .foregroundStyle(Color.accentColor)
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
                Text("Volume")
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
            Text("Fade")
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Fade In")
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
                    Text("Fade Out")
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
                // A11Y-01: the visible title lives in a sibling Text — without
                // an explicit label VoiceOver announces a bare "slider".
                .accessibilityLabel(Text(title))
                .accessibilityValue(Text(String(format: "%.2f", value)))
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
                let clamped = ColorGrade(
                    lift: grade.lift,
                    gamma: grade.gamma,
                    gain: grade.gain,
                    hslBands: grade.hslBands,
                    curves: grade.curves
                )
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
