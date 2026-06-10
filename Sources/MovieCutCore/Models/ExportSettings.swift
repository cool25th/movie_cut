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

/// Output container format presets.
public enum ExportContainerFormat: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// MPEG-4 movie.
    case mp4

    /// QuickTime movie.
    case mov

    /// Apple MPEG-4 video.
    case m4v

    /// Stable filename extension for this container.
    public var fileExtension: String {
        rawValue
    }

    /// User-facing display name.
    public var displayName: String {
        rawValue.uppercased()
    }
}

/// Export quality presets.
public enum ExportQuality: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    /// Smaller file size target.
    case low

    /// Balanced file size target.
    case medium

    /// Higher visual quality target.
    case high

    /// User-provided bitrate target.
    case custom

    /// User-facing display name.
    public var displayName: String {
        switch self {
        case .low:
            return "Low"
        case .medium:
            return "Medium"
        case .high:
            return "High"
        case .custom:
            return "Custom"
        }
    }

    /// Default video bitrate target in megabits per second for the resolution.
    public func defaultVideoBitrateMbps(for resolution: ExportResolution) -> Int? {
        switch (self, resolution) {
        case (.low, .p720):
            return 3
        case (.low, .p1080):
            return 5
        case (.low, .p4K):
            return 15
        case (.medium, .p720):
            return 6
        case (.medium, .p1080):
            return 10
        case (.medium, .p4K):
            return 30
        case (.high, .p720):
            return 12
        case (.high, .p1080):
            return 20
        case (.high, .p4K):
            return 60
        case (.custom, _):
            return nil
        }
    }
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

    /// Output container format.
    public var containerFormat: ExportContainerFormat

    /// Output quality preset.
    public var quality: ExportQuality

    /// Optional target video bitrate in megabits per second when using custom quality.
    public var videoBitrateMbps: Int?

    private enum CodingKeys: String, CodingKey {
        case resolution
        case frameRate
        case codec
        case audioCodec
        case containerFormat
        case quality
        case videoBitrateMbps
    }

    /// Creates export settings with common H.264/AAC 1080p defaults.
    public init(
        resolution: ExportResolution = .p1080,
        frameRate: ExportFrameRate = .fps30,
        codec: ExportCodec = .h264,
        audioCodec: AudioCodec = .aac,
        containerFormat: ExportContainerFormat = .mp4,
        quality: ExportQuality = .high,
        videoBitrateMbps: Int? = nil
    ) {
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.audioCodec = audioCodec
        self.containerFormat = containerFormat
        self.quality = quality
        self.videoBitrateMbps = videoBitrateMbps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = try container.decodeIfPresent(ExportResolution.self, forKey: .resolution) ?? .p1080
        frameRate = try container.decodeIfPresent(ExportFrameRate.self, forKey: .frameRate) ?? .fps30
        codec = try container.decodeIfPresent(ExportCodec.self, forKey: .codec) ?? .h264
        audioCodec = try container.decodeIfPresent(AudioCodec.self, forKey: .audioCodec) ?? .aac
        containerFormat = try container.decodeIfPresent(ExportContainerFormat.self, forKey: .containerFormat) ?? .mp4
        quality = try container.decodeIfPresent(ExportQuality.self, forKey: .quality) ?? .high
        videoBitrateMbps = try container.decodeIfPresent(Int.self, forKey: .videoBitrateMbps)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(codec, forKey: .codec)
        try container.encode(audioCodec, forKey: .audioCodec)
        try container.encode(containerFormat, forKey: .containerFormat)
        try container.encode(quality, forKey: .quality)
        try container.encodeIfPresent(videoBitrateMbps, forKey: .videoBitrateMbps)
    }

    /// Resolved target video bitrate in megabits per second.
    public var resolvedVideoBitrateMbps: Int? {
        if quality == .custom {
            guard let videoBitrateMbps, videoBitrateMbps > 0 else {
                return nil
            }
            return videoBitrateMbps
        }

        return quality.defaultVideoBitrateMbps(for: resolution)
    }
}
