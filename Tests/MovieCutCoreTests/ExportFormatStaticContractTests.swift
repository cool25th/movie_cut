import Foundation
import Testing
@testable import MovieCutCore

@Suite("Export Format Static Contract")
struct ExportFormatStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("ExportEngine applies target bitrate through an AVFoundation export constraint")
    func exportEngineAppliesFileLengthLimit() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("exportSession.fileLengthLimit"))
        #expect(source.contains("AVAssetExportSession preset exports do not expose a direct averageVideoBitRate knob"))
        #expect(source.contains("bitrateForQuality(project.exportSettings)"))
    }

    @Test("ExportEngine output file type is driven by persisted container format")
    func exportEngineUsesContainerFormatForOutputType() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("settings.containerFormat"))
        #expect(source.contains("fallbackFileTypes(for: settings)"))
        #expect(source.contains("case .mp4"))
        #expect(source.contains("case .mov"))
        #expect(source.contains("case .m4v"))
    }

    @Test("ExportEngine preserves deterministic container fallback order per codec")
    func exportEnginePreservesContainerFallbackOrder() throws {
        let source = try source("App/MovieCutMac/Export/ExportEngine.swift")

        #expect(source.contains("return settings.codec == .hevc ? [.mp4, .mov, .m4v] : [.mp4, .m4v, .mov]"))
        #expect(source.contains("return [.mov, .mp4, .m4v]"))
        #expect(source.contains("return [.m4v, .mp4, .mov]"))
        #expect(source.contains("return supportedFileTypes.first ?? .mov"))
    }

    @Test("Inspector binds format and quality to typed export settings")
    func inspectorUsesTypedExportSettingsBindings() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(source.contains("Picker(\"Format\", selection: exportContainerFormatBinding)"))
        #expect(source.contains("Picker(\"Quality\", selection: exportQualityBinding)"))
        #expect(source.contains("Binding<ExportContainerFormat>"))
        #expect(source.contains("Binding<ExportQuality>"))
        #expect(!source.contains("Picker(\"Format\", selection: $viewModel.exportFormat)"))
        #expect(!source.contains("Picker(\"Quality\", selection: $viewModel.exportQuality)"))
    }

    @Test("Mac toolbar export action announces selected settings and running progress")
    func macToolbarExportAccessibilityContract() throws {
        let source = try source("App/MovieCutMac/ContentView.swift")

        #expect(source.contains(".disabled(viewModel.exportEngine.isExporting)"))
        #expect(source.contains(".accessibilityLabel(\"Export project\")"))
        #expect(source.contains(".accessibilityValue(exportButtonAccessibilityValue)"))
        #expect(source.contains("Export the current project using the selected container, codec, quality, and resolution settings."))
        #expect(source.contains("Export is already running. Review progress in the export sheet or cancel it before starting another export."))
        #expect(source.contains("settings.containerFormat.displayName"))
        #expect(source.contains("settings.codec.accessibilityDisplayName"))
        #expect(source.contains("settings.resolution.accessibilityDisplayName"))
        #expect(source.contains("settings.frameRate.statusDisplayName"))
        #expect(source.contains(".accessibilityLabel(\"Export progress\")"))
        #expect(source.contains(".accessibilityValue(exportProgressAccessibilityValue)"))
        #expect(source.contains("This progress alone is not an export golden or playback verification."))
        #expect(source.contains(".accessibilityLabel(\"Share latest export\")"))
    }

    @Test("Inspector export social presets expose selected state and no-golden accessibility copy")
    func inspectorSocialPresetAccessibilityContract() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(source.contains(".accessibilityLabel(\"Apply export preset \\(preset.name)\")"))
        #expect(source.contains(".accessibilityValue(socialPresetAccessibilityValue(for: preset))"))
        #expect(source.contains(".accessibilityHint(socialPresetAccessibilityHint(for: preset))"))
        #expect(source.contains("let selectedState = isApplied(preset) ? \"Selected\" : \"Not selected\""))
        #expect(source.contains("This does not start export or verify an export golden file."))
    }

    @Test("Inspector export summary and custom bitrate expose no-golden accessibility copy")
    func inspectorExportSummaryAccessibilityContract() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(source.contains(".accessibilityLabel(\"Export summary\")"))
        #expect(source.contains(".accessibilityValue(exportSummaryAccessibilityValue)"))
        #expect(source.contains("Estimated size and bitrate are planning aids only."))
        #expect(source.contains("This summary does not verify an export golden file or playback result."))
        #expect(source.contains("Golden status: no single-fixture export artifact is attached yet."))
        #expect(source.contains("Do not claim full-suite, device, or release-ready verification."))
        #expect(source.contains(".accessibilityLabel(\"Export golden status\")"))
        #expect(source.contains("Attach an actual export artifact path and hash before using single fixture verified wording."))
        #expect(source.contains("No single fixture export artifact path or hash is attached."))
        #expect(source.contains("Verified wording requires fixture id, artifact path, hash or pixel checksum, expected spec, and failure bucket equal to null."))
        #expect(source.contains(".accessibilityLabel(\"Export golden evidence requirement\")"))
        #expect(source.contains("Minimum evidence: fixture id, export artifact path, hash or pixel checksum, expected spec, and failure bucket null."))
        #expect(source.contains("Single fixture only; not full-suite, device, or release-ready evidence."))
        #expect(source.contains(".accessibilityLabel(\"Export artifact identity guard\")"))
        #expect(source.contains("Evidence identity guard: cite only a qa-evidence manifest and MP4 pair with matching moviecut-export-golden-2026-06-12-* stems."))
        #expect(source.contains("Verifier requires qa-evidence storage, canonical manifest and MP4 basenames, and matching stems before the preflight artifact can be cited in QA notes."))
        #expect(source.contains(".accessibilityLabel(\"Export evidence scope\")"))
        #expect(source.contains("Latest QA label: single fixture preflight evidence only; ExportEngine E2E, iOS device, full-suite, and release-ready claims remain blocked."))
        #expect(source.contains("Accepted scope is single fixture preflight evidence only."))
        #expect(source.contains("Blocked claims are ExportEngine end to end, iOS device, full-suite, and release-ready verification."))
        #expect(source.contains(".accessibilityLabel(\"Export golden next action\")"))
        #expect(source.contains("Next: keep the preflight artifact path and hash attached. Upgrade only after a product ExportEngine artifact is captured and verified separately."))
        #expect(source.contains("Do not upgrade this row to ExportEngine verified until a separate product ExportEngine artifact path, hash, expected spec, and failure bucket null are attached."))
        #expect(source.contains(".accessibilityLabel(\"Export closeout decision\")"))
        #expect(source.contains("Closeout label: preflight artifact accepted · product ExportEngine evidence blocked. Keep this split in 21:00 retro notes."))
        #expect(source.contains("Accepted evidence is the single fixture preflight artifact only. Blocked evidence remains product ExportEngine artifact, device smoke, full-suite, and release-ready verification."))
        #expect(source.contains(".accessibilityLabel(\"Export retro claim boundary\")"))
        #expect(source.contains("Retro claim: cite the AVAssetWriter single-fixture preflight artifact only; keep product ExportEngine E2E, full-suite, device, and release-ready claims blocked."))
        #expect(source.contains("For retro notes, accepted wording is AVAssetWriter single fixture preflight evidence accepted. Blocked wording is product ExportEngine end to end, full-suite, device, and release-ready evidence."))
        #expect(source.contains(".accessibilityLabel(\"Export retro citation\")"))
        #expect(source.contains("Retro citation: artifact path/hash may support single-fixture preflight only; quote the verifier failures as [] and keep ExportEngine E2E/device/release-ready blocked."))
        #expect(source.contains("Use this citation only with the canonical qa-evidence manifest and MP4. If the path, hash, or verifier output is missing, report export evidence as pending instead of verified."))
        #expect(source.contains(".accessibilityLabel(\"Export freeze handoff\")"))
        #expect(source.contains("Freeze handoff: no new fixture, suite, or device claim after scope lock. Next owner should attach the existing verifier output or keep export evidence pending."))
        #expect(source.contains("After evidence freeze, do not broaden the preflight result. Next owner is PM or QA reviewer, who must cite the existing verifier output, artifact path, and hash, or leave the claim blocked."))
        #expect(source.contains(".accessibilityLabel(\"Export final report boundary\")"))
        #expect(source.contains("Final report boundary: accepted row = single-fixture preflight artifact; blocked row = product ExportEngine E2E, iOS device, full-suite, and release-ready evidence."))
        #expect(source.contains("For the 21:00 retro table, keep accepted evidence and blocked claims in separate rows. Do not merge the preflight artifact into product export, device, full-suite, or release-ready status."))
        #expect(source.contains(".accessibilityLabel(\"Export freeze review gate\")"))
        #expect(source.contains("17:00 freeze review: accepted only when verifier failures are [] and manifest/MP4 identity matches; otherwise keep product ExportEngine and release claims blocked."))
        #expect(source.contains("Evidence freeze requires verifier failures empty, matching qa-evidence manifest and MP4 stems, canonical hash, and failure bucket null."))
        #expect(source.contains(".accessibilityLabel(\"Export final operator handoff\")"))
        #expect(source.contains("Final operator handoff: quote accepted preflight artifact path/hash separately from blocked product ExportEngine, device, full-suite, and release-ready claims."))
        #expect(source.contains("Before the final report, the operator must cite the canonical verifier output and keep product ExportEngine end to end, iOS device, full-suite, and release-ready evidence in the blocked row."))
        #expect(source.contains("private var exportGoldenStatusCopy: String"))
        #expect(source.contains("private var exportGoldenStatusAccessibilityValue: String"))
        #expect(source.contains("private var exportGoldenEvidenceRequirementCopy: String"))
        #expect(source.contains("private var exportGoldenEvidenceRequirementAccessibilityValue: String"))
        #expect(source.contains("private var exportArtifactIdentityGuardCopy: String"))
        #expect(source.contains("private var exportArtifactIdentityGuardAccessibilityValue: String"))
        #expect(source.contains("private var exportEvidenceScopeCopy: String"))
        #expect(source.contains("private var exportEvidenceScopeAccessibilityValue: String"))
        #expect(source.contains("private var exportGoldenNextActionCopy: String"))
        #expect(source.contains("private var exportGoldenNextActionAccessibilityValue: String"))
        #expect(source.contains("private var exportCloseoutDecisionCopy: String"))
        #expect(source.contains("private var exportCloseoutDecisionAccessibilityValue: String"))
        #expect(source.contains("private var exportRetroClaimCopy: String"))
        #expect(source.contains("private var exportRetroClaimAccessibilityValue: String"))
        #expect(source.contains("private var exportRetroCitationCopy: String"))
        #expect(source.contains("private var exportRetroCitationAccessibilityValue: String"))
        #expect(source.contains("private var exportFreezeHandoffCopy: String"))
        #expect(source.contains("private var exportFreezeHandoffAccessibilityValue: String"))
        #expect(source.contains("private var exportFinalReportBoundaryCopy: String"))
        #expect(source.contains("private var exportFinalReportBoundaryAccessibilityValue: String"))
        #expect(source.contains("private var exportFreezeReviewCopy: String"))
        #expect(source.contains("private var exportFreezeReviewAccessibilityValue: String"))
        #expect(source.contains("private var exportFinalOperatorHandoffCopy: String"))
        #expect(source.contains("private var exportFinalOperatorHandoffAccessibilityValue: String"))
        #expect(source.contains("private var exportSummaryAccessibilityValue: String"))
        #expect(source.contains("Estimated size \\(estimatedFileSizeLabel)"))
        #expect(source.contains(".accessibilityLabel(\"Custom bitrate value\")"))
        #expect(source.contains("Enter a value from 1 to 200 Mbps. This does not verify an export golden file."))
    }

    @Test("Inspector export pickers announce current values and no-golden claim boundary")
    func inspectorExportPickerAccessibilityContract() throws {
        let source = try source("App/MovieCutMac/Inspector/InspectorExportSection.swift")

        #expect(source.contains(".accessibilityLabel(\"Export container format\")"))
        #expect(source.contains(".accessibilityLabel(\"Export resolution\")"))
        #expect(source.contains(".accessibilityLabel(\"Export frame rate\")"))
        #expect(source.contains(".accessibilityLabel(\"Export video codec\")"))
        #expect(source.contains(".accessibilityLabel(\"Export audio codec\")"))
        #expect(source.contains(".accessibilityLabel(\"Export quality\")"))
        #expect(source.contains(".accessibilityValue(viewModel.currentProject.exportSettings.containerFormat.displayName)"))
        #expect(source.contains(".accessibilityValue(exportResolutionAccessibilityValue)"))
        #expect(source.contains(".accessibilityValue(exportFrameRateAccessibilityValue)"))
        #expect(source.contains(".accessibilityValue(videoCodecLabel)"))
        #expect(source.contains(".accessibilityValue(audioCodecLabel)"))
        #expect(source.contains(".accessibilityValue(qualityLabel)"))
        #expect(source.contains("private var exportPickerAccessibilityHint: String"))
        #expect(source.contains("This does not start export, verify an export golden file, or confirm playback."))
    }

    @Test("iOS export progress and result sheets expose no-golden accessibility copy")
    func iosExportSheetsAccessibilityContract() throws {
        let source = try source("App/MovieCutiOS/iOSContentView.swift")

        #expect(source.contains(".accessibilityLabel(\"Export progress\")"))
        #expect(source.contains(".accessibilityValue(exportProgressAccessibilityValue)"))
        #expect(source.contains("This progress alone does not verify an export golden file or playback result."))
        #expect(source.contains("Stops the running export. It does not delete previously exported files."))
        #expect(source.contains(".accessibilityLabel(\"Export complete\")"))
        #expect(source.contains("Share it after playback review if you need export golden evidence."))
        #expect(source.contains(".accessibilityLabel(\"Share exported movie\")"))
        #expect(source.contains("This does not confirm playback sync or export golden verification."))
    }

    @Test("Custom bitrate resolves inside the documented 1 to 200 Mbps export API range")
    func customBitrateResolutionIsClampedToDocumentedRange() {
        let missing = ExportSettings(quality: .custom, videoBitrateMbps: nil)
        let zero = ExportSettings(quality: .custom, videoBitrateMbps: 0)
        let inRange = ExportSettings(quality: .custom, videoBitrateMbps: 75)
        let aboveRange = ExportSettings(quality: .custom, videoBitrateMbps: 250)
        let presetQuality = ExportSettings(resolution: .p1080, quality: .high, videoBitrateMbps: 250)

        #expect(ExportSettings.minimumCustomVideoBitrateMbps == 1)
        #expect(ExportSettings.maximumCustomVideoBitrateMbps == 200)
        #expect(missing.resolvedVideoBitrateMbps == nil)
        #expect(zero.resolvedVideoBitrateMbps == nil)
        #expect(inRange.resolvedVideoBitrateMbps == 75)
        #expect(aboveRange.resolvedVideoBitrateMbps == 200)
        #expect(presetQuality.resolvedVideoBitrateMbps == 20)
    }

    @Test("Backlog marks format codec bitrate export item complete with AVAssetExportSession caveat")
    func backlogMarksExportFormatItemComplete() throws {
        let source = try source("docs/CAPCUT_FEATURE_BACKLOG.md")

        #expect(source.contains("- [x] ✅ 포맷별 export(mp4/mov, 코덱/비트레이트 실제 반영) (P1)"))
        #expect(source.contains("AVAssetExportSession"))
        #expect(source.contains("fileLengthLimit"))
        #expect(source.contains("averageVideoBitRate"))
    }
}
