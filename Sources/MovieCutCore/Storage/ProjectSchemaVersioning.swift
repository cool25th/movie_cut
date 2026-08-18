import Foundation
import OSLog

/// Core-side signposter for project storage work. Reuses AppLog's subsystem
/// string so a single Instruments filter covers both App and Core intervals;
/// Core cannot link the App-only AppLog, so this is its minimal counterpart
/// (the first OSLog use in Core).
private let storageSignposter = OSSignposter(subsystem: "com.moviecut.mac", category: "storage")

// MARK: - Schema version

/// The schema version the running app reads and writes.
///
/// Bump this constant whenever a breaking change is made to the on-disk
/// `Project` JSON shape, and register a `ProjectMigration` for the previous
/// version in `ProjectSchema.migrations`. (S1 of
/// `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
///
/// - v1 → v2 (S2): `MediaAsset.originalBookmark` added. The field decodes
///   as nil for v1 projects; this migrator only bumps the version so the
///   loader recognises them and the app can re-create bookmarks on load.
/// - v2 → v3 (S7): `PlaybackSettings.autoProxyOnThermalPressure` added
///   (default true). The field decodes as true for v2 projects, so this
///   migrator only bumps the version.
/// - v3 → v4 (parity spec §6): `Clip.blendMode`, `PlaybackSettings.previewQuality`,
///   `Project.compounds`, and `Clip.compoundId` added in a single batch. Every
///   new field decodes to its default for v3 projects (`decodeIfPresent ??
///   default`), so no payload transform is needed — this migrator only bumps
///   the version so the chain reaches `currentSchemaVersion`.
/// - v4 → v5 (G-25 Inc 9): `Track.isSolo` added. The field decodes to false
///   for v4 projects, so this migrator only bumps the version.
public let currentSchemaVersion: Int = 5

/// Schema versioning + migration registry for the on-disk `Project` format.
public enum ProjectSchema {
    /// The ordered migration chain. Index 0 migrates v1 → v2, index 1 migrates
    /// v2 → v3, and so on. A project at version `n` is run through every
    /// migrator from index `n - 1` onward until it reaches `currentSchemaVersion`.
    public static let migrations: [any ProjectMigration] = [
        AddSecurityScopedBookmarkMigration(),
        AddAutoProxyOnThermalPressureMigration(),
        AddBlendPreviewQualityCompoundMigration(),
        AddTrackSoloMigration()
    ]
}

/// v4 → v5: introduces `Track.isSolo` (G-25 Inc 9 audio solo). The field is
/// optional on decode and falls back to false for v4 projects, so no payload
/// transform is needed — this migrator only bumps the schema version so the
/// chain reaches `currentSchemaVersion`.
public struct AddTrackSoloMigration: ProjectMigration {
    public let version = 5

    public init() {}

    public func migrate(_ project: inout Project) throws {
        // No payload change: `Track.isSolo` decodes to its default (false).
    }
}

/// v3 → v4: introduces `Clip.blendMode`, `PlaybackSettings.previewQuality`,
/// `Project.compounds`, and `Clip.compoundId`. All four fields are optional on
/// decode and fall back to their defaults for v3 projects, so this migrator
/// performs no payload transform — it only bumps the schema version so the chain
/// reaches `currentSchemaVersion`. (parity spec §6 / task 6.1)
public struct AddBlendPreviewQualityCompoundMigration: ProjectMigration {
    public let version = 4

    public init() {}

    public func migrate(_ project: inout Project) throws {
        // No payload change: the new fields' defaults apply on decode.
    }
}

/// v2 → v3: introduces `PlaybackSettings.autoProxyOnThermalPressure`. The field
/// is optional and v2 projects decode with the default (true), so no payload
/// transform is needed — this migrator only bumps the version so the chain
/// reaches `currentSchemaVersion`. (S7)
public struct AddAutoProxyOnThermalPressureMigration: ProjectMigration {
    public let version = 3

    public init() {}

    public func migrate(_ project: inout Project) throws {
        // No payload change: the new field's default (true) applies on decode.
    }
}

/// v1 → v2: introduces `MediaAsset.originalBookmark`. No data transformation is
/// required — the field is optional and v1 projects decode with `nil` bookmarks.
/// The app layer re-creates bookmarks on load when the file path still lives.
/// This migrator exists so the loader recognises a v1 file as needing v1→v2
/// handling and so the chain reaches `currentSchemaVersion`. (S2)
public struct AddSecurityScopedBookmarkMigration: ProjectMigration {
    public let version = 2

    public init() {}

    public func migrate(_ project: inout Project) throws {
        // No payload change: bookmarks are regenerated lazily on load by the
        // app layer when the resolved path is still reachable. v1 assets keep
        // `originalBookmark == nil`, which is a valid post-v2 state.
    }
}

// MARK: - Migration protocol

/// A single step that upgrades a decoded `Project` from one schema version to
/// the next. Migrators are stateless value/reference types registered in
/// `ProjectSchema.migrations`.
public protocol ProjectMigration: Sendable {
    /// The schema version this migrator produces (its input is `version - 1`).
    var version: Int { get }

    /// Upgrades an in-memory project decoded at the previous version.
    func migrate(_ project: inout Project) throws
}

// MARK: - Errors

/// Errors surfaced when a project file cannot be loaded because of a schema
/// mismatch. Reaches the UI via `EditorViewModel.openProject`'s
/// `lastErrorMessage = error.localizedDescription` path. (S1)
public enum ProjectMigrationError: Error, LocalizedError, Sendable, Equatable {
    /// The file was written by a newer app version (`schemaVersion` is greater
    /// than `currentSchemaVersion`). The user must update the app; migrating
    /// forward is impossible and silently downgrading would corrupt data.
    case newerThanCurrent(found: Int, current: Int)

    /// A registered migrator failed to transform the project.
    case migrationFailed(from: Int, to: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case let .newerThanCurrent(found, current):
            return """
            This project was saved by a newer version of MovieCut \
            (schema \(found); this build understands up to schema \(current)). \
            Update MovieCut to the latest version to open it.
            """
        case let .migrationFailed(from, to, message):
            return """
            This project could not be upgraded from schema \(from) to \(to): \
            \(message)
            """
        }
    }
}

// MARK: - Migration runner

/// Runs the migration chain over a decoded project, enforcing the version
/// invariant: a file newer than `currentSchemaVersion` is rejected before any
/// transformation; an older file is stepped forward to `currentSchemaVersion`.
public enum ProjectMigrationRunner {
    /// Validates `project.schemaVersion` and migrates it forward in place,
    /// using the registered `ProjectSchema.migrations` chain.
    ///
    /// - Throws: `ProjectMigrationError.newerThanCurrent` if the file is from a
    ///   newer app build; `migrationFailed` if a registered migrator throws.
    public static func migrate(_ project: inout Project) throws {
        try migrate(&project, chain: ProjectSchema.migrations)
    }

    /// Internal overload that runs an explicit chain, so the stepping logic can
    /// be exercised in tests without depending on the production registry.
    internal static func migrate(_ project: inout Project, chain: [any ProjectMigration]) throws {
        // Signpost the stepping loop (skipped entirely for current-version
        // files) so Instruments can attribute migration cost on old projects.
        let signpostState = storageSignposter.beginInterval("storage.migrate")
        defer { storageSignposter.endInterval("storage.migrate", signpostState) }
        let found = project.schemaVersion

        // Future versions: refuse. We cannot know how to read keys a newer app
        // added, and silently dropping them would corrupt the project.
        guard found <= currentSchemaVersion else {
            throw ProjectMigrationError.newerThanCurrent(found: found, current: currentSchemaVersion)
        }

        // Same or current version: nothing to do.
        guard found < currentSchemaVersion else { return }

        // Older version: step forward through the chain from index (version - 1).
        var version = found
        for migrator in chain.dropFirst(version - 1) {
            let next = migrator.version
            do {
                try migrator.migrate(&project)
            } catch {
                throw ProjectMigrationError.migrationFailed(from: version, to: next, message: "\(error)")
            }
            project.schemaVersion = next
            version = next
            if version >= currentSchemaVersion { break }
        }

        // If the chain didn't reach current (gap in registrations), fail loudly
        // rather than loading a partially-migrated project.
        guard project.schemaVersion == currentSchemaVersion else {
            throw ProjectMigrationError.migrationFailed(
                from: found,
                to: project.schemaVersion,
                message: "migration chain is incomplete (no migrator reaches schema \(currentSchemaVersion))"
            )
        }
    }
}
