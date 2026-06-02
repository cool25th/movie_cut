#if canImport(AppKit)
import AppKit
import Foundation

/// Handles media URLs dropped from AppKit pasteboards.
public struct DragDropHandler {
    /// Pasteboard types accepted by media drag and drop.
    public static func supportedTypes() -> [NSPasteboard.PasteboardType] {
        [.fileURL]
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
        "heic", "jpg", "m4a", "mov", "mp4", "png", "wav"
    ]

    private static func isSupportedMediaURL(_ url: URL) -> Bool {
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

    private static func fileURL(from item: (any NSSecureCoding)?) -> URL? {
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
#endif
