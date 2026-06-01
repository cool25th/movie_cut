import Foundation

/// Placeholder thumbnail generation API until AVFoundation is introduced.
public struct ThumbnailGenerator: Sendable {
    /// Generates image data for a media asset at the requested timeline time.
    public static func generate(for asset: MediaAsset, at time: TimeInterval, size: CGSize) -> Data? {
        nil
    }
}
