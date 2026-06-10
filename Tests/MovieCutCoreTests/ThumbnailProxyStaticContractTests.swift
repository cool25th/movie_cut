import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

@Suite("Thumbnail Proxy Static Contract")
struct ThumbnailProxyStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    @Test("MediaAsset decodes legacy JSON without thumbnail or proxy data")
    func mediaAssetDecodesLegacyJSONWithoutThumbnailOrProxy() throws {
        let assetId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let json = """
        {
          "id": "\(assetId.uuidString)",
          "originalURL": "file:///tmp/source.mov",
          "kind": "video",
          "duration": 5,
          "metadata": {
            "width": 1920,
            "height": 1080,
            "fileSize": 1234
          }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(MediaAsset.self, from: json)

        #expect(decoded.id == assetId)
        #expect(decoded.thumbnailData == nil)
        #expect(decoded.proxy == nil)
        #expect(decoded.metadata.width == 1920)
    }

    @Test("MediaAsset round trip preserves thumbnail and proxy metadata")
    func mediaAssetRoundTripPreservesThumbnailAndProxy() throws {
        let asset = MediaAsset(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            originalURL: URL(fileURLWithPath: "/tmp/source.mov"),
            kind: .video,
            duration: 3,
            metadata: MediaMetadata(width: 3840, height: 2160),
            thumbnailData: Data([0x89, 0x50, 0x4E, 0x47]),
            proxy: ProxyInfo(
                proxyURL: URL(fileURLWithPath: "/tmp/proxy.mp4"),
                resolution: CGSize(width: 960, height: 540)
            )
        )

        let encoded = try JSONEncoder().encode(asset)
        let decoded = try JSONDecoder().decode(MediaAsset.self, from: encoded)

        #expect(decoded == asset)
        #expect(decoded.thumbnailData == asset.thumbnailData)
        #expect(decoded.proxy?.proxyURL == asset.proxy?.proxyURL)
    }

    @Test("ProxyGenerator plans deterministic targets and only reports ready files")
    func proxyGeneratorPlansDeterministicTargetsAndRequiresReadyFile() throws {
        let assetId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutProxyContract-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let asset = MediaAsset(
            id: assetId,
            originalURL: URL(fileURLWithPath: "/tmp/source.mov"),
            kind: .video,
            metadata: MediaMetadata(width: 3840, height: 2160)
        )
        let plan = try #require(ProxyGenerator.makeProxyPlan(for: asset, in: directory))

        #expect(plan.sourceURL == asset.originalURL)
        #expect(plan.targetURL.lastPathComponent == "\(assetId.uuidString)-proxy.mp4")
        #expect(plan.resolution.width == 960)
        #expect(plan.resolution.height == 540)
        #expect(ProxyGenerator.proxyInfoIfReady(for: plan) == nil)

        try Data([0x01]).write(to: plan.targetURL)
        let proxy = try #require(ProxyGenerator.proxyInfoIfReady(for: plan))

        #expect(proxy.proxyURL == plan.targetURL)
        #expect(proxy.resolution == plan.resolution)
        #expect(ProxyGenerator.makeProxyPlan(for: MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/audio.wav"), kind: .audio), in: directory) == nil)
    }

    @Test("MediaLibraryPanel renders thumbnails with icon fallback and proxy state")
    func mediaLibraryPanelRendersThumbnailsAndProxyState() throws {
        let source = try source("App/MovieCutMac/MediaLibraryPanel.swift")

        #expect(source.contains("asset.thumbnailData"))
        #expect(source.contains("Image(nsImage: image)"))
        #expect(source.contains("iconForKind(asset.kind)"))
        #expect(source.contains("Generate Proxy"))
        #expect(source.contains("viewModel.generateProxy(for: asset.id)"))
        #expect(source.contains("Proxy ready"))
        #expect(source.contains("No proxy"))
        #expect(source.contains("Thumbnail ready"))
        #expect(source.contains("Thumbnail missing"))
    }

    @Test("TimelineView renders thumbnail strip for visual clips and waveform for audio")
    func timelineViewRendersThumbnailStripAndKeepsWaveformPath() throws {
        let source = try source("App/MovieCutMac/TimelineView.swift")

        #expect(source.contains("thumbnailImage(for: clip)"))
        #expect(source.contains("viewModel.thumbnailData(for: clip)"))
        #expect(source.contains("clip.kind == .video || clip.kind == .image"))
        #expect(source.contains("thumbnailStrip(image)"))
        #expect(source.contains("shouldRenderWaveform(for: clip, trackKind: trackKind)"))
        #expect(source.contains("clip.kind == .audio || clip.kind == .video"))
        #expect(source.contains("viewModel.waveform(for: clip)"))
    }

    @Test("EditorViewModel enriches imported media with thumbnails and proxy command")
    func editorViewModelImportEnrichesThumbnailsAndGeneratesProxy() throws {
        let source = try source("App/MovieCutMac/EditorViewModel.swift")

        #expect(source.contains("func thumbnailData(for clip: Clip) -> Data?"))
        #expect(source.contains("func generateProxyForSelectedAsset()"))
        #expect(source.contains("func generateProxy(for assetId: UUID)"))
        #expect(source.contains("ProxyGenerator.makeProxyPlan"))
        #expect(source.contains("ProxyGenerator.generateProxy"))
        #expect(source.contains("UpdateMediaAssetCommand(asset: asset)"))
        #expect(source.contains("func enrichAssetWithThumbnail"))
        #expect(source.contains("ThumbnailGenerator.generate(for: asset"))
        #expect(source.contains("return await Self.enrichAssetWithThumbnail(asset)"))
        #expect(source.contains("ImportMediaCommand(asset: asset)"))
    }
}
