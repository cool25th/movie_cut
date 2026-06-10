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
