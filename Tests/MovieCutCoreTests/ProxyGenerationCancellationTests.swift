import Foundation
import MovieCutCore
import Testing

/// CA-22 2차 behavioral tests for proxy-generation cancellation.
///
/// The deterministic seam is the entry cancellation check: a task that is
/// already cancelled must refuse to start and must not touch the filesystem.
/// Mid-encode cancellation (AVAssetExportSession.cancelExport through the
/// task-cancellation handler) is exercised end-to-end by
/// `scripts/run_ca22_proxy_gate.sh` on a real fixture, where the encode runs
/// long enough for the cancel to land in flight.
@Suite("ProxyGenerationCancellation")
struct ProxyGenerationCancellationTests {
    private func videoAsset() -> MediaAsset {
        MediaAsset(
            originalURL: URL(fileURLWithPath: "/nonexistent/source-\(UUID().uuidString).mp4"),
            kind: .video,
            metadata: MediaMetadata(width: 1920, height: 1080)
        )
    }

    @Test("a cancelled task refuses to start and leaves no trace")
    func cancelledTaskDoesNotStart() async throws {
        let asset = videoAsset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca22-\(UUID().uuidString)", isDirectory: true)
        let plan = try #require(
            ProxyGenerator.makeProxyPlan(for: asset, in: directory)
        )

        let task = Task {
            try await ProxyGenerator.generateProxy(for: asset, using: plan)
        }
        // Cancel before the task gets any CPU — the entry check must throw
        // before the directory or target file is created.
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(!FileManager.default.fileExists(atPath: plan.targetURL.path))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("an already-ready proxy short-circuits without touching the source")
    func readyProxyReturnsImmediately() async throws {
        // The ready-file fast path is what makes resume cheap: switching back
        // to a previously generated resolution must not re-encode.
        let asset = videoAsset()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca22-ready-\(UUID().uuidString)", isDirectory: true)
        let plan = try #require(
            ProxyGenerator.makeProxyPlan(for: asset, in: directory)
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data([0x00]).write(to: plan.targetURL)

        let info = try await ProxyGenerator.generateProxy(for: asset, using: plan)
        #expect(info?.proxyURL == plan.targetURL)
        #expect(info?.resolution == plan.resolution)

        try? FileManager.default.removeItem(at: directory)
    }

    @Test("auto-on-import default stays on and round-trips through settings")
    func defaultSettingRoundTrip() throws {
        // The 1차 contract: default ON so a fresh user gets proxies without
        // discovering the setting; Codable keeps old projects decoding.
        let settings = PlaybackSettings()
        #expect(settings.autoGenerateProxyOnImport == true)

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        var legacy = settings
        legacy.autoGenerateProxyOnImport = false
        let data = try encoder.encode(legacy)
        let decoded = try decoder.decode(PlaybackSettings.self, from: data)
        #expect(decoded.autoGenerateProxyOnImport == false)
    }
}
