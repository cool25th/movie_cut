import SwiftUI
import MovieCutCore

struct AutoSubtitlesView: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Provider", selection: Binding(
                get: { viewModel.transcriptionService.currentProvider.providerName },
                set: { providerName in
                    if let provider = viewModel.transcriptionService.availableProviders.first(where: { $0.providerName == providerName }) {
                        viewModel.transcriptionService.currentProvider = provider
                    }
                }
            )) {
                ForEach(viewModel.transcriptionService.availableProviders.map(\.providerName), id: \.self) { providerName in
                    Text(providerName).tag(providerName)
                }
            }
            .controlSize(.small)

            Button("Generate Subtitles") {
                Task { await viewModel.prepareSubtitles() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.canGenerateSubtitles || viewModel.transcriptionService.isTranscribing)

            if viewModel.transcriptionService.isTranscribing {
                ProgressView(value: viewModel.transcriptionService.progress)
            }

            if !viewModel.generatedSubtitleSegments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.generatedSubtitleSegments) { segment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(segment.text)
                                    .font(.caption)
                                    .lineLimit(2)
                                Text(timeRangeText(for: segment))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .separatorColor).opacity(0.12))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 140)

                Button("Apply to Timeline") {
                    Task { await viewModel.applyGeneratedSubtitles() }
                }
                .controlSize(.small)
                .disabled(viewModel.pendingSubtitleClips.isEmpty)
            }
        }
    }

    private func timeRangeText(for segment: TranscriptionSegment) -> String {
        "\(timeText(segment.startTime)) - \(timeText(segment.endTime))"
    }

    private func timeText(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
