import Foundation

/// Reads and writes self-contained project packages (F-23). A `.mctemplate`
/// package bundles a project with copies of its referenced media so it can be
/// shared and re-opened on another machine, then have its media replaced.
///
/// Layout:
/// ```
/// <name>.mctemplate/
///   project.json     // Project with asset URLs rewritten to media/<id>.<ext>
///   media/<id>.<ext> // copied source files (best effort)
/// ```
/// The package is a directory so Core stays dependency-free and testable; the
/// app layer may zip it for sharing.
public enum ProjectPackage {
    /// File extension for project packages.
    public static let fileExtension = "mctemplate"

    /// Name of the media subdirectory inside a package.
    public static let mediaDirectoryName = "media"

    /// Name of the project manifest inside a package.
    public static let manifestName = "project.json"

    public enum PackageError: Error, Equatable, Sendable {
        case manifestMissing
        /// BUG-IOS-04 (external review, verified): media that could not be
        /// copied into the package — exporting anyway would produce a
        /// broken package (manifest references with no files) behind a
        /// success message. The list names the failed files.
        case mediaCopyFailed(fileNames: [String])
    }
    /// Writes `project` and copies its media into a package at `packageURL`.
    ///
    /// Fails with `PackageError.mediaCopyFailed` when any source file is
    /// missing or cannot be copied — a package with absent media is never
    /// written. The destination is removed on failure so no partial package
    /// survives.
    @discardableResult
    public static func export(
        _ project: Project,
        to packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> Project {
        if fileManager.fileExists(atPath: packageURL.path) {
            try fileManager.removeItem(at: packageURL)
        }
        let mediaURL = packageURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: mediaURL, withIntermediateDirectories: true)

        // Collect every failure; only throw once the full list is known so the
        // error names ALL missing media, not just the first.
        var failedCopies: [String] = []
        var packaged = project
        var rewritten: [UUID: MediaAsset] = [:]
        for (id, asset) in project.mediaLibrary.assets {
            var copy = asset
            let ext = asset.originalURL.pathExtension.isEmpty ? "dat" : asset.originalURL.pathExtension
            let fileName = "\(id.uuidString).\(ext)"
            let destination = mediaURL.appendingPathComponent(fileName)

            do {
                try fileManager.copyItem(at: asset.originalURL, to: destination)
            } catch {
                failedCopies.append(asset.originalURL.lastPathComponent)
                continue
            }

            // Store a package-relative reference; proxies are machine-local.
            // Bookmarks are also machine-local (security-scoped to the origin
            // device/account), so drop them too — a stale bookmark from another
            // machine would only mislead the loader. (S2)
            copy.originalURL = URL(fileURLWithPath: "\(mediaDirectoryName)/\(fileName)")
            copy.proxy = nil
            copy.originalBookmark = nil
            rewritten[id] = copy
        }

        if !failedCopies.isEmpty {
            // Never leave a partial package behind.
            try? fileManager.removeItem(at: packageURL)
            throw PackageError.mediaCopyFailed(fileNames: failedCopies.sorted())
        }

        packaged.mediaLibrary.assets = rewritten

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(packaged)
        try data.write(to: packageURL.appendingPathComponent(manifestName), options: .atomic)

        return packaged
    }

    /// Loads a project from a package, resolving media references back to
    /// absolute paths inside the package.
    public static func load(
        from packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> Project {
        let manifestURL = packageURL.appendingPathComponent(manifestName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw PackageError.manifestMissing
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var project = try decoder.decode(Project.self, from: Data(contentsOf: manifestURL))

        let mediaURL = packageURL.appendingPathComponent(mediaDirectoryName, isDirectory: true)
        var resolved: [UUID: MediaAsset] = [:]
        for (id, asset) in project.mediaLibrary.assets {
            var copy = asset
            // Stored references are media/<file>; resolve by file name.
            let fileName = asset.originalURL.lastPathComponent
            copy.originalURL = mediaURL.appendingPathComponent(fileName)
            copy.proxy = nil
            // Package media lives inside the package, so it needs no bookmark.
            copy.originalBookmark = nil
            resolved[id] = copy
        }
        project.mediaLibrary.assets = resolved
        return project
    }
}

extension ProjectPackage.PackageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "The package is missing its project manifest."
        case .mediaCopyFailed(let fileNames):
            let list = fileNames.joined(separator: ", ")
            return "Could not copy media into the package: \(list). Check that the files still exist, then try again."
        }
    }
}
