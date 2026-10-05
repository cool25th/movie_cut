import AVFoundation
import AppKit
import Foundation
import MovieCutCore

/// Validates local media files, probes basic attributes, and creates verified `MediaAsset`s
/// for AI creation flows.
public enum PreparedAssetStore {

    public enum StoreError: LocalizedError, Sendable, Equatable {
        case fileNotFound(URL)
        case invalidImageData(URL)
        case invalidAudioData(URL)

        public var errorDescription: String? {
            switch self {
            case .fileNotFound(let url):
                return "File not found at \(url.path)"
            case .invalidImageData(let url):
                return "Unable to decode image at \(url.path)"
            case .invalidAudioData(let url):
                return "Unable to probe audio at \(url.path)"
            }
        }
    }

    /// Prepares verified image assets from local URLs.
    public static func preparePhotoAssets(from urls: [URL]) throws -> [MediaAsset] {
        try urls.map { url in
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw StoreError.fileNotFound(url)
            }
            guard let image = NSImage(contentsOf: url), image.isValid else {
                throw StoreError.invalidImageData(url)
            }

            let metadata = MediaMetadata(
                width: Int(image.size.width),
                height: Int(image.size.height)
            )
            let bookmark = SecurityScopedAccess.makeBookmark(for: url)
            return MediaAsset(
                id: UUID(),
                originalURL: url,
                kind: .image,
                metadata: metadata,
                originalBookmark: bookmark
            )
        }
    }

    /// Prepares a verified audio asset from a local URL.
    public static func prepareMusicAsset(from url: URL) async throws -> MediaAsset {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.fileNotFound(url)
        }

        let avAsset = AVAsset(url: url)
        let durationSeconds: Double
        if #available(macOS 13.0, *) {
            let cmDuration = try await avAsset.load(.duration)
            durationSeconds = CMTimeGetSeconds(cmDuration)
        } else {
            durationSeconds = CMTimeGetSeconds(avAsset.duration)
        }

        guard durationSeconds.isFinite, durationSeconds > 0 else {
            throw StoreError.invalidAudioData(url)
        }

        let bookmark = SecurityScopedAccess.makeBookmark(for: url)
        return MediaAsset(
            id: UUID(),
            originalURL: url,
            kind: .audio,
            duration: durationSeconds,
            originalBookmark: bookmark
        )
    }
}
