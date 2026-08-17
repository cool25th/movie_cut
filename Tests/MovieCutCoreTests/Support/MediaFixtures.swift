import Foundation

/// Resolves the committed media fixtures under `Tests/Fixtures/` (Phase 0.1a).
///
/// The path is derived from this source file's location via `#filePath`, so it
/// works regardless of the test runner's working directory (Xcode and SwiftPM
/// differ). Regenerate the files with `scripts/make_fixtures.sh`.
enum MediaFixtures {
    static let directory: URL = URL(filePath: #filePath)   // .../Tests/MovieCutCoreTests/Support/MediaFixtures.swift
        .deletingLastPathComponent()                       // Support/
        .deletingLastPathComponent()                       // MovieCutCoreTests/
        .deletingLastPathComponent()                       // Tests/
        .appending(path: "Fixtures")

    static func url(_ name: String) -> URL { directory.appending(path: name) }

    static let solidRedVideo = url("solid_red_320x240_2s_30fps.mp4")
    static let colorBarsVideo = url("bars_320x240_3s_30fps.mp4")
    static let movingSubjectVideo = url("moving_subject_320x240_2s_30fps.mp4")
    static let movingSubjectOccludedVideo = url("moving_subject_occluded_320x240_3s_30fps.mp4")
    static let toneAudio = url("tone_440hz_2s_mono.wav")
    static let blueSwatchImage = url("swatch_blue_64x64.png")

    static let all: [URL] = [solidRedVideo, colorBarsVideo, movingSubjectVideo, movingSubjectOccludedVideo, toneAudio, blueSwatchImage]
}
