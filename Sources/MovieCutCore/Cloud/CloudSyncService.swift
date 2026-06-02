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

/// Mock cloud synchronization service.
public final class CloudSyncService: ObservableObject, @unchecked Sendable {
    /// Current synchronization state.
    @Published public private(set) var status: SyncStatus

    /// Date of the most recent successful sync.
    @Published public private(set) var lastSyncDate: Date?

    /// Creates a cloud synchronization service.
    public init(status: SyncStatus = .idle, lastSyncDate: Date? = nil) {
        self.status = status
        self.lastSyncDate = lastSyncDate
    }

    /// Performs a mock project sync.
    public func sync(project: Project) async throws {
        _ = project.id
        status = .syncing

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            lastSyncDate = Date()
            status = .synced
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
