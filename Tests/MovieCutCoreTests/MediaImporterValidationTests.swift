import Foundation
import Testing
@testable import MovieCutCore

/// BUG-02 (CA-03 audit): import-time validation. `probe(url:)` is
/// extension-only and defaulted unknown extensions to `.video` — a garbage or
/// mislabeled file imported cleanly and exploded at preview/export. These
/// tests pin the validated probe's allow-list and magic-byte sniff.
@Suite("Media importer validated probe (BUG-02)")
struct MediaImporterValidationTests {
    private func temporaryFile(extension ext: String, bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug02-\(UUID().uuidString).\(ext)")
        try Data(bytes).write(to: url)
        return url
    }

    @Test("valid signatures pass and keep their extension-derived kind")
    func validFilesPass() throws {
        // Minimal mp4 (ftyp at offset 4), wav (RIFF), png.
        let mp4 = try temporaryFile(
            extension: "mp4",
            bytes: [0, 0, 0, 0x18] + Array("ftypisom".utf8) + Array(repeating: 0, count: 16))
        #expect(try MediaImporter.validatedProbe(url: mp4).kind == .video)

        let wav = try temporaryFile(
            extension: "wav",
            bytes: Array("RIFF".utf8) + [0x24, 0x08, 0x00, 0x00] + Array("WAVEfmt ".utf8))
        #expect(try MediaImporter.validatedProbe(url: wav).kind == .audio)

        let png = try temporaryFile(
            extension: "png",
            bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 8))
        #expect(try MediaImporter.validatedProbe(url: png).kind == .image)

        let mkv = try temporaryFile(
            extension: "mkv",
            bytes: [0x1A, 0x45, 0xDF, 0xA3] + Array(repeating: 0, count: 12))
        #expect(try MediaImporter.validatedProbe(url: mkv).kind == .video)
    }

    @Test("unknown extensions are rejected explicitly, never defaulted to video")
    func unknownExtensionRejected() throws {
        let txt = try temporaryFile(extension: "txt", bytes: Array("hello world".utf8))
        #expect(throws: MediaImportValidationError.unsupportedExtension("txt")) {
            _ = try MediaImporter.validatedProbe(url: txt)
        }
        // No extension at all.
        let none = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug02-\(UUID().uuidString)")
        try Data([0x00]).write(to: none)
        #expect(throws: MediaImportValidationError.unsupportedExtension("file")) {
            _ = try MediaImporter.validatedProbe(url: none)
        }
    }

    @Test("garbage content with a supported extension is rejected as unrecognized")
    func garbageContentRejected() throws {
        // Text bytes renamed .mp4 — no ftyp anywhere in the window.
        let fake = try temporaryFile(extension: "mp4", bytes: Array("this is definitely not a video file at all".utf8))
        #expect(throws: MediaImportValidationError.unrecognizedContent("mp4")) {
            _ = try MediaImporter.validatedProbe(url: fake)
        }
    }

    @Test("mislabeled content — recognizable signature of the wrong family — is rejected")
    func wrongFamilyRejected() throws {
        // PNG bytes inside a .mp4: the signature is recognizable but its
        // family excludes video.
        let pngInMp4 = try temporaryFile(
            extension: "mp4",
            bytes: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 8))
        #expect(throws: MediaImportValidationError.unrecognizedContent("mp4")) {
            _ = try MediaImporter.validatedProbe(url: pngInMp4)
        }
    }

    @Test("empty and missing files are rejected as unreadable")
    func emptyAndMissingRejected() throws {
        let empty = try temporaryFile(extension: "mov", bytes: [])
        #expect(throws: MediaImportValidationError.unreadableFile) {
            _ = try MediaImporter.validatedProbe(url: empty)
        }
        #expect(throws: MediaImportValidationError.unreadableFile) {
            _ = try MediaImporter.validatedProbe(
                url: URL(fileURLWithPath: "/nonexistent-dir-abc/missing.mov"))
        }
    }

    @Test("raw-stream formats (mp3/aac) pass on the extension allow-list alone")
    func weakMagicFormatsPass() throws {
        // Raw MP3 frames without an ID3 tag carry no dependable magic.
        let rawMp3 = try temporaryFile(extension: "mp3", bytes: [0xFF, 0xFB, 0x90, 0x00, 0x00])
        #expect(try MediaImporter.validatedProbe(url: rawMp3).kind == .audio)
    }

    @Test("error messages are user-actionable via LocalizedError")
    func messagesAreActionable() {
        #expect(MediaImportValidationError.unsupportedExtension("txt").localizedDescription
                .contains("aren't supported"))
        #expect(MediaImportValidationError.unrecognizedContent("mp4").localizedDescription
                .contains("damaged"))
        #expect(MediaImportValidationError.unreadableFile.localizedDescription
                .contains("read"))
    }
}
