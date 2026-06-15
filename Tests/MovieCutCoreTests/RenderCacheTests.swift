import Foundation
import Testing
@testable import MovieCutCore

@Suite("Render Cache")
struct RenderCacheTests {
    private func makeTempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutRenderCacheTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("bin")
        try Data(contents.utf8).write(to: url)
        return url
    }

    // MARK: - Hashing

    @Test("Hex digest is deterministic and content-sensitive")
    func hexDigestContract() {
        let a = RenderContentHasher.hexDigest(of: Data("frame".utf8))
        let b = RenderContentHasher.hexDigest(of: Data("frame".utf8))
        let c = RenderContentHasher.hexDigest(of: Data("frame!".utf8))
        #expect(a == b)
        #expect(a != c)
        #expect(a.count == 64)
    }

    @Test("Component keys are deterministic and order-sensitive")
    func componentKeyContract() {
        let key1 = RenderContentHasher.key("clip", "1.5", "1920x1080")
        let key2 = RenderContentHasher.key("clip", "1.5", "1920x1080")
        let key3 = RenderContentHasher.key("1.5", "clip", "1920x1080")
        #expect(key1 == key2)
        #expect(key1 != key3)
    }

    @Test("Content-hash keys are path-independent and auto-invalidating")
    func contentHashKeyContract() throws {
        let directory = makeTempDirectory()
        let fileA = try writeFile("identical bytes", in: directory)
        let fileB = try writeFile("identical bytes", in: directory)
        let fileC = try writeFile("different bytes", in: directory)

        let keyA = try RenderContentHasher.key(forFileAt: fileA)
        let keyB = try RenderContentHasher.key(forFileAt: fileB)
        let keyC = try RenderContentHasher.key(forFileAt: fileC)

        // Same content at different paths -> same key (path-independent).
        #expect(keyA == keyB)
        // Different content -> different key (auto-invalidating).
        #expect(keyA != keyC)
    }

    @Test("Fingerprint keys change when file content changes")
    func fingerprintKeyContract() throws {
        let directory = makeTempDirectory()
        let url = directory.appendingPathComponent("media.bin")
        try Data("short".utf8).write(to: url)
        let key1 = try RenderContentHasher.key(fingerprintOfFileAt: url, parameters: ["thumb"])

        try Data("a much longer set of bytes".utf8).write(to: url)
        let key2 = try RenderContentHasher.key(fingerprintOfFileAt: url, parameters: ["thumb"])

        #expect(key1 != key2)
    }

    // MARK: - Cache behavior

    @Test("Store and fetch round-trips through the memory tier")
    func storeAndFetch() async throws {
        let cache = RenderCache(directory: makeTempDirectory())
        let key = RenderContentHasher.key("artifact")
        let payload = Data("thumbnail-bytes".utf8)

        #expect(await cache.contains(key) == false)
        try await cache.store(payload, for: key)
        #expect(await cache.contains(key))
        #expect(await cache.data(for: key) == payload)

        let stats = await cache.statistics
        #expect(stats.memoryHits == 1)
    }

    @Test("Artifacts persist on disk across cache instances")
    func diskPersistence() async throws {
        let directory = makeTempDirectory()
        let key = RenderContentHasher.key("persisted")
        let payload = Data("proxy-bytes".utf8)

        let writer = RenderCache(directory: directory)
        try await writer.store(payload, for: key)

        // A fresh cache over the same directory must still resolve the artifact.
        let reader = RenderCache(directory: directory)
        #expect(await reader.data(for: key) == payload)
        let stats = await reader.statistics
        #expect(stats.diskHits == 1)
    }

    @Test("Memory tier evicts LRU entries while disk retains them")
    func memoryEvictionKeepsDisk() async throws {
        let cache = RenderCache(directory: makeTempDirectory(), memoryLimit: 2)
        let keys = (0..<3).map { RenderContentHasher.key("entry", "\($0)") }
        for (index, key) in keys.enumerated() {
            try await cache.store(Data("payload-\(index)".utf8), for: key)
        }

        // Memory holds at most the limit; the oldest entry was evicted from RAM.
        #expect(await cache.memoryCount == 2)
        // The evicted entry is still served from disk.
        #expect(await cache.data(for: keys[0]) == Data("payload-0".utf8))
    }

    @Test("Cache-aside computes only on a miss")
    func cacheAsideComputesOnce() async throws {
        let cache = RenderCache(directory: makeTempDirectory())
        let key = RenderContentHasher.key("compute-once")
        let counter = CallCounter()

        let first = try await cache.data(for: key) {
            await counter.increment()
            return Data("rendered".utf8)
        }
        let second = try await cache.data(for: key) {
            await counter.increment()
            return Data("rendered-again".utf8)
        }

        #expect(first == Data("rendered".utf8))
        #expect(second == Data("rendered".utf8))
        #expect(await counter.count == 1)
    }

    @Test("Remove and clear drop artifacts from both tiers")
    func removeAndClear() async throws {
        let cache = RenderCache(directory: makeTempDirectory())
        let key = RenderContentHasher.key("removable")
        try await cache.store(Data("x".utf8), for: key)

        try await cache.remove(key)
        #expect(await cache.contains(key) == false)

        try await cache.store(Data("y".utf8), for: key)
        try await cache.clear()
        #expect(await cache.contains(key) == false)
        #expect(await cache.memoryCount == 0)
    }
}

private actor CallCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
