import AVFoundation
import Foundation
import Testing
@testable import MovieCutCore

/// Behavioral tests for the HDR feature gate and SDR output tagging.
///
/// These are NOT static-contract tests — they exercise the real `ExportPlanner`
/// and inspect the resolved plan and the `AVAssetWriter` output settings. They
/// pin the render-reliability guarantees:
///   1. The HDR flag is ON only because the stage-3 e2e probe verified a real
///      10-bit Rec.2020/HLG master; delivery planning stays SDR-only.
///   2. SDR exports are explicitly tagged Rec.709, so players don't guess the
///      color space (previously outputs were untagged — a preview↔export and
///      cross-player drift source).
@Suite("HDR Profile Gating + SDR Color Tagging")
struct HDRProfileGatingTests {
    private let planner = ExportPlanner()

    private func makeVideoSettings() -> ExportSettings {
        ExportSettings(resolution: .p1080, codec: .hevc, quality: .high)
    }

    // MARK: - HDR gate

    @Test("HDR flag is ON after the stage-3 e2e verification; explicit overrides remain the mastering route")
    func hdrFlagFlippedAfterE2EVerification() {
        // Flipped in capcut-surpass stage-3 increment B (2026-09-02) after the
        // e2e probe verified a REAL 10-bit Rec.2020/HLG master end to end
        // (run_e2e_export.sh: Main 10 / yuv420p10le / bt2020 / arib-std-b67 /
        // bt2020nc, SDR regression 8-bit bt709 intact). The persisted delivery
        // path stays SDR (ExportCodec has no HDR member), so the UI HDR Master
        // entry — the only consumer of this flag — exposes the verified
        // mastering output. If this assertion fails because the flag went back
        // OFF, re-check what regressed; do not flip it back without evidence.
        #expect(FeatureFlag.hdrMaster == true,
                "The HDR gate was flipped ON after the stage-3 e2e verification; an OFF value needs a regression reason.")
    }

    // MARK: - SDR color tagging

    @Test("SDR HEVC export is tagged Rec.709 in writer output settings")
    func sdrHEVCExportIsTaggedRec709() {
        let settings = makeVideoSettings()
        let canvas = CanvasPreset(aspectRatio: .landscape16x9)
        let plan = planner.plan(settings: settings, canvas: canvas)
        guard let outputSettings = planner.assetWriterVideoOutputSettings(for: plan) else {
            Issue.record("output settings were nil"); return
        }

        // Previously the SDR branch set NO color properties, leaving the file
        // untagged. v1 pins Rec.709 explicitly so the file advertises the same
        // space the render pipeline produced.
        let colorProps = outputSettings[AVVideoColorPropertiesKey] as? [String: Any]
        #expect(colorProps != nil, "SDR export must set AVVideoColorPropertiesKey; an untagged file lets players guess the color space.")
        #expect(colorProps?[AVVideoColorPrimariesKey] as? String == AVVideoColorPrimaries_ITU_R_709_2,
                "SDR primaries must be Rec.709, got \(colorProps?[AVVideoColorPrimariesKey] ?? "nil")")
        #expect(colorProps?[AVVideoTransferFunctionKey] as? String == AVVideoTransferFunction_ITU_R_709_2,
                "SDR transfer must be Rec.709, got \(colorProps?[AVVideoTransferFunctionKey] ?? "nil")")
        #expect(colorProps?[AVVideoYCbCrMatrixKey] as? String == AVVideoYCbCrMatrix_ITU_R_709_2,
                "SDR matrix must be Rec.709, got \(colorProps?[AVVideoYCbCrMatrixKey] ?? "nil")")
    }

    @Test("SDR H.264 export is tagged Rec.709 in writer output settings")
    func sdrH264ExportIsTaggedRec709() {
        let settings = ExportSettings(resolution: .p1080, codec: .h264, quality: .high)
        let canvas = CanvasPreset(aspectRatio: .landscape16x9)
        let plan = planner.plan(settings: settings, canvas: canvas)
        guard let outputSettings = planner.assetWriterVideoOutputSettings(for: plan) else {
            Issue.record("output settings were nil"); return
        }

        let colorProps = outputSettings[AVVideoColorPropertiesKey] as? [String: Any]
        #expect(colorProps != nil, "H.264 SDR export must also be tagged Rec.709, not left untagged.")
        #expect(colorProps?[AVVideoColorPrimariesKey] as? String == AVVideoColorPrimaries_ITU_R_709_2)
    }

    @Test("HDR-flagged output settings (when allowed) carry Rec.2020/HLG")
    func hdrOutputSettingsCarryRec2020WhenComputed() {
        // Even though the v1 gate prevents an HDR profile from being RESOLVED
        // into a plan, the writer-settings builder itself still must tag HDR
        // correctly IF it ever receives an HDR profile (post-v1). This test
        // constructs an HDR ResolvedVideoEncoding directly to verify that
        // branch without depending on the flag.
        let hdrVideo = ResolvedVideoEncoding(
            profile: .hevcHDR,
            width: 1920,
            height: 1080,
            frameRate: 30,
            averageBitrateBitsPerSecond: nil
        )
        let hdrPlan = ResolvedExportPlan(
            mediaKind: .video,
            fileExtension: "mov",
            contentTypeIdentifier: AVFileType.mov.rawValue,
            video: hdrVideo,
            audio: nil,
            gif: nil,
            stillFrameTimeSeconds: nil
        )
        guard let outputSettings = planner.assetWriterVideoOutputSettings(for: hdrPlan) else {
            Issue.record("output settings were nil"); return
        }
        let colorProps = outputSettings[AVVideoColorPropertiesKey] as? [String: Any]
        #expect(colorProps?[AVVideoColorPrimariesKey] as? String == AVVideoColorPrimaries_ITU_R_2020)
        #expect(colorProps?[AVVideoTransferFunctionKey] as? String == AVVideoTransferFunction_ITU_R_2100_HLG)
        #expect(colorProps?[AVVideoYCbCrMatrixKey] as? String == AVVideoYCbCrMatrix_ITU_R_2020)
    }
}
