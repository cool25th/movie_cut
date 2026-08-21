import AppKit
import SwiftUI
import MovieCutCore

/// The inspector's clip-scoped section tabs. Lives at file scope (not private
/// to InspectorPanel) because the selection is owned by `EditorViewModel` —
/// the UI test harness drives it via `MOVIECUT_UITEST_INSPECTOR_TAB` so the
/// dhash goldens can capture each tab as a visually distinct editor state.
enum InspectorSubtab: String, CaseIterable, Identifiable {
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
                        SelectedClipHeaderView(clip: clip)
                            .movieCutInspectorSelectedHeader()

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
                        .movieCutInspectorSelectedFlatRow()
                    } else {
                        ProjectOverviewInspectorView(viewModel: viewModel)
                        DisclosureGroup(isExpanded: $projectToolsExpanded) {
                            projectToolsSections(carded: false)
                                .padding(.top, MovieCutSpacing.small)
                        } label: {
                            MovieCutIconTitle(
                                title: "Project Tools",
                                systemImage: "wrench.and.screwdriver",
                                titleFont: .caption.weight(.semibold)
                            )
                        }
                        .movieCutInspectorOverviewGroup(
                            background: MovieCutTheme.controlSurface.opacity(0.24),
                            border: MovieCutTheme.border.opacity(0.08)
                        )
                    }
                }
                .padding(MovieCutSpacing.small)
            }
            .movieCutScrollBackground(viewModel.selectedClip == nil ? MovieCutTheme.panelBackground : MovieCutTheme.inspectorSelectedPanelBackground)
        }
        .frame(minWidth: 240)
        .movieCutPanelBackground()
        .onChange(of: viewModel.selectedClipId) { _, _ in
            viewModel.selectedInspectorSubtab = .basic
        }
    }

    /// R4-01: selected clip inspectors swap by ClipKind instead of showing
    /// the all-purpose clip inspector as the first/default surface.
    @ViewBuilder
    private func selectedClipInspectorSections(for clip: Clip) -> some View {
        switch clip.kind {
        case .audio:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.audio)
                .movieCutInspectorSelectedFlatRow()
        case .text:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.text)
                .movieCutInspectorSelectedFlatRow()
        case .video, .image:
            visualClipInspectorSections(for: clip)
        }
    }

    /// R4-02: visual clips use Inspector subtabs instead of rendering every
    /// visual/effects/mask/animation control at once.
    @ViewBuilder
    private func visualClipInspectorSections(for clip: Clip) -> some View {
        Picker("Inspector section", selection: $viewModel.selectedInspectorSubtab) {
            ForEach(InspectorSubtab.allCases) { subtab in
                Text(subtab.rawValue).tag(subtab)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .tint(MovieCutTheme.accentCyan)
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(MovieCutTheme.inspectorSelectedControlSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(MovieCutTheme.inspectorSelectedBorder.opacity(0.34), lineWidth: 0.5)
        )
        .accessibilityLabel("Inspector section")
        .accessibilityHint("Switches between clip inspector sections.")

        switch viewModel.selectedInspectorSubtab {
        case .basic:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.visual)
                .movieCutInspectorSelectedFlatRow()
        case .speed:
            InspectorBasicSection(viewModel: viewModel, clip: clip, mode: InspectorBasicMode.speed)
                .movieCutInspectorSelectedFlatRow()
        case .adjustment:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.adjustment)
                .movieCutInspectorSelectedFlatRow()
        case .mask:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.mask)
                .movieCutInspectorSelectedFlatRow()
        case .animation:
            InspectorEffectsSection(viewModel: viewModel, clip: clip, mode: InspectorEffectsMode.animation)
                .movieCutInspectorSelectedFlatRow()
        }

        InspectorAnalysisSection(viewModel: viewModel, clip: clip)
            .movieCutInspectorSelectedFlatRow()
    }

    /// Project-wide tools that are not tied to the selected clip.
    @ViewBuilder
    private func projectToolsSections(carded: Bool) -> some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            if carded {
                MasterLoudnessSection(viewModel: viewModel)
                    .movieCutCard()
                MarkerManagementSection(viewModel: viewModel)
                    .movieCutCard()
                AssistantSection(viewModel: viewModel)
                    .movieCutCard()
                HighlightsSection(viewModel: viewModel)
                    .movieCutCard()
                AnalysisResultsSection(viewModel: viewModel)
                    .movieCutCard()
            } else {
                MasterLoudnessSection(viewModel: viewModel)
                MarkerManagementSection(viewModel: viewModel)
                AssistantSection(viewModel: viewModel)
                HighlightsSection(viewModel: viewModel)
                AnalysisResultsSection(viewModel: viewModel)
            }
        }
    }
}

/// G-26 master processing inspector + G-25 loudness meter. The preset picker
/// edits the serialized project-level chain choice; measurements always describe
/// the currently selected/bypassed master chain and are invalidated on changes.
private struct MasterLoudnessSection: View {
    var viewModel: EditorViewModel
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
                VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                    Text("Master Processing")
                        .font(.caption.weight(.semibold))

                    Picker("Master processing", selection: masterProcessingBinding) {
                        Text("Off").tag(nil as MasterAudioProcessing?)
                        Text("SNS 좋은 소리").tag(MasterAudioProcessing.sns as MasterAudioProcessing?)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .accessibilityLabel("Master audio processing")
                    .accessibilityHint("Chooses bypass or the SNS 좋은 소리 master processing preset for this project.")

                    Text(masterProcessingDescription)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(MovieCutTheme.divider.opacity(0.7))

                if let measurement = viewModel.masterLoudness {
                    meterRow(
                        title: NSLocalizedString("Integrated Loudness", comment: ""),
                        value: measurement.integratedLufs.map { String(format: "%.1f LUFS", $0) }
                            ?? NSLocalizedString("Silence", comment: ""),
                        within: measurement.integratedLufs.map {
                            AudioGraphLoudness.snsGuidelineLufsRange.contains($0)
                        }
                    )
                    meterRow(
                        title: NSLocalizedString("True Peak", comment: ""),
                        value: String(format: "%.2f dBTP", measurement.truePeakDbTp),
                        within: measurement.truePeakDbTp <= AudioGraphLoudness.snsGuidelineTruePeakDbTp
                    )
                    Text("SNS guideline: −16…−14 LUFS-I, ≤ −1 dBTP (§7)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No measurement yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.masterLoudnessError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Button {
                    Task { await viewModel.measureMasterLoudness() }
                } label: {
                    HStack(spacing: MovieCutSpacing.xSmall) {
                        if viewModel.isMeasuringMasterLoudness {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isMeasuringMasterLoudness
                             ? NSLocalizedString("Measuring…", comment: "")
                             : NSLocalizedString("Measure", comment: ""))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isMeasuringMasterLoudness)
            }
            .padding(.top, MovieCutSpacing.small)
        } label: {
            HStack(spacing: MovieCutSpacing.small) {
                Label("Audio Master", systemImage: "waveform")
                Spacer()
                if let lufs = viewModel.masterLoudness?.integratedLufs {
                    Text(String(format: "%.1f LUFS", lufs))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var masterProcessingBinding: Binding<MasterAudioProcessing?> {
        Binding(
            get: { viewModel.currentProject.masterAudioProcessing },
            set: { processing in
                Task { await viewModel.setMasterAudioProcessing(processing) }
            }
        )
    }

    private var masterProcessingDescription: String {
        switch viewModel.currentProject.masterAudioProcessing {
        case .sns:
            return "Gentle compression · room reverb · −1 dBTP limiter."
        case nil:
            return "Bypass the project master chain; clip and track processing still applies."
        }
    }

    private func meterRow(title: String, value: String, within: Bool?) -> some View {
        HStack(spacing: MovieCutSpacing.small) {
            Text(title)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
            if let within {
                Image(systemName: within ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(within ? Color.green : Color.orange)
                    .font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ProjectOverviewInspectorView: View {
    var viewModel: EditorViewModel
    @State private var isExportSummaryExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            // P1 inspector polish contract: no-selection remains useful but
            // reads as compact project context, not a dashboard card stack.
            ProjectOverviewHeader(
                projectName: viewModel.projectDisplayName,
                status: viewModel.projectSaveStatusLabel,
                mediaCount: countText(viewModel.currentProject.mediaLibrary.assets.count, singular: "asset")
            )

            ProjectOverviewSummaryStrip(items: [
                ProjectOverviewSummaryItem(title: NSLocalizedString("Canvas", comment: ""), value: viewModel.canvasResolutionBadgeText),
                ProjectOverviewSummaryItem(title: NSLocalizedString("Timeline", comment: ""), value: durationText),
                ProjectOverviewSummaryItem(title: NSLocalizedString("Clips", comment: ""), value: countText(clipCount, singular: "clip"))
            ])

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

            DisclosureGroup(isExpanded: $isExportSummaryExpanded) {
                VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                    ProjectOverviewRow(title: "Output", value: viewModel.canvasResolutionBadgeText)
                    ProjectOverviewRow(title: "Format", value: viewModel.currentProject.exportSettings.containerFormat.displayName)
                    ProjectOverviewRow(title: "Video", value: videoSummaryText)
                    ProjectOverviewRow(title: "Audio", value: viewModel.currentProject.exportSettings.audioCodec.inspectorDisplayName)
                }
                .padding(.top, MovieCutSpacing.xSmall)
            } label: {
                HStack(spacing: MovieCutSpacing.small) {
                    MovieCutIconTitle(
                        title: "Export Summary",
                        systemImage: "square.and.arrow.up",
                        subtitle: "\(viewModel.canvasResolutionBadgeText) · \(viewModel.currentProject.exportSettings.containerFormat.displayName)",
                        titleFont: MovieCutTypography.cardTitle
                    )
                    .foregroundStyle(.secondary)

                    Spacer(minLength: MovieCutSpacing.small)

                    Text("Export")
                        .font(MovieCutTypography.micro)
                        .foregroundStyle(MovieCutTheme.mutedText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(MovieCutTheme.panelBackgroundRaised.opacity(0.72))
                        )
                }
            }
            .movieCutInspectorOverviewGroup(
                background: MovieCutTheme.controlSurface.opacity(0.26),
                border: MovieCutTheme.border.opacity(0.08)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Export summary")
            .accessibilityValue(exportAccessibilityValue)
            .accessibilityHint("Summarizes read-only settings for the next export. Use the top-right export control to export or choose formats.")

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

private struct SelectedClipHeaderView: View {
    let clip: Clip

    var body: some View {
        HStack(alignment: .center, spacing: MovieCutSpacing.small) {
            MovieCutIconTitle(
                title: selectedTitle,
                systemImage: systemImage,
                subtitle: selectedSubtitle,
                iconColor: MovieCutTheme.accentCyan,
                titleFont: .caption.weight(.semibold)
            )

            Spacer(minLength: MovieCutSpacing.small)

            Text(kindBadgeText)
                .font(MovieCutTypography.micro)
                .foregroundStyle(MovieCutTheme.accentCyan)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(MovieCutTheme.accentCyan.opacity(0.12))
                )
                .overlay(
                    Capsule()
                        .stroke(MovieCutTheme.accentCyan.opacity(0.24), lineWidth: 0.5)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected clip")
        .accessibilityValue("\(kindBadgeText), \(durationText)")
        .accessibilityHint("Shows the active inspector context for the selected timeline clip.")
    }

    private var selectedTitle: String {
        "\(kindBadgeText) Inspector"
    }

    private var selectedSubtitle: String {
        "Duration \(durationText)"
    }

    private var kindBadgeText: String {
        if clip.kind == .text, let textContent = clip.textContent, textContent.isSticker {
            return "Sticker"
        }

        return clip.kind.rawValue.capitalized
    }

    private var systemImage: String {
        switch clip.kind {
        case .video:
            return "film"
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        case .text:
            return "textformat"
        }
    }

    private var durationText: String {
        String(format: "%.2fs", clip.timelineRange.duration)
    }
}

private struct ProjectOverviewHeader: View {
    let projectName: String
    let status: String
    let mediaCount: String

    var body: some View {
        HStack(alignment: .center, spacing: MovieCutSpacing.small) {
            MovieCutIconTitle(
                title: projectName,
                systemImage: "slider.horizontal.below.rectangle",
                subtitle: mediaCount,
                iconColor: MovieCutTheme.mutedText,
                titleFont: .caption.weight(.semibold)
            )

            Spacer(minLength: MovieCutSpacing.small)

            Text(status)
                .font(MovieCutTypography.micro)
                .foregroundStyle(MovieCutTheme.mutedText)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(MovieCutTheme.controlSurface.opacity(0.72))
                )
        }
        .movieCutInspectorOverviewGroup(
            background: MovieCutTheme.panelBackgroundRaised.opacity(0.56),
            border: MovieCutTheme.border.opacity(0.08)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Project overview")
        .accessibilityValue("\(projectName), \(status), \(mediaCount)")
    }
}

private struct ProjectOverviewSummaryItem: Identifiable {
    var id: String { title }
    let title: String
    let value: String
}

private struct ProjectOverviewSummaryStrip: View {
    let items: [ProjectOverviewSummaryItem]

    var body: some View {
        HStack(spacing: MovieCutSpacing.xSmall) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(MovieCutTypography.micro)
                        .foregroundStyle(MovieCutTheme.mutedText)
                    Text(item.value)
                        .font(MovieCutTypography.metadata.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                        .fill(MovieCutTheme.controlSurface.opacity(0.42))
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.value)
            }
        }
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
        VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
            MovieCutIconTitle(title: title, systemImage: systemImage, titleFont: MovieCutTypography.cardTitle)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                content
            }
        }
        .movieCutInspectorOverviewGroup()
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
        .padding(.horizontal, 0)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .fill(Color.clear)
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
        .movieCutInspectorOverviewGroup(
            background: MovieCutTheme.controlSurface.opacity(0.34),
            border: MovieCutTheme.border.opacity(0.08)
        )
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
        guard let hex, let rgb = HexColorMath.rgb(fromHex: hex) else { return nil }
        return Color(
            nsColor: NSColor(
                red: CGFloat(rgb.red),
                green: CGFloat(rgb.green),
                blue: CGFloat(rgb.blue),
                alpha: 1
            )
        )
    }
}
