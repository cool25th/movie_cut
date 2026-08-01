import CoreGraphics
import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
#endif
#if canImport(ImageIO)
import ImageIO
#endif

/// Best-effort AVFoundation / ImageIO metadata probing for imported media.
///
/// `MediaImporter.probe(url:)` is deliberately extension-only (it avoids
/// platform media frameworks to stay cheap and synchronous). This type is the
/// richer complement: it reads duration, dimensions, frame rate, codec, and
/// audio format from `AVAssetTrack` / `CGImageSource`, and enriches a
/// `MediaAsset` with a thumbnail. All access is `async` and best-effort —
/// every probe falls back to the supplied base metadata on failure.
///
/// Platform guarded so the package still compiles on toolchains without
/// AVFoundation. Image dimensions use `CGImageSource` (cross-platform); the
/// previous AppKit `NSImage` fallback is removed so the probe is identical on
/// macOS and iOS.
public enum AVFoundationProbe {
    /// Probes a media URL for duration and rich metadata (dimensions, codec,
    /// frame rate, sample rate, channel count) based on its kind.
    public static func appMetadataProbe(
        for url: URL,
        kind: MediaKind,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        #if canImport(AVFoundation)
        switch kind {
        case .video:
            return await videoMetadataProbe(for: url, baseMetadata: baseMetadata)
        case .audio:
            return await audioMetadataProbe(for: url, baseMetadata: baseMetadata)
        case .image:
            return (nil, imageMetadataProbe(for: url, baseMetadata: baseMetadata))
        }
        #else
        return (nil, baseMetadata)
        #endif
    }

    /// Enriches a media asset with a thumbnail image, when the kind supports
    /// one (video / image). Audio assets pass through unchanged.
    public static func enrichAssetWithThumbnail(_ asset: MediaAsset) async -> MediaAsset {
        guard asset.kind == .video || asset.kind == .image else {
            return asset
        }

        var enrichedAsset = asset
        let thumbnailTime = thumbnailTime(for: asset)
        let thumbnailSize = ThumbnailGenerator.defaultSize
        enrichedAsset.thumbnailData = await Task.detached(priority: .utility) {
            ThumbnailGenerator.generate(for: asset, at: thumbnailTime, size: thumbnailSize)
        }.value
        return enrichedAsset
    }

    /// Whether a video URL also carries an audio track.
    public static func videoAssetContainsAudioTrack(_ url: URL) async -> Bool {
        #if canImport(AVFoundation)
        await firstTrack(in: AVURLAsset(url: url), mediaType: .audio) != nil
        #else
        false
        #endif
    }

    /// The duration of an `AVURLAsset`, or `nil` when it is missing/invalid.
    public static func avAssetDuration(for url: URL) async -> TimeInterval? {
        #if canImport(AVFoundation)
        await avAssetDuration(for: AVURLAsset(url: url))
        #else
        nil
        #endif
    }

    #if canImport(AVFoundation)
    /// Probes a video URL for duration, dimensions, frame rate, and codec.
    public static func videoMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        let avAsset = AVURLAsset(url: url)
        var metadata = baseMetadata

        let duration = await avAssetDuration(for: avAsset)
        guard let videoTrack = await firstTrack(in: avAsset, mediaType: .video) else {
            return (duration, metadata)
        }

        if let dimensions = await videoDisplayDimensions(for: videoTrack) {
            metadata.width = dimensions.width
            metadata.height = dimensions.height
        }
        if let frameRate = await videoFrameRate(for: videoTrack) {
            metadata.frameRate = frameRate
        }
        if let codec = await codecDescription(for: videoTrack) {
            metadata.codec = codec
        }

        return (duration, metadata)
    }

    /// Probes an audio URL for duration, sample rate, channel count, and codec.
    public static func audioMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) async -> (duration: TimeInterval?, metadata: MediaMetadata) {
        let avAsset = AVURLAsset(url: url)
        var metadata = baseMetadata

        let duration = await avAssetDuration(for: avAsset)
        guard let audioTrack = await firstTrack(in: avAsset, mediaType: .audio) else {
            return (duration, metadata)
        }

        if let audioDescription = await audioFormatDescription(for: audioTrack) {
            if let sampleRate = audioDescription.sampleRate {
                metadata.sampleRate = sampleRate
            }
            if let channelCount = audioDescription.channelCount {
                metadata.channelCount = channelCount
            }
        }
        if let codec = await codecDescription(for: audioTrack) {
            metadata.codec = codec
        }

        return (duration, metadata)
    }
    #endif

    /// Probes an image URL for pixel dimensions via `CGImageSource`.
    public static func imageMetadataProbe(
        for url: URL,
        baseMetadata: MediaMetadata
    ) -> MediaMetadata {
        var metadata = baseMetadata

        #if canImport(ImageIO)
        if let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any] {
            if let width = properties[kCGImagePropertyPixelWidth] as? NSNumber {
                metadata.width = width.intValue
            }
            if let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                metadata.height = height.intValue
            }
        }
        #endif

        return metadata
    }

    /// Chooses a representative thumbnail timecode for a video asset
    /// (5% of duration, clamped to [0, 1]); images and unknowns return 0.
    public static func thumbnailTime(for asset: MediaAsset) -> TimeInterval {
        guard asset.kind == .video else {
            return 0
        }

        guard let duration = asset.duration, duration.isFinite, duration > 0 else {
            return 0
        }

        return min(max(duration * 0.05, 0), 1)
    }

    #if canImport(AVFoundation)
    public static func avAssetDuration(for asset: AVURLAsset) async -> TimeInterval? {
        do {
            let duration = try await asset.load(.duration)
            let seconds = duration.seconds
            guard seconds.isFinite, seconds > 0 else {
                return nil
            }
            return seconds
        } catch {
            return nil
        }
    }

    public static func firstTrack(
        in asset: AVURLAsset,
        mediaType: AVMediaType
    ) async -> AVAssetTrack? {
        do {
            return try await asset.loadTracks(withMediaType: mediaType).first
        } catch {
            return nil
        }
    }

    public static func videoDisplayDimensions(for track: AVAssetTrack) async -> (width: Int, height: Int)? {
        do {
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedBounds = CGRect(origin: CGPoint(x: 0, y: 0), size: naturalSize)
                .applying(preferredTransform)
            let width = Int(abs(transformedBounds.width).rounded())
            let height = Int(abs(transformedBounds.height).rounded())

            if width > 0, height > 0 {
                return (width, height)
            }

            let fallbackWidth = Int(abs(naturalSize.width).rounded())
            let fallbackHeight = Int(abs(naturalSize.height).rounded())
            guard fallbackWidth > 0, fallbackHeight > 0 else {
                return nil
            }
            return (fallbackWidth, fallbackHeight)
        } catch {
            return nil
        }
    }

    public static func videoFrameRate(for track: AVAssetTrack) async -> Double? {
        do {
            let frameRate = try await track.load(.nominalFrameRate)
            guard frameRate.isFinite, frameRate > 0 else {
                return nil
            }
            return Double(frameRate)
        } catch {
            return nil
        }
    }

    public static func audioFormatDescription(for track: AVAssetTrack) async -> (sampleRate: Int?, channelCount: Int?)? {
        guard let formatDescription = await firstFormatDescription(for: track),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)?.pointee else {
            return nil
        }

        let sampleRate = streamDescription.mSampleRate.isFinite && streamDescription.mSampleRate > 0
            ? Int(streamDescription.mSampleRate.rounded())
            : nil
        let channelCount = streamDescription.mChannelsPerFrame > 0
            ? Int(streamDescription.mChannelsPerFrame)
            : nil
        return (sampleRate, channelCount)
    }

    public static func codecDescription(for track: AVAssetTrack) async -> String? {
        guard let formatDescription = await firstFormatDescription(for: track) else {
            return nil
        }

        return codecName(from: CMFormatDescriptionGetMediaSubType(formatDescription))
    }

    public static func firstFormatDescription(for track: AVAssetTrack) async -> CMFormatDescription? {
        do {
            return try await track.load(.formatDescriptions).first
        } catch {
            return nil
        }
    }

    public static func codecName(from mediaSubType: FourCharCode) -> String? {
        guard let subtype = fourCharacterCodeString(from: mediaSubType) else {
            return nil
        }

        switch subtype {
        case "avc1":
            return "H.264"
        case "hvc1", "hev1":
            return "HEVC"
        case "apch":
            return "ProRes 422 HQ"
        case "apcn":
            return "ProRes 422"
        case "apcs":
            return "ProRes 422 LT"
        case "apco":
            return "ProRes 422 Proxy"
        case "ap4h":
            return "ProRes 4444"
        case "mp4a":
            return "AAC"
        case "lpcm":
            return "PCM"
        default:
            return subtype
        }
    }

    public static func fourCharacterCodeString(from code: FourCharCode) -> String? {
        var bigEndianCode = code.bigEndian
        let bytes = withUnsafeBytes(of: &bigEndianCode) { Array($0) }
        guard bytes.allSatisfy({ byte in
            byte >= 32 && byte <= 126
        }) else {
            return nil
        }

        let string = String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return string?.isEmpty == false ? string : nil
    }
    #endif
}
