import AVFoundation
import Foundation
import Testing

/// Behavioral coverage that the committed fixtures load as real media through
/// AVFoundation with their documented properties (Phase 0.1a).
///
/// This establishes the "real media in a test" pattern the 🟡 verification sweep
/// depends on (audio ducking, beat detection, background removal all need actual
/// decoded media, not string contracts) and guards the fixtures against drift.
@Suite("Media Fixtures")
struct MediaFixtureTests {
    @Test("all committed fixtures exist on disk")
    func fixturesExist() {
        for url in MediaFixtures.all {
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "missing fixture: \(url.lastPathComponent) — run scripts/make_fixtures.sh"
            )
        }
    }

    @Test("solid red video loads with the expected duration and resolution")
    func solidRedVideoProperties() async throws {
        let asset = AVURLAsset(url: MediaFixtures.solidRedVideo)
        let duration = try await asset.load(.duration)
        #expect(abs(CMTimeGetSeconds(duration) - 2.0) < 0.05)

        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        #expect(Int(size.width.rounded()) == 320)
        #expect(Int(size.height.rounded()) == 240)
    }

    @Test("color bars video loads as a distinct 3s clip")
    func colorBarsVideoProperties() async throws {
        let asset = AVURLAsset(url: MediaFixtures.colorBarsVideo)
        let duration = try await asset.load(.duration)
        #expect(abs(CMTimeGetSeconds(duration) - 3.0) < 0.05)
        #expect(try await !asset.loadTracks(withMediaType: .video).isEmpty)
    }

    @Test("moving subject video loads with the expected tracking fixture properties")
    func movingSubjectVideoProperties() async throws {
        let asset = AVURLAsset(url: MediaFixtures.movingSubjectVideo)
        let duration = try await asset.load(.duration)
        #expect(abs(CMTimeGetSeconds(duration) - 2.0) < 0.05)

        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let size = try await track.load(.naturalSize)
        let frameRate = try await track.load(.nominalFrameRate)
        #expect(Int(size.width.rounded()) == 320)
        #expect(Int(size.height.rounded()) == 240)
        #expect(abs(frameRate - 30) < 0.01)
    }

    @Test("tone audio loads with the expected duration and an audio track")
    func toneAudioProperties() async throws {
        let asset = AVURLAsset(url: MediaFixtures.toneAudio)
        let duration = try await asset.load(.duration)
        #expect(abs(CMTimeGetSeconds(duration) - 2.0) < 0.05)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty)
    }
}
