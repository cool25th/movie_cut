import SwiftUI
import MovieCutCore

struct InspectorPanel: View {
    var viewModel: EditorViewModel
    @State private var isTransitionExpanded = false
    @State private var isAnimationExpanded = false
    @State private var selectedKeyframeId: UUID?

    private let speedPresets: [Double] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(12)

            Divider()

            if let clip = viewModel.selectedClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Clip Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Clip Info")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            LabeledContent("Type", value: clip.kind.rawValue)
                            LabeledContent("Duration", value: String(format: "%.2fs", clip.timelineRange.duration))
                        }

                        // Transform
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transform")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            LabeledContent("X", value: String(format: "%.1f", clip.transform.position.x))
                            LabeledContent("Y", value: String(format: "%.1f", clip.transform.position.y))
                            LabeledContent("Scale", value: String(format: "%.2f", clip.transform.scale.width))
                            LabeledContent("Rotation", value: String(format: "%.1f\u{00B0}", clip.transform.rotation))
                        }

                        // Opacity
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Opacity")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack {
                                Slider(value: Binding(
                                    get: { clip.opacity },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedOpacity(newValue) }
                                    }
                                ), in: 0 ... 1)
                                Text(String(format: "%.0f%%", clip.opacity * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44)
                            }
                        }

                        // Volume
                        if clip.kind.supportsVolume {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Volume")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                HStack {
                                    Slider(value: Binding(
                                        get: { clip.volume },
                                        set: { newValue in
                                            Task { await viewModel.updateSelectedVolume(newValue) }
                                        }
                                    ), in: 0 ... 2)
                                    Text(String(format: "%.0f%%", clip.volume * 100))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44)
                                }
                            }
                        }

                        // Speed
                        if clip.kind.supportsSpeed {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Speed")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(String(format: "%.0f%%", clip.playbackRate * 100))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Slider(value: Binding(
                                    get: { clip.playbackRate },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedPlaybackRate(newValue) }
                                    }
                                ), in: 0.25 ... 4.0)

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48), spacing: 6)], spacing: 6) {
                                    ForEach(speedPresets, id: \.self) { preset in
                                        Button(speedPresetLabel(preset)) {
                                            Task { await viewModel.updateSelectedPlaybackRate(preset) }
                                        }
                                        .controlSize(.small)
                                    }
                                }
                            }
                        }

                        // Text Content
                        if let textContent = clip.textContent {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Text")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                TextField("Text", text: Binding(
                                    get: { textContent.text },
                                    set: { newValue in
                                        var updated = textContent
                                        updated.text = newValue
                                        Task { await viewModel.updateSelectedTextContent(updated) }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Chroma Key
                        if clip.kind == .video {
                            ChromaKeyView(clip: clip) { chromaKey in
                                Task { await viewModel.updateSelectedChromaKey(chromaKey) }
                            }
                        }

                        // Effects
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Effects")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                Spacer()
                                Menu {
                                    ForEach(EffectType.allCases, id: \.self) { type in
                                        Button(type.displayName) {
                                            addEffect(type, to: clip)
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
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(effect.type.displayName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Spacer()
                                        Button {
                                            removeEffect(effect.id, from: clip)
                                        } label: {
                                            Image(systemName: "trash")
                                        }
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(.secondary)
                                    }

                                    ForEach(parameterDefinitions(for: effect.type)) { definition in
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(definition.title)
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: definition.valueFormat, effect.parameters[definition.key] ?? definition.defaultValue))
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                            Slider(value: Binding(
                                                get: { effect.parameters[definition.key] ?? definition.defaultValue },
                                                set: { newValue in
                                                    updateEffect(effect.id, parameter: definition.key, value: newValue, in: clip)
                                                }
                                            ), in: definition.range)
                                        }
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: .separatorColor).opacity(0.12))
                                .cornerRadius(6)
                            }
                        }

                        // Subtitles
                        if clip.kind.supportsSubtitles {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Subtitles")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                AutoSubtitlesView(viewModel: viewModel)
                            }
                        }

                        // Keyframes
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

                        // Transition
                        DisclosureGroup("Transition", isExpanded: $isTransitionExpanded) {
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Type", selection: Binding(
                                    get: { clip.transition?.type ?? .none },
                                    set: { type in
                                        updateTransitionType(type, for: clip)
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
                                                updateTransitionDuration(duration, for: clip)
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
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a clip to inspect")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .controlBackgroundColor))
        .onChange(of: viewModel.selectedClipId) { _, _ in
            selectedKeyframeId = nil
        }
    }

    private func speedPresetLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }

    private func addEffect(_ type: EffectType, to clip: Clip) {
        var effects = clip.effects
        let parameters = Dictionary(
            uniqueKeysWithValues: parameterDefinitions(for: type).map { ($0.key, $0.defaultValue) }
        )
        effects.append(Effect(type: type, parameters: parameters))
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func removeEffect(_ effectId: UUID, from clip: Clip) {
        let effects = clip.effects.filter { $0.id != effectId }
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateEffect(_ effectId: UUID, parameter: String, value: Double, in clip: Clip) {
        var effects = clip.effects
        guard let index = effects.firstIndex(where: { $0.id == effectId }) else { return }
        effects[index].parameters[parameter] = value
        Task { await viewModel.updateSelectedEffects(effects) }
    }

    private func updateTransitionType(_ type: TransitionType, for clip: Clip) {
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

    private func updateTransitionDuration(_ duration: Double, for clip: Clip) {
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

private struct EffectParameterDefinition: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var range: ClosedRange<Double>
    var defaultValue: Double
    var valueFormat: String = "%.2f"
}

private extension ClipKind {
    var supportsVolume: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }

    var supportsSpeed: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }

    var supportsSubtitles: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }
}

private extension EffectType {
    var displayName: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .temperature: return "Temperature"
        case .exposure: return "Exposure"
        case .fadeIn: return "Fade In"
        case .fadeOut: return "Fade Out"
        case .crossDissolve: return "Cross Dissolve"
        case .grayscale: return "Grayscale"
        case .sepia: return "Sepia"
        case .blur: return "Blur"
        }
    }
}

private extension TransitionType {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .crossDissolve: return "Cross Dissolve"
        case .fadeThroughBlack: return "Fade Through Black"
        case .wipeRight: return "Wipe Right"
        }
    }
}
