import Foundation

/// Optional technical metadata discovered during media import.
public struct MediaMetadata: Codable, Sendable, Equatable {
    /// Pixel width for video or image assets.
    public var width: Int?

    /// Pixel height for video or image assets.
    public var height: Int?

    /// Video frame rate, when known.
    public var frameRate: Double?

    /// Codec name, when known.
    public var codec: String?

    /// Audio sample rate in hertz, when known.
    public var sampleRate: Int?

    /// Audio channel count, when known.
    public var channelCount: Int?

    /// File size in bytes, when known.
    public var fileSize: Int64?

    /// Creates metadata with optional probed values.
    public init(
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        codec: String? = nil,
        sampleRate: Int? = nil,
        channelCount: Int? = nil,
        fileSize: Int64? = nil
    ) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.fileSize = fileSize
    }
}
