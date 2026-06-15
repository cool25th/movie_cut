import CryptoKit
import Foundation

/// A stable, content-derived cache key.
///
/// Two inputs with identical content produce the same key regardless of file
/// path, so cached render artifacts are path-independent and auto-invalidate
/// when the underlying content changes.
public struct RenderCacheKey: Hashable, Sendable, CustomStringConvertible {
    /// The hex SHA-256 string that identifies the cached artifact.
    public let value: String

    /// Creates a cache key from a precomputed hex digest.
    public init(value: String) {
        self.value = value
    }

    public var description: String { value }
}

/// Builds content-derived cache keys with SHA-256.
///
/// Use ``key(forFileAt:parameters:)`` for strict content-addressing (hashes the
/// whole file) or ``key(fingerprintOfFileAt:parameters:)`` for a cheap key from
/// file size and modification date when full hashing would be wasteful (large
/// media used only for thumbnails/scrubbing).
public enum RenderContentHasher {
    /// The hex SHA-256 digest of the supplied bytes.
    public static func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The hex SHA-256 digest of a file's full content, read in chunks so large
    /// media does not need to be loaded into memory at once.
    public static func hexDigest(ofFileAt url: URL, chunkSize: Int = 1 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// A key derived from ordered string components (order-sensitive).
    public static func key(components: [String]) -> RenderCacheKey {
        let joined = components.joined(separator: "\u{1f}")
        return RenderCacheKey(value: hexDigest(of: Data(joined.utf8)))
    }

    /// A key derived from ordered string components (variadic convenience).
    public static func key(_ components: String...) -> RenderCacheKey {
        key(components: components)
    }

    /// A content-addressed key from a file's full content plus parameters.
    public static func key(forFileAt url: URL, parameters: [String] = []) throws -> RenderCacheKey {
        let contentDigest = try hexDigest(ofFileAt: url)
        return key(components: [contentDigest] + parameters)
    }

    /// A cheap path-independent fingerprint from file size and modification date.
    public static func fingerprint(ofFileAt url: URL, fileManager: FileManager = .default) throws -> String {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size):\(Int(modified.rounded()))"
    }

    /// A key from a file's cheap fingerprint plus parameters.
    public static func key(
        fingerprintOfFileAt url: URL,
        parameters: [String] = [],
        fileManager: FileManager = .default
    ) throws -> RenderCacheKey {
        let fingerprint = try fingerprint(ofFileAt: url, fileManager: fileManager)
        return key(components: [fingerprint] + parameters)
    }
}

/// A two-tier (in-memory + file-backed) content-addressed cache for expensive
/// render artifacts such as thumbnails, proxies, and effect frames.
///
/// The cache is content-addressed: entries are stored under their content hash,
/// so identical content is deduplicated and stale content is never served. The
/// memory tier is a small LRU in front of durable on-disk storage.
public actor RenderCache {
    /// Hit/miss accounting for diagnostics and tests.
    public struct Statistics: Sendable, Equatable {
        /// Lookups served from the memory tier.
        public var memoryHits = 0
        /// Lookups served from the disk tier.
        public var diskHits = 0
        /// Lookups not present in either tier.
        public var misses = 0

        /// Creates empty statistics.
        public init() {}
    }

    private let directory: URL
    private let fileManager: FileManager
    private let memoryLimit: Int
    private var memory: [RenderCacheKey: Data] = [:]
    private var recency: [RenderCacheKey] = []

    /// Cumulative lookup statistics.
    public private(set) var statistics = Statistics()

    /// Creates a render cache rooted at the supplied directory.
    ///
    /// - Parameters:
    ///   - directory: The on-disk location for cached artifacts. Created lazily.
    ///   - memoryLimit: The maximum number of entries held in the memory tier.
    ///   - fileManager: The file manager used for disk operations.
    public init(directory: URL, memoryLimit: Int = 128, fileManager: FileManager = .default) {
        self.directory = directory
        self.memoryLimit = max(1, memoryLimit)
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The number of entries currently held in the memory tier.
    public var memoryCount: Int { memory.count }

    /// Whether an artifact exists in either tier.
    public func contains(_ key: RenderCacheKey) -> Bool {
        if memory[key] != nil { return true }
        return fileManager.fileExists(atPath: fileURL(for: key).path)
    }

    /// Returns a cached artifact from the memory tier, falling back to disk.
    ///
    /// A disk hit promotes the artifact into the memory tier.
    public func data(for key: RenderCacheKey) -> Data? {
        if let cached = memory[key] {
            touch(key)
            statistics.memoryHits += 1
            return cached
        }

        let url = fileURL(for: key)
        guard let data = try? Data(contentsOf: url) else {
            statistics.misses += 1
            return nil
        }

        statistics.diskHits += 1
        insertIntoMemory(data, for: key)
        return data
    }

    /// Stores an artifact in both tiers.
    public func store(_ data: Data, for key: RenderCacheKey) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL(for: key), options: [.atomic])
        insertIntoMemory(data, for: key)
    }

    /// Returns a cached artifact, or computes, stores, and returns it on a miss.
    ///
    /// This is the cache-aside entry point callers should prefer: the expensive
    /// `compute` closure runs only when the content hash is not already cached.
    @discardableResult
    public func data(
        for key: RenderCacheKey,
        orCompute compute: @Sendable () async throws -> Data
    ) async throws -> Data {
        if let cached = data(for: key) {
            return cached
        }
        let produced = try await compute()
        try store(produced, for: key)
        return produced
    }

    /// Removes an artifact from both tiers.
    public func remove(_ key: RenderCacheKey) throws {
        memory.removeValue(forKey: key)
        recency.removeAll { $0 == key }
        let url = fileURL(for: key)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Clears both tiers.
    public func clear() throws {
        memory.removeAll()
        recency.removeAll()
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Resets cumulative statistics.
    public func resetStatistics() {
        statistics = Statistics()
    }

    /// The on-disk location for a key's artifact (may not exist yet).
    ///
    /// Callers that need a file path rather than bytes (e.g. downloaded media
    /// assets) can `store` the content, then reference it by this URL.
    public func cachedFileURL(for key: RenderCacheKey) -> URL {
        fileURL(for: key)
    }

    // MARK: - Private

    private func fileURL(for key: RenderCacheKey) -> URL {
        directory.appendingPathComponent(key.value, isDirectory: false)
    }

    private func insertIntoMemory(_ data: Data, for key: RenderCacheKey) {
        memory[key] = data
        touch(key)
        evictIfNeeded()
    }

    private func touch(_ key: RenderCacheKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }

    private func evictIfNeeded() {
        while memory.count > memoryLimit, let oldest = recency.first {
            recency.removeFirst()
            memory.removeValue(forKey: oldest)
        }
    }
}
