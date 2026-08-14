#if canImport(AppKit)
import AppKit
import Foundation
import UniformTypeIdentifiers

/// `@unchecked Sendable` carrier for an `NSItemProvider` handed to a load
/// completion closure. `NSItemProvider` is not Sendable on the macOS 15 SDK
/// (it is on later SDKs), so re-capturing it inside the already-`@Sendable`
/// `loadFileRepresentation` completion fails strict concurrency on the pinned
/// Xcode 16. The provider's load APIs are documented callable from any queue
/// and each one here is used from a single sequential fallback chain.
private struct ItemProviderBox: @unchecked Sendable {
    let provider: NSItemProvider
}

/// Handles media URLs dropped from AppKit pasteboards.
public struct DragDropHandler {
    /// Pasteboard types accepted by media drag and drop.
    public static func supportedTypes() -> [NSPasteboard.PasteboardType] {
        [.fileURL]
    }

    /// Type identifiers accepted from external drag sources. File URLs cover
    /// Finder; movie/image cover promise- or data-backed drags from Photos,
    /// browsers, and mail clients that do not expose an on-disk URL.
    public static let externalMediaTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        UTType.movie.identifier,
        UTType.image.identifier
    ]

    /// Returns true when the provider offers any payload this handler can
    /// turn into an importable media file URL.
    public static func providesExternalMedia(_ provider: NSItemProvider) -> Bool {
        externalMediaTypeIdentifiers.contains {
            provider.hasItemConformingToTypeIdentifier($0)
        }
    }

    /// Directory that receives media payloads which arrive as data or file
    /// promises rather than as existing on-disk URLs.
    public static func importDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Loads importable media file URLs from external drag sources, in
    /// provider order. File URLs are passed through; image/movie payloads are
    /// materialized into `importDirectory()` so the import pipeline can treat
    /// every result as a plain media file.
    public static func loadExternalMediaURLs(
        from providers: [NSItemProvider],
        completion: @escaping @Sendable ([URL]) -> Void
    ) {
        guard !providers.isEmpty else {
            completion([])
            return
        }

        let accumulator = ExternalDropPayloadAccumulator(count: providers.count, completion: completion)
        for (index, provider) in providers.enumerated() {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url = fileURL(from: item).flatMap { isSupportedMediaURL($0) ? $0 : nil }
                    accumulator.complete(index: index, value: url)
                }
                continue
            }

            guard let typeIdentifier = preferredExternalTypeIdentifier(for: provider) else {
                accumulator.complete(index: index, value: nil)
                continue
            }

            let suggestedName = provider.suggestedName
            let providerBox = ItemProviderBox(provider)
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, _ in
                if let url,
                   let copied = copyIntoImportDirectory(url, suggestedName: suggestedName) {
                    accumulator.complete(index: index, value: copied)
                    return
                }

                providerBox.provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    let written = data.flatMap {
                        writeImportedData($0, typeIdentifier: typeIdentifier, suggestedName: suggestedName)
                    }
                    accumulator.complete(index: index, value: written)
                }
            }
        }
    }

    /// Picks the concrete registered identifier to load for a non-file-URL
    /// provider, preferring movie payloads over their image thumbnails.
    public static func preferredExternalTypeIdentifier(for provider: NSItemProvider) -> String? {
        let registered = provider.registeredTypeIdentifiers

        func firstConforming(to type: UTType) -> String? {
            registered.first { identifier in
                UTType(identifier)?.conforms(to: type) == true
            }
        }

        return firstConforming(to: .movie) ?? firstConforming(to: .image)
    }

    /// Writes a data payload into the import directory using the payload
    /// type's preferred filename extension.
    public static func writeImportedData(
        _ data: Data,
        typeIdentifier: String,
        suggestedName: String?
    ) -> URL? {
        let fileExtension = UTType(typeIdentifier)?.preferredFilenameExtension
            ?? suggestedName.flatMap { name in
                let ext = (name as NSString).pathExtension
                return ext.isEmpty ? nil : ext
            }
            ?? "png"
        let baseName = importedBaseName(from: suggestedName)
        let destination = uniqueImportSubdirectory()
            .appendingPathComponent("\(baseName).\(fileExtension)")

        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            return nil
        }
    }

    private static func copyIntoImportDirectory(_ url: URL, suggestedName: String?) -> URL? {
        let name: String
        if let suggestedName, !(suggestedName as NSString).pathExtension.isEmpty {
            name = suggestedName
        } else if !url.pathExtension.isEmpty {
            name = "\(importedBaseName(from: suggestedName)).\(url.pathExtension)"
        } else {
            name = url.lastPathComponent
        }
        let destination = uniqueImportSubdirectory().appendingPathComponent(name)

        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    private static func uniqueImportSubdirectory() -> URL {
        let directory = importDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func importedBaseName(from suggestedName: String?) -> String {
        guard let suggestedName else { return "Imported Media" }
        let base = (suggestedName as NSString).deletingPathExtension
        return base.isEmpty ? "Imported Media" : base
    }

    /// Loads file URLs from item providers and returns supported media files.
    public static func handleDrop(providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(NSPasteboard.PasteboardType.fileURL.rawValue),
                  let url = await loadFileURL(from: provider),
                  isSupportedMediaURL(url)
            else {
                continue
            }

            urls.append(url)
        }

        return urls
    }

    private static let supportedMediaExtensions: Set<String> = [
        "aac", "aif", "aiff", "avi", "bmp", "flac", "gif", "heic",
        "jpeg", "jpg", "m4a", "m4v", "mkv", "mov", "mp3", "mp4",
        "mpeg", "mpg", "ogg", "png", "tif", "tiff", "wav", "webm", "webp"
    ]

    public static func isSupportedMediaURL(_ url: URL) -> Bool {
        supportedMediaExtensions.contains(url.pathExtension.lowercased())
    }

    private static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: NSPasteboard.PasteboardType.fileURL.rawValue,
                options: nil
            ) { item, _ in
                continuation.resume(returning: fileURL(from: item))
            }
        }
    }

    public static func fileURL(from item: (any NSSecureCoding)?) -> URL? {
        if let url = item as? URL {
            return url
        }

        if let url = item as? NSURL {
            return url as URL
        }

        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }

        if let string = item as? String {
            return URL(string: string)
        }

        return nil
    }
}

/// Collects async drop payload results while preserving provider order.
private final class ExternalDropPayloadAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [URL?]
    private var remaining: Int
    private let completion: @Sendable ([URL]) -> Void

    init(count: Int, completion: @escaping @Sendable ([URL]) -> Void) {
        self.values = Array(repeating: nil, count: count)
        self.remaining = count
        self.completion = completion
    }

    func complete(index: Int, value: URL?) {
        let finishedValues: [URL]?
        lock.lock()
        values[index] = value
        remaining -= 1
        finishedValues = remaining == 0 ? values.compactMap { $0 } : nil
        lock.unlock()

        if let finishedValues {
            completion(finishedValues)
        }
    }
}
#endif
