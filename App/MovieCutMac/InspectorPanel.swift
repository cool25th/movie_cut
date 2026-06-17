import AppKit
import SwiftUI
import MovieCutCore

private enum InspectorSubtab: String, CaseIterable, Identifiable {
    case basic = "Basic"
    case speed = "Speed"
    case animation = "Animation"
    case adjustment = "Adjustment"
    case mask = "Mask"

    var id: Self { self }
}

struct InspectorPanel: View {
    @Bindable var viewModel: EditorViewModel
    @State private var projectToolsExpanded = false
    @State private var selectedInspectorSubtab: InspectorSubtab = .basic

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MovieCutPanelHeader(
                title: viewModel.selectedClip == nil ? "Inspector" : "Clip",
                systemImage: "slider.horizontal.3"
            )

            Divider()
                .overlay(MovieCutTheme.divider)

            ScrollView {
                VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                    // UX-03: when a clip is selected, its editing controls come
                    // first so they are reachable without scrolling past the
                    // project-wide tools; those collapse into a disclosure.
                    if let clip = viewModel.selectedClip {
                        selectedClipInspectorSections(for: clip)

                        Divider()
                            .overlay(MovieCutTheme.divider)

                        DisclosureGroup(isExpanded: $projectToolsExpanded) {
                            projectToolsSections(carded: false)
                                .padding(.top, MovieCutSpacing.small)
                        } label: {
                            MovieCutIconTitle(
                                title: "Project Tools",
                                systemImage: "wrench.and.screwdriver",
                                titleFont: .subheadline.weight(.semibold)
                            )
                        }
                        .movieCutCard()
                    } else {
                        ProjectOverviewInspectorView(viewModel: viewModel)
                        projectToolsSections(carded: true)
                    }
                }
                .padding(MovieCutSpacing.small)
            }
            .movieCutScrollBackground(MovieCutTheme.panelBackground)
        }
        .frame(minWidth: 240)
        .movieCutPanelBackground()
        .onChange(of: viewModel.selectedClipId) { _, _ in
            selectedInspectorSubtab = .basic
        }
    }

    /// R4-01: selected clip inspectors swap by ClipKind instead of showing
    /// the all-purpose clip inspector as the first/default surface.
    @ViewBuilder
    private func selectedClipInspectorSections(for clip: Clip) -> some View {
        switch clip.kind {
        case .audio:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.audio)
                .movieCutCard()
        case .text:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.text)
                .movieCutCard()
        case .video, .image:
            visualClipInspectorSections(for: clip)
        }
    }

    /// R4-02: visual clips use Inspector subtabs instead of rendering every
    /// visual/effects/mask/animation control at once.
    @ViewBuilder
    private func visualClipInspectorSections(for clip: Clip) -> some View {
        Picker("Inspector section", selection: $selectedInspectorSubtab) {
            ForEach(InspectorSubtab.allCases) { subtab in
                Text(subtab.rawValue).tag(subtab)
            }
        }
        .pickerStyle(.segmented)
        .tint(MovieCutTheme.accentCyan)
        .accessibilityLabel("Inspector section")
        .accessibilityHint("Switches between clip inspector sections.")

        switch selectedInspectorSubtab {
        case .basic:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.visual)
                .movieCutCard()
        case .speed:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.speed)
                .movieCutCard()
        case .adjustment:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.adjustment)
                .movieCutCard()
        case .mask:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.mask)
                .movieCutCard()
        case .animation:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.animation)
                .movieCutCard()
        }

        InspectorAnalysisSection(viewModel: viewModel, clip: clip)
            .movieCutCard()
    }

    /// Project-wide tools that are not tied to the selected clip.
    @ViewBuilder
    private func projectToolsSections(carded: Bool) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            if carded {
                MarkerManagementSection(viewModel: viewModel)
                    .movieCutCard()
                AssistantSection(viewModel: viewModel)
                    .movieCutCard()
                HighlightsSection(viewModel: viewModel)
                    .movieCutCard()
                AnalysisResultsSection(viewModel: viewModel)
                    .movieCutCard()
            } else {
                MarkerManagementSection(viewModel: viewModel)
                AssistantSection(viewModel: viewModel)
                HighlightsSection(viewModel: viewModel)
                AnalysisResultsSection(viewModel: viewModel)
            }
        }
    }
}

private struct ProjectOverviewInspectorView: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            ProjectOverviewInfoCard(
                title: "Project",
                systemImage: "doc.text",
                accessibilityLabel: "Project information",
                accessibilityValue: projectAccessibilityValue,
                accessibilityHint: "Shows the current project name and save status."
            ) {
                ProjectOverviewRow(title: "Name", value: viewModel.projectDisplayName)
                ProjectOverviewRow(title: "Status", value: viewModel.projectSaveStatusLabel)
                ProjectOverviewRow(title: "Media", value: countText(viewModel.currentProject.mediaLibrary.assets.count, singular: "asset"))
            }

            ProjectOverviewInfoCard(
                title: "Canvas",
                systemImage: "rectangle.ratio",
                accessibilityLabel: "Canvas information",
                accessibilityValue: canvasAccessibilityValue,
                accessibilityHint: "Shows canvas aspect ratio, canvas size, and frame rate."
            ) {
                ProjectOverviewRow(title: "Aspect", value: viewModel.currentProject.canvas.aspectRatio.displayName)
                ProjectOverviewRow(title: "Canvas Size", value: canvasSizeText)
                ProjectOverviewRow(title: "Frame Rate", value: viewModel.currentProject.canvas.frameRate.inspectorDisplayName)
            }

            ProjectOverviewInfoCard(
                title: "Timeline",
                systemImage: "timeline.selection",
                accessibilityLabel: "Timeline information",
                accessibilityValue: timelineAccessibilityValue,
                accessibilityHint: "Shows track, clip, marker, and duration totals."
            ) {
                ProjectOverviewRow(title: "Tracks", value: countText(trackCount, singular: "track"))
                ProjectOverviewRow(title: "Clips", value: countText(clipCount, singular: "clip"))
                ProjectOverviewRow(title: "Markers", value: countText(markerCount, singular: "marker"))
                ProjectOverviewRow(title: "Duration", value: durationText)
            }

            ProjectOverviewInfoCard(
                title: "Export Summary",
                systemImage: "square.and.arrow.up",
                accessibilityLabel: "Export summary",
                accessibilityValue: exportAccessibilityValue,
                accessibilityHint: "Summarizes read-only settings for the next export. Use the top-right export control to export or choose formats."
            ) {
                ProjectOverviewRow(title: "Output", value: viewModel.canvasResolutionBadgeText)
                ProjectOverviewRow(title: "Format", value: viewModel.currentProject.exportSettings.containerFormat.displayName)
                ProjectOverviewRow(title: "Video", value: videoSummaryText)
                ProjectOverviewRow(title: "Audio", value: viewModel.currentProject.exportSettings.audioCodec.inspectorDisplayName)
            }

            ProjectOverviewSelectionHint()
        }
    }

    private var projectAccessibilityValue: String {
        "\(viewModel.projectDisplayName), \(viewModel.projectSaveStatusLabel), \(countText(viewModel.currentProject.mediaLibrary.assets.count, singular: "asset"))."
    }

    private var canvasAccessibilityValue: String {
        "\(viewModel.currentProject.canvas.aspectRatio.displayName), \(canvasSizeText), \(viewModel.currentProject.canvas.frameRate.inspectorDisplayName)."
    }

    private var timelineAccessibilityValue: String {
        "\(countText(trackCount, singular: "track")), \(countText(clipCount, singular: "clip")), \(countText(markerCount, singular: "marker")), \(durationText)."
    }

    private var exportAccessibilityValue: String {
        "\(viewModel.canvasResolutionBadgeText), \(viewModel.currentProject.exportSettings.containerFormat.displayName), \(videoSummaryText), \(viewModel.currentProject.exportSettings.audioCodec.inspectorDisplayName)."
    }

    private var canvasSizeText: String {
        let size = viewModel.currentProject.canvas.size
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private var trackCount: Int {
        viewModel.currentProject.timeline.tracks.count
    }

    private var clipCount: Int {
        viewModel.currentProject.timeline.tracks.flatMap(\.clips).count
    }

    private var markerCount: Int {
        viewModel.currentProject.markers.count + viewModel.currentProject.timeline.markers.count
    }

    private var durationText: String {
        let duration = max(0, viewModel.currentProject.timeline.duration)
        let totalSeconds = Int(duration.rounded(.down))
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private var videoSummaryText: String {
        let settings = viewModel.currentProject.exportSettings
        let bitrate = settings.resolvedVideoBitrateMbps.map { "\($0) Mbps" } ?? "Auto bitrate"
        return "\(settings.codec.inspectorDisplayName) · \(settings.quality.displayName) · \(bitrate)"
    }

    private func countText(_ count: Int, singular: String) -> String {
        "\(count) \(singular)\(count == 1 ? "" : "s")"
    }
}

private struct ProjectOverviewInfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let content: Content

    init(
        title: String,
        systemImage: String,
        accessibilityLabel: String,
        accessibilityValue: String,
        accessibilityHint: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.accessibilityHint = accessibilityHint
        self.content = content()
    }

    var body: some View {
        MovieCutSectionCard(title: title, systemImage: systemImage) {
            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                content
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(accessibilityHint)
    }
}

private struct ProjectOverviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: MovieCutSpacing.small) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MovieCutTheme.mutedText)
                .lineLimit(1)

            Spacer(minLength: MovieCutSpacing.small)

            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, MovieCutSpacing.small)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.controlSurface)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

private struct ProjectOverviewSelectionHint: View {
    var body: some View {
        HStack(alignment: .top, spacing: MovieCutSpacing.small) {
            Image(systemName: "cursorarrow.click.2")
                .font(.caption.weight(.semibold))
                .foregroundStyle(MovieCutTheme.accentCyan)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text("Select a clip")
                    .font(.caption.weight(.semibold))
                Text("Clip controls appear here when a timeline clip is selected.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .movieCutCard(background: MovieCutTheme.controlSurface)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Select a clip")
        .accessibilityHint("Select a timeline clip to show clip-specific inspector controls.")
    }
}

private extension ExportCodec {
    var inspectorDisplayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }
}

private extension MovieCutCore.AudioCodec {
    var inspectorDisplayName: String {
        switch self {
        case .aac:
            return "AAC"
        case .pcm:
            return "PCM"
        }
    }
}

private extension ExportFrameRate {
    var inspectorDisplayName: String {
        switch self {
        case .fps24:
            return "24 fps"
        case .fps30:
            return "30 fps"
        case .fps60:
            return "60 fps"
        }
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
                VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                    ForEach(sortedMarkers) { marker in
                        MarkerManagementRow(viewModel: viewModel, marker: marker)
                    }
                }
                .padding(.top, MovieCutSpacing.small)
            }
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
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
        HStack(spacing: MovieCutSpacing.small) {
            Circle()
                .fill(Color.markerHex(marker.color) ?? .yellow)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.5))

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                TextField("Marker name", text: $draftName)
                    .movieCutInputField()
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
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                HStack(spacing: MovieCutSpacing.small) {
                    TextField("e.g. apply cinematic filter to all clips", text: $instruction)
                        .movieCutInputField()
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
                    VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
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
            .padding(.top, MovieCutSpacing.small)
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
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                HStack(spacing: MovieCutSpacing.small) {
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
            .padding(.top, MovieCutSpacing.small)
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
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
        HStack(spacing: MovieCutSpacing.small) {
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
        .movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.elevatedCardBackground
        )
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
                VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                    ForEach(viewModel.recentAnalysisResults) { item in
                        AnalysisResultHistoryRow(item: item)
                    }
                }
                .padding(.top, MovieCutSpacing.small)
            }
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
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
        HStack(alignment: .top, spacing: MovieCutSpacing.small) {
            Image(systemName: iconName)
                .frame(width: 16)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: MovieCutSpacing.small) {
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

                HStack(spacing: MovieCutSpacing.small) {
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
