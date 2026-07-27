import XCTest

/// Step 1 actual-app E2E for the project-composition Preview path
/// (`docs/CAPCUT_CORE_EDITING_REPAIR_HANDOFF_20260727.md`).
///
/// The handoff forbids source-string StaticContract tests as completion
/// evidence and requires an actual-app test that proves the main Preview
/// consumes the project composition (not the selected clip's raw asset).
/// This suite launches the real app and drives the DEBUG
/// `runPreviewProjectCompositionUITestScenario` harness, then asserts the
/// serialized acceptance criteria written to `MOVIECUT_UITEST_RESULT`:
///
/// - `player_item_installed=1` — composition installed an AVPlayerItem
///   instead of silently clearing on a build failure.
/// - `composition_error=none` — any build error is surfaced (not swallowed).
/// - `boundary_crossing=1` — playhead advances across the first clip end.
/// - `selection_keeps_time=1` — selection change does not reset time to 0.
/// - `stale_guard_held=1` — the generation token advanced across a burst of
///   rebuilds and the engine remained on a clean item.
final class PreviewProjectCompositionUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private var fixturesDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()   // MovieCutMacUITests/
            .deletingLastPathComponent()   // App/
            .deletingLastPathComponent()   // repo root
            .appending(path: "Tests/Fixtures")
    }

    private var tempDirectory: URL {
        URL(filePath: NSTemporaryDirectory())
            .appending(path: "moviecut-preview-uitest-\(UUID().uuidString)")
    }

    /// Runs the harness and returns the parsed `key=value` status string.
    private func runHarnessStatus(
        importPaths: [String],
        extraEnv: [String: String] = [:]
    ) throws -> [String: String] {
        let outputDirectory = tempDirectory
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        let resultPath = outputDirectory.appending(path: "result.txt").path

        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_UITEST"] = "1"
        app.launchEnvironment["MOVIECUT_UITEST_IMPORT"] = importPaths.joined(separator: ",")
        app.launchEnvironment["MOVIECUT_UITEST_RESULT"] = resultPath
        app.launchEnvironment["MOVIECUT_UITEST_QUIT"] = "1"
        for (key, value) in extraEnv {
            app.launchEnvironment[key] = value
        }
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)

        // The harness writes the result file and then terminates (QUIT=1).
        let deadline = Date().addingTimeInterval(90)
        var statusText: String?
        while Date() < deadline {
            if let data = try? String(contentsOfFile: resultPath, encoding: .utf8),
               !data.isEmpty {
                statusText = data
                break
            }
            usleep(500_000)
        }

        guard let statusText else {
            XCTFail("harness did not write a result to \(resultPath)")
            return [:]
        }

        var parsed: [String: String] = [:]
        for token in statusText.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                parsed[String(parts[0])] = String(parts[1])
            }
        }
        return parsed
    }

    func testPreviewConsumesProjectComposition() throws {
        // Two video fixtures + one audio fixture so the composition exercises
        // a multi-clip timeline and the audio mix path.
        let videoA = fixturesDirectory.appending(path: "solid_red_320x240_2s_30fps.mp4")
        let videoB = fixturesDirectory.appending(path: "bars_320x240_3s_30fps.mp4")
        let audio = fixturesDirectory.appending(path: "tone_440hz_2s_mono.wav")
        for fixture in [videoA, videoB, audio] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fixture.path),
                "missing fixture \(fixture.lastPathComponent); run scripts/make_fixtures.sh"
            )
        }

        let status = try runHarnessStatus(
            importPaths: [videoA.path, videoB.path, audio.path],
            extraEnv: ["MOVIECUT_UITEST_PREVIEW_PROJECT": "1"]
        )

        XCTAssertEqual(status["player_item_installed"], "1",
                       "composition did not install a player item: \(status)")
        XCTAssertEqual(status["composition_error"], "none",
                       "composition build surfaced an error: \(status)")
        XCTAssertEqual(status["boundary_crossing"], "1",
                       "playhead did not advance across the first clip end: \(status)")
        XCTAssertEqual(status["selection_keeps_time"], "1",
                       "selection change reset playback time to zero: \(status)")
        XCTAssertEqual(status["stale_guard_held"], "1",
                       "generation token / stale-rebuild guard regressed: \(status)")
        XCTAssertEqual(status["error"], "none",
                       "harness reported an error: \(status)")
    }
}
