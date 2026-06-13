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
    /// Keep whichever version was modified most recently (F-22 default).
    case latestWins
}

/// The outcome of resolving a sync conflict: the winning project plus the
/// superseded version kept as a backup so no edits are lost (F-22).
public struct ConflictResolution: Sendable, Equatable {
    /// The version that becomes the active project.
    public var resolved: Project
    /// The superseded version to preserve as a backup, or nil when there was
    /// no real conflict.
    public var backup: Project?

    public init(resolved: Project, backup: Project?) {
        self.resolved = resolved
        self.backup = backup
    }
}

/// Lightweight metadata for a synced project document.
public struct CloudProjectInfo: Sendable, Equatable, Identifiable {
    /// Unique identifier based on name.
    public var id: String { name }

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

/// Sidecar metadata stored next to a synced project document.
public struct CloudSyncMetadata: Codable, Sendable, Equatable {
    /// Project identifier from the document snapshot.
    public var projectId: UUID

    /// Project name used for the backing document.
    public var projectName: String

    /// Stable checksum for the encoded project payload.
    public var checksum: String

    /// Metadata write time.
    public var timestamp: Date

    /// Project update time from the document snapshot.
    public var updatedAt: Date

    /// Backing project file size in bytes.
    public var fileSize: Int

    /// Creates cloud sidecar metadata.
    public init(
        projectId: UUID,
        projectName: String,
        checksum: String,
        timestamp: Date = Date(),
        updatedAt: Date,
        fileSize: Int
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.checksum = checksum
        self.timestamp = timestamp
        self.updatedAt = updatedAt
        self.fileSize = fileSize
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
    private let versionHistory = VersionHistory()
    private var metadataQuery: NSMetadataQuery?
    private var metadataQueryObservers: [NSObjectProtocol]
    private var autoSyncTasks: [UUID: Task<Void, Never>]

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
        self.metadataQueryObservers = []
        self.autoSyncTasks = [:]
    }

    /// Returns whether iCloud Drive storage is currently available.
    public func isCloudAvailable() -> Bool {
        fileManager.ubiquityIdentityToken != nil && iCloudDocumentStorageURL() != nil
    }

    /// Serializes and writes a project to iCloud Drive, or Application Support when iCloud is unavailable.
    public func sync(project: Project) async throws {
        status = .syncing

        do {
            try await versionHistory.save(project, description: "Auto-save before cloud sync")
            let fileURL = try projectFileURL(name: project.name, createDirectory: true)
            try await projectStore.save(project, to: fileURL)
            try await syncMetadata(project: project)
            lastSyncDate = Date()
            status = .synced
        } catch {
            status = .failed(error)
            throw error
        }
    }

    /// Starts an iCloud metadata query that watches MovieCut documents for remote changes.
    public func startCloudWatcher() {
        stopCloudWatcher()

        guard isCloudAvailable() else {
            status = .offline
            return
        }

        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K ENDSWITH %@", NSMetadataItemFSNameKey, ".moviecut")

        let notificationCenter = NotificationCenter.default
        let finishName = Notification.Name.NSMetadataQueryDidFinishGathering
        let updateName = Notification.Name.NSMetadataQueryDidUpdate

        let finishObserver = notificationCenter.addObserver(
            forName: finishName,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cloudMetadataDidChange()
            }
        }

        let updateObserver = notificationCenter.addObserver(
            forName: updateName,
            object: query,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cloudMetadataDidChange()
            }
        }

        metadataQueryObservers = [finishObserver, updateObserver]
        metadataQuery = query
        query.start()
    }

    /// Starts periodic synchronization for a project when the service is not busy.
    public func autoSync(project: Project, with interval: TimeInterval = 30) {
        autoSyncTasks[project.id]?.cancel()

        let delay = Self.sleepNanoseconds(for: interval)
        autoSyncTasks[project.id] = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delay)
                } catch {
                    break
                }

                guard let self, !Task.isCancelled else {
                    break
                }

                guard self.canStartAutomaticSync else {
                    continue
                }

                do {
                    try await self.sync(project: project)
                } catch {
                    continue
                }
            }
        }
    }

    /// Synchronizes a `.moviecut.meta` sidecar for the supplied project.
    @discardableResult
    public func syncMetadata(project: Project) async throws -> CloudSyncMetadata {
        let projectURL = try projectFileURL(name: project.name, createDirectory: true)
        let metadataURL = metadataFileURL(for: projectURL)
        _ = try? loadMetadata(from: metadataURL)

        let projectData = try Self.encodedProjectData(project)
        let fileSize = projectFileSize(at: projectURL) ?? projectData.count
        let metadata = CloudSyncMetadata(
            projectId: project.id,
            projectName: project.name,
            checksum: Self.checksum(for: projectData),
            updatedAt: project.updatedAt,
            fileSize: fileSize
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: [.atomic])
        return metadata
    }

    /// Returns true when local and remote project metadata diverge.
    public func detectConflict(local: Project, remote: Project) -> Bool {
        let timestampDiffers = local.updatedAt != remote.updatedAt
        let sizeDiffers = Self.encodedProjectSize(local) != Self.encodedProjectSize(remote)
        let hasConflict = timestampDiffers || sizeDiffers

        if hasConflict {
            status = .conflict
        }

        return hasConflict
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
        case .latestWins:
            return remote.updatedAt > local.updatedAt ? remote : local
        }
    }

    /// Resolves a conflict with the F-22 default policy: the most recently
    /// modified version wins, and the superseded version is returned as a
    /// backup. When there is no real conflict, `backup` is nil.
    public func resolveConflictKeepingBackup(local: Project, remote: Project) -> ConflictResolution {
        guard local.updatedAt != remote.updatedAt
            || Self.encodedProjectSize(local) != Self.encodedProjectSize(remote) else {
            return ConflictResolution(resolved: local, backup: nil)
        }

        if remote.updatedAt > local.updatedAt {
            return ConflictResolution(resolved: remote, backup: local)
        }
        // Local is newer or ties; keep local and back up the remote copy.
        return ConflictResolution(resolved: local, backup: remote)
    }

    /// Persists a superseded project version as a timestamped backup document
    /// next to the synced projects, so a latest-wins resolution never discards
    /// the other device's edits (F-22).
    @discardableResult
    public func writeConflictBackup(_ project: Project, at date: Date) async throws -> URL {
        let backupName = Self.conflictBackupName(for: project.name, at: date)
        let backupURL = try projectFileURL(name: backupName, createDirectory: true)
        try await projectStore.save(project, to: backupURL)
        return backupURL
    }

    /// Deterministic backup document name for a superseded version.
    public static func conflictBackupName(for projectName: String, at date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        return "\(projectName) (conflict backup \(stamp))"
    }

    private func projectFileURL(name: String, createDirectory: Bool) throws -> URL {
        try movieCutDirectoryURL(create: createDirectory)
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension("moviecut")
    }

    private func metadataFileURL(for projectURL: URL) -> URL {
        projectURL.appendingPathExtension("meta")
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

    private func stopCloudWatcher() {
        metadataQuery?.stop()
        metadataQuery = nil

        metadataQueryObservers.forEach { observer in
            NotificationCenter.default.removeObserver(observer)
        }
        metadataQueryObservers.removeAll()
    }

    private func cloudMetadataDidChange() {
        lastSyncDate = Date()

        if case .syncing = status {
            return
        }

        status = .idle
    }

    private var canStartAutomaticSync: Bool {
        switch status {
        case .idle, .synced:
            return true
        case .syncing, .conflict, .offline, .failed:
            return false
        }
    }

    private func loadMetadata(from url: URL) throws -> CloudSyncMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CloudSyncMetadata.self, from: data)
    }

    private func projectFileSize(at url: URL) -> Int? {
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        return try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }

    private static func sleepNanoseconds(for interval: TimeInterval) -> UInt64 {
        let seconds = max(interval, 1)
        return UInt64(seconds * 1_000_000_000)
    }

    private static func encodedProjectSize(_ project: Project) -> Int {
        (try? encodedProjectData(project).count) ?? 0
    }

    private static func encodedProjectData(_ project: Project) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(project)
    }

    private static func checksum(for data: Data) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return String(format: "%016llx", hash)
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
