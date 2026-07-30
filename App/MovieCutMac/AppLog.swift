import Foundation
import OSLog

/// Structured logging categories for MovieCut's core subsystems.
///
/// Before S10, only the filmstrip path used `OSLog` (one "TimelineFilmstrip"
/// category). Production failures in export, playback, and import went
/// unlogged, so a post-release regression had no on-device trace. This catalog
/// adds one `Logger` per subsystem under a single bundle subsystem, so
/// `log stream --predicate 'subsystem == "com.moviecut.mac"'` captures all of
/// them and `--predicate 'category == "export"'` narrows to one. (S10 of
/// `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
///
/// Privacy: these log the *what failed*, never media content or user data. No
/// PII, file paths beyond a basename, or audio/video payloads are logged.
/// MetricKit / remote telemetry are intentionally NOT introduced — the app's
/// privacy positioning is fully on-device, so this is local diagnostic logging
/// only.
enum AppLog {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.moviecut.mac"

    /// Timeline playback / composition build failures.
    static let playback = Logger(subsystem: subsystem, category: "playback")
    /// Export pipeline failures (session creation, composition, encoding).
    static let export = Logger(subsystem: subsystem, category: "export")
    /// Media import / project load failures (probe, decode, bookmark).
    static let importLog = Logger(subsystem: subsystem, category: "import")
    /// On-device AI providers (speech transcription, analysis).
    static let ai = Logger(subsystem: subsystem, category: "ai")
}
