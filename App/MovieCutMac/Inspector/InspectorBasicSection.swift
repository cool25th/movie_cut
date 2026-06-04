import SwiftUI
import MovieCutCore

struct InspectorBasicSection: View {
    @Bindable var viewModel: EditorViewModel
    let clip: Clip

    private let speedPresets: [Double] = [0.25, 0.5, 1.0, 1.5, 2.0, 4.0]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            clipInfoSection
            transformSection
            opacitySection

            if clip.kind.supportsVolume {
                volumeSection
                equalizerSection
            }

            if clip.kind.supportsSpeed {
                speedSection
            }

            if let textContent = clip.textContent {
                textContentSection(textContent)
            }
        }
    }

    private var clipInfoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clip Info")
                .font(.subheadline)
                .fontWeight(.semibold)
            LabeledContent("Type", value: clip.kind.rawValue)
            LabeledContent("Duration", value: String(format: "%.2fs", clip.timelineRange.duration))
        }
    }

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transform")
                .font(.subheadline)
                .fontWeight(.semibold)
            LabeledContent("X", value: String(format: "%.1f", clip.transform.position.x))
            LabeledContent("Y", value: String(format: "%.1f", clip.transform.position.y))
            LabeledContent("Scale", value: String(format: "%.2f", clip.transform.scale.width))
            LabeledContent("Rotation", value: String(format: "%.1f\u{00B0}", clip.transform.rotation))
        }
    }

    private var opacitySection: some View {
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
    }

    private var volumeSection: some View {
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
            Slider(value: Binding(
                get: { clip.fadeInDuration },
                set: { newValue in
                    Task { await viewModel.updateSelectedAudioFade(fadeInDuration: newValue) }
                }
            ), in: 0 ... 5, step: 0.1) {
                Text("Fade In")
            }
            Slider(value: Binding(
                get: { clip.fadeOutDuration },
                set: { newValue in
                    Task { await viewModel.updateSelectedAudioFade(fadeOutDuration: newValue) }
                }
            ), in: 0 ... 5, step: 0.1) {
                Text("Fade Out")
            }

            HStack {
                Button("Noise Reduction") {
                    if let clipId = viewModel.selectedClipId {
                        Task { try? await viewModel.applyNoiseReduction(for: clipId) }
                    }
                }
                .controlSize(.small)

                Button("Extract Audio") {
                    if let clipId = viewModel.selectedClipId {
                        Task { try? await viewModel.extractAudio(from: clipId) }
                    }
                }
                .controlSize(.small)
                .disabled(clip.kind != .video)
            }
        }
    }

    private var equalizerSection: some View {
        Section("Equalizer") {
            Picker("Preset", selection: $viewModel.selectedEQPreset) {
                ForEach(EqualizerPresetOption.allCases) { opt in
                    Text(opt.displayName).tag(opt.rawValue)
                }
            }
            .onChange(of: viewModel.selectedEQPreset) { _, newValue in
                Task { await viewModel.applyEQPreset(newValue) }
            }
        }
    }

    private var speedSection: some View {
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

    private func textContentSection(_ textContent: TextClipContent) -> some View {
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

    private func speedPresetLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}
