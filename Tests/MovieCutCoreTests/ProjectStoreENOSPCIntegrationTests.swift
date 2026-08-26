import CryptoKit
import Foundation
import MovieCutCore
import Testing

@Suite("ProjectStore ENOSPC Integration")
struct ProjectStoreENOSPCIntegrationTests {
    @Test("temp-write ENOSPC preserves destination, cleans temp, and never commits")
    func tempWriteENOSPCIsFailClosed() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("moviecut-enospc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let destination = directory.appendingPathComponent("project.moviecut")
        let sentinel = Data("existing-project-sentinel".utf8)
        try sentinel.write(to: destination)
        let beforeDigest = SHA256.hash(data: try Data(contentsOf: destination))

        let writer = PartialWriteENOSPCWriter()
        let store = ProjectStore(autosaveDirectory: nil, fileWriter: writer)

        do {
            try await store.save(Project(name: "must not commit"), to: destination)
            Issue.record("expected injected ENOSPC")
        } catch let error as FileOperationError {
            #expect(error == .diskFull)
        } catch {
            Issue.record("expected FileOperationError.diskFull, got \(error)")
        }

        let afterDigest = SHA256.hash(data: try Data(contentsOf: destination))
        #expect(beforeDigest == afterDigest, "existing destination bytes must be preserved")
        #expect(writer.commitCalls == 0, "a failed temp write must not emit a successful commit")
        #expect(writer.cleanupCalls == 1)

        let residue = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(".project.moviecut.") && $0.pathExtension == "tmp" }
        #expect(residue.isEmpty, "partial temporary files must be removed")
    }
}

private final class PartialWriteENOSPCWriter: ProjectFileWriting, @unchecked Sendable {
    private(set) var commitCalls = 0
    private(set) var cleanupCalls = 0

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func write(_ data: Data, to temporaryURL: URL) throws {
        try Data(data.prefix(max(1, data.count / 2))).write(to: temporaryURL)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.ENOSPC.rawValue))
    }

    func commit(_ temporaryURL: URL, to destinationURL: URL) throws {
        commitCalls += 1
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
    }

    func removeIfPresent(at url: URL) throws {
        cleanupCalls += 1
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}