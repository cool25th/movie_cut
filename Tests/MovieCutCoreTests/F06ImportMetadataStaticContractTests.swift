import Foundation
import Testing

/// SwiftPM builds Core only, so F-06's macOS app-layer probing is guarded with
/// source contracts in the package test loop.
@Suite("F06 Import Metadata StaticContract")
struct F06ImportMetadataStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("EditorViewModel has best-effort AV and image metadata probe helpers")
    func editorViewModelHasBestEffortMetadataProbeHelpers() throws {
        // The probe implementation lives in Core's AVFoundationProbe
        // (Sources/MovieCutCore/Media/AVFoundationProbe.swift), shared by Mac
        // and iOS. The Mac VM forwards to it from EditorViewModel+MediaProbe.swift.
        let source = try source("Sources/MovieCutCore/Media/AVFoundationProbe.swift")

        #expect(source.contains("static func appMetadataProbe"))
        #expect(source.contains("static func videoMetadataProbe"))
        #expect(source.contains("static func audioMetadataProbe"))
        #expect(source.contains("static func imageMetadataProbe"))
        #expect(source.contains("AVURLAsset(url: url)"))
        #expect(source.contains("firstTrack(in: avAsset, mediaType: .video)"))
        #expect(source.contains("firstTrack(in: avAsset, mediaType: .audio)"))
        #expect(source.contains("loadTracks(withMediaType: mediaType)"))
        #expect(source.contains("track.load(.naturalSize)"))
        #expect(source.contains("track.load(.preferredTransform)"))
        #expect(source.contains("track.load(.nominalFrameRate)"))
        #expect(source.contains("track.load(.formatDescriptions)"))
        #expect(source.contains("CMFormatDescriptionGetMediaSubType"))
        #expect(source.contains("CMAudioFormatDescriptionGetStreamBasicDescription"))
        #expect(source.contains("CGImageSourceCreateWithURL"))
    }

    @Test("EditorViewModel fills F-06 metadata without dropping Core fileSize")
    func editorViewModelFillsMetadataWithoutDroppingFileSize() throws {
        // The probe call site (passing baseMetadata) stays in EditorViewModel.swift;
        // the probe body that fills the metadata fields lives in Core's
        // AVFoundationProbe. Both files are checked.
        let callSite = try source("App/MovieCutMac/EditorViewModel.swift")
        let probes = try source("Sources/MovieCutCore/Media/AVFoundationProbe.swift")
        let importer = try source("Sources/MovieCutCore/Media/MediaImporter.swift")

        #expect(callSite.contains("baseMetadata: asset.metadata"))
        #expect(probes.contains("var metadata = baseMetadata"))
        #expect(probes.contains("metadata.width = dimensions.width"))
        #expect(probes.contains("metadata.height = dimensions.height"))
        #expect(probes.contains("metadata.frameRate = frameRate"))
        #expect(probes.contains("metadata.codec = codec"))
        #expect(probes.contains("metadata.sampleRate = sampleRate"))
        #expect(probes.contains("metadata.channelCount = channelCount"))
        #expect(importer.contains("metadata: MediaMetadata(fileSize: fileSize)"))
    }

    @Test("MediaLibraryPanel exposes compact metadata summary and accessibility")
    func mediaLibraryPanelExposesMetadataSummaryAndAccessibility() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        #expect(source.contains("private func assetDetailSummary"))
        #expect(source.contains("private func metadataSummary"))
        #expect(source.contains("private func resolutionSummary"))
        #expect(source.contains("\"\\(width)×\\(height)\""))
        #expect(source.contains("frameRateSummary(metadata.frameRate)"))
        #expect(source.contains("\"%.0f fps\""))
        #expect(source.contains("\"%.2f fps\""))
        #expect(source.contains("sampleRateSummary(metadata.sampleRate)"))
        #expect(source.contains("\"%.0f kHz\""))
        #expect(source.contains("\"%.1f kHz\""))
        #expect(source.contains("channelCountSummary(metadata.channelCount)"))
        #expect(source.contains("\"%d ch\""))
        #expect(source.contains("codecSummary(metadata.codec)"))
        #expect(source.contains("if let metadata = metadataSummary(asset)"))
        #expect(source.contains("states.append(metadata)"))
        #expect(source.contains("assetDetailSummary(asset)"))
    }
}
