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
            let didStart = url.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    url.stopAccessingSecurityScopedResource()
                }
            }
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
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }
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

    /// Resolves and refreshes a prepared asset's security-scoped bookmark across process restarts (`AI-03a` M3b).
    public static func verifyAndRefreshBookmark(for asset: MediaAsset) throws -> MediaAsset {
        var updated = asset
        if let resolved = SecurityScopedAccess.resolveBookmark(for: asset) {
            updated.originalURL = resolved.url
            if resolved.isStale {
                let didStart = resolved.url.startAccessingSecurityScopedResource()
                defer {
                    if didStart {
                        resolved.url.stopAccessingSecurityScopedResource()
                    }
                }
                if let refreshed = SecurityScopedAccess.makeBookmark(for: resolved.url) {
                    updated.originalBookmark = refreshed
                }
            }
        }
        let exists = try SecurityScopedAccess.withSecurityScope(for: updated) { scopedURL in
            FileManager.default.fileExists(atPath: scopedURL.path)
        }
        guard exists else {
            throw StoreError.fileNotFound(updated.originalURL)
        }
        return updated
    }
}
