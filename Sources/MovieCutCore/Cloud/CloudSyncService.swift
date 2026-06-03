import Combine
import Foundation

/// Cloud synchronization lifecycle state.
public enum SyncStatus: Sendable {
    case idle
    case syncing
    case synced
    case conflict
    case offline
    case failed(Error)
}

/// Conflict resolution behavior for local and remote project versions.
public enum ConflictStrategy: Sendable {
    case keepLocal
    case keepRemote
    case merge
}

/// Lightweight metadata for a synced project document.
public struct CloudProjectInfo: Sendable, Equatable {
    /// Project name without the `.moviecut` extension.
    public var name: String

    /// Last known modification date from the backing file.
    public var modifiedDate: Date

    /// Backing file size in bytes.
    public var size: Int

    /// Creates cloud project metadata.
    public init(name: String, modifiedDate: Date, size: Int) {
        self.name = name
        self.modifiedDate = modifiedDate
        self.size = size
    }
}

/// iCloud Drive-backed project synchronization service with local fallback storage.
@MainActor
public final class CloudSyncService: ObservableObject, Sendable {
    /// Current synchronization state.
    @Published public private(set) var status: SyncStatus

    /// Date of the most recent successful sync.
    @Published public private(set) var lastSyncDate: Date?

    private let fileManager: FileManager
    private let projectStore: ProjectStore

    /// Creates a cloud synchronization service.
    public init(
        status: SyncStatus = .idle,
        lastSyncDate: Date? = nil,
        projectStore: ProjectStore = ProjectStore(),
        fileManager: FileManager = .default
    ) {
        self.status = status
        self.lastSyncDate = lastSyncDate
        self.projectStore = projectStore
        self.fileManager = fileManager
    }

    /// Returns whether iCloud Drive storage is currently available.
    public func isCloudAvailable() -> Bool {
        fileManager.ubiquityIdentityToken != nil && iCloudDocumentStorageURL() != nil
    }

    /// Serializes and writes a project to iCloud Drive, or Application Support when iCloud is unavailable.
    public func sync(project: Project) async throws {
        status = .syncing

        do {
            let fileURL = try projectFileURL(name: project.name, createDirectory: true)
            try await projectStore.save(project, to: fileURL)
            lastSyncDate = Date()
            status = .synced
        } catch {
            status = .failed(error)
            throw error
        }
    }

    /// Lists synced project documents from iCloud Drive, or local fallback storage.
    public func listRemoteProjects() async throws -> [CloudProjectInfo] {
        do {
            let directoryURL = try movieCutDirectoryURL(create: false)
            guard fileManager.fileExists(atPath: directoryURL.path) else {
                return []
            }

            let fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            return try fileURLs.compactMap { fileURL in
                guard fileURL.pathExtension == "moviecut" else {
                    return nil
                }

                let resourceValues = try fileURL.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isRegularFileKey
                ])

                guard resourceValues.isRegularFile ?? true else {
                    return nil
                }

                return CloudProjectInfo(
                    name: fileURL.deletingPathExtension().lastPathComponent,
                    modifiedDate: resourceValues.contentModificationDate ?? .distantPast,
                    size: resourceValues.fileSize ?? 0
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
        } catch {
            status = .failed(error)
            throw error
        }
    }

    /// Downloads and deserializes a synced project document.
    public func download(name: String) async throws -> Project {
        status = .syncing

        do {
            let fileURL = try projectFileURL(name: name, createDirectory: false)
            let project = try await projectStore.load(from: fileURL)
            lastSyncDate = Date()
            status = .synced
            return project
        } catch {
            status = .failed(error)
            throw error
        }
    }

    /// Resolves a local/remote conflict according to the selected strategy.
    public func resolveConflict(local: Project, remote: Project, strategy: ConflictStrategy) -> Project {
        switch strategy {
        case .keepLocal:
            return local
        case .keepRemote:
            return remote
        case .merge:
            return mergedProject(local: local, remote: remote)
        }
    }

    private func projectFileURL(name: String, createDirectory: Bool) throws -> URL {
        try movieCutDirectoryURL(create: createDirectory)
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension("moviecut")
    }

    private func movieCutDirectoryURL(create: Bool) throws -> URL {
        let directoryURL = try documentStorageURL(create: create)
            .appendingPathComponent("MovieCut", isDirectory: true)

        if create {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func documentStorageURL(create: Bool) throws -> URL {
        if let iCloudURL = iCloudDocumentStorageURL() {
            if create {
                try fileManager.createDirectory(at: iCloudURL, withIntermediateDirectories: true)
            }
            return iCloudURL
        }

        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
    }

    private func iCloudDocumentStorageURL() -> URL? {
        guard fileManager.ubiquityIdentityToken != nil,
              let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }

        return containerURL.appendingPathComponent("Documents", isDirectory: true)
    }

    private func mergedProject(local: Project, remote: Project) -> Project {
        var mergedProject = local
        let remoteIsNewer = remote.updatedAt > local.updatedAt

        if remoteIsNewer {
            mergedProject.name = remote.name
            mergedProject.timeline = remote.timeline
            mergedProject.canvas = remote.canvas
            mergedProject.exportSettings = remote.exportSettings
        }

        mergedProject.mediaLibrary = remoteIsNewer ? remote.mediaLibrary : local.mediaLibrary
        mergedProject.appVersion = remoteIsNewer ? remote.appVersion : local.appVersion
        mergedProject.schemaVersion = max(local.schemaVersion, remote.schemaVersion)
        mergedProject.updatedAt = max(local.updatedAt, remote.updatedAt)
        return mergedProject
    }
}
