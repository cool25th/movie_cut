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
