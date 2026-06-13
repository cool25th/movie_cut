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
    }

    /// Writes `project` and copies its media into a package at `packageURL`.
    /// Missing source files are skipped (the manifest still references them).
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

        var packaged = project
        var rewritten: [UUID: MediaAsset] = [:]
        for (id, asset) in project.mediaLibrary.assets {
            var copy = asset
            let ext = asset.originalURL.pathExtension.isEmpty ? "dat" : asset.originalURL.pathExtension
            let fileName = "\(id.uuidString).\(ext)"
            let destination = mediaURL.appendingPathComponent(fileName)

            if fileManager.fileExists(atPath: asset.originalURL.path) {
                try? fileManager.copyItem(at: asset.originalURL, to: destination)
            }

            // Store a package-relative reference; proxies are machine-local.
            copy.originalURL = URL(fileURLWithPath: "\(mediaDirectoryName)/\(fileName)")
            copy.proxy = nil
            rewritten[id] = copy
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
            resolved[id] = copy
        }
        project.mediaLibrary.assets = resolved
        return project
    }
}
