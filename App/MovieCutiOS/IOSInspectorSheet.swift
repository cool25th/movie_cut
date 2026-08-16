#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSInspectorSheet: View {
    @Bindable var viewModel: IOSEditorViewModel

    var body: some View {
        NavigationStack {
            Group {
                if let clip = viewModel.selectedClip {
                    Form {
                        Section("Clip") {
                            LabeledContent("Type", value: clip.kind.rawValue.capitalized)
                            LabeledContent("Start", value: timeString(clip.timelineRange.start))
                            LabeledContent("Duration", value: timeString(clip.timelineRange.duration))

                            if let fileName = assetName(for: clip) {
                                LabeledContent("Source", value: fileName)
                            }
                        }

                        Section("Adjust") {
                            sliderRow(
                                title: "Opacity",
                                value: Binding(
                                    get: { viewModel.selectedClip?.opacity ?? clip.opacity },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedOpacity(newValue) }
                                    }
                                ),
                                range: 0...1,
                                valueText: percentText(viewModel.selectedClip?.opacity ?? clip.opacity)
                            )

                            sliderRow(
                                title: "Volume",
                                value: Binding(
                                    get: { viewModel.selectedClip?.volume ?? clip.volume },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedVolume(newValue) }
                                    }
                                ),
                                range: 0...2,
                                valueText: "\(Int(((viewModel.selectedClip?.volume ?? clip.volume) * 100).rounded()))%"
                            )

                            sliderRow(
                                title: "Speed",
                                value: Binding(
                                    get: { viewModel.selectedClip?.playbackRate ?? clip.playbackRate },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedPlaybackRate(newValue) }
                                    }
                                ),
                                range: 0.25...4,
                                valueText: String(format: "%.2fx", viewModel.selectedClip?.playbackRate ?? clip.playbackRate)
                            )
                        }

                        if clip.kind == .video || clip.kind == .image {
                            cropSection(for: clip)
                        }

                        if clip.kind == .video {
                            Section("Color") {
                                sliderRow(
                                    title: "Brightness",
                                    value: Binding(
                                        get: { brightnessSliderValue(for: clip) },
                                        set: { newValue in
                                            updateColorCorrection(for: clip, brightnessSliderValue: newValue)
                                        }
                                    ),
                                    range: 0...2,
                                    valueText: numericText(brightnessSliderValue(for: clip))
                                )

                                sliderRow(
                                    title: "Contrast",
                                    value: Binding(
                                        get: { colorCorrection(for: clip).contrast },
                                        set: { newValue in
                                            updateColorCorrection(for: clip, contrast: newValue)
                                        }
                                    ),
                                    range: 0...2,
                                    valueText: numericText(colorCorrection(for: clip).contrast)
                                )

                                sliderRow(
                                    title: "Saturation",
                                    value: Binding(
                                        get: { colorCorrection(for: clip).saturation },
                                        set: { newValue in
                                            updateColorCorrection(for: clip, saturation: newValue)
                                        }
                                    ),
                                    range: 0...2,
                                    valueText: numericText(colorCorrection(for: clip).saturation)
                                )
                            }

                            Section("Transition") {
                                Picker(
                                    "Type",
                                    selection: Binding(
                                        get: { viewModel.selectedClip?.transition?.type ?? clip.transition?.type ?? .none },
                                        set: { newValue in
                                            Task { await viewModel.setTransition(newValue) }
                                        }
                                    )
                                ) {
                                    ForEach(TransitionType.allCases, id: \.self) { transitionType in
                                        Text(transitionTitle(for: transitionType))
                                            .tag(transitionType)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        Section {
                            Button("Split at Playhead", systemImage: "scissors") {
                                Task { await viewModel.splitClip() }
                            }

                            Button("Duplicate Clip", systemImage: "plus.square.on.square") {
                                Task { await viewModel.duplicateClip() }
                            }

                            Button("Delete Clip", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.deleteClip() }
                            }

                            Button("Ripple Delete", systemImage: "delete.left", role: .destructive) {
                                Task { await viewModel.rippleDeleteClip() }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Clip Selected",
                        systemImage: "slider.horizontal.3",
                        description: Text("Select a timeline clip to edit it here.")
                    )
                }
            }
            .navigationTitle("Inspector")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range)
                .frame(minHeight: 44)
        }
    }

    private func assetName(for clip: Clip) -> String? {
        guard let assetId = clip.assetId else { return nil }
        return viewModel.currentProject.mediaLibrary.assets[assetId]?.originalURL.lastPathComponent
    }

    // MARK: Crop (G-23)

    private struct CropPreset {
        var label: String
        var aspect: Double?
    }

    private let cropPresets: [CropPreset] = [
        CropPreset(label: "Original", aspect: nil),
        CropPreset(label: "1:1", aspect: 1),
        CropPreset(label: "4:3", aspect: 4.0 / 3.0),
        CropPreset(label: "3:4", aspect: 3.0 / 4.0),
        CropPreset(label: "16:9", aspect: 16.0 / 9.0),
        CropPreset(label: "9:16", aspect: 9.0 / 16.0)
    ]

    /// Same ratio presets as the Mac inspector; each selects the largest
    /// centered region of that pixel aspect inside the source through the
    /// shared CropPixelProcessor, so iOS and Mac crop identical regions and
    /// the export compositors render identical pixels.
    private func cropSection(for clip: Clip) -> some View {
        Section("Crop") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cropPresets, id: \.label) { preset in
                        Button {
                            let cropRect = preset.aspect.flatMap { aspect in
                                CropPixelProcessor.centeredCropRect(
                                    sourceAspect: viewModel.selectedClipSourceAspect ?? 16.0 / 9.0,
                                    targetAspect: aspect
                                )
                            }
                            Task { await viewModel.updateSelectedCropRect(cropRect) }
                        } label: {
                            Text(preset.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(
                                        isActiveCropPreset(preset, for: clip)
                                            ? Color.accentColor.opacity(0.22)
                                            : Color(.secondarySystemBackground)
                                    )
                                )
                                .overlay {
                                    Capsule().stroke(
                                        isActiveCropPreset(preset, for: clip)
                                            ? Color.accentColor
                                            : Color.clear,
                                        lineWidth: 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Crop \(preset.label)")
                        .accessibilityHint("Crops the clip to the \(preset.label) ratio.")
                    }
                }
            }

            if let cropRect = clip.cropRect {
                LabeledContent(
                    "Region",
                    value: String(
                        format: "%.0f%% × %.0f%% at (%.0f%%, %.0f%%)",
                        cropRect.width * 100,
                        cropRect.height * 100,
                        cropRect.x * 100,
                        cropRect.y * 100
                    )
                )
                .font(.caption)
            }
        }
    }

    /// Whether `preset` matches the clip's current crop (same centered rect
    /// the preset would produce), so the active ratio is visibly selected.
    private func isActiveCropPreset(_ preset: CropPreset, for clip: Clip) -> Bool {
        guard let cropRect = clip.cropRect else {
            return preset.aspect == nil
        }
        guard let aspect = preset.aspect else { return false }
        let expected = CropPixelProcessor.centeredCropRect(
            sourceAspect: viewModel.selectedClipSourceAspect ?? 16.0 / 9.0,
            targetAspect: aspect
        )
        guard let expected else { return false }
        return abs(cropRect.x - expected.x) < 1.0e-6
            && abs(cropRect.y - expected.y) < 1.0e-6
            && abs(cropRect.width - expected.width) < 1.0e-6
            && abs(cropRect.height - expected.height) < 1.0e-6
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func colorCorrection(for clip: Clip) -> ColorCorrection {
        viewModel.selectedClip?.colorCorrection ?? clip.colorCorrection ?? ColorCorrection()
    }

    private func brightnessSliderValue(for clip: Clip) -> Double {
        colorCorrection(for: clip).brightness + 1
    }

    private func updateColorCorrection(
        for clip: Clip,
        brightnessSliderValue: Double? = nil,
        contrast: Double? = nil,
        saturation: Double? = nil
    ) {
        let current = colorCorrection(for: clip)
        let correction = ColorCorrection(
            brightness: (brightnessSliderValue ?? (current.brightness + 1)) - 1,
            contrast: contrast ?? current.contrast,
            saturation: saturation ?? current.saturation,
            warmth: current.warmth,
            tint: current.tint
        )

        Task { await viewModel.updateSelectedColorCorrection(correction) }
    }

    private func numericText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func transitionTitle(for type: TransitionType) -> String {
        switch type {
        case .none:
            "None"
        case .crossDissolve:
            "Cross Dissolve"
        case .fadeThroughBlack:
            "Fade Through Black"
        case .wipeRight:
            "Wipe Right"
        case .wipeLeft:
            "Wipe Left"
        case .wipeUp:
            "Wipe Up"
        case .wipeDown:
            "Wipe Down"
        case .slideLeft:
            "Slide Left"
        case .slideRight:
            "Slide Right"
        case .zoomIn:
            "Zoom In"
        case .zoomOut:
            "Zoom Out"
        case .glitch:
            "Glitch"
        }
    }

    private func timeString(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
#endif
