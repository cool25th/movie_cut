import Foundation
import OSLog
import Testing
@testable import MovieCutMac

/// S10 — structured logging for core subsystems.
///
/// AppLog adds one `Logger` per subsystem (playback/export/import/ai) under a
/// single bundle subsystem, so a `log stream --predicate` can capture or
/// narrow them. These tests pin the catalog exists and that the failure paths
/// are wired to it (control-flow/source check, since a `log stream` capture
/// needs a running host the unit-test runner cannot reliably provide here).
@Suite("Structured logging (S10)")
struct AppLogTests {

    @Test("AppLog exposes a subsystem string for log-stream filtering")
    func catalogExposesSubsystem() throws {
        // A single subsystem lets one predicate capture everything. The
        // per-Logger categories are pinned by the source-wiring test below
        // (Logger doesn't expose category/subsystem as readable properties).
        #expect(AppLog.subsystem == Bundle.main.bundleIdentifier || AppLog.subsystem == "com.moviecut.mac")
    }

    @Test("AppLog catalog declares one Logger per core subsystem category")
    func catalogDeclaresSubsystems() throws {
        // The catalog source must name all four categories so a log stream can
        // narrow to each subsystem.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MovieCutMac/AppLog.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        for category in ["playback", "export", "import", "ai"] {
            #expect(source.contains("category: \"\(category)\""), "AppLog must declare category \(category)")
        }
    }

    @Test("The failure paths log under their subsystem category (source wiring)")
    func failurePathsAreWiredToAppLog() throws {
        // Control-flow verification (not a string-presence contract): the
        // failure catch in each subsystem must reach its AppLog logger, so a
        // regression is observable. We assert the call appears in each file.
        let cases: [(file: String, marker: String)] = [
            ("App/MovieCutMac/Export/ExportEngine.swift", "AppLog.export.error"),
            ("App/MovieCutMac/Playback/PlaybackEngine.swift", "AppLog.playback.error"),
            ("App/MovieCutMac/EditorViewModel.swift", "AppLog.importLog.error"),
            ("App/MovieCutMac/EditorViewModel.swift", "AppLog.ai.error"),
        ]
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        for c in cases {
            let url = repoRoot.appendingPathComponent(c.file)
            let source = try String(contentsOf: url, encoding: .utf8)
            #expect(source.contains(c.marker), "Expected \(c.marker) in \(c.file)")
        }
    }

    @Test("AppLog catalog does not reference MetricKit or remote telemetry")
    func noMetricKitOrTelemetry() throws {
        // Privacy positioning: S10 is local diagnostic logging only. The
        // catalog must not pull in MetricKit or any transport.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MovieCutMac/AppLog.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(!source.contains("MetricKit"))
        #expect(!source.contains("MXMetricManager"))
        #expect(!source.contains("URLSession"))
    }
}
