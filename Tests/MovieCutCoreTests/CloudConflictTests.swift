import Foundation
import Testing
@testable import MovieCutCore

/// F-22 iCloud sync conflict resolution: a two-device simulation where the
/// latest edit wins and the superseded version is kept as a backup.
@MainActor
@Suite("Cloud Conflict Resolution")
struct CloudConflictTests {
    private func project(name: String, updatedAt: Date, clipCount: Int) -> Project {
        var project = Project(name: name)
        project.updatedAt = updatedAt
        var track = Track(kind: .video, name: "Video 1")
        track.clips = (0..<clipCount).map { index in
            Clip(
                kind: .video,
                sourceRange: TimeRange(start: 0, duration: 1),
                timelineRange: TimeRange(start: Double(index), duration: 1)
            )
        }
        project.timeline.tracks = [track]
        return project
    }

    @Test("two-device edit: newer remote wins and local is backed up (AC)")
    func twoDeviceRemoteNewer() {
        let service = CloudSyncService()
        let base = Date(timeIntervalSince1970: 1_000_000)

        // Device A saved at T1; device B edited the same project at T2 > T1.
        let deviceA = project(name: "Trip", updatedAt: base, clipCount: 2)
        let deviceB = project(name: "Trip", updatedAt: base.addingTimeInterval(60), clipCount: 3)

        #expect(service.detectConflict(local: deviceA, remote: deviceB))

        let resolution = service.resolveConflictKeepingBackup(local: deviceA, remote: deviceB)
        #expect(resolution.resolved == deviceB)         // newer wins
        #expect(resolution.backup == deviceA)           // older preserved
    }

    @Test("two-device edit: newer local wins and remote is backed up")
    func twoDeviceLocalNewer() {
        let service = CloudSyncService()
        let base = Date(timeIntervalSince1970: 2_000_000)

        let deviceA = project(name: "Trip", updatedAt: base.addingTimeInterval(120), clipCount: 4)
        let deviceB = project(name: "Trip", updatedAt: base, clipCount: 2)

        let resolution = service.resolveConflictKeepingBackup(local: deviceA, remote: deviceB)
        #expect(resolution.resolved == deviceA)
        #expect(resolution.backup == deviceB)
    }

    @Test("identical versions are not a conflict and need no backup")
    func noConflictNoBackup() {
        let service = CloudSyncService()
        let shared = project(name: "Trip", updatedAt: Date(timeIntervalSince1970: 3_000_000), clipCount: 2)

        #expect(!service.detectConflict(local: shared, remote: shared))
        let resolution = service.resolveConflictKeepingBackup(local: shared, remote: shared)
        #expect(resolution.resolved == shared)
        #expect(resolution.backup == nil)
    }

    @Test("latestWins strategy returns the most recently modified version")
    func latestWinsStrategy() {
        let service = CloudSyncService()
        let base = Date(timeIntervalSince1970: 4_000_000)
        let older = project(name: "Trip", updatedAt: base, clipCount: 1)
        let newer = project(name: "Trip", updatedAt: base.addingTimeInterval(10), clipCount: 5)

        #expect(service.resolveConflict(local: older, remote: newer, strategy: .latestWins) == newer)
        #expect(service.resolveConflict(local: newer, remote: older, strategy: .latestWins) == newer)
    }

    @Test("conflict backup name is deterministic and filesystem-safe")
    func backupNameDeterministic() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = CloudSyncService.conflictBackupName(for: "My Trip", at: date)
        #expect(name.hasPrefix("My Trip (conflict backup "))
        #expect(name.hasSuffix(")"))
        // No colons (replaced with dashes) so it is a valid file name.
        #expect(!name.contains(":"))
    }

    @Test("writeConflictBackup persists a loadable backup document")
    func writeBackupPersists() async throws {
        let service = CloudSyncService()
        let proj = project(name: "BackupTest-\(UUID().uuidString)", updatedAt: Date(timeIntervalSince1970: 5_000_000), clipCount: 2)

        let url = try await service.writeConflictBackup(proj, at: Date(timeIntervalSince1970: 5_000_000))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent.contains("conflict backup"))
        let reloaded = try await ProjectStore().load(from: url)
        #expect(reloaded.timeline.tracks.first?.clips.count == 2)
    }
}
