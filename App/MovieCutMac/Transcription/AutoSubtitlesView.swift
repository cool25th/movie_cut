import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

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

            HStack(spacing: 6) {
                Button("Generate Subtitles") {
                    Task { await viewModel.prepareSubtitles() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!viewModel.canGenerateSubtitles || viewModel.transcriptionService.isTranscribing)

                Spacer()

                Button("Import SRT...") {
                    importSRT()
                }
                .controlSize(.small)
                .accessibilityHint(NSLocalizedString("Imports SubRip subtitles as pending subtitle clips.", comment: ""))

                Button("Export SRT...") {
                    exportSRT()
                }
                .controlSize(.small)
                .accessibilityHint(NSLocalizedString("Exports the current subtitles as a SubRip file.", comment: ""))
            }

            if viewModel.transcriptionService.isTranscribing {
                ProgressView(value: viewModel.transcriptionService.progress)
            }

            if !viewModel.generatedSubtitleSegments.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(viewModel.generatedSubtitleSegments) { segment in
                            SubtitleSegmentRow(viewModel: viewModel, segment: segment)
                        }
                    }
                }
                .frame(maxHeight: 200)

                Button("Apply to Timeline") {
                    Task { await viewModel.applyGeneratedSubtitles() }
                }
                .controlSize(.small)
                .disabled(viewModel.pendingSubtitleClips.isEmpty)
            }
        }
    }

    private func importSRT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let srtType = UTType(filenameExtension: "srt") {
            panel.allowedContentTypes = [srtType, .plainText]
        }
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.importSubtitles(from: url) }
        }
    }

    private func exportSRT() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "subtitles.srt"
        if let srtType = UTType(filenameExtension: "srt") {
            panel.allowedContentTypes = [srtType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.exportSubtitles(to: url)
        }
    }
}

/// One editable subtitle cue. Edits are buffered locally and committed on
/// submit/focus loss so the segment list does not rebuild on each keystroke.
private struct SubtitleSegmentRow: View {
    var viewModel: EditorViewModel
    var segment: TranscriptionSegment

    @State private var text: String = ""
    @State private var startTime: Double = 0
    @State private var endTime: Double = 0
    @FocusState private var isTextFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                NSLocalizedString("Subtitle text", comment: ""),
                text: $text,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .font(.caption)
            .lineLimit(1...3)
            .focused($isTextFocused)
            .onSubmit { commit() }
            .onChange(of: isTextFocused) { _, focused in
                if !focused { commit() }
            }
            .accessibilityLabel(NSLocalizedString("Subtitle text", comment: ""))

            HStack(spacing: 4) {
                TextField("Start", value: $startTime, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2.monospaced())
                    .frame(width: 56)
                    .onSubmit { commit() }
                    .accessibilityLabel(NSLocalizedString("Subtitle start seconds", comment: ""))

                Text("-")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                TextField("End", value: $endTime, format: .number.precision(.fractionLength(2)))
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2.monospaced())
                    .frame(width: 56)
                    .onSubmit { commit() }
                    .accessibilityLabel(NSLocalizedString("Subtitle end seconds", comment: ""))

                Spacer()

                Button {
                    Task { await viewModel.splitGeneratedSubtitleSegment(segment.id) }
                } label: {
                    Image(systemName: "scissors")
                }
                .buttonStyle(.borderless)
                .help(NSLocalizedString("Split this subtitle in half", comment: ""))
                .accessibilityLabel(NSLocalizedString("Split subtitle", comment: ""))

                Button {
                    Task { await viewModel.mergeGeneratedSubtitleSegmentWithNext(segment.id) }
                } label: {
                    Image(systemName: "arrow.triangle.merge")
                }
                .buttonStyle(.borderless)
                .help(NSLocalizedString("Merge with the next subtitle", comment: ""))
                .accessibilityLabel(NSLocalizedString("Merge subtitle with next", comment: ""))

                Button {
                    Task { await viewModel.deleteGeneratedSubtitleSegment(segment.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(NSLocalizedString("Delete this subtitle", comment: ""))
                .accessibilityLabel(NSLocalizedString("Delete subtitle", comment: ""))
            }
        }
        .padding(6)
        .background(Color(nsColor: .separatorColor).opacity(0.12))
        .cornerRadius(6)
        .onAppear { syncFromSegment() }
        .onChange(of: segment) { _, _ in syncFromSegment() }
    }

    private func syncFromSegment() {
        text = segment.text
        startTime = segment.startTime
        endTime = segment.endTime
    }

    private func commit() {
        let changedText = text != segment.text ? text : nil
        let changedStart = abs(startTime - segment.startTime) > 0.0001 ? startTime : nil
        let changedEnd = abs(endTime - segment.endTime) > 0.0001 ? endTime : nil
        guard changedText != nil || changedStart != nil || changedEnd != nil else { return }

        Task {
            await viewModel.updateGeneratedSubtitleSegment(
                segment.id,
                text: changedText,
                startTime: changedStart,
                endTime: changedEnd
            )
        }
    }
}
