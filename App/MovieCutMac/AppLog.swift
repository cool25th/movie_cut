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
/// Each category also exposes an `OSSignposter` so Instruments can profile the
/// hot paths (export encode, composition build, seek, proxy, project open,
/// migration). Signposts share the category so a single Instruments filter
/// covers both log lines and intervals for a subsystem.
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

    /// One `OSSignposter` per subsystem, sharing its category so Instruments
    /// grouping matches the log lines. Use `withIntervalSignpost(...)` or the
    /// `makeSignpost` helper to time a hot path; signposts compile to a no-op
    /// overhead in shipping builds.
    enum Signpost {
        static let playback = OSSignposter(subsystem: subsystem, category: "playback")
        static let export = OSSignposter(subsystem: subsystem, category: "export")
        static let importLog = OSSignposter(subsystem: subsystem, category: "import")
        static let ai = OSSignposter(subsystem: subsystem, category: "ai")
    }

    /// Times a synchronous or async closure under a named signpost interval.
    /// The interval is always ended — including on a thrown error — so failed
    /// runs still show up in Instruments rather than leaving an open interval.
    ///
    /// Example: `await AppLog.time(.export, "export.encode") { try await engine.export(...) }`
    static func time<T>(
        _ category: SignpostCategory,
        _ name: StaticString,
        body: () async throws -> T
    ) async rethrows -> T {
        let signposter = category.signposter
        let state = signposter.beginInterval(name)
        do {
            let value = try await body()
            signposter.endInterval(name, state)
            return value
        } catch {
            signposter.endInterval(name, state, "\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// The categories that expose a signposter. Bridges a `.playback` /
    /// `.export` / `.importLog` / `.ai` enum case to its `OSSignposter`.
    enum SignpostCategory {
        case playback, export, importLog, ai

        var signposter: OSSignposter {
            switch self {
            case .playback: return Signpost.playback
            case .export: return Signpost.export
            case .importLog: return Signpost.importLog
            case .ai: return Signpost.ai
            }
        }
    }
}
