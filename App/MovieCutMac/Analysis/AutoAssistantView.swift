import SwiftUI
import MovieCutCore

struct AutoAssistantView: View {
    var viewModel: EditorViewModel

    @State private var isAnalyzing = false
    @State private var analysisResult: AnalysisResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Assistant")
                .font(.headline)

            if isAnalyzing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyzing...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let result = analysisResult {
                if result.suggestions.isEmpty {
                    Text("No suggestions found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.suggestions.enumerated()), id: \.offset) { index, suggestion in
                                suggestionRow(suggestion, index: index)
                            }
                        }
                    }

                    Button("Apply All") {
                        Task { await applyAll(result.suggestions) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            HStack {
                Button("Analyze") {
                    Task { await runAnalysis() }
                }
                .disabled(isAnalyzing || viewModel.selectedTranscribableAsset == nil)

                Spacer()

                if analysisResult != nil {
                    Button("Clear") {
                        analysisResult = nil
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func suggestionRow(_ suggestion: AnalysisSuggestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForSuggestion(suggestion))
                    .foregroundStyle(colorForSuggestion(suggestion))
                Text(titleForSuggestion(suggestion))
                    .font(.subheadline.bold())
                Spacer()
                Button("Apply") {
                    Task { await applySuggestion(suggestion) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(descriptionForSuggestion(suggestion))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func runAnalysis() async {
        guard let asset = viewModel.selectedTranscribableAsset else { return }
        isAnalyzing = true
        defer { isAnalyzing = false }

        let provider = StubAnalysisProvider()
        do {
            let snapshot = await viewModel.sessionSnapshot()
            let result = try await provider.analyze(asset: asset, in: snapshot)
            analysisResult = result
        } catch {
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }

    private func applySuggestion(_ suggestion: AnalysisSuggestion) async {
        do {
            let commands = try await viewModel.applyAnalysisSuggestion(suggestion)
            for command in commands {
                try await viewModel.dispatchCommand(command)
            }
        } catch {
            viewModel.lastErrorMessage = error.localizedDescription
        }
    }

    private func applyAll(_ suggestions: [AnalysisSuggestion]) async {
        for suggestion in suggestions {
            await applySuggestion(suggestion)
        }
    }

    private func iconForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval: "speaker.slash"
        case .sceneChanges: "film"
        case .autoCut: "scissors"
        }
    }

    private func colorForSuggestion(_ suggestion: AnalysisSuggestion) -> Color {
        switch suggestion {
        case .silenceRemoval: .orange
        case .sceneChanges: .blue
        case .autoCut: .purple
        }
    }

    private func titleForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval: "Silence Removal"
        case .sceneChanges: "Scene Changes"
        case .autoCut: "Auto Cut"
        }
    }

    private func descriptionForSuggestion(_ suggestion: AnalysisSuggestion) -> String {
        switch suggestion {
        case .silenceRemoval(let ranges):
            "\(ranges.count) silent segment(s) detected"
        case .sceneChanges(let times):
            "\(times.count) scene change(s) at \(times.prefix(3).map { String(format: "%.1fs", $0) }.joined(separator: ", "))\(times.count > 3 ? "..." : "")"
        case .autoCut(let ranges):
            "\(ranges.count) segment(s) suggested for removal"
        }
    }
}
