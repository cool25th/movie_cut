import Foundation

/// Lightweight media import utilities that avoid platform media frameworks.
public struct MediaImporter: Sendable {
    private static let videoExtensions: Set<String> = [
        "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
    ]
    private static let audioExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "ogg", "wav"
    ]
    private static let imageExtensions: Set<String> = [
        "bmp", "gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]

    /// Creates a media asset from a file URL using extension-based detection.
    public static func probe(url: URL) -> MediaAsset {
        let fileExtension = url.pathExtension.lowercased()
        let kind = mediaKind(for: fileExtension)
        let fileSize = fileSize(for: url)

        return MediaAsset(
            originalURL: url,
            kind: kind,
            duration: nil,
            metadata: MediaMetadata(fileSize: fileSize)
        )
    }

    /// Creates and stores a media asset in the supplied project media library.
    @discardableResult
    public static func importToLibrary(_ url: URL, library: inout MediaLibrary) -> MediaAsset {
        let asset = probe(url: url)
        library.assets[asset.id] = asset
        return asset
    }

    private static func mediaKind(for fileExtension: String) -> MediaKind {
        if imageExtensions.contains(fileExtension) {
            return .image
        }
        if audioExtensions.contains(fileExtension) {
            return .audio
        }
        if videoExtensions.contains(fileExtension) {
            return .video
        }
        return .video
    }

    private static func fileSize(for url: URL) -> Int64? {
        guard let value = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            return nil
        }
        return Int64(value)
    }
}
