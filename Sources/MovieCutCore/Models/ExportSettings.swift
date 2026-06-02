import Foundation

/// Export resolution presets.
public enum ExportResolution: String, Codable, Sendable, Equatable, Hashable {
    /// 1280 by 720.
    case p720

    /// 1920 by 1080.
    case p1080

    /// 3840 by 2160.
    case p4K
}

/// Export frame-rate presets.
public enum ExportFrameRate: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// 24 frames per second.
    case fps24

    /// 30 frames per second.
    case fps30

    /// 60 frames per second.
    case fps60
}

/// Video codec export presets.
public enum ExportCodec: String, Codable, Sendable, Equatable, Hashable {
    /// H.264 video.
    case h264

    /// HEVC video.
    case hevc
}

/// Audio codec export presets.
public enum AudioCodec: String, Codable, Sendable, Equatable, Hashable {
    /// AAC audio.
    case aac

    /// Linear PCM audio.
    case pcm
}

/// User-selectable export settings.
public struct ExportSettings: Codable, Sendable, Equatable {
    /// Output resolution.
    public var resolution: ExportResolution

    /// Output frame rate.
    public var frameRate: ExportFrameRate

    /// Output video codec.
    public var codec: ExportCodec

    /// Output audio codec.
    public var audioCodec: AudioCodec

    /// Creates export settings with common H.264/AAC 1080p defaults.
    public init(
        resolution: ExportResolution = .p1080,
        frameRate: ExportFrameRate = .fps30,
        codec: ExportCodec = .h264,
        audioCodec: AudioCodec = .aac
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.audioCodec = audioCodec
    }
}
