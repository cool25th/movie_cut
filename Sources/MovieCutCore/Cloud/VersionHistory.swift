import Foundation

/// A JSON snapshot of a project at a point in time.
public struct ProjectVersion: Codable, Sendable, Identifiable, Equatable {
    /// The version identifier.
    public var id: UUID

    /// The version creation time.
    public var timestamp: Date

    /// User-visible version description.
    public var description: String

    /// JSON-encoded project snapshot.
    public var snapshot: Data

    /// Creates a project version.
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        description: String,
        snapshot: Data
    ) {
        self.id = id
        self.timestamp = timestamp
        self.description = description
        self.snapshot = snapshot
    }
}

/// In-memory project version history.
public final class VersionHistory: @unchecked Sendable {
    /// Stored project versions.
    public private(set) var versions: [ProjectVersion]

    /// Maximum number of versions retained.
    public let maxVersions: Int

    /// Current version count.
    public var count: Int {
        versions.count
    }

    /// Creates a version history.
    public init(versions: [ProjectVersion] = [], maxVersions: Int = 50) {
        self.maxVersions = max(1, maxVersions)
        self.versions = Array(versions.suffix(self.maxVersions))
    }

    /// Encodes and stores a project snapshot.
    public func save(_ project: Project, description: String) throws {
        let snapshot = try JSONEncoder().encode(project)
        let version = ProjectVersion(description: description, snapshot: snapshot)

        versions.append(version)
        trimVersions()
    }

    /// Restores a project from a stored version.
    public func restore(version: ProjectVersion) throws -> Project {
        try JSONDecoder().decode(Project.self, from: version.snapshot)
    }

    private func trimVersions() {
        let overflow = versions.count - maxVersions
        if overflow > 0 {
            versions.removeFirst(overflow)
        }
    }
}
