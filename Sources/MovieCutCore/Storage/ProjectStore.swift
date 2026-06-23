import Foundation

/// Loads and saves MovieCut projects as JSON documents.
public actor ProjectStore {
    private let autosaveDirectory: URL?

    /// Creates a project store using the default autosave location
    /// (Application Support/MovieCut).
    public init() {
        self.autosaveDirectory = Self.defaultAutosaveDirectory()
    }

    /// Creates a project store with an explicit autosave directory (tests), or
    /// `nil` to disable crash-recovery autosave.
    public init(autosaveDirectory: URL?) {
        self.autosaveDirectory = autosaveDirectory
    }

    private static func defaultAutosaveDirectory() -> URL? {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MovieCut", isDirectory: true)
    }

    private var autosaveURL: URL? {
        autosaveDirectory?.appendingPathComponent("recovery.moviecut")
    }

    /// Writes the project to the crash-recovery autosave location (atomic).
    public func saveAutosave(_ project: Project) async throws {
        guard let url = autosaveURL else { return }
        try await save(project, to: url)
    }

    /// Returns the autosaved project if a recovery file exists. Its presence on
    /// launch indicates the previous session did not exit cleanly.
    public func loadAutosaveIfAvailable() async -> Project? {
        guard let url = autosaveURL, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try? await load(from: url)
    }

    /// Whether a recovery autosave is present.
    public func hasAutosave() -> Bool {
        guard let url = autosaveURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Removes the recovery autosave. Call on a clean quit or after a successful
    /// manual save so the next launch does not offer stale recovery.
    public func clearAutosave() {
        guard let url = autosaveURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Saves a project to a JSON file using a temp-file replacement flow.
    public func save(_ project: Project, to url: URL) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(project)
        let fileManager = FileManager.default
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: [.atomic])

        do {
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Loads a project from a JSON file.
    public func load(from url: URL) async throws -> Project {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Project.self, from: data)
    }
}
