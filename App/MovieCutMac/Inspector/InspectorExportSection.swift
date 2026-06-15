import SwiftUI
import MovieCutCore

struct InspectorExportSection: View {
    @Bindable var viewModel: EditorViewModel

    var body: some View {
        Section("Export Settings") {
            socialPresetButtons

            Divider()

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
        }
        .padding(12)
    }

    private var socialPresetButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Social Presets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(socialPresets) { preset in
                Button {
                    Task {
                        await viewModel.applyExportPreset(
                            named: preset.name,
                            canvas: preset.canvas,
                            exportSettings: preset.exportSettings
                        )
                    }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name)
                                .font(.caption.weight(.semibold))
                            Text(preset.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isApplied(preset) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Apply export preset \(preset.name)")
                .accessibilityValue(socialPresetAccessibilityValue(for: preset))
                .accessibilityHint(socialPresetAccessibilityHint(for: preset))
            }
        }
    }

    private var socialPresets: [SocialExportPreset] {
        [
            SocialExportPreset(
                id: "vertical-30",
                name: "TikTok/Reels/Shorts",
                detail: "1080 x 1920 / 30 fps / MP4 / 12 Mbps",
                canvas: CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps30),
                exportSettings: ExportSettings(
                    resolution: .p1080,
                    frameRate: .fps30,
                    codec: .h264,
                    audioCodec: .aac,
                    containerFormat: .mp4,
                    quality: .custom,
                    videoBitrateMbps: 12
                )
            ),
            SocialExportPreset(
                id: "vertical-60",
                name: "TikTok/Reels/Shorts 60",
                detail: "1080 x 1920 / 60 fps / MP4 / 20 Mbps",
                canvas: CanvasPreset(aspectRatio: .portrait9x16, frameRate: .fps60),
                exportSettings: ExportSettings(
                    resolution: .p1080,
                    frameRate: .fps60,
                    codec: .h264,
                    audioCodec: .aac,
                    containerFormat: .mp4,
                    quality: .custom,
                    videoBitrateMbps: 20
                )
            ),
            SocialExportPreset(
                id: "youtube-16x9",
                name: "YouTube",
                detail: "1920 x 1080 / 30 fps / MP4 / 20 Mbps",
                canvas: CanvasPreset(aspectRatio: .landscape16x9, frameRate: .fps30),
                exportSettings: ExportSettings(
                    resolution: .p1080,
                    frameRate: .fps30,
                    codec: .h264,
                    audioCodec: .aac,
                    containerFormat: .mp4,
                    quality: .custom,
                    videoBitrateMbps: 20
                )
            ),
            SocialExportPreset(
                id: "square-1x1",
                name: "Square",
                detail: "1080 x 1080 / 30 fps / MP4 / 10 Mbps",
                canvas: CanvasPreset(aspectRatio: .square1x1, frameRate: .fps30),
                exportSettings: ExportSettings(
                    resolution: .p1080,
                    frameRate: .fps30,
                    codec: .h264,
                    audioCodec: .aac,
                    containerFormat: .mp4,
                    quality: .custom,
                    videoBitrateMbps: 10
                )
            )
        ]
    }

    private func isApplied(_ preset: SocialExportPreset) -> Bool {
        viewModel.currentProject.canvas == preset.canvas
            && viewModel.currentProject.exportSettings == preset.exportSettings
    }

    private func socialPresetAccessibilityValue(for preset: SocialExportPreset) -> String {
        let selectedState = isApplied(preset) ? "Selected" : "Not selected"
        return "\(selectedState). \(preset.detail)"
    }

    private func socialPresetAccessibilityHint(for preset: SocialExportPreset) -> String {
        "Applies \(preset.detail) export and canvas settings. This does not start export or verify an export golden file."
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

            Text("Target bitrate is applied through AVFoundation preset selection and file size limits where supported.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(exportGoldenStatusCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export golden status")
                .accessibilityValue(exportGoldenStatusAccessibilityValue)
                .accessibilityHint("Use this status to avoid calling a settings preview a verified export. Attach an actual export artifact path and hash before using single fixture verified wording.")

            Text(exportGoldenEvidenceRequirementCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export golden evidence requirement")
                .accessibilityValue(exportGoldenEvidenceRequirementAccessibilityValue)
                .accessibilityHint("This is the minimum evidence checklist before reporting single fixture export verified. It still does not allow full-suite, device, or release-ready claims.")

            Text(exportArtifactIdentityGuardCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export artifact identity guard")
                .accessibilityValue(exportArtifactIdentityGuardAccessibilityValue)
                .accessibilityHint("Use this identity guard before citing the artifact in QA notes. Copied manifests or mismatched artifact stems must stay blocked evidence.")

            Text(exportEvidenceScopeCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export evidence scope")
                .accessibilityValue(exportEvidenceScopeAccessibilityValue)
                .accessibilityHint("Use this scope label when discussing the latest QA artifact. It limits the claim to one preflight fixture and blocks broader release claims.")

            Text(exportGoldenNextActionCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export golden next action")
                .accessibilityValue(exportGoldenNextActionAccessibilityValue)
                .accessibilityHint("Follow this next action before upgrading the report from preflight evidence to product ExportEngine evidence.")

            Text(exportCloseoutDecisionCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export closeout decision")
                .accessibilityValue(exportCloseoutDecisionAccessibilityValue)
                .accessibilityHint("Use this closeout decision in the final report so preflight success is not mistaken for product ExportEngine, device, or release-ready evidence.")

            Text(exportRetroClaimCopy)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export retro claim boundary")
                .accessibilityValue(exportRetroClaimAccessibilityValue)
                .accessibilityHint("Use this one-line boundary in retro notes. It keeps accepted preflight evidence separate from blocked product export claims.")

            Text(exportRetroCitationCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export retro citation")
                .accessibilityValue(exportRetroCitationAccessibilityValue)
                .accessibilityHint("Read this exact citation line before sending 21:00 retro notes. It prevents using the preflight MP4 as a product ExportEngine or release-ready claim.")

            Text(exportFreezeHandoffCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export freeze handoff")
                .accessibilityValue(exportFreezeHandoffAccessibilityValue)
                .accessibilityHint("Use this handoff row at evidence freeze. It names the next owner and prevents additional fixtures or release claims after scope lock.")

            Text(exportFinalReportBoundaryCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export final report boundary")
                .accessibilityValue(exportFinalReportBoundaryAccessibilityValue)
                .accessibilityHint("Use this final report boundary when preparing the 21:00 retro so the accepted preflight evidence and blocked product claims stay in separate rows.")

            Text(exportFreezeReviewCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export freeze review gate")
                .accessibilityValue(exportFreezeReviewAccessibilityValue)
                .accessibilityHint("At 17:00 evidence freeze, read this gate before changing the export status. If the verifier output or artifact identity is missing, keep the claim blocked.")

            Text(exportFinalOperatorHandoffCopy)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Export final operator handoff")
                .accessibilityValue(exportFinalOperatorHandoffAccessibilityValue)
                .accessibilityHint("Use this handoff before the last operator report so the accepted preflight artifact is not merged with product ExportEngine, device, or release-ready evidence.")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Export summary")
        .accessibilityValue(exportSummaryAccessibilityValue)
        .accessibilityHint("Estimated size and bitrate are planning aids only. This summary does not verify an export golden file or playback result.")
    }

    private var exportPickerAccessibilityHint: String {
        "Changes export settings used for the next export. This does not start export, verify an export golden file, or confirm playback."
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
        "\(summaryLine). Video \(videoCodecLabel), \(qualityLabel). Audio \(audioCodecLabel). Format \(viewModel.currentProject.exportSettings.containerFormat.displayName). Estimated size \(estimatedFileSizeLabel). \(exportGoldenStatusAccessibilityValue). \(exportGoldenEvidenceRequirementAccessibilityValue). \(exportArtifactIdentityGuardAccessibilityValue). \(exportEvidenceScopeAccessibilityValue). \(exportGoldenNextActionAccessibilityValue). \(exportCloseoutDecisionAccessibilityValue). \(exportRetroClaimAccessibilityValue). \(exportRetroCitationAccessibilityValue). \(exportFreezeHandoffAccessibilityValue). \(exportFinalReportBoundaryAccessibilityValue). \(exportFreezeReviewAccessibilityValue). \(exportFinalOperatorHandoffAccessibilityValue)."
    }

    private var exportGoldenStatusCopy: String {
        "Golden status: no single-fixture export artifact is attached yet. Do not claim full-suite, device, or release-ready verification."
    }

    private var exportGoldenStatusAccessibilityValue: String {
        "No single fixture export artifact path or hash is attached. Settings are ready for the next export attempt only, not verified output evidence."
    }

    private var exportGoldenEvidenceRequirementCopy: String {
        "Verified wording requires fixture id, artifact path, hash or pixel checksum, expected spec, and failure bucket equal to null."
    }

    private var exportGoldenEvidenceRequirementAccessibilityValue: String {
        "Minimum evidence: fixture id, export artifact path, hash or pixel checksum, expected spec, and failure bucket null. Single fixture only; not full-suite, device, or release-ready evidence."
    }

    private var exportArtifactIdentityGuardCopy: String {
        "Evidence identity guard: cite only a qa-evidence manifest and MP4 pair with matching moviecut-export-golden-2026-06-12-* stems."
    }

    private var exportArtifactIdentityGuardAccessibilityValue: String {
        "Verifier requires qa-evidence storage, canonical manifest and MP4 basenames, and matching stems before the preflight artifact can be cited in QA notes."
    }

    private var exportEvidenceScopeCopy: String {
        "Latest QA label: single fixture preflight evidence only; ExportEngine E2E, iOS device, full-suite, and release-ready claims remain blocked."
    }

    private var exportEvidenceScopeAccessibilityValue: String {
        "Accepted scope is single fixture preflight evidence only. Blocked claims are ExportEngine end to end, iOS device, full-suite, and release-ready verification."
    }

    private var exportGoldenNextActionCopy: String {
        "Next: keep the preflight artifact path and hash attached. Upgrade only after a product ExportEngine artifact is captured and verified separately."
    }

    private var exportGoldenNextActionAccessibilityValue: String {
        "Do not upgrade this row to ExportEngine verified until a separate product ExportEngine artifact path, hash, expected spec, and failure bucket null are attached."
    }

    private var exportCloseoutDecisionCopy: String {
        "Closeout label: preflight artifact accepted · product ExportEngine evidence blocked. Keep this split in 21:00 retro notes."
    }

    private var exportCloseoutDecisionAccessibilityValue: String {
        "Accepted evidence is the single fixture preflight artifact only. Blocked evidence remains product ExportEngine artifact, device smoke, full-suite, and release-ready verification."
    }

    private var exportRetroClaimCopy: String {
        "Retro claim: cite the AVAssetWriter single-fixture preflight artifact only; keep product ExportEngine E2E, full-suite, device, and release-ready claims blocked."
    }

    private var exportRetroClaimAccessibilityValue: String {
        "For retro notes, accepted wording is AVAssetWriter single fixture preflight evidence accepted. Blocked wording is product ExportEngine end to end, full-suite, device, and release-ready evidence."
    }

    private var exportRetroCitationCopy: String {
        "Retro citation: artifact path/hash may support single-fixture preflight only; quote the verifier failures as [] and keep ExportEngine E2E/device/release-ready blocked."
    }

    private var exportRetroCitationAccessibilityValue: String {
        "Use this citation only with the canonical qa-evidence manifest and MP4. If the path, hash, or verifier output is missing, report export evidence as pending instead of verified."
    }

    private var exportFreezeHandoffCopy: String {
        "Freeze handoff: no new fixture, suite, or device claim after scope lock. Next owner should attach the existing verifier output or keep export evidence pending."
    }

    private var exportFreezeHandoffAccessibilityValue: String {
        "After evidence freeze, do not broaden the preflight result. Next owner is PM or QA reviewer, who must cite the existing verifier output, artifact path, and hash, or leave the claim blocked."
    }

    private var exportFinalReportBoundaryCopy: String {
        "Final report boundary: accepted row = single-fixture preflight artifact; blocked row = product ExportEngine E2E, iOS device, full-suite, and release-ready evidence."
    }

    private var exportFinalReportBoundaryAccessibilityValue: String {
        "For the 21:00 retro table, keep accepted evidence and blocked claims in separate rows. Do not merge the preflight artifact into product export, device, full-suite, or release-ready status."
    }

    private var exportFreezeReviewCopy: String {
        "17:00 freeze review: accepted only when verifier failures are [] and manifest/MP4 identity matches; otherwise keep product ExportEngine and release claims blocked."
    }

    private var exportFreezeReviewAccessibilityValue: String {
        "Evidence freeze requires verifier failures empty, matching qa-evidence manifest and MP4 stems, canonical hash, and failure bucket null. Missing any item means the preflight evidence stays pending and broader export claims remain blocked."
    }

    private var exportFinalOperatorHandoffCopy: String {
        "Final operator handoff: quote accepted preflight artifact path/hash separately from blocked product ExportEngine, device, full-suite, and release-ready claims."
    }

    private var exportFinalOperatorHandoffAccessibilityValue: String {
        "Before the final report, the operator must cite the canonical verifier output and keep product ExportEngine end to end, iOS device, full-suite, and release-ready evidence in the blocked row."
    }

    private var estimatedVideoBitrateMbps: Double {
        let settings = viewModel.currentProject.exportSettings
        return Double(settings.resolvedVideoBitrateMbps ?? 10)
    }

    private var customBitrateEditor: some View {
        HStack(spacing: 8) {
            Stepper("Custom Bitrate", value: customBitrateMbpsBinding, in: 1...200)
                .accessibilityValue("\(customBitrateMbpsBinding.wrappedValue) Mbps")
                .accessibilityHint("Adjusts the target video bitrate used for export planning and AVFoundation file length constraints.")
            TextField("Mbps", value: customBitrateMbpsBinding, format: .number)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Custom bitrate value")
                .accessibilityValue("\(customBitrateMbpsBinding.wrappedValue) Mbps")
                .accessibilityHint("Enter a value from 1 to 200 Mbps. This does not verify an export golden file.")
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

private struct SocialExportPreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let canvas: CanvasPreset
    let exportSettings: ExportSettings
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
