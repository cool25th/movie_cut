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
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(source.contains("private nonisolated static func appMetadataProbe"))
        #expect(source.contains("private nonisolated static func videoMetadataProbe"))
        #expect(source.contains("private nonisolated static func audioMetadataProbe"))
        #expect(source.contains("private nonisolated static func imageMetadataProbe"))
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
        #expect(source.contains("NSImage(contentsOf: url)"))
    }

    @Test("EditorViewModel fills F-06 metadata without dropping Core fileSize")
    func editorViewModelFillsMetadataWithoutDroppingFileSize() throws {
        let viewModel = try source("App/MovieCutMac/EditorViewModel.swift")
        let importer = try source("Sources/MovieCutCore/Media/MediaImporter.swift")

        #expect(viewModel.contains("baseMetadata: asset.metadata"))
        #expect(viewModel.contains("var metadata = baseMetadata"))
        #expect(viewModel.contains("metadata.width = dimensions.width"))
        #expect(viewModel.contains("metadata.height = dimensions.height"))
        #expect(viewModel.contains("metadata.frameRate = frameRate"))
        #expect(viewModel.contains("metadata.codec = codec"))
        #expect(viewModel.contains("metadata.sampleRate = sampleRate"))
        #expect(viewModel.contains("metadata.channelCount = channelCount"))
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

    @Test("Docs mark F-06 complete and advance next queue to F-01 verification")
    func docsMarkF06CompleteAndAdvanceNextQueue() throws {
        let parity = try source("docs/CAPCUT_PARITY_SPEC.md")
        let backlog = try source("docs/CAPCUT_FEATURE_BACKLOG.md")
        let handoff = try source("docs/SESSION_HANDOFF.md")

        #expect(parity.contains("#### F-06. 임포트 메타데이터 완성 (해상도/fps) — ✅ 구현+정적 계약 완료"))
        #expect(parity.contains("best-effort metadata probing"))
        #expect(parity.contains("GUI visual verification not included"))
        #expect(backlog.contains("- [x] ✅ 실제 import metadata probe"))
        #expect(backlog.contains("다음 1순위는 F-01 실기기 검증"))
        #expect(!backlog.contains("다음 1순위는 F-06 임포트 메타데이터"))
        #expect(handoff.contains("| 1 | **F-01 실기기 검증**"))
        #expect(handoff.contains("| 완료 | ✅ **F-06 임포트 메타데이터**"))
        #expect(!handoff.contains("| 1 | **F-06 임포트 메타데이터"))
    }
}
