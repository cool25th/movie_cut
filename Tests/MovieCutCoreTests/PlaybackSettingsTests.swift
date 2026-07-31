import Foundation
import MovieCutCore
import Testing

@Suite("Playback Settings")
struct PlaybackSettingsTests {
    @Test("Project defaults proxy playback to off")
    func projectDefaultsProxyPlaybackOff() {
        let project = Project(name: "Proxy")
        #expect(project.playbackSettings.useProxyPlayback == false)
    }

    @Test("PlaybackSettings codable round trip preserves the flag")
    func codableRoundTrip() throws {
        let settings = PlaybackSettings(useProxyPlayback: true)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: encoded)
        #expect(decoded == settings)
    }

    @Test("Legacy projects without playbackSettings decode to proxy off")
    func legacyProjectWithoutPlaybackSettingsDecodesToOff() throws {
        // A project payload written before PlaybackSettings existed must still
        // decode, defaulting to proxy-off rather than throwing. We synthesize the
        // legacy shape by encoding a current project then stripping the new key.
        let project = Project(name: "Legacy source")
        var encoded = try JSONEncoder().encode(project)
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Project did not encode to a JSON object")
            return
        }
        object.removeValue(forKey: "playbackSettings")
        encoded = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Project.self, from: encoded)
        #expect(decoded.playbackSettings.useProxyPlayback == false)
    }

    @Test("SetProjectPlaybackSettingsCommand updates and inverts")
    func commandUpdatesAndInverts() async throws {
        let session = EditorSession(project: Project(name: "Proxy"))
        try await session.dispatch(SetProjectPlaybackSettingsCommand(playbackSettings: PlaybackSettings(useProxyPlayback: true)))

        var snapshot = await session.snapshot()
        #expect(snapshot.playbackSettings.useProxyPlayback == true)

        try await session.undo()
        snapshot = await session.snapshot()
        #expect(snapshot.playbackSettings.useProxyPlayback == false)

        try await session.redo()
        snapshot = await session.snapshot()
        #expect(snapshot.playbackSettings.useProxyPlayback == true)
    }

    @Test("Project codable round trip preserves playback settings")
    func projectRoundTripPreservesPlaybackSettings() throws {
        let project = Project(name: "Round Trip")
        var modified = project
        modified.playbackSettings = PlaybackSettings(useProxyPlayback: true)

        let encoded = try JSONEncoder().encode(modified)
        let decoded = try JSONDecoder().decode(Project.self, from: encoded)
        #expect(decoded.playbackSettings == modified.playbackSettings)
    }

    // MARK: - Requirement 5: PreviewQuality

    @Test("Project defaults preview quality to full")
    func projectDefaultsPreviewQualityFull() {
        let project = Project(name: "Preview")
        #expect(project.playbackSettings.previewQuality == .full)
    }

    @Test("A PlaybackSettings JSON without previewQuality decodes to .full")
    func playbackSettingsWithoutPreviewQualityDecodesToFull() throws {
        // Requirement 5.3 + 4.6: a payload written before the previewQuality key
        // existed must decode without throwing and default to .full, so existing
        // projects render identically.
        let preR5JSON = """
        { "useProxyPlayback": false, "proxyResolution": "p540", "autoProxyOnThermalPressure": true }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(PlaybackSettings.self, from: preR5JSON)
        #expect(settings.previewQuality == .full)
        // The other keys are untouched by the new field.
        #expect(settings.useProxyPlayback == false)
        #expect(settings.proxyResolution == .p540)
        #expect(settings.autoProxyOnThermalPressure == true)
    }

    @Test("The default quality is not encoded, so a no-op project is unchanged")
    func defaultPreviewQualityIsOmittedFromEncoding() throws {
        // Encoding only when not default keeps project files byte-stable for
        // users who never touched the dial. The encoded JSON must NOT contain a
        // previewQuality key.
        let settings = PlaybackSettings()
        let encoded = try JSONEncoder().encode(settings)
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("PlaybackSettings did not encode to a JSON object")
            return
        }
        #expect(object["previewQuality"] == nil)
    }

    @Test("A non-default preview quality round-trips through JSON")
    func nonDefaultPreviewQualityRoundTrips() throws {
        let settings = PlaybackSettings(useProxyPlayback: false, previewQuality: .half)
        let encoded = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(PlaybackSettings.self, from: encoded)
        #expect(decoded == settings)
        #expect(decoded.previewQuality == .half)

        // The key must be present in the encoded payload.
        guard let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("PlaybackSettings did not encode to a JSON object")
            return
        }
        #expect(object["previewQuality"] as? String == "half")
    }

    @Test("An unknown previewQuality raw value falls back to .full rather than throwing")
    func unknownPreviewQualityFallsBackToFull() throws {
        // Forward compatibility: if a case is removed in the future, an old file
        // referencing it must still load, defaulting to full.
        let json = #"{ "useProxyPlayback": false, "previewQuality": "ultraHD" }"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(PlaybackSettings.self, from: json)
        #expect(settings.previewQuality == .full)
    }
}
