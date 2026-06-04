import SwiftUI
import MovieCutCore

struct InspectorEffectsSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    @State private var isTransitionExpanded = false
    @State private var isAnimationExpanded = false
    @State private var selectedKeyframeId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            colorCorrectionSection
            maskSection
            backgroundRemovalSection
            styleTransferSection
            effectsSection

            if clip.kind == .video {
                chromaKeySection
            }

            reverseFreezeSection
            transitionSection
            animationSection
        }
        .onChange(of: viewModel.selectedClipId) { _, _ in
            selectedKeyframeId = nil
        }
    }

    private var colorCorrectionSection: some View {
        let colorCorrection = clip.colorCorrection ?? ColorCorrection()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Color Correction")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset") {
                    Task { await viewModel.updateSelectedColorCorrection(nil) }
                }
                .controlSize(.small)
                .disabled(clip.colorCorrection == nil)
            }

            inspectorSlider(
                title: "Brightness",
                value: colorCorrection.brightness,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.brightness)
            )

            inspectorSlider(
                title: "Contrast",
                value: colorCorrection.contrast,
                range: 0 ... 2,
                binding: colorCorrectionBinding(keyPath: \.contrast)
            )

            inspectorSlider(
                title: "Saturation",
                value: colorCorrection.saturation,
                range: 0 ... 2,
                binding: colorCorrectionBinding(keyPath: \.saturation)
            )

            inspectorSlider(
                title: "Color Temperature",
                value: colorCorrection.warmth,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.warmth)
            )

            inspectorSlider(
                title: "Tint",
                value: colorCorrection.tint,
                range: -1 ... 1,
                binding: colorCorrectionBinding(keyPath: \.tint)
            )
        }
    }

    private var maskSection: some View {
        let mask = clip.mask ?? defaultMask()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mask")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Clear Mask") {
                    Task { await viewModel.updateSelectedMask(nil) }
                }
                .controlSize(.small)
                .disabled(clip.mask == nil)
            }

            Picker("Shape", selection: Binding(
                get: { mask.shape },
                set: { shape in
                    var updatedMask = clip.mask ?? defaultMask(shape: shape)
                    updatedMask.shape = shape
                    Task { await viewModel.updateSelectedMask(updatedMask) }
                }
            )) {
                ForEach(MaskShape.allCases, id: \.self) { shape in
                    Text(shape.displayName).tag(shape)
                }
            }
            .pickerStyle(.menu)

            inspectorSlider(
                title: "Feather",
                value: mask.feather,
                range: 0 ... 1,
                binding: maskFeatherBinding()
            )

            Toggle("Inverted", isOn: Binding(
                get: { mask.inverted },
                set: { inverted in
                    var updatedMask = clip.mask ?? defaultMask()
                    updatedMask.inverted = inverted
                    Task { await viewModel.updateSelectedMask(updatedMask) }
                }
            ))
        }
    }

    private var backgroundRemovalSection: some View {
        Section("Background Removal") {
            Toggle("Remove Background", isOn: $viewModel.isBackgroundRemoved)
                .onChange(of: viewModel.isBackgroundRemoved) { _, newValue in
                    Task { await viewModel.toggleBackgroundRemoval(newValue) }
                }
        }
    }

    private var styleTransferSection: some View {
        Section("Style Transfer") {
            Picker("Style", selection: $viewModel.selectedStyle) {
                Text("None").tag("none")
                Text("Comic").tag("comic")
                Text("Noir").tag("noir")
                Text("Vintage").tag("vintage")
                Text("Cyberpunk").tag("cyberpunk")
                Text("Watercolor").tag("watercolor")
            }
            .onChange(of: viewModel.selectedStyle) { _, newValue in
                Task { await viewModel.applyStyleTransfer(newValue) }
            }
        }
    }

    private var effectsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Effects")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Menu {
                    ForEach(EffectType.allCases, id: \.self) { type in
                        Button(type.displayName) {
                            addEffect(type)
                        }
                    }
                } label: {
                    Label("Add Effect", systemImage: "plus")
                }
                .menuStyle(.button)
                .controlSize(.small)
            }

            if clip.effects.isEmpty {
                Text("No effects")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            ForEach(clip.effects) { effect in
                EffectRowView(
                    effect: effect,
                    parameterDefinitions: parameterDefinitions(for: effect.type),
                    onRemove: {
                        removeEffect(effect.id)
                    },
                    onParameterChange: { key, newValue in
                        updateEffect(effect.id, parameter: key, value: newValue)
                    }
                )
            }
        }
    }

    private var chromaKeySection: some View {
        ChromaKeyView(clip: clip) { chromaKey in
            Task { await viewModel.updateSelectedChromaKey(chromaKey) }
        }
    }

    private var reverseFreezeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reverse & Freeze")
                .font(.subheadline)
                .fontWeight(.semibold)

            Toggle("Reverse playback", isOn: Binding(
                get: { clip.isReversed },
                set: { isReversed in
                    Task { await viewModel.updateSelectedReversePlayback(isReversed) }
                }
            ))

            Button("Freeze Frame") {
                Task { await viewModel.freezeSelectedFrame() }
            }
            .controlSize(.small)
            .disabled(!canFreezeFrame())
        }
    }

    private var transitionSection: some View {
        DisclosureGroup("Transition", isExpanded: $isTransitionExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Type", selection: Binding(
                    get: { clip.transition?.type ?? .none },
                    set: { type in
                        updateTransitionType(type)
                    }
                )) {
                    ForEach(TransitionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                if let transition = clip.transition {
                    HStack {
                        Slider(value: Binding(
                            get: { transition.duration },
                            set: { duration in
                                updateTransitionDuration(duration)
                            }
                        ), in: 0.1 ... 3)
                        Text(String(format: "%.1fs", transition.duration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 44)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var animationSection: some View {
        DisclosureGroup("Animation", isExpanded: $isAnimationExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                KeyframeEditorView(
                    clip: clip,
                    playheadTime: viewModel.playheadTime,
                    selectedKeyframeId: selectedKeyframeId,
                    onSelect: { selectedKeyframeId = $0 },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )

                KeyframeListView(
                    clip: clip,
                    selectedKeyframeId: selectedKeyframeId,
                    onSelect: { selectedKeyframeId = $0 },
                    onChange: { keyframes in
                        Task { await viewModel.updateSelectedKeyframes(keyframes) }
                    }
                )
            }
            .padding(.top, 4)
        }
    }

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
                    .frame(width: 38, alignment: .trailing)
            }
            Slider(value: binding, in: range, step: 0.01)
        }
    }

    private func colorCorrectionBinding(
        keyPath: WritableKeyPath<ColorCorrection, Double>
    ) -> Binding<Double> {
        Binding(
            get: {
                let colorCorrection = clip.colorCorrection ?? ColorCorrection()
                return colorCorrection[keyPath: keyPath]
            },
            set: { newValue in
                var colorCorrection = clip.colorCorrection ?? ColorCorrection()
                colorCorrection[keyPath: keyPath] = newValue
                Task { await viewModel.updateSelectedColorCorrection(colorCorrection) }
            }
        )
    }

    private func maskFeatherBinding() -> Binding<Double> {
        Binding(
            get: { (clip.mask ?? defaultMask()).feather },
            set: { feather in
                var mask = clip.mask ?? defaultMask()
                mask.feather = feather
                Task { await viewModel.updateSelectedMask(mask) }
            }
        )
    }

    private func defaultMask(shape: MaskShape = .rectangle) -> Mask {
        let canvasSize = viewModel.currentProject.canvas.size
        return Mask(
            shape: shape,
            position: CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.5),
            size: CGSize(width: canvasSize.width * 0.5, height: canvasSize.height * 0.5)
        )
    }

    private func canFreezeFrame() -> Bool {
        let freezeTime = viewModel.playheadTime - clip.timelineRange.start
        return freezeTime > 0 && freezeTime < clip.timelineRange.duration
    }

    private func addEffect(_ type: EffectType) {
        var effects = clip.effects
        let parameters = Dictionary(
            uniqueKeysWithValues: parameterDefinitions(for: type).map { ($0.key, $0.defaultValue) }
        )
        effects.append(Effect(type: type, parameters: parameters))
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func removeEffect(_ effectId: UUID) {
        let effects = clip.effects.filter { $0.id != effectId }
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateEffect(_ effectId: UUID, parameter: String, value: Double) {
        var effects = clip.effects
        guard let index = effects.firstIndex(where: { $0.id == effectId }) else { return }
        effects[index].parameters[parameter] = value
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateTransitionType(_ type: TransitionType) {
        let transition: MovieCutCore.Transition?
        if type == .none {
            transition = nil
        } else {
            transition = MovieCutCore.Transition(
                id: clip.transition?.id ?? UUID(),
                type: type,
                duration: clip.transition?.duration ?? 0.5
            )
        }
        Task { await viewModel.updateSelectedTransition(transition) }
    }

    private func updateTransitionDuration(_ duration: Double) {
        guard var transition = clip.transition else { return }
        transition.duration = duration
        Task { await viewModel.updateSelectedTransition(transition) }
    }

    private func parameterDefinitions(for type: EffectType) -> [EffectParameterDefinition] {
        switch type {
        case .brightness:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .contrast:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .saturation:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: 0 ... 2, defaultValue: 1)]
        case .temperature:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -1 ... 1, defaultValue: 0)]
        case .exposure:
            return [EffectParameterDefinition(key: "amount", title: "Amount", range: -2 ... 2, defaultValue: 0)]
        case .fadeIn, .fadeOut, .crossDissolve:
            return [EffectParameterDefinition(key: "duration", title: "Duration", range: 0.1 ... 3, defaultValue: 0.5, valueFormat: "%.1fs")]
        case .grayscale, .sepia:
            return []
        case .blur:
            return [EffectParameterDefinition(key: "radius", title: "Radius", range: 1 ... 12, defaultValue: 1, valueFormat: "%.0f")]
        }
    }
}
