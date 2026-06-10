import AVFoundation
import Foundation
import Testing
@testable import MovieCutCore

/// Built-in SFX catalog must stay aligned with bundled WAV resources.
/// 바비 backend/data pipeline QA, 2026-06-09.
@Suite("SFXLibrary resource integrity")
struct SFXLibraryResourceTests {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private static var sfxResourceDirectory: URL {
        repositoryRoot
            .appendingPathComponent("App")
            .appendingPathComponent("MovieCutMac")
            .appendingPathComponent("Resources")
            .appendingPathComponent("SFX")
    }

    @Test("Every catalog SFX resolves to a parseable non-empty WAV resource")
    func catalogWAVResourcesAreParseableAndNonEmpty() throws {
        let items = SFXLibrary.all
        #expect(items.count == 12)

        let fileNames = items.map(\.fileName)
        #expect(Set(fileNames).count == fileNames.count, "SFX file names must be unique")

        for item in items {
            let url = Self.sfxResourceDirectory.appendingPathComponent(item.fileName)
            #expect(FileManager.default.fileExists(atPath: url.path), "Missing SFX resource: \(item.fileName)")

            let file = try AVAudioFile(forReading: url)
            #expect(file.length > 0, "SFX resource has no audio frames: \(item.fileName)")
            #expect(file.fileFormat.sampleRate > 0, "SFX resource has invalid sample rate: \(item.fileName)")
            #expect(file.fileFormat.channelCount > 0, "SFX resource has no channels: \(item.fileName)")
        }
    }

    @Test("Bundled SFX directory does not contain uncataloged WAV files")
    func bundledSFXDirectoryDoesNotContainUncatalogedWAVFiles() throws {
        let bundledWAVNames = try FileManager.default.contentsOfDirectory(
            at: Self.sfxResourceDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "wav" }
        .map(\.lastPathComponent)

        #expect(Set(bundledWAVNames) == Set(SFXLibrary.all.map(\.fileName)))
    }
}
