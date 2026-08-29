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

/// BUG-02 (CA-03 audit): import-time validation failures. `probe(url:)` is
/// deliberately extension-only; the validated entry rejects unknown
/// extensions and files whose header bytes don't match a known media
/// signature, so a corrupt or mislabeled file fails AT IMPORT with an
/// explicit reason instead of exploding at preview/export time.
public enum MediaImportValidationError: Error, Equatable, Sendable, LocalizedError {
    /// The file extension is not in the supported media allow-list (a `.txt`
    /// used to silently become a "video" asset).
    case unsupportedExtension(String)
    /// The file could not be read at all (missing, unreadable, or empty).
    case unreadableFile
    /// The extension is supported but the header contains no known media
    /// signature — corrupt or mislabeled content.
    case unrecognizedContent(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedExtension(let ext):
            return "“.\(ext)” files aren't supported. Use a video, audio, or image file."
        case .unreadableFile:
            return "The file can't be read. It may be missing or empty."
        case .unrecognizedContent(let ext):
            return "This “.\(ext)” file doesn't look like valid media — it may be damaged."
        }
    }
}

extension MediaImporter {
    /// Extensions whose formats carry no reliable magic bytes (raw streams);
    /// these pass on the extension allow-list alone.
    private static let weakMagicExtensions: Set<String> = ["mp3", "aac"]

    private static func isKnownExtension(_ fileExtension: String) -> Bool {
        imageExtensions.contains(fileExtension)
            || audioExtensions.contains(fileExtension)
            || videoExtensions.contains(fileExtension)
    }

    /// A known media signature and the kinds it can belong to. A signature
    /// whose kinds exclude the extension's kind is a CONFLICT (a `.mp4` whose
    /// header is a PNG) and rejects the import.
    private struct KnownSignature {
        let bytes: [UInt8]
        /// Offset the signature must appear at (`nil` = contained anywhere in
        /// the header window).
        let offset: Int?
        let kinds: Set<MediaKind>
    }

    private static let knownSignatures: [KnownSignature] = [
        // ISO base media (mp4/m4v/mov/m4a/heic) — "ftyp" at offset 4.
        KnownSignature(bytes: Array("ftyp".utf8), offset: 4,
                       kinds: [.video, .audio, .image]),
        // RIFF containers (wav/avi/webp) — kind decided by extension.
        KnownSignature(bytes: Array("RIFF".utf8), offset: 0,
                       kinds: [.video, .audio, .image]),
        // Matroska / WebM (EBML header).
        KnownSignature(bytes: [0x1A, 0x45, 0xDF, 0xA3], offset: nil, kinds: [.video]),
        // MPEG program stream start code (mpg/mpeg).
        KnownSignature(bytes: [0x00, 0x00, 0x01], offset: 0, kinds: [.video]),
        KnownSignature(bytes: Array("OggS".utf8), offset: 0, kinds: [.audio]),
        KnownSignature(bytes: Array("fLaC".utf8), offset: 0, kinds: [.audio]),
        KnownSignature(bytes: Array("caff".utf8), offset: 0, kinds: [.audio]),
        KnownSignature(bytes: Array("ID3".utf8), offset: 0, kinds: [.audio]),
        KnownSignature(bytes: [0x89] + Array("PNG".utf8), offset: 0, kinds: [.image]),
        KnownSignature(bytes: [0xFF, 0xD8, 0xFF], offset: 0, kinds: [.image]),
        KnownSignature(bytes: Array("GIF8".utf8), offset: 0, kinds: [.image]),
        KnownSignature(bytes: Array("BM".utf8), offset: 0, kinds: [.image]),
        // TIFF (little/big endian).
        KnownSignature(bytes: [0x49, 0x49, 0x2A, 0x00], offset: 0, kinds: [.image]),
        KnownSignature(bytes: [0x4D, 0x4D, 0x00, 0x2A], offset: 0, kinds: [.image]),
    ]

    /// Validated probe: extension allow-list + lightweight magic-byte sniff of
    /// the first 512 bytes. Full decode verification stays delegated to the
    /// first preview load — this is the cheap gate that catches garbage and
    /// mislabeled files at import time.
    public static func validatedProbe(url: URL) throws(MediaImportValidationError) -> MediaAsset {
        let fileExtension = url.pathExtension.lowercased()
        guard isKnownExtension(fileExtension) else {
            throw .unsupportedExtension(fileExtension.isEmpty ? "file" : fileExtension)
        }

        guard let header = try? Data(contentsOf: url, options: [.alwaysMapped]).prefix(512),
              !header.isEmpty else {
            throw .unreadableFile
        }

        // Raw-stream formats have no dependable magic — the allow-list is the
        // whole check for them.
        guard !weakMagicExtensions.contains(fileExtension) else {
            return probe(url: url)
        }

        let kind = mediaKind(for: fileExtension)
        let window = [UInt8](header)
        for signature in knownSignatures {
            if matches(signature, in: window) {
                guard signature.kinds.contains(kind) else {
                    // Recognizable content of the WRONG family for this
                    // extension — mislabeled, not media of the promised kind.
                    throw .unrecognizedContent(fileExtension)
                }
                return probe(url: url)
            }
        }
        // No known signature anywhere in the header window: corrupt or
        // mislabeled content (e.g. a text file renamed .mp4).
        throw .unrecognizedContent(fileExtension)
    }

    private static func matches(_ signature: KnownSignature, in window: [UInt8]) -> Bool {
        let count = signature.bytes.count
        guard window.count >= count else { return false }
        if let offset = signature.offset {
            guard offset + count <= window.count else { return false }
            return Array(window[offset..<(offset + count)]) == signature.bytes
        }
        return window.indices.contains(where: { index in
            index + count <= window.count
                && Array(window[index..<(index + count)]) == signature.bytes
        })
    }
}
