import CoreGraphics
import Foundation
import Testing
@testable import MovieCutCore

/// Thumbnail/proxy persistence behavior (the former wiring checks moved out —
/// the app-side thumbnail/fallback/proxy surfaces are covered by the G-04
/// filmstrip e2e sections and the proxy preset e2e in run_e2e_export.sh).
@Suite("Thumbnail Proxy")
struct ThumbnailProxyStaticContractTests {

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
        // The target carries the resolution token so proxies of different sizes
        // do not collide on disk; without it `proxyInfoIfReady` would return a
        // previously generated file and changing the resolution setting would
        // silently do nothing. `ProxyResolutionTests` covers the switch itself.
        #expect(
            plan.targetURL.lastPathComponent
                == "\(assetId.uuidString)-proxy-\(ProxyResolution.default.shortLabel).mp4"
        )
        #expect(plan.resolution.width == 960)
        #expect(plan.resolution.height == 540)
        #expect(ProxyGenerator.proxyInfoIfReady(for: plan) == nil)

        try Data([0x01]).write(to: plan.targetURL)
        let proxy = try #require(ProxyGenerator.proxyInfoIfReady(for: plan))

        #expect(proxy.proxyURL == plan.targetURL)
        #expect(proxy.resolution == plan.resolution)
        #expect(ProxyGenerator.makeProxyPlan(for: MediaAsset(originalURL: URL(fileURLWithPath: "/tmp/audio.wav"), kind: .audio), in: directory) == nil)
    }
}
