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
            if isStickerClip {
                stickerTransformSection
            }
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
            LabeledContent("Type", value: clipTypeLabel)
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

    private var stickerTransformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sticker Transform")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Quick")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            transformSlider(
                title: "X",
                value: Double(clip.transform.position.x),
                range: 0 ... Double(max(canvasSize.width, 1))
            ) { newValue in
                var transform = clip.transform
                transform.position.x = CGFloat(newValue)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Y",
                value: Double(clip.transform.position.y),
                range: 0 ... Double(max(canvasSize.height, 1))
            ) { newValue in
                var transform = clip.transform
                transform.position.y = CGFloat(newValue)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Scale",
                value: Double((clip.transform.scale.width + clip.transform.scale.height) * 0.5),
                range: 0.25 ... 2.5
            ) { newValue in
                var transform = clip.transform
                let scale = CGFloat(newValue)
                transform.scale = CGSize(width: scale, height: scale)
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            transformSlider(
                title: "Rotate",
                value: clip.transform.rotation,
                range: -180 ... 180
            ) { newValue in
                var transform = clip.transform
                transform.rotation = newValue
                Task { await viewModel.updateSelectedStickerTransform(transform) }
            }

            HStack(spacing: 6) {
                Button {
                    Task { await viewModel.centerSelectedSticker() }
                } label: {
                    Label("Center", systemImage: "dot.scope")
                }
                .controlSize(.small)

                Button {
                    Task { await viewModel.fitSelectedStickerToSocialSafeArea() }
                } label: {
                    Label("Safe", systemImage: "viewfinder")
                }
                .controlSize(.small)

                Button {
                    Task { await viewModel.resetSelectedStickerTransform() }
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .controlSize(.small)
            }
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

    private let fontFamilies = [
        "System", "Helvetica Neue", "Helvetica Neue Bold",
        "SF Pro", "SF Pro Rounded", "Georgia", "Menlo",
        "Avenir Next", "Futura", "Courier New"
    ]

    private func textContentSection(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isStickerClip ? "Sticker" : "Text")
                .font(.subheadline)
                .fontWeight(.semibold)

            TextField(isStickerClip ? "Sticker" : "Text", text: Binding(
                get: { textContent.text },
                set: { newValue in
                    var updated = textContent
                    updated.text = newValue
                    if isStickerClip {
                        updated.contentKind = .sticker
                    }
                    Task { await viewModel.updateSelectedTextContent(updated) }
                }
            ))
            .textFieldStyle(.roundedBorder)

            if isStickerClip {
                stickerMetadataSection(textContent)
            } else {
                HStack(spacing: 8) {
                    Picker("Font", selection: Binding(
                        get: { textContent.fontFamily },
                        set: { newValue in
                            var updated = textContent
                            updated.fontFamily = newValue
                            Task { await viewModel.updateSelectedTextContent(updated) }
                        }
                    )) {
                        ForEach(fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 160)

                    HStack(spacing: 4) {
                        Text("Size")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { textContent.fontSize },
                            set: { newValue in
                                var updated = textContent
                                updated.fontSize = newValue
                                Task { await viewModel.updateSelectedTextContent(updated) }
                            }
                        ), in: 8 ... 144, step: 1)
                        Text(String(format: "%.0f", textContent.fontSize))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                HStack(spacing: 8) {
                    Picker("Alignment", selection: Binding(
                        get: { textContent.alignment },
                        set: { newValue in
                            var updated = textContent
                            updated.alignment = newValue
                            Task { await viewModel.updateSelectedTextContent(updated) }
                        }
                    )) {
                        Label("Left", systemImage: "text.alignleft").tag(MovieCutCore.TextAlignment.leading)
                        Label("Center", systemImage: "text.aligncenter").tag(MovieCutCore.TextAlignment.center)
                        Label("Right", systemImage: "text.alignright").tag(MovieCutCore.TextAlignment.trailing)
                        Label("Justify", systemImage: "text.justify").tag(MovieCutCore.TextAlignment.justified)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)

                    ColorPicker("Color", selection: Binding(
                        get: {
                            colorFromHex(textContent.fontColor)
                        },
                        set: { newValue in
                            var updated = textContent
                            updated.fontColor = hexFromColor(newValue)
                            Task { await viewModel.updateSelectedTextContent(updated) }
                        }
                    ))
                    .labelsHidden()
                }
            }
        }
    }

    private func stickerMetadataSection(_ textContent: TextClipContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Kind", value: textContent.stickerImageURL == nil ? "Emoji sticker" : "Image/badge sticker")
                .font(.caption)

            if let stickerAssetID = textContent.stickerAssetID {
                LabeledContent("Asset", value: stickerAssetID.uuidString.prefix(8).description)
                    .font(.caption)
            }

            if let stickerImageURL = textContent.stickerImageURL {
                LabeledContent("Image", value: stickerImageURL.lastPathComponent)
                    .font(.caption)
            }
        }
    }

    private var clipTypeLabel: String {
        if isStickerClip {
            if clip.textContent?.stickerImageURL != nil {
                return "Image Sticker"
            }

            return "Sticker"
        }

        return clip.kind.rawValue.capitalized
    }

    private var isStickerClip: Bool {
        guard clip.kind == .text, let textContent = clip.textContent else {
            return false
        }

        return textContent.isSticker || textContent.fontFamily == "Apple Color Emoji"
    }

    private var canvasSize: CGSize {
        let timelineSize = viewModel.currentProject.timeline.canvasSize
        if timelineSize.width > 0, timelineSize.height > 0 {
            return timelineSize
        }

        return viewModel.currentProject.canvas.size
    }

    private func transformSlider(
        title: String,
        value: Double,
        range: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            Text(sliderValueLabel(title: title, value: value))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func sliderValueLabel(title: String, value: Double) -> String {
        if title == "Scale" {
            return String(format: "%.2f", value)
        }

        if title == "Rotate" {
            return String(format: "%.0f\u{00B0}", value)
        }

        return String(format: "%.0f", value)
    }

    private func colorFromHex(_ hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return .white
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    private func hexFromColor(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int((rgb.redComponent * 255).rounded())
        let g = Int((rgb.greenComponent * 255).rounded())
        let b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func speedPresetLabel(_ rate: Double) -> String {
        if rate.rounded() == rate {
            return String(format: "%.0fx", rate)
        }
        return String(format: "%.2gx", rate)
    }
}
