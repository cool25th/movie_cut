import Foundation
import CoreGraphics
#if canImport(AVFoundation)
import AVFoundation
import CoreImage
#endif

public struct ThumbnailGenerator: Sendable {
    public static let defaultSize = CGSize(width: 160, height: 90)

    public static func generate(for asset: MediaAsset, at time: TimeInterval, size: CGSize) -> Data? {
        #if canImport(AVFoundation)
        let context = CIContext(options: RenderColorConfiguration.contextOptions)

        if asset.kind == .image || isImageFile(asset.originalURL) {
            guard let image = CIImage(contentsOf: asset.originalURL) else {
                return nil
            }

            return pngData(from: image, fitting: size, context: context)
        }

        guard asset.kind == .video else {
            return nil
        }

        guard time.isFinite else {
            return nil
        }

        let avAsset = AVAsset(url: asset.originalURL)
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        if size.width > 0, size.height > 0 {
            generator.maximumSize = size
        }

        let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        guard let cgImage = try? generator.copyCGImage(at: requestedTime, actualTime: nil) else {
            return nil
        }

        return pngData(from: CIImage(cgImage: cgImage), fitting: size, context: context)
        #else
        return nil
        #endif
    }

    #if canImport(AVFoundation)
    private static func isImageFile(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "heic", "jpg", "jpeg", "png":
            return true
        default:
            return false
        }
    }

    private static func pngData(from image: CIImage, fitting size: CGSize, context: CIContext) -> Data? {
        let image = image.oriented(.up)
        let scaledImage = image.transformed(by: scaleTransform(for: image.extent.size, fitting: size))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        return context.pngRepresentation(
            of: scaledImage,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }

    private static func scaleTransform(for imageSize: CGSize, fitting targetSize: CGSize) -> CGAffineTransform {
        guard imageSize.width > 0,
              imageSize.height > 0,
              targetSize.width > 0,
              targetSize.height > 0 else {
            return .identity
        }

        let scale = min(targetSize.width / imageSize.width, targetSize.height / imageSize.height, 1)
        return CGAffineTransform(scaleX: scale, y: scale)
    }
    #endif
}

extension ThumbnailGenerator {
    /// Returns a thumbnail from the cache, generating and caching it on a miss.
    ///
    /// The cache key is a cheap path-independent fingerprint (file size +
    /// modification date + thumbnail parameters), so identical source media
    /// reuses a single cached thumbnail and edits to the source invalidate it.
    /// Generation falls back to the uncached path if the source cannot be
    /// fingerprinted.
    public static func cachedThumbnail(
        for asset: MediaAsset,
        at time: TimeInterval,
        size: CGSize = defaultSize,
        cache: RenderCache
    ) async -> Data? {
        let parameters = [
            "thumbnail",
            String(format: "%.3f", time),
            "\(Int(size.width))x\(Int(size.height))"
        ]
        guard let key = try? RenderContentHasher.key(
            fingerprintOfFileAt: asset.originalURL,
            parameters: parameters
        ) else {
            return generate(for: asset, at: time, size: size)
        }

        if let cached = await cache.data(for: key) {
            return cached
        }

        guard let data = generate(for: asset, at: time, size: size) else {
            return nil
        }
        try? await cache.store(data, for: key)
        return data
    }
}

/// Deterministic target metadata for a generated video proxy.
public struct ProxyGenerationPlan: Sendable, Equatable {
    /// The source media URL used to create the proxy.
    public var sourceURL: URL

    /// The file URL where the proxy should be written.
    public var targetURL: URL

    /// The intended proxy frame size.
    public var resolution: CGSize

    /// Creates a proxy generation plan.
    public init(sourceURL: URL, targetURL: URL, resolution: CGSize) {
        self.sourceURL = sourceURL
        self.targetURL = targetURL
        self.resolution = resolution
    }
}

/// Lightweight proxy planning and best-effort AVFoundation transcoding.
public enum ProxyGenerator {
    public static let defaultMaxDimension: CGFloat = 960

    public static func makeProxyPlan(
        for asset: MediaAsset,
        in directory: URL,
        proxyResolution selected: ProxyResolution = .default
    ) -> ProxyGenerationPlan? {
        guard asset.kind == .video else { return nil }

        // The resolution token keeps proxies of different sizes in separate
        // files. They used to share one path, so `proxyInfoIfReady` handed back
        // whatever had been generated first and changing the setting silently
        // did nothing.
        let targetURL = directory
            .appendingPathComponent("\(asset.id.uuidString)-proxy-\(selected.fileToken)")
            .appendingPathExtension("mp4")
        let resolution = proxyResolution(
            width: asset.metadata.width,
            height: asset.metadata.height,
            maxDimension: selected.maxDimension
        )

        return ProxyGenerationPlan(
            sourceURL: asset.originalURL,
            targetURL: targetURL,
            resolution: resolution
        )
    }

    public static func proxyInfoIfReady(for plan: ProxyGenerationPlan) -> ProxyInfo? {
        guard proxyFileExists(at: plan.targetURL) else {
            return nil
        }

        return ProxyInfo(proxyURL: plan.targetURL, resolution: plan.resolution)
    }

    public static func generateProxy(
        for asset: MediaAsset,
        in directory: URL,
        proxyResolution selected: ProxyResolution = .default
    ) async throws -> ProxyInfo? {
        guard let plan = makeProxyPlan(for: asset, in: directory, proxyResolution: selected) else {
            return nil
        }

        return try await generateProxy(for: asset, using: plan, proxyResolution: selected)
    }

    public static func generateProxy(
        for asset: MediaAsset,
        using plan: ProxyGenerationPlan,
        proxyResolution selected: ProxyResolution = .default
    ) async throws -> ProxyInfo? {
        guard asset.kind == .video else {
            return nil
        }

        try FileManager.default.createDirectory(
            at: plan.targetURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let readyInfo = proxyInfoIfReady(for: plan) {
            return readyInfo
        }

        if FileManager.default.fileExists(atPath: plan.targetURL.path) {
            try FileManager.default.removeItem(at: plan.targetURL)
        }

        #if canImport(AVFoundation)
        let sourceAsset = AVURLAsset(url: asset.originalURL)
        // The preset has to follow the selected resolution. It used to be
        // hardwired to 960x540 while `makeProxyPlan` computed a size from the
        // caller's dimension, so `ProxyInfo.resolution` could report a size the
        // file on disk never had.
        guard let exportSession = AVAssetExportSession(
            asset: sourceAsset,
            presetName: exportPresetName(for: selected)
        ) else {
            return nil
        }

        guard exportSession.supportedFileTypes.contains(.mp4) else {
            return nil
        }

        do {
            try await exportSession.export(to: plan.targetURL, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: plan.targetURL)
            throw error
        }

        guard let proxyInfo = proxyInfoIfReady(for: plan) else {
            try? FileManager.default.removeItem(at: plan.targetURL)
            return nil
        }

        return proxyInfo
        #else
        return nil
        #endif
    }

    #if canImport(AVFoundation)
    /// Maps a selected proxy resolution to the AVFoundation export preset that
    /// produces it.
    private static func exportPresetName(for selected: ProxyResolution) -> String {
        switch selected {
        case .p480: return AVAssetExportPreset640x480
        case .p540: return AVAssetExportPreset960x540
        case .p720: return AVAssetExportPreset1280x720
        case .p1080: return AVAssetExportPreset1920x1080
        }
    }
    #endif

    private static func proxyResolution(width: Int?, height: Int?, maxDimension: CGFloat) -> CGSize {
        guard
            let width,
            let height,
            width > 0,
            height > 0
        else {
            return CGSize(width: maxDimension, height: maxDimension * 9 / 16)
        }

        let sourceSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        let longestSide = max(sourceSize.width, sourceSize.height)
        guard longestSide > maxDimension else {
            return sourceSize
        }

        let scale = maxDimension / longestSide
        return CGSize(
            width: (sourceSize.width * scale).rounded(),
            height: (sourceSize.height * scale).rounded()
        )
    }

    private static func proxyFileExists(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return (fileSize ?? 0) > 0
    }
}
