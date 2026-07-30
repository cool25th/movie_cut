import Foundation

// MARK: - Schema version

/// The schema version the running app reads and writes.
///
/// Bump this constant whenever a breaking change is made to the on-disk
/// `Project` JSON shape, and register a `ProjectMigration` for the previous
/// version in `ProjectSchema.migrations`. (S1 of
/// `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.)
public let currentSchemaVersion: Int = 1

/// Schema versioning + migration registry for the on-disk `Project` format.
public enum ProjectSchema {
    /// The ordered migration chain. Index 0 migrates v1 → v2, index 1 migrates
    /// v2 → v3, and so on. A project at version `n` is run through every
    /// migrator from index `n - 1` onward until it reaches `currentSchemaVersion`.
    ///
    /// There is currently no real migration (v1 is the only version), so the
    /// chain is empty. The first real migrator — v1 → v2, which adds
    /// security-scoped bookmarks to `MediaAsset` — is added by S2.
    public static let migrations: [any ProjectMigration] = []
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
