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
}
