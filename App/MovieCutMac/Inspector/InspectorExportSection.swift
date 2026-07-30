import SwiftUI
import MovieCutCore

struct InspectorExportSection: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Section("Export Settings") {
            socialPresetButtons

            Divider()

            Text("Custom Export")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Format", selection: exportContainerFormatBinding) {
                ForEach(ExportContainerFormat.allCases, id: \.self) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .accessibilityLabel("Export container format")
            .accessibilityValue(viewModel.currentProject.exportSettings.containerFormat.displayName)
            .accessibilityHint(exportPickerAccessibilityHint)
            Picker("Resolution", selection: exportResolutionBinding) {
                Text("4K (3840x2160)").tag(ExportResolution.p4K)
                Text("1080p (1920x1080)").tag(ExportResolution.p1080)
                Text("720p (1280x720)").tag(ExportResolution.p720)
            }
            .accessibilityLabel("Export resolution")
            .accessibilityValue(exportResolutionAccessibilityValue)
            .accessibilityHint(exportPickerAccessibilityHint)
            Picker("Frame Rate", selection: exportFrameRateBinding) {
                Text("24 fps").tag(ExportFrameRate.fps24)
                Text("30 fps").tag(ExportFrameRate.fps30)
                Text("60 fps").tag(ExportFrameRate.fps60)
            }
            .accessibilityLabel("Export frame rate")
            .accessibilityValue(exportFrameRateAccessibilityValue)
            .accessibilityHint(exportPickerAccessibilityHint)
            Picker("Video Codec", selection: exportCodecBinding) {
                Text("H.264").tag(ExportCodec.h264)
                Text("HEVC").tag(ExportCodec.hevc)
            }
            .accessibilityLabel("Export video codec")
            .accessibilityValue(videoCodecLabel)
            .accessibilityHint(exportPickerAccessibilityHint)
            Picker("Audio Codec", selection: exportAudioCodecBinding) {
                Text("AAC").tag(MovieCutCore.AudioCodec.aac)
                Text("PCM").tag(MovieCutCore.AudioCodec.pcm)
            }
            .accessibilityLabel("Export audio codec")
            .accessibilityValue(audioCodecLabel)
            .accessibilityHint(exportPickerAccessibilityHint)
            Picker("Quality", selection: exportQualityBinding) {
                ForEach(ExportQuality.allCases, id: \.self) { quality in
                    Text(qualityPickerLabel(for: quality)).tag(quality)
                }
            }
            .accessibilityLabel("Export quality")
            .accessibilityValue(qualityLabel)
            .accessibilityHint(exportPickerAccessibilityHint)
            if viewModel.currentProject.exportSettings.quality == .custom {
                customBitrateEditor
            }

            Divider()

            exportEstimateView

            Divider()

            proxyPlaybackToggle
        }
        .padding(12)
    }

    /// Toggles whether the editing preview plays back a generated proxy in
    /// place of the original media for smoother playback on heavy clips.
    /// Export always uses the original regardless of this setting.
    private var proxyPlaybackToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Playback")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle("Use proxy media for playback", isOn: Binding(
                get: { viewModel.currentProject.playbackSettings.useProxyPlayback },
                set: { newValue in
                    Task { await viewModel.updatePlaybackSettings(useProxyPlayback: newValue) }
                }
            ))
            .toggleStyle(.checkbox)
            .accessibilityLabel("Use proxy media for playback")
            .accessibilityHint("When on, the preview plays back a lower-resolution proxy for smoother editing. The proxy must be generated per media asset; falls back to the original when absent.")

            Toggle("Auto-use proxy under thermal pressure", isOn: Binding(
                get: { viewModel.currentProject.playbackSettings.autoProxyOnThermalPressure },
                set: { newValue in
                    Task { await viewModel.updatePlaybackSettings(autoProxyOnThermalPressure: newValue) }
                }
            ))
            .toggleStyle(.checkbox)
            .accessibilityLabel("Auto-use proxy under thermal pressure")
            .accessibilityHint("When on, the preview drops to a generated proxy while the device is hot, then restores the original when it cools. Turn off to keep the original at all times.")

            proxyResolutionPicker
        }
    }

    /// Chooses the resolution newly generated proxies are transcoded to (B-I7).
    ///
    /// Enabled independently of the playback toggle: the resolution governs
    /// generation, which happens per asset in the media library, so it stays
    /// adjustable while playback is still on the originals.
    private var proxyResolutionPicker: some View {
        Picker("Proxy resolution", selection: Binding(
            get: { viewModel.currentProject.playbackSettings.proxyResolution },
            set: { newValue in
                Task { await viewModel.updatePlaybackSettings(proxyResolution: newValue) }
            }
        )) {
            ForEach(ProxyResolution.allCases, id: \.self) { resolution in
                Text(
                    resolution.isRecommended
                        ? String(
                            format: NSLocalizedString("%@ (recommended)", comment: ""),
                            resolution.shortLabel
                        )
                        : resolution.shortLabel
                )
                .tag(resolution)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
        .accessibilityLabel(NSLocalizedString("Proxy resolution", comment: ""))
        .accessibilityHint(NSLocalizedString("Sets the resolution used when generating new proxies. Existing proxies are kept; each resolution is stored separately, so switching back reuses what was already generated.", comment: ""))
    }

    private var socialPresetButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Platform Presets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: socialPresetColumns, alignment: .leading, spacing: 8) {
                ForEach(socialPresets) { preset in
                    Button {
                        Task {
                            await viewModel.applyPlatformExportPreset(preset)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: socialPresetSystemImage(for: preset))
                                    .font(.title3)
                                Spacer(minLength: 4)
                                if isApplied(preset) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }

                            Text(preset.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)

                            Text(preset.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Text(preset.maxDurationHint)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isApplied(preset) ? MovieCutTheme.accentCyan.opacity(0.18) : MovieCutTheme.controlSurface.opacity(0.28))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isApplied(preset) ? MovieCutTheme.accentCyan.opacity(0.7) : MovieCutTheme.border.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Apply export preset \(preset.name)")
                    .accessibilityValue(socialPresetAccessibilityValue(for: preset))
                    .accessibilityHint(socialPresetAccessibilityHint(for: preset))
                }
            }

            LabeledContent("Estimated Size", value: estimatedFileSizeLabel)
                .font(.caption)
        }
    }

    private var socialPresetColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 104), spacing: 8),
            GridItem(.flexible(minimum: 104), spacing: 8)
        ]
    }

    private var socialPresets: [PlatformExportPreset] {
        PlatformExportPreset.allCases
    }

    private func socialPresetSystemImage(for preset: PlatformExportPreset) -> String {
        switch preset {
        case .tikTok:
            return "music.note"
        case .instagramReels:
            return "camera.aperture"
        case .youtubeShorts:
            return "play.square.fill"
        case .youtubeStandard:
            return "play.rectangle.fill"
        case .instagramPost:
            return "square.grid.2x2"
        }
    }

    private func isApplied(_ preset: PlatformExportPreset) -> Bool {
        viewModel.currentProject.canvas == preset.canvas
            && viewModel.currentProject.exportSettings == preset.exportSettings
    }

    private func socialPresetAccessibilityValue(for preset: PlatformExportPreset) -> String {
        let selectedState = isApplied(preset) ? "Selected" : "Not selected"
        return "\(selectedState). \(preset.detail). \(preset.maxDurationHint). Estimated size \(estimatedFileSizeLabel)."
    }

    private func socialPresetAccessibilityHint(for preset: PlatformExportPreset) -> String {
        "Applies \(preset.detail) export and canvas settings. This does not start export."
    }

    private var exportEstimateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Export Summary")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(summaryLine)
                .font(.caption)
                .lineLimit(2)

            LabeledContent("Video", value: "\(videoCodecLabel) · \(qualityLabel)")
                .font(.caption)
            LabeledContent("Audio", value: audioCodecLabel)
                .font(.caption)
            LabeledContent("Format", value: viewModel.currentProject.exportSettings.containerFormat.displayName)
                .font(.caption)
            LabeledContent("Estimated Size", value: estimatedFileSizeLabel)
                .font(.caption)

            Text("Target bitrate may be adjusted by the selected format and system encoder.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export summary")
        .accessibilityValue(exportSummaryAccessibilityValue)
        .accessibilityHint("Summarizes export settings for the next export.")
    }

    private var exportPickerAccessibilityHint: String {
        "Changes export settings used for the next export. This does not start export."
    }

    private var summaryLine: String {
        let settings = viewModel.currentProject.exportSettings
        let size = estimatedRenderSize
        let presetName = activeSocialPresetName ?? "Custom"
        return "\(presetName) · \(Int(size.width)) x \(Int(size.height)) · \(settings.frameRate.framesPerSecond) fps"
    }

    private var activeSocialPresetName: String? {
        socialPresets.first(where: isApplied)?.name
    }

    private var qualityLabel: String {
        let settings = viewModel.currentProject.exportSettings
        let target = settings.resolvedVideoBitrateMbps.map { "\($0) Mbps target" } ?? "No target"
        return "\(settings.quality.displayName) · \(target)"
    }

    private var videoCodecLabel: String {
        switch viewModel.currentProject.exportSettings.codec {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC"
        }
    }

    private var exportResolutionAccessibilityValue: String {
        switch viewModel.currentProject.exportSettings.resolution {
        case .p4K:
            return "4K 3840 by 2160"
        case .p1080:
            return "1080p 1920 by 1080"
        case .p720:
            return "720p 1280 by 720"
        }
    }

    private var exportFrameRateAccessibilityValue: String {
        "\(viewModel.currentProject.exportSettings.frameRate.framesPerSecond) fps"
    }

    private var audioCodecLabel: String {
        switch viewModel.currentProject.exportSettings.audioCodec {
        case .aac:
            return "AAC"
        case .pcm:
            return "PCM"
        }
    }

    private var estimatedRenderSize: CGSize {
        renderSize(
            for: viewModel.currentProject.exportSettings.resolution,
            canvas: viewModel.currentProject.canvas
        )
    }

    private var estimatedFileSizeLabel: String {
        let duration = max(viewModel.currentProject.timeline.duration, 0)
        guard duration > 0 else {
            return "Timeline empty"
        }

        let audioMbps = viewModel.currentProject.exportSettings.audioCodec == .pcm ? 1.5 : 0.192
        let megabytes = duration * (estimatedVideoBitrateMbps + audioMbps) / 8
        return String(format: "~%.1f MB for %.1fs", megabytes, duration)
    }

    private var exportSummaryAccessibilityValue: String {
        "\(summaryLine). Video \(videoCodecLabel), \(qualityLabel). Audio \(audioCodecLabel). Format \(viewModel.currentProject.exportSettings.containerFormat.displayName). Estimated size \(estimatedFileSizeLabel)."
    }

    private var estimatedVideoBitrateMbps: Double {
        let settings = viewModel.currentProject.exportSettings
        return Double(settings.resolvedVideoBitrateMbps ?? 10)
    }

    private var customBitrateEditor: some View {
        HStack(spacing: 8) {
            Stepper("Custom Bitrate", value: customBitrateMbpsBinding, in: 1...200)
                .accessibilityValue("\(customBitrateMbpsBinding.wrappedValue) Mbps")
                .accessibilityHint("Adjusts the target video bitrate used for export size and quality.")
            TextField("Mbps", value: customBitrateMbpsBinding, format: .number)
                .movieCutInputField()
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Custom bitrate value")
                .accessibilityValue("\(customBitrateMbpsBinding.wrappedValue) Mbps")
                .accessibilityHint("Enter a value from 1 to 200 Mbps.")
            Text("Mbps")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func qualityPickerLabel(for quality: ExportQuality) -> String {
        if quality == .custom {
            return quality.displayName
        }

        let resolution = viewModel.currentProject.exportSettings.resolution
        let bitrate = quality.defaultVideoBitrateMbps(for: resolution) ?? 0
        return "\(quality.displayName) (\(bitrate) Mbps)"
    }

    private func renderSize(for resolution: ExportResolution, canvas: CanvasPreset) -> CGSize {
        let shortEdge: CGFloat
        switch resolution {
        case .p4K:
            shortEdge = 2160
        case .p1080:
            shortEdge = 1080
        case .p720:
            shortEdge = 720
        }

        let canvasSize = canvas.size
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return CGSize(width: evenDimension(shortEdge * 16 / 9), height: evenDimension(shortEdge))
        }

        let aspectRatio = canvasSize.width / canvasSize.height
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return CGSize(width: evenDimension(shortEdge * 16 / 9), height: evenDimension(shortEdge))
        }

        if aspectRatio >= 1 {
            return CGSize(width: evenDimension(shortEdge * aspectRatio), height: evenDimension(shortEdge))
        }

        return CGSize(width: evenDimension(shortEdge), height: evenDimension(shortEdge / aspectRatio))
    }

    private func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded - (rounded % 2))
    }

    private var exportContainerFormatBinding: Binding<ExportContainerFormat> {
        Binding(
            get: { viewModel.currentProject.exportSettings.containerFormat },
            set: { newValue in
                Task { await viewModel.updateExportSettings(containerFormat: newValue) }
            }
        )
    }

    private var exportResolutionBinding: Binding<ExportResolution> {
        Binding(
            get: { viewModel.currentProject.exportSettings.resolution },
            set: { newValue in
                Task { await viewModel.updateExportSettings(resolution: newValue) }
            }
        )
    }

    private var exportFrameRateBinding: Binding<ExportFrameRate> {
        Binding(
            get: { viewModel.currentProject.exportSettings.frameRate },
            set: { newValue in
                Task { await viewModel.updateExportSettings(frameRate: newValue) }
            }
        )
    }

    private var exportCodecBinding: Binding<ExportCodec> {
        Binding(
            get: { viewModel.currentProject.exportSettings.codec },
            set: { newValue in
                Task { await viewModel.updateExportSettings(codec: newValue) }
            }
        )
    }

    private var exportAudioCodecBinding: Binding<MovieCutCore.AudioCodec> {
        Binding(
            get: { viewModel.currentProject.exportSettings.audioCodec },
            set: { newValue in
                Task { await viewModel.updateExportSettings(audioCodec: newValue) }
            }
        )
    }

    private var exportQualityBinding: Binding<ExportQuality> {
        Binding(
            get: { viewModel.currentProject.exportSettings.quality },
            set: { newValue in
                let currentTarget = viewModel.currentProject.exportSettings.resolvedVideoBitrateMbps
                    ?? ExportQuality.medium.defaultVideoBitrateMbps(for: viewModel.currentProject.exportSettings.resolution)
                    ?? 10
                Task {
                    await viewModel.updateExportSettings(
                        quality: newValue,
                        videoBitrateMbps: newValue == .custom ? currentTarget : nil
                    )
                }
            }
        )
    }

    private var customBitrateMbpsBinding: Binding<Int> {
        Binding(
            get: {
                viewModel.currentProject.exportSettings.videoBitrateMbps
                    ?? ExportQuality.medium.defaultVideoBitrateMbps(for: viewModel.currentProject.exportSettings.resolution)
                    ?? 10
            },
            set: { newValue in
                Task {
                    await viewModel.updateExportSettings(
                        quality: .custom,
                        videoBitrateMbps: min(max(newValue, 1), 200)
                    )
                }
            }
        )
    }
}

private extension ExportFrameRate {
    var framesPerSecond: Int {
        switch self {
        case .fps24:
            return 24
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }
}
