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

                        Section {
                            Button("Split at Playhead", systemImage: "scissors") {
                                Task { await viewModel.splitClip() }
                            }

                            Button("Delete Clip", systemImage: "trash", role: .destructive) {
                                Task { await viewModel.deleteClip() }
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

    private func timeString(_ time: TimeInterval) -> String {
        let clampedTime = max(0, time.isFinite ? time : 0)
        let totalSeconds = Int(clampedTime.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
#endif
