import AppKit
import SwiftUI
import MovieCutCore

struct InspectorPanel: View {
    @Bindable var viewModel: EditorViewModel
    @State private var projectToolsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
                Text(viewModel.selectedClip == nil ? "Inspector" : "Clip")
                    .font(.headline)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // UX-03: when a clip is selected, its editing controls come
                    // first so they are reachable without scrolling past the
                    // project-wide tools; those collapse into a disclosure.
                    if let clip = viewModel.selectedClip {
                        InspectorBasicSection(viewModel: viewModel, clip: clip)
                        InspectorEffectsSection(viewModel: viewModel, clip: clip)
                        InspectorAnalysisSection(viewModel: viewModel, clip: clip)

                        Divider()

                        DisclosureGroup(isExpanded: $projectToolsExpanded) {
                            projectToolsSections
                                .padding(.top, 8)
                        } label: {
                            Label("Project Tools", systemImage: "wrench.and.screwdriver")
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        EmptyInspectorSelectionView()
                        projectToolsSections
                    }
                }
                .padding(12)
            }

            Divider()

            InspectorExportSection(viewModel: viewModel)
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Project-wide tools that are not tied to the selected clip.
    @ViewBuilder
    private var projectToolsSections: some View {
        VStack(alignment: .leading, spacing: 16) {
            MarkerManagementSection(viewModel: viewModel)
            AssistantSection(viewModel: viewModel)
            HighlightsSection(viewModel: viewModel)
            AnalysisResultsSection(viewModel: viewModel)
        }
    }
}

private struct EmptyInspectorSelectionView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Select a clip to inspect")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

private struct MarkerManagementSection: View {
    var viewModel: EditorViewModel
    @State private var isExpanded = true

    private var sortedMarkers: [Marker] {
        viewModel.currentProject.markers.sorted { lhs, rhs in
            if lhs.time == rhs.time {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.time < rhs.time
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if sortedMarkers.isEmpty {
                Text("No markers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedMarkers) { marker in
                        MarkerManagementRow(viewModel: viewModel, marker: marker)
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            HStack(spacing: 6) {
                Label("Markers", systemImage: "flag.fill")
                Spacer()
                Text("\(sortedMarkers.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

private struct MarkerManagementRow: View {
    var viewModel: EditorViewModel
    let marker: Marker
    @State private var draftName: String

    init(viewModel: EditorViewModel, marker: Marker) {
        self.viewModel = viewModel
        self.marker = marker
        _draftName = State(initialValue: marker.name)
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.markerHex(marker.color) ?? .yellow)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: 4) {
                TextField("Marker name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.renameMarker(marker, to: draftName)
                    }
                    .onChange(of: marker.name) { _, newValue in
                        if draftName != newValue {
                            draftName = newValue
                        }
                    }

                Text(markerTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button {
                viewModel.goToMarker(marker)
            } label: {
                Image(systemName: "arrow.right.to.line")
            }
            .buttonStyle(.borderless)
            .help("Jump to Marker")

            Button {
                viewModel.renameMarker(marker, to: draftName)
            } label: {
                Image(systemName: "checkmark")
            }
            .buttonStyle(.borderless)
            .disabled(!canSaveName)
            .help("Rename Marker")

            Button(role: .destructive) {
                viewModel.deleteMarker(marker)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Marker")
        }
        .font(.caption)
    }

    private var markerTime: String {
        String(format: "%.2fs", marker.time)
    }

    private var canSaveName: Bool {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && trimmedName != marker.name
    }
}

/// Natural-language assistant: maps an instruction to existing edits (F-21).
private struct AssistantSection: View {
    var viewModel: EditorViewModel
    @State private var isExpanded = false
    @State private var instruction = ""

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField("e.g. apply cinematic filter to all clips", text: $instruction)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit { run() }
                        .accessibilityLabel("Assistant instruction")

                    Button("Run") { run() }
                        .controlSize(.small)
                        .disabled(instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let message = viewModel.assistantResultMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !viewModel.assistantSuggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(viewModel.assistantSuggestions, id: \.self) { suggestion in
                            Button {
                                instruction = suggestion
                                run()
                            } label: {
                                Text(suggestion)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Use suggestion: \(suggestion)")
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("AI Assistant", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func run() {
        let text = instruction
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task { await viewModel.runAssistantCommand(text) }
    }
}

/// Auto-highlight candidates with create-sequence actions (F-20).
private struct HighlightsSection: View {
    var viewModel: EditorViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Button("Find Highlights") {
                        Task { await viewModel.detectHighlights() }
                    }
                    .controlSize(.small)
                    .disabled(!viewModel.canDetectHighlights)
                    .accessibilityHint("Scores highlight candidates from speech, scene changes, and beats.")

                    if !viewModel.highlightCandidates.isEmpty {
                        Button("Clear") {
                            viewModel.clearHighlights()
                        }
                        .controlSize(.small)
                    }
                }

                if viewModel.highlightCandidates.isEmpty {
                    Text("No highlights yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.highlightCandidates) { candidate in
                        HighlightCandidateRow(viewModel: viewModel, candidate: candidate)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 6) {
                Label("Auto Highlights", systemImage: "wand.and.stars")
                Spacer()
                if !viewModel.highlightCandidates.isEmpty {
                    Text("\(viewModel.highlightCandidates.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

private struct HighlightCandidateRow: View {
    var viewModel: EditorViewModel
    var candidate: HighlightCandidate

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(timeRangeText)
                    .font(.caption.monospaced())
                Text(String(
                    format: "score %.0f%% · speech %.0f%%",
                    candidate.score * 100,
                    candidate.speechDensity * 100
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Create") {
                Task { await viewModel.createSequenceFromHighlight(candidate) }
            }
            .controlSize(.small)
            .accessibilityLabel("Create sequence from highlight")
        }
        .padding(6)
        .background(Color(nsColor: .separatorColor).opacity(0.12))
        .cornerRadius(6)
    }

    private var timeRangeText: String {
        "\(timeText(candidate.range.start)) - \(timeText(candidate.range.end))"
    }

    private func timeText(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct AnalysisResultsSection: View {
    var viewModel: EditorViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if viewModel.recentAnalysisResults.isEmpty {
                Text("No analysis results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentAnalysisResults) { item in
                        AnalysisResultHistoryRow(item: item)
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            HStack(spacing: 6) {
                Label("Analysis Results", systemImage: "chart.line.uptrend.xyaxis")
                Spacer()
                Text("\(viewModel.recentAnalysisResults.count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

private struct AnalysisResultHistoryRow: View {
    let item: EditorViewModel.AnalysisHistoryItem

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: iconName)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.action)
                        .font(.caption.weight(.semibold))
                    if let count = item.count {
                        Text("\(count)")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }

                Text(item.message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if let clipDescription = item.clipDescription {
                        Text(clipDescription)
                    }
                    Text(item.timestamp.formatted(date: .omitted, time: .shortened))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var iconName: String {
        switch item.action {
        case "Auto Cut":
            return "speaker.slash"
        case "Detect Scenes":
            return "film.stack"
        case "Auto Reframe":
            return "viewfinder"
        case "Noise Reduction":
            return "waveform.badge.minus"
        case "Extract Audio":
            return "waveform"
        default:
            return "checkmark.circle"
        }
    }
}

private extension Color {
    static func markerHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let clean = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else {
            return nil
        }

        return Color(
            nsColor: NSColor(
                red: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        )
    }
}
