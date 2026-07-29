import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the proxy resolution picker (benchmark B-I7's remaining
/// requirement: "해상도 선택").
@Suite("ProxyResolution")
struct ProxyResolutionTests {
    private func videoAsset(width: Int? = 3840, height: Int? = 2160) -> MediaAsset {
        MediaAsset(
            originalURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            kind: .video,
            metadata: MediaMetadata(width: width, height: height)
        )
    }

    @Test("every resolution maps to a distinct max dimension and label")
    func casesAreDistinct() {
        let dimensions = Set(ProxyResolution.allCases.map(\.maxDimension))
        let labels = Set(ProxyResolution.allCases.map(\.shortLabel))
        #expect(dimensions.count == ProxyResolution.allCases.count)
        #expect(labels.count == ProxyResolution.allCases.count)
        // 720p is what CapCut recommends, and exactly one option may say so.
        #expect(ProxyResolution.allCases.filter(\.isRecommended) == [.p720])
    }

    @Test("default stays at the size proxies were hardwired to")
    func defaultPreservesLegacyOutput() {
        // Generation used AVAssetExportPreset960x540 before the picker existed.
        // Defaulting anywhere else would change the output of every project
        // that never touches the setting.
        #expect(ProxyResolution.default == .p540)
        #expect(ProxyResolution.default.presetSize == CGSize(width: 960, height: 540))
    }

    @Test("each resolution plans a distinct file so switching regenerates")
    func distinctTargetsPerResolution() throws {
        // Before the token existed every resolution planned the same path, so
        // proxyInfoIfReady returned the previously generated file and changing
        // the setting silently did nothing.
        let asset = videoAsset()
        let directory = URL(fileURLWithPath: "/tmp/proxies")
        var paths: Set<String> = []
        for resolution in ProxyResolution.allCases {
            let plan = try #require(
                ProxyGenerator.makeProxyPlan(for: asset, in: directory, proxyResolution: resolution)
            )
            paths.insert(plan.targetURL.lastPathComponent)
            #expect(plan.targetURL.lastPathComponent.contains(resolution.shortLabel))
        }
        #expect(paths.count == ProxyResolution.allCases.count)
    }

    @Test("planned resolution scales the source down to the selection")
    func plannedResolutionFollowsSelection() throws {
        let asset = videoAsset(width: 3840, height: 2160)
        let directory = URL(fileURLWithPath: "/tmp/proxies")

        for resolution in ProxyResolution.allCases {
            let plan = try #require(
                ProxyGenerator.makeProxyPlan(for: asset, in: directory, proxyResolution: resolution)
            )
            let longest = max(plan.resolution.width, plan.resolution.height)
            #expect(
                abs(longest - resolution.maxDimension) < 1.0,
                "\(resolution.shortLabel): longest side \(longest) should match \(resolution.maxDimension)"
            )
            // 16:9 source must stay 16:9.
            #expect(abs(plan.resolution.width / plan.resolution.height - 16.0 / 9.0) < 0.01)
        }
    }

    @Test("a source smaller than the selection is not upscaled")
    func smallSourceIsNotUpscaled() throws {
        let asset = videoAsset(width: 320, height: 240)
        let plan = try #require(
            ProxyGenerator.makeProxyPlan(
                for: asset,
                in: URL(fileURLWithPath: "/tmp/proxies"),
                proxyResolution: .p1080
            )
        )
        #expect(plan.resolution == CGSize(width: 320, height: 240))
    }

    @Test("playback settings round-trip the resolution and default when absent")
    func settingsCodableMigration() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let explicit = PlaybackSettings(useProxyPlayback: true, proxyResolution: .p1080)
        let decoded = try decoder.decode(PlaybackSettings.self, from: encoder.encode(explicit))
        #expect(decoded == explicit)

        // A project saved before the picker existed carries no key at all.
        let legacy = Data(#"{"useProxyPlayback":true}"#.utf8)
        let migrated = try decoder.decode(PlaybackSettings.self, from: legacy)
        #expect(migrated.useProxyPlayback)
        #expect(migrated.proxyResolution == .default)
    }

    @Test("changing resolution is undoable through the command path")
    func resolutionChangeIsUndoable() throws {
        var project = Project(name: "P")
        #expect(project.playbackSettings.proxyResolution == .default)

        var updated = project.playbackSettings
        updated.proxyResolution = .p720
        let command = SetProjectPlaybackSettingsCommand(playbackSettings: updated)
        let result = try command.apply(to: &project)
        #expect(project.playbackSettings.proxyResolution == .p720)

        _ = try command.invert(from: result).apply(to: &project)
        #expect(project.playbackSettings.proxyResolution == .default)
    }
}
