#if canImport(AppKit)
import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MovieCutCore

/// Behavioral coverage for F-01: external (non-file-URL) drag payloads from
/// Photos/browser-style sources must materialize as importable media files.
/// These tests drive real NSItemProvider payload loading rather than source
/// string checks, because the drag-and-drop P0 showed static contracts alone
/// cannot catch runtime drop failures.
@Suite("External Media Drop")
struct ExternalMediaDropTests {
    private func loadURLs(from providers: [NSItemProvider]) async -> [URL] {
        await withCheckedContinuation { continuation in
            DragDropHandler.loadExternalMediaURLs(from: providers) { urls in
                continuation.resume(returning: urls)
            }
        }
    }

    private func pngFixtureData() -> Data {
        let image = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        let tiff = image.tiffRepresentation!
        let rep = NSBitmapImageRep(data: tiff)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("browser-style image data payload is written as an importable png file")
    func imageDataPayloadBecomesFile() async throws {
        let pngData = pngFixtureData()
        let provider = NSItemProvider()
        provider.suggestedName = "web-image"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.png.identifier,
            visibility: .all
        ) { completion in
            completion(pngData, nil)
            return nil
        }

        let urls = await loadURLs(from: [provider])

        #expect(urls.count == 1)
        let url = try #require(urls.first)
        #expect(url.pathExtension.lowercased() == "png")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(DragDropHandler.isSupportedMediaURL(url))
        let written = try Data(contentsOf: url)
        #expect(!written.isEmpty)
    }

    @Test("movie data payload is written with a movie file extension")
    func movieDataPayloadBecomesFile() async throws {
        let payload = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        let provider = NSItemProvider()
        provider.suggestedName = "clip"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.mpeg4Movie.identifier,
            visibility: .all
        ) { completion in
            completion(payload, nil)
            return nil
        }

        let urls = await loadURLs(from: [provider])

        #expect(urls.count == 1)
        let url = try #require(urls.first)
        #expect(url.pathExtension.lowercased() == "mp4")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("file URL payloads pass through unchanged")
    func fileURLPayloadPassesThrough() async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mp4")
        try Data([0x01]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.fileURL.identifier,
            visibility: .all
        ) { completion in
            completion(source.dataRepresentation, nil)
            return nil
        }

        let urls = await loadURLs(from: [provider])

        #expect(urls.count == 1)
        #expect(urls.first?.standardizedFileURL == source.standardizedFileURL)
    }

    @Test("non-media payloads resolve to an empty result")
    func nonMediaPayloadIsRejected() async {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.plainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data("hello".utf8), nil)
            return nil
        }

        #expect(!DragDropHandler.providesExternalMedia(provider))
        let urls = await loadURLs(from: [provider])
        #expect(urls.isEmpty)
    }

    @Test("movie representation is preferred over image thumbnail")
    func moviePreferredOverImage() {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.jpeg.identifier,
            visibility: .all
        ) { completion in
            completion(Data(), nil)
            return nil
        }
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.mpeg4Movie.identifier,
            visibility: .all
        ) { completion in
            completion(Data(), nil)
            return nil
        }

        let preferred = DragDropHandler.preferredExternalTypeIdentifier(for: provider)
        #expect(preferred == UTType.mpeg4Movie.identifier)
    }

    @Test("imported data filename uses payload type extension and suggested name")
    func writeImportedDataNaming() throws {
        let url = try #require(DragDropHandler.writeImportedData(
            Data([0xFF, 0xD8]),
            typeIdentifier: UTType.jpeg.identifier,
            suggestedName: "holiday photo"
        ))
        #expect(url.lastPathComponent.hasPrefix("holiday photo"))
        #expect(["jpg", "jpeg"].contains(url.pathExtension.lowercased()))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }
}
#endif
