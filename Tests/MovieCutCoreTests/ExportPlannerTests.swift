import AVFoundation
import AudioToolbox
import Foundation
import Testing
@testable import MovieCutCore

@Suite("Export Planner")
struct ExportPlannerTests {
    private let planner = ExportPlanner()

    /// Compares a `CGSize` by components. The package defines its own
    /// `CGSize.==`, which makes a direct `==` against a `CGSize` literal
    /// ambiguous with the CoreGraphics overload, so tests compare edges.
    private func expectSize(_ size: CGSize, width: CGFloat, height: CGFloat) {
        #expect(size.width == width)
        #expect(size.height == height)
    }

    // MARK: - Render size

    @Test("Landscape render size follows resolution short edge and 16:9 aspect")
    func landscapeRenderSize() {
        let canvas = CanvasPreset(aspectRatio: .landscape16x9)
        expectSize(planner.renderSize(for: .p1080, canvas: canvas), width: 1920, height: 1080)
        expectSize(planner.renderSize(for: .p720, canvas: canvas), width: 1280, height: 720)
        expectSize(planner.renderSize(for: .p4K, canvas: canvas), width: 3840, height: 2160)
    }

    @Test("Portrait and square render sizes keep the short edge on the smaller dimension")
    func portraitAndSquareRenderSize() {
        let portrait = CanvasPreset(aspectRatio: .portrait9x16)
        expectSize(planner.renderSize(for: .p1080, canvas: portrait), width: 1080, height: 1920)

        let square = CanvasPreset(aspectRatio: .square1x1)
        expectSize(planner.renderSize(for: .p1080, canvas: square), width: 1080, height: 1080)
    }

    @Test("Render dimensions are always even for encoder compatibility")
    func renderDimensionsAreEven() {
        let canvas = CanvasPreset(aspectRatio: .portrait4x5)
        let size = planner.renderSize(for: .p720, canvas: canvas)
        #expect(Int(size.width) % 2 == 0)
        #expect(Int(size.height) % 2 == 0)
        // 4:5 short edge 720 => 720 x 900.
        expectSize(size, width: 720, height: 900)
    }

    // MARK: - Bitrate

    @Test("Video bitrate resolves preset quality to bits per second")
    func videoBitratePreset() {
        let high1080 = ExportSettings(resolution: .p1080, quality: .high)
        #expect(planner.videoBitrateBitsPerSecond(for: high1080) == 20_000_000)

        let low720 = ExportSettings(resolution: .p720, quality: .low)
        #expect(planner.videoBitrateBitsPerSecond(for: low720) == 3_000_000)
    }

    @Test("Custom video bitrate is honored and clamped, nil when unset")
    func videoBitrateCustom() {
        let custom = ExportSettings(quality: .custom, videoBitrateMbps: 50)
        #expect(planner.videoBitrateBitsPerSecond(for: custom) == 50_000_000)

        let overCap = ExportSettings(quality: .custom, videoBitrateMbps: 500)
        #expect(planner.videoBitrateBitsPerSecond(for: overCap) == 200_000_000)

        let unset = ExportSettings(quality: .custom, videoBitrateMbps: nil)
        #expect(planner.videoBitrateBitsPerSecond(for: unset) == nil)
    }

    @Test("Audio bitrate is set for AAC and nil for lossless PCM")
    func audioBitrate() {
        #expect(planner.audioBitrateBitsPerSecond(for: .aac) == 192_000)
        #expect(planner.audioBitrateBitsPerSecond(for: .pcm) == nil)
    }

    // MARK: - Video plan

    @Test("Default video plan resolves an MP4/H.264/AAC movie")
    func defaultVideoPlan() throws {
        let settings = ExportSettings()
        let plan = planner.plan(settings: settings, canvas: CanvasPreset(aspectRatio: .landscape16x9))

        #expect(plan.mediaKind == .video)
        #expect(plan.fileExtension == "mp4")
        #expect(plan.contentTypeIdentifier == AVFileType.mp4.rawValue)

        let video = try #require(plan.video)
        #expect(video.profile == .h264)
        #expect(video.width == 1920)
        #expect(video.height == 1080)
        #expect(video.frameRate == 30)
        #expect(video.averageBitrateBitsPerSecond == 20_000_000)

        let audio = try #require(plan.audio)
        #expect(audio.formatID == kAudioFormatMPEG4AAC)
        #expect(audio.bitrateBitsPerSecond == 192_000)
    }

    @Test("HEVC settings select the HEVC profile and MOV container when requested")
    func hevcVideoPlan() {
        let settings = ExportSettings(codec: .hevc, containerFormat: .mov)
        let plan = planner.plan(settings: settings, canvas: CanvasPreset(aspectRatio: .landscape16x9))

        #expect(plan.fileExtension == "mov")
        #expect(plan.video?.profile == .hevc)
    }

    @Test("ProRes override forces a QuickTime container and drops average bitrate")
    func proResVideoPlan() {
        let settings = ExportSettings(containerFormat: .mp4)
        let options = ExportPlanOptions(videoProfileOverride: .proRes422)
        let plan = planner.plan(
            settings: settings,
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            options: options
        )

        #expect(plan.fileExtension == "mov")
        #expect(plan.contentTypeIdentifier == AVFileType.mov.rawValue)
        #expect(plan.video?.profile == .proRes422)
        #expect(plan.video?.averageBitrateBitsPerSecond == nil)
    }

    @Test("hevcHDR profile is a 10-bit HDR HEVC variant")
    func hdrProfileFlags() {
        #expect(VideoCompressionProfile.hevcHDR.isHDR)
        #expect(!VideoCompressionProfile.hevc.isHDR)
        #expect(VideoCompressionProfile.hevcHDR.avVideoCodecValue == AVVideoCodecType.hevc.rawValue)
        #expect(VideoCompressionProfile.hevcHDR.requiresQuickTimeContainer == false)
        #expect(VideoCompressionProfile.hevcHDR.supportsAverageBitrate)
    }

    @Test("HDR override is downgraded to SDR while the v1 HDR flag is off")
    func hdrOverrideIsDowngradedUnderV1Gate() throws {
        // v1 policy: the HDR flag is off and the render pipeline is 8-bit SDR
        // end to end, so an HDR override must NOT survive planning — otherwise
        // the export would tag 8-bit pixels as HDR (a mislabeled file). When the
        // flag is flipped back on, the HDR writer-settings branch is still
        // covered by HDRProfileGatingTests.hdrOutputSettingsCarryRec2020WhenComputed.
        #expect(FeatureFlag.hdrMaster == false,
                "This test asserts the v1 default; re-evaluate the HDR gate before flipping the flag.")

        let options = ExportPlanOptions(videoProfileOverride: .hevcHDR)
        let plan = planner.plan(
            settings: ExportSettings(resolution: .p1080, quality: .high),
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            options: options
        )
        // Downgraded to the SDR H.264 delivery profile (H.264 because the
        // settings' default codec is .h264). The key point: it is NOT HDR.
        #expect(plan.video?.profile == .h264)
        #expect(plan.video?.profile.isHDR == false)

        let settings = try #require(planner.assetWriterVideoOutputSettings(for: plan))
        #expect(settings[AVVideoCodecKey] as? String == AVVideoCodecType.h264.rawValue)
        // SDR outputs are tagged Rec.709 (the v1 render contract), NOT Rec.2020.
        let colorProperties = try #require(settings[AVVideoColorPropertiesKey] as? [String: Any])
        #expect(colorProperties[AVVideoColorPrimariesKey] as? String == AVVideoColorPrimaries_ITU_R_709_2)
        #expect(colorProperties[AVVideoTransferFunctionKey] as? String == AVVideoTransferFunction_ITU_R_709_2)
        #expect(colorProperties[AVVideoYCbCrMatrixKey] as? String == AVVideoYCbCrMatrix_ITU_R_709_2)
    }

    // MARK: - Audio-only / GIF / still plans

    @Test("Audio-only plan with AAC resolves an m4a file with no video")
    func audioOnlyAACPlan() {
        let settings = ExportSettings(audioCodec: .aac)
        let plan = planner.plan(
            settings: settings,
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            mediaKind: .audioOnly
        )

        #expect(plan.mediaKind == .audioOnly)
        #expect(plan.fileExtension == "m4a")
        #expect(plan.contentTypeIdentifier == AVFileType.m4a.rawValue)
        #expect(plan.video == nil)
        #expect(plan.audio?.formatID == kAudioFormatMPEG4AAC)
        #expect(plan.audio?.bitrateBitsPerSecond == 192_000)
    }

    @Test("Audio-only plan with PCM resolves a lossless WAV file")
    func audioOnlyPCMPlan() {
        let settings = ExportSettings(audioCodec: .pcm)
        let plan = planner.plan(
            settings: settings,
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            mediaKind: .audioOnly
        )

        #expect(plan.fileExtension == "wav")
        #expect(plan.contentTypeIdentifier == AVFileType.wav.rawValue)
        #expect(plan.audio?.formatID == kAudioFormatLinearPCM)
        #expect(plan.audio?.bitrateBitsPerSecond == nil)
    }

    @Test("Animated GIF plan scales the canvas aspect to the max edge with even dimensions")
    func gifPlan() throws {
        let plan = planner.plan(
            settings: ExportSettings(),
            canvas: CanvasPreset(aspectRatio: .portrait9x16),
            mediaKind: .animatedGIF,
            options: ExportPlanOptions(gifFrameRate: 15, gifMaxEdge: 480)
        )

        #expect(plan.mediaKind == .animatedGIF)
        #expect(plan.fileExtension == "gif")
        #expect(plan.contentTypeIdentifier == "com.compuserve.gif")
        #expect(plan.video == nil)
        #expect(plan.audio == nil)

        let gif = try #require(plan.gif)
        #expect(gif.frameRate == 15)
        #expect(gif.height == 480)
        // 9:16 aspect => width 270 (even), height 480.
        #expect(gif.width == 270)
        #expect(gif.width % 2 == 0)
        #expect(gif.loopForever)
        #expect(abs(gif.frameDelaySeconds - (1.0 / 15.0)) < 1e-9)
    }

    @Test("Still-frame plan resolves a PNG at the requested timeline time")
    func stillFramePlan() {
        let plan = planner.plan(
            settings: ExportSettings(),
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            mediaKind: .stillFrame,
            options: ExportPlanOptions(stillFrameTimeSeconds: 4.25)
        )

        #expect(plan.mediaKind == .stillFrame)
        #expect(plan.fileExtension == "png")
        #expect(plan.contentTypeIdentifier == "public.png")
        #expect(plan.stillFrameTimeSeconds == 4.25)
    }

    // MARK: - AVAssetWriter output settings

    @Test("Video writer settings carry explicit average bitrate for H.264")
    func videoWriterSettingsH264() throws {
        let plan = planner.plan(settings: ExportSettings(resolution: .p1080, quality: .high), canvas: CanvasPreset(aspectRatio: .landscape16x9))
        let settings = try #require(planner.assetWriterVideoOutputSettings(for: plan))

        #expect(settings[AVVideoCodecKey] as? String == AVVideoCodecType.h264.rawValue)
        #expect(settings[AVVideoWidthKey] as? Int == 1920)
        #expect(settings[AVVideoHeightKey] as? Int == 1080)

        let compression = try #require(settings[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect(compression[AVVideoAverageBitRateKey] as? Int == 20_000_000)
        #expect(compression[AVVideoMaxKeyFrameIntervalKey] as? Int == 60)
    }

    @Test("ProRes video writer settings omit the average bitrate constraint")
    func videoWriterSettingsProRes() throws {
        let plan = planner.plan(
            settings: ExportSettings(),
            canvas: CanvasPreset(aspectRatio: .landscape16x9),
            options: ExportPlanOptions(videoProfileOverride: .proRes4444)
        )
        let settings = try #require(planner.assetWriterVideoOutputSettings(for: plan))

        #expect(settings[AVVideoCodecKey] as? String == AVVideoCodecType.proRes4444.rawValue)
        #expect(settings[AVVideoCompressionPropertiesKey] == nil)
    }

    @Test("Audio writer settings encode AAC bitrate and PCM bit depth")
    func audioWriterSettings() throws {
        let aacPlan = planner.plan(settings: ExportSettings(audioCodec: .aac), canvas: CanvasPreset(aspectRatio: .landscape16x9), mediaKind: .audioOnly)
        let aacSettings = try #require(planner.assetWriterAudioOutputSettings(for: aacPlan))
        #expect(aacSettings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(aacSettings[AVEncoderBitRateKey] as? Int == 192_000)

        let pcmPlan = planner.plan(settings: ExportSettings(audioCodec: .pcm), canvas: CanvasPreset(aspectRatio: .landscape16x9), mediaKind: .audioOnly)
        let pcmSettings = try #require(planner.assetWriterAudioOutputSettings(for: pcmPlan))
        #expect(pcmSettings[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
        #expect(pcmSettings[AVLinearPCMBitDepthKey] as? Int == 16)
    }
}
