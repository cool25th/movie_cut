import Foundation

/// User-facing export presets for common output formats.
public struct ExportPreset: Codable, Sendable, Identifiable, Equatable {
    /// The preset identifier.
    public var id: UUID

    /// User-visible preset name.
    public var name: String

    /// Output pixel size.
    public var resolution: CGSize

    /// Output frames per second.
    public var frameRate: Int

    /// Output video codec identifier.
    public var codec: String

    /// Target video bitrate in bits per second. `nil` uses automatic bitrate selection.
    public var bitrate: Int?

    /// Creates an export preset.
    public init(
        id: UUID = UUID(),
        name: String,
        resolution: CGSize,
        frameRate: Int,
        codec: String,
        bitrate: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.resolution = resolution
        self.frameRate = frameRate
        self.codec = codec
        self.bitrate = bitrate
    }

    /// Standard export presets.
    public static var all: [ExportPreset] {
        allPresets
    }

    private static let allPresets: [ExportPreset] = [
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000720")!,
            name: "HD 720p",
            resolution: CGSize(width: 1280, height: 720),
            frameRate: 30,
            codec: "h264"
        ),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001080")!,
            name: "Full HD",
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 30,
            codec: "h264"
        ),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000006060")!,
            name: "Full HD 60fps",
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            codec: "h264"
        ),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000002000")!,
            name: "2K",
            resolution: CGSize(width: 2560, height: 1440),
            frameRate: 30,
            codec: "h265"
        ),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004000")!,
            name: "4K",
            resolution: CGSize(width: 3840, height: 2160),
            frameRate: 30,
            codec: "h265"
        ),
        ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000004024")!,
            name: "ProRes 4K",
            resolution: CGSize(width: 3840, height: 2160),
            frameRate: 24,
            codec: "proRes"
        )
    ]
}
