import Foundation

/// Loads and saves MovieCut projects as JSON documents.
public actor ProjectStore {
    private let autosaveDirectory: URL?

    /// The most recent autosave-load failure, if the recovery file existed but
    /// could not be decoded. Set by `loadAutosaveIfAvailable` when it detects a
    /// corrupt recovery file; cleared on a successful load or `clearAutosave`.
    /// The launch flow reads this to tell the user their recovery file was
    /// damaged (previously this was silently swallowed via `try?`).
    public private(set) var lastAutosaveLoadFailure: FileOperationError?

    /// Creates a project store using the default autosave location
    /// (Application Support/MovieCut).
    public init() {
        self.autosaveDirectory = Self.defaultAutosaveDirectory()
    }

    /// Creates a project store with an explicit autosave directory (tests), or
    /// `nil` to disable crash-recovery autosave.
    public init(autosaveDirectory: URL?) {
        self.autosaveDirectory = autosaveDirectory
    }

    private static func defaultAutosaveDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MovieCut", isDirectory: true)
    }

    /// SURV-01 (review 2026-08-26): the managed media-imports root —
    /// Application Support is never OS-purged (unlike temporaryDirectory), so
    /// imported originals survive alongside the recovery project that
    /// references them. iOS copies photo-picker imports beneath this root;
    /// Mac keeps its bookmark-based originals.
    public static func defaultImportsDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MovieCut/Imports", isDirectory: true)
    }

    private var autosaveURL: URL? {
        autosaveDirectory?.appendingPathComponent("recovery.moviecut")
    }

    /// Writes the project to the crash-recovery autosave location (atomic).
    public func saveAutosave(_ project: Project) async throws {
        guard let url = autosaveURL else { return }
        try await save(project, to: url)
    }

    /// Returns the autosaved project if a recovery file exists. Its presence on
    /// launch indicates the previous session did not exit cleanly.
    ///
    /// If the recovery file exists but is corrupt (decode fails), this records
    /// the classified failure in `lastAutosaveLoadFailure` and removes the
    /// damaged file so a broken recovery state can't trap the user on every
    /// launch. Returns `nil` in that case — there is no project to recover —
    /// but the caller can surface the failure reason. Previously this path used
    /// `try?` and silently dropped the error, leaving the corrupt file on disk
    /// indefinitely.
    public func loadAutosaveIfAvailable() async -> Project? {
        guard let url = autosaveURL, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            var project = try await load(from: url)
            // SURV-01 2차: a restored project may carry absolute import URLs
            // from a previous container (reinstall/restore) — resolve them
            // through the managed root before the app treats them as
            // missing.
            Self.rebaseManagedImports(
                in: &project,
                importsRoot: Self.defaultImportsDirectory()
            )
            lastAutosaveLoadFailure = nil
            return project
        } catch {
            let classified = FileOperationError.classify(error)
            lastAutosaveLoadFailure = classified
            // Remove the corrupt recovery file so it doesn't resurface every
            // launch; the user has been told (via lastAutosaveLoadFailure).
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Whether a recovery autosave is present.
    public func hasAutosave() -> Bool {
        guard let url = autosaveURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Removes the recovery autosave. Call on a clean quit or after a successful
    /// manual save so the next launch does not offer stale recovery.
    public func clearAutosave() {
        guard let url = autosaveURL else { return }
        try? FileManager.default.removeItem(at: url)
        lastAutosaveLoadFailure = nil
    }

    /// Saves a project to a JSON file using a temp-file replacement flow.
    public func save(_ project: Project, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(project)
        let fileManager = FileManager.default
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: [.atomic])

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Loads a project from a JSON file, then validates and migrates its schema.
    ///
    /// Decoding itself remains lenient: Swift's `JSONDecoder` ignores unknown
    /// keys, so a project with extra future keys still decodes. The schema
    /// guard then runs:
    /// - `schemaVersion > currentSchemaVersion` → throws
    ///   `ProjectMigrationError.newerThanCurrent` (the user must update the
    ///   app; we never silently drop keys a newer app wrote).
    /// - `schemaVersion < currentSchemaVersion` → runs the migration chain in
    ///   `ProjectSchema` forward to `currentSchemaVersion`.
    /// - equal → loaded as-is.
    ///
    /// See S1 of `docs/PRO_SPEC_GAP_WORKORDER_20260730.md`.
    public func load(from url: URL) async throws -> Project {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(Project.self, from: data)
        try ProjectMigrationRunner.migrate(&project)
        // Compound-clip structural validation (Requirement 7.6): enforce
        // no-nesting and resolved references after decode + migration so a
        // damaged file is rejected explicitly instead of rendered half-flat.
        try project.validateCompounds()
        return project
    }

    /// SURV-01 2차: re-points managed-import media at their CURRENT
    /// location. The iOS container's absolute Application Support path
    /// changes across reinstalls and device restores, so a project decoded
    /// with a stale absolute URL must resolve through its relative
    /// reference. Two strategies per asset, only when the absolute path is
    /// dead:
    ///
    /// 1. `managedImportPath` — resolve it against the imports root.
    /// 2. Legacy (pre-2차 saves carry absolute URLs only): match the
    ///    `…/MovieCut/Imports/<projectId>/<file>` suffix of the dead path and
    ///    re-resolve it against the CURRENT root, stamping the relative
    ///    reference for next time.
    ///
    /// Assets that survive neither stay as-is — the app layer surfaces them
    /// as missing media for the relink flow. Returns the rebased asset count.
    @discardableResult
    public static func rebaseManagedImports(
        in project: inout Project,
        importsRoot: URL?
    ) -> Int {
        guard let importsRoot else { return 0 }
        let fileManager = FileManager.default
        var rebased = 0
        for assetId in project.mediaLibrary.assets.keys {
            guard var asset = project.mediaLibrary.assets[assetId] else { continue }
            if fileManager.fileExists(atPath: asset.originalURL.path) { continue }

            if let relative = asset.managedImportPath {
                let candidate = importsRoot.appendingPathComponent(relative)
                if fileManager.fileExists(atPath: candidate.path) {
                    asset.originalURL = candidate
                    project.mediaLibrary.assets[assetId] = asset
                    rebased += 1
                    continue
                }
            }

            // Legacy suffix match: everything after the imports root marker
            // in the dead absolute path is `<projectId>/<file>` by
            // staged-import construction.
            let marker = "/MovieCut/Imports/"
            if let range = asset.originalURL.path.range(of: marker) {
                let suffix = String(asset.originalURL.path[range.upperBound...])
                let components = suffix.split(separator: "/")
                if components.count >= 2 {
                    let candidate = importsRoot.appendingPathComponent(String(suffix))
                    if fileManager.fileExists(atPath: candidate.path) {
                        asset.originalURL = candidate
                        asset.managedImportPath = String(suffix)
                        project.mediaLibrary.assets[assetId] = asset
                        rebased += 1
                    }
                }
            }
        }
        return rebased
    }

    /// SURV-01 2차: the stale-imports cleanup policy. Every staged import
    /// lives under `<importsRoot>/<projectId>/`; projects the user abandoned
    /// (no recovery file, never saved) leave their directories behind
    /// forever. A per-project directory is removable when it is NOT
    /// referenced by a live project (`keepingProjectIds`) AND has not been
    /// touched for `olderThanDays` — the grace period covers a project the
    /// user is about to recover on this very launch. Best-effort: failures
    /// are skipped, never thrown. Returns the removed directory count.
    @discardableResult
    public static func cleanupOrphanedImports(
        importsRoot: URL?,
        keepingProjectIds: Set<UUID>,
        olderThanDays: Int = 7
    ) -> Int {
        guard let importsRoot,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: importsRoot,
                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]
              )
        else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        var removed = 0
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  let projectId = UUID(uuidString: entry.lastPathComponent),
                  !keepingProjectIds.contains(projectId),
                  let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified < cutoff
            else { continue }
            if (try? FileManager.default.removeItem(at: entry)) != nil {
                removed += 1
            }
        }
        return removed
    }
}
