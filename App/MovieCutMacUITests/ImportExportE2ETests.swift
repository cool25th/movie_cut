import XCTest

/// App-level end-to-end safety net (Phase 0.1c).
///
/// Unlike the static-contract suite — which only checks that strings exist in
/// source — this launches the real app and drives the real
/// import → timeline → export pipeline through the DEBUG launch harness, then
/// asserts a genuine exported movie file appears on disk. If import or export
/// regresses at runtime (the failure mode that hid the drag-and-drop bug), the
/// artifact never materializes and this fails.
final class ImportExportE2ETests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private var fixturesDirectory: URL {
        URL(filePath: #filePath)               // .../App/MovieCutMacUITests/ImportExportE2ETests.swift
            .deletingLastPathComponent()       // MovieCutMacUITests/
            .deletingLastPathComponent()       // App/
            .deletingLastPathComponent()       // repo root
            .appending(path: "Tests/Fixtures")
    }

    func testImportThenExportProducesAMovieFile() throws {
        let fixture = fixturesDirectory.appending(path: "solid_red_320x240_2s_30fps.mp4")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixture.path),
            "missing fixture; run scripts/make_fixtures.sh"
        )

        let outputDirectory = URL(filePath: NSTemporaryDirectory())
            .appending(path: "moviecut-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let output = outputDirectory.appending(path: "e2e_export.mp4")

        let app = XCUIApplication()
        app.launchEnvironment["MOVIECUT_UITEST"] = "1"
        app.launchEnvironment["MOVIECUT_UITEST_IMPORT"] = fixture.path
        app.launchEnvironment["MOVIECUT_UITEST_EXPORT"] = output.path
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach the foreground")

        // Poll for the real export artifact produced by the import→export pipeline.
        let deadline = Date().addingTimeInterval(120)
        var exportedSize = 0
        while Date() < deadline {
            if let size = try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int,
               size > 0 {
                exportedSize = size
                break
            }
            usleep(500_000)
        }

        XCTAssertGreaterThan(
            exportedSize, 0,
            "no export artifact at \(output.path) — import or export regressed at runtime"
        )

        // Secondary signal: the harness status text reports no error.
        let status = app.staticTexts["moviecut.status"]
        if status.waitForExistence(timeout: 5) {
            XCTAssertTrue(
                status.label.contains("error=none"),
                "harness reported an error: \(status.label)"
            )
        }
    }

    func testAppLaunchesToForeground() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not launch")
    }
}
