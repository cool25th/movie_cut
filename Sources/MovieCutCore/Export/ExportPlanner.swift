import AVFoundation
import AudioToolbox
import CoreGraphics
import Foundation
import VideoToolbox

/// The kind of artifact an export produces.
///
/// `ExportSettings` only models the common video path. The planner adds the
/// audio-only, animated GIF, and still-frame paths that CapCut/OpenCut expose
/// without forcing new cases onto the persisted settings enums.
public enum ExportMediaKind: String, Codable, Sendable, Equatable, CaseIterable {
    /// A muxed video + audio movie file.
    case video

    /// An audio-only file with no video track.
    case audioOnly

    /// An animated GIF rendered from sampled frames.
    case animatedGIF

    /// A single still image extracted from the timeline.
    case stillFrame
}

/// A concrete video compression profile resolved for an export.
///
/// `ExportCodec` only carries the two delivery codecs persisted in a project.
/// ProRes is an export-time mastering choice, so it lives here instead of being
/// forced onto every exhaustive `ExportCodec` switch in the app.
public enum VideoCompressionProfile: String, Sendable, Equatable, CaseIterable {
    /// H.264 / AVC delivery codec.
    case h264

    /// HEVC / H.265 delivery codec.
    case hevc

    /// HEVC Main 10 HDR (Rec. 2020 + HLG), 10-bit.
    case hevcHDR

    /// Apple ProRes 422 mastering codec.
    case proRes422

    /// Apple ProRes 4444 mastering codec (alpha-capable).
    case proRes4444

    /// The `AVVideoCodecType` raw value for this profile.
    public var avVideoCodecValue: String {
        switch self {
        case .h264:
            return AVVideoCodecType.h264.rawValue
        case .hevc, .hevcHDR:
            return AVVideoCodecType.hevc.rawValue
        case .proRes422:
            return AVVideoCodecType.proRes422.rawValue
        case .proRes4444:
            return AVVideoCodecType.proRes4444.rawValue
        }
    }

    /// Whether the profile honors an explicit average bitrate target.
    ///
    /// ProRes is intra-frame with a fixed quality ladder and ignores an average
    /// bitrate, so the planner omits the constraint for those profiles.
    public var supportsAverageBitrate: Bool {
        switch self {
        case .h264, .hevc, .hevcHDR:
            return true
        case .proRes422, .proRes4444:
            return false
        }
    }

    /// ProRes is only valid inside a QuickTime (`.mov`) container.
    public var requiresQuickTimeContainer: Bool {
        switch self {
        case .h264, .hevc, .hevcHDR:
            return false
        case .proRes422, .proRes4444:
            return true
        }
    }

    /// Whether this profile produces a 10-bit Rec. 2020 / HLG HDR master.
    public var isHDR: Bool {
        self == .hevcHDR
    }

    /// Derives the default delivery profile from persisted export settings.
    public static func deliveryProfile(for codec: ExportCodec) -> VideoCompressionProfile {
        switch codec {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        }
    }
}

/// Resolved video encoding parameters for an export.
public struct ResolvedVideoEncoding: Sendable, Equatable {
    /// The resolved compression profile.
    public var profile: VideoCompressionProfile

    /// Output pixel width (always even).
    public var width: Int

    /// Output pixel height (always even).
    public var height: Int

    /// Output frame rate in frames per second.
    public var frameRate: Int

    /// Target average bitrate in bits per second, or `nil` when the profile
    /// does not honor an explicit bitrate (ProRes) or none could be resolved.
    public var averageBitrateBitsPerSecond: Int?

    /// Maximum keyframe interval in seconds used by the writer.
    public var maxKeyframeIntervalSeconds: Double

    /// Creates resolved video encoding parameters.
    public init(
        profile: VideoCompressionProfile,
        width: Int,
        height: Int,
        frameRate: Int,
        averageBitrateBitsPerSecond: Int?,
        maxKeyframeIntervalSeconds: Double = 2
    ) {
        self.profile = profile
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.averageBitrateBitsPerSecond = averageBitrateBitsPerSecond
        self.maxKeyframeIntervalSeconds = maxKeyframeIntervalSeconds
    }
}

/// Resolved audio encoding parameters for an export.
public struct ResolvedAudioEncoding: Sendable, Equatable {
    /// The `AudioFormatID` for the output (AAC or Linear PCM).
    public var formatID: AudioFormatID

    /// Target bitrate in bits per second, or `nil` for lossless PCM.
    public var bitrateBitsPerSecond: Int?

    /// Output sample rate in hertz.
    public var sampleRate: Int

    /// Output channel count.
    public var channelCount: Int

    /// Creates resolved audio encoding parameters.
    public init(
        formatID: AudioFormatID,
        bitrateBitsPerSecond: Int?,
        sampleRate: Int = 48_000,
        channelCount: Int = 2
    ) {
        self.formatID = formatID
        self.bitrateBitsPerSecond = bitrateBitsPerSecond
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

/// Resolved animated-GIF encoding parameters.
public struct ResolvedGIFEncoding: Sendable, Equatable {
    /// Output pixel width (always even).
    public var width: Int

    /// Output pixel height (always even).
    public var height: Int

    /// Sampling frame rate in frames per second.
    public var frameRate: Int

    /// Whether the GIF loops forever.
    public var loopForever: Bool

    /// Creates resolved GIF encoding parameters.
    public init(width: Int, height: Int, frameRate: Int, loopForever: Bool = true) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.loopForever = loopForever
    }

    /// Per-frame delay in seconds derived from the frame rate.
    public var frameDelaySeconds: Double {
        guard frameRate > 0 else { return 0.1 }
        return 1.0 / Double(frameRate)
    }
}

/// A fully resolved export plan: the single source of truth for what a concrete
/// export should produce, independent of the AVFoundation glue that executes it.
public struct ResolvedExportPlan: Sendable, Equatable {
    /// The artifact kind.
    public var mediaKind: ExportMediaKind

    /// Filename extension without a leading dot (for example `mp4`, `m4a`, `gif`).
    public var fileExtension: String

    /// The output Uniform Type Identifier (for example `public.mpeg-4`).
    public var contentTypeIdentifier: String

    /// Resolved video encoding, present for `.video` and used to drive writers.
    public var video: ResolvedVideoEncoding?

    /// Resolved audio encoding, present for `.video` and `.audioOnly`.
    public var audio: ResolvedAudioEncoding?

    /// Resolved GIF encoding, present for `.animatedGIF`.
    public var gif: ResolvedGIFEncoding?

    /// The timeline time, in seconds, sampled for `.stillFrame`.
    public var stillFrameTimeSeconds: Double?

    /// Creates a resolved export plan.
    public init(
        mediaKind: ExportMediaKind,
        fileExtension: String,
        contentTypeIdentifier: String,
        video: ResolvedVideoEncoding? = nil,
        audio: ResolvedAudioEncoding? = nil,
        gif: ResolvedGIFEncoding? = nil,
        stillFrameTimeSeconds: Double? = nil
    ) {
        self.mediaKind = mediaKind
        self.fileExtension = fileExtension
        self.contentTypeIdentifier = contentTypeIdentifier
        self.video = video
        self.audio = audio
        self.gif = gif
        self.stillFrameTimeSeconds = stillFrameTimeSeconds
    }
}

/// Optional inputs for the additional (non-video) export kinds.
public struct ExportPlanOptions: Sendable, Equatable {
    /// Overrides the delivery profile, used to request ProRes mastering.
    public var videoProfileOverride: VideoCompressionProfile?

    /// Frame rate used when sampling frames into an animated GIF.
    public var gifFrameRate: Int

    /// Longest GIF edge in pixels; the planner scales the canvas aspect to fit.
    public var gifMaxEdge: Int

    /// Whether the produced GIF loops forever.
    public var gifLoopForever: Bool

    /// The timeline time, in seconds, sampled for a still-frame export.
    public var stillFrameTimeSeconds: Double

    /// Creates export plan options with GIF/still defaults.
    public init(
        videoProfileOverride: VideoCompressionProfile? = nil,
        gifFrameRate: Int = 12,
        gifMaxEdge: Int = 480,
        gifLoopForever: Bool = true,
        stillFrameTimeSeconds: Double = 0
    ) {
        self.videoProfileOverride = videoProfileOverride
        self.gifFrameRate = gifFrameRate
        self.gifMaxEdge = gifMaxEdge
        self.gifLoopForever = gifLoopForever
        self.stillFrameTimeSeconds = stillFrameTimeSeconds
    }
}

/// Centralized, side-effect-free export decision engine.
///
/// `ExportPlanner` owns the math the app's `ExportEngine` previously scattered
/// across private helpers: render size, explicit average bitrate, codec/profile
/// selection, container/file type, and the `AVAssetWriter` `outputSettings`
/// dictionaries. Keeping it pure makes the export contract unit-testable without
/// touching real media.
public struct ExportPlanner: Sendable {
    /// Creates an export planner.
    public init() {}

    // MARK: - Render size

    /// The output pixel size for a resolution preset against a canvas aspect.
    ///
    /// The short edge follows the resolution preset (2160/1080/720) and the long
    /// edge follows the canvas aspect ratio, both rounded to even dimensions so
    /// H.264/HEVC encoders accept them.
    public func renderSize(for resolution: ExportResolution, canvas: CanvasPreset) -> CGSize {
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
            return CGSize(width: Self.evenDimension(shortEdge * 16 / 9), height: Self.evenDimension(shortEdge))
        }

        let aspectRatio = canvasSize.width / canvasSize.height
        guard aspectRatio.isFinite, aspectRatio > 0 else {
            return CGSize(width: Self.evenDimension(shortEdge * 16 / 9), height: Self.evenDimension(shortEdge))
        }

        if aspectRatio >= 1 {
            return CGSize(width: Self.evenDimension(shortEdge * aspectRatio), height: Self.evenDimension(shortEdge))
        }

        return CGSize(width: Self.evenDimension(shortEdge), height: Self.evenDimension(shortEdge / aspectRatio))
    }

    /// Rounds a dimension down to the nearest even integer, with a floor of 2.
    public static func evenDimension(_ value: CGFloat) -> CGFloat {
        let rounded = max(2, Int(value.rounded()))
        return CGFloat(rounded - (rounded % 2))
    }

    // MARK: - Bitrate

    /// The resolved average video bitrate in bits per second, or `nil` when the
    /// settings do not resolve a target (for example custom quality with no value).
    public func videoBitrateBitsPerSecond(for settings: ExportSettings) -> Int? {
        guard let megabits = settings.resolvedVideoBitrateMbps, megabits > 0 else {
            return nil
        }
        return megabits * 1_000_000
    }

    /// The estimated audio bitrate in bits per second, or `nil` for lossless PCM.
    public func audioBitrateBitsPerSecond(for codec: AudioCodec) -> Int? {
        switch codec {
        case .aac:
            return 192_000
        case .pcm:
            return nil
        }
    }

    // MARK: - Planning

    /// Resolves a concrete export plan for the requested media kind.
    public func plan(
        settings: ExportSettings,
        canvas: CanvasPreset,
        mediaKind: ExportMediaKind = .video,
        options: ExportPlanOptions = ExportPlanOptions()
    ) -> ResolvedExportPlan {
        switch mediaKind {
        case .video:
            return videoPlan(settings: settings, canvas: canvas, options: options)
        case .audioOnly:
            return audioOnlyPlan(settings: settings)
        case .animatedGIF:
            return gifPlan(canvas: canvas, options: options)
        case .stillFrame:
            return stillFramePlan(options: options)
        }
    }

    private func videoPlan(
        settings: ExportSettings,
        canvas: CanvasPreset,
        options: ExportPlanOptions
    ) -> ResolvedExportPlan {
        var profile = options.videoProfileOverride ?? VideoCompressionProfile.deliveryProfile(for: settings.codec)
        // HDR mastering is feature-gated for v1. The render pipeline is 8-bit
        // SDR end to end (`RenderColorConfiguration`), so an HDR profile would
        // tag 8-bit pixels as HDR — the output would lie about its depth. When
        // the flag is off, downgrade any HDR profile to the SDR delivery
        // profile for the same codec instead of producing a mislabeled file.
        // The flag governs what the PRODUCT offers: a persisted delivery
        // codec (the UI path, gated in EditorViewModel/ContentView) is
        // downgraded so v1 never ships a mislabeled HDR file. An EXPLICIT
        // profile override is the developer/mastering path — it passes
        // through so the 10-bit writer contract and e2e verification can be
        // exercised before the flag flips (capcut-surpass stage-3 port).
        if options.videoProfileOverride == nil, profile.isHDR, !FeatureFlag.hdrMaster {
            profile = VideoCompressionProfile.deliveryProfile(for: settings.codec)
        }
        let size = renderSize(for: settings.resolution, canvas: canvas)
        let bitrate = profile.supportsAverageBitrate ? videoBitrateBitsPerSecond(for: settings) : nil

        let video = ResolvedVideoEncoding(
            profile: profile,
            width: Int(size.width),
            height: Int(size.height),
            frameRate: settings.frameRate.framesPerSecond,
            averageBitrateBitsPerSecond: bitrate
        )

        let audio = ResolvedAudioEncoding(
            formatID: audioFormatID(for: settings.audioCodec),
            bitrateBitsPerSecond: audioBitrateBitsPerSecond(for: settings.audioCodec)
        )

        // ProRes must live in a QuickTime container regardless of the persisted
        // container preference.
        let container: ExportContainerFormat = profile.requiresQuickTimeContainer ? .mov : settings.containerFormat

        return ResolvedExportPlan(
            mediaKind: .video,
            fileExtension: container.fileExtension,
            contentTypeIdentifier: contentTypeIdentifier(for: container),
            video: video,
            audio: audio
        )
    }

    private func audioOnlyPlan(settings: ExportSettings) -> ResolvedExportPlan {
        let audio = ResolvedAudioEncoding(
            formatID: audioFormatID(for: settings.audioCodec),
            bitrateBitsPerSecond: audioBitrateBitsPerSecond(for: settings.audioCodec)
        )

        switch settings.audioCodec {
        case .aac:
            return ResolvedExportPlan(
                mediaKind: .audioOnly,
                fileExtension: "m4a",
                contentTypeIdentifier: AVFileType.m4a.rawValue,
                audio: audio
            )
        case .pcm:
            return ResolvedExportPlan(
                mediaKind: .audioOnly,
                fileExtension: "wav",
                contentTypeIdentifier: AVFileType.wav.rawValue,
                audio: audio
            )
        }
    }

    private func gifPlan(canvas: CanvasPreset, options: ExportPlanOptions) -> ResolvedExportPlan {
        let canvasSize = canvas.size
        let aspect = canvasSize.height > 0 ? canvasSize.width / canvasSize.height : 16.0 / 9.0
        let maxEdge = CGFloat(max(16, options.gifMaxEdge))

        let width: CGFloat
        let height: CGFloat
        if aspect >= 1 {
            width = maxEdge
            height = maxEdge / max(aspect, 0.0001)
        } else {
            height = maxEdge
            width = maxEdge * aspect
        }

        let gif = ResolvedGIFEncoding(
            width: Int(Self.evenDimension(width)),
            height: Int(Self.evenDimension(height)),
            frameRate: max(1, options.gifFrameRate),
            loopForever: options.gifLoopForever
        )

        return ResolvedExportPlan(
            mediaKind: .animatedGIF,
            fileExtension: "gif",
            contentTypeIdentifier: "com.compuserve.gif",
            gif: gif
        )
    }

    private func stillFramePlan(options: ExportPlanOptions) -> ResolvedExportPlan {
        ResolvedExportPlan(
            mediaKind: .stillFrame,
            fileExtension: "png",
            contentTypeIdentifier: "public.png",
            stillFrameTimeSeconds: max(0, options.stillFrameTimeSeconds)
        )
    }

    // MARK: - AVAssetWriter output settings

    /// The `AVAssetWriterInput` video `outputSettings` dictionary for a plan.
    ///
    /// This is the explicit-bitrate path the legacy preset export could not
    /// express: `AVVideoAverageBitRateKey` is set directly from the resolved
    /// target. Returns `nil` when the plan has no video component.
    public func assetWriterVideoOutputSettings(for plan: ResolvedExportPlan) -> [String: Any]? {
        guard let video = plan.video else { return nil }

        var compression: [String: Any] = [:]
        if video.profile.supportsAverageBitrate, let bitrate = video.averageBitrateBitsPerSecond, bitrate > 0 {
            compression[AVVideoAverageBitRateKey] = bitrate
            compression[AVVideoExpectedSourceFrameRateKey] = video.frameRate
            compression[AVVideoMaxKeyFrameIntervalKey] = max(1, Int(Double(video.frameRate) * video.maxKeyframeIntervalSeconds))
            if video.profile == .h264 {
                compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel
            }
        }

        var settings: [String: Any] = [
            AVVideoCodecKey: video.profile.avVideoCodecValue,
            AVVideoWidthKey: video.width,
            AVVideoHeightKey: video.height
        ]

        if video.profile.isHDR {
            // Rec. 2020 primaries + HLG transfer for a 10-bit HDR master, encoded
            // with the HEVC Main 10 profile. The 10-bit SURFACE is requested by
            // the reader side (ExportEngine picks 420YpCbCr10BiPlanarVideoRange
            // for HDR profiles); these writer settings must NOT carry
            // kCVPixelBufferPixelFormatTypeKey — AVAssetWriterInput REJECTS
            // outputSettings containing a pixel-format key alongside
            // AVVideoCodecKey (NSInvalidArgumentException, measured by the
            // stage-3 e2e probe), which kills the export task outright.
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_2100_HLG,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
            compression[AVVideoProfileLevelKey] = kVTProfileLevel_HEVC_Main10_AutoLevel as String
        } else {
            // SDR outputs are tagged explicitly Rec.709 so the file's color
            // primaries/transfer/matrix match the v1 render pipeline
            // (`RenderColorConfiguration` is end-to-end sRGB/Rec.709). Without
            // this, exported files were untagged and players had to guess,
            // which is a source of preview↔export and cross-player drift.
            settings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }

        if !compression.isEmpty {
            settings[AVVideoCompressionPropertiesKey] = compression
        }
        return settings
    }

    /// The `AVAssetWriterInput` audio `outputSettings` dictionary for a plan.
    ///
    /// Returns `nil` when the plan has no audio component.
    public func assetWriterAudioOutputSettings(for plan: ResolvedExportPlan) -> [String: Any]? {
        guard let audio = plan.audio else { return nil }

        var settings: [String: Any] = [
            AVFormatIDKey: audio.formatID,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: audio.channelCount
        ]

        if audio.formatID == kAudioFormatLinearPCM {
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
        } else if let bitrate = audio.bitrateBitsPerSecond, bitrate > 0 {
            settings[AVEncoderBitRateKey] = bitrate
        }

        return settings
    }

    // MARK: - Format helpers

    private func audioFormatID(for codec: AudioCodec) -> AudioFormatID {
        switch codec {
        case .aac:
            return kAudioFormatMPEG4AAC
        case .pcm:
            return kAudioFormatLinearPCM
        }
    }

    private func contentTypeIdentifier(for container: ExportContainerFormat) -> String {
        switch container {
        case .mp4:
            return AVFileType.mp4.rawValue
        case .mov:
            return AVFileType.mov.rawValue
        case .m4v:
            return AVFileType.m4v.rawValue
        }
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
