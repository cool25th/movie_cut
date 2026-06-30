import Foundation

/// One-tap export targets for common social and creator platforms.
///
/// These presets are intentionally additive: projects still persist only
/// `CanvasPreset` and `ExportSettings`, while this enum resolves to those
/// existing Codable models when a user chooses a platform.
public enum PlatformExportPreset: String, Codable, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    /// TikTok vertical video delivery.
    case tikTok

    /// Instagram Reels vertical video delivery.
    case instagramReels

    /// YouTube Shorts vertical video delivery.
    case youtubeShorts

    /// YouTube standard landscape video delivery.
    case youtubeStandard

    /// Instagram square feed post delivery.
    case instagramPost

    public var id: String {
        rawValue
    }

    /// User-visible platform name.
    public var name: String {
        switch self {
        case .tikTok:
            return "TikTok"
        case .instagramReels:
            return "Instagram Reels"
        case .youtubeShorts:
            return "YouTube Shorts"
        case .youtubeStandard:
            return "YouTube"
        case .instagramPost:
            return "Instagram Post"
        }
    }

    /// Canvas aspect ratio required by the platform preset.
    public var aspectRatio: AspectRatio {
        switch self {
        case .tikTok, .instagramReels, .youtubeShorts:
            return .portrait9x16
        case .youtubeStandard:
            return .landscape16x9
        case .instagramPost:
            return .square1x1
        }
    }

    /// Export resolution preset used with the selected aspect ratio.
    public var resolution: ExportResolution {
        .p1080
    }

    /// Exact output pixel size resolved from the preset aspect ratio and resolution.
    public var pixelSize: CGSize {
        aspectRatio.size
    }

    /// Recommended video bitrate in megabits per second.
    public var recommendedBitrateMbps: Int {
        switch self {
        case .tikTok:
            return 15
        case .instagramReels, .instagramPost:
            return 12
        case .youtubeShorts, .youtubeStandard:
            return 20
        }
    }

    /// Platform upload duration hint in seconds.
    public var maxDurationSeconds: TimeInterval {
        switch self {
        case .tikTok:
            return 600
        case .instagramReels, .youtubeShorts:
            return 180
        case .youtubeStandard:
            return 43_200
        case .instagramPost:
            return 3_600
        }
    }

    /// User-visible duration guidance for the preset.
    public var maxDurationHint: String {
        switch self {
        case .tikTok:
            return "Up to 10 min"
        case .instagramReels, .youtubeShorts:
            return "Up to 3 min"
        case .youtubeStandard:
            return "Up to 12 hr"
        case .instagramPost:
            return "Up to 60 min"
        }
    }

    /// Canvas settings applied when the preset is selected.
    public var canvas: CanvasPreset {
        CanvasPreset(aspectRatio: aspectRatio, frameRate: .fps30)
    }

    /// Export settings applied when the preset is selected.
    public var exportSettings: ExportSettings {
        ExportSettings(
            resolution: resolution,
            frameRate: .fps30,
            codec: .h264,
            audioCodec: .aac,
            containerFormat: .mp4,
            quality: .custom,
            videoBitrateMbps: recommendedBitrateMbps
        )
    }

    /// Compact preset summary suitable for buttons and accessibility.
    public var detail: String {
        "\(Int(pixelSize.width)) x \(Int(pixelSize.height)) / 30 fps / MP4 / \(recommendedBitrateMbps) Mbps"
    }
}
