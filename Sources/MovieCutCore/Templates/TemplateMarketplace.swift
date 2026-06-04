import Foundation
import os

/// Marketplace metadata for a downloadable template.
public struct TemplateMarketplaceItem: Codable, Sendable, Identifiable, Equatable {
    /// The marketplace item identifier.
    public var id: UUID

    /// User-visible item name.
    public var name: String

    /// Template author or organization.
    public var author: String

    /// User-visible item description.
    public var description: String

    /// Marketplace category name.
    public var category: String

    /// Optional image asset name used for previews.
    public var previewImageName: String?

    /// Optional remote URL for downloading the template bundle payload.
    public var downloadURL: URL?

    /// The template payload returned on download.
    public var bundle: TemplateBundle

    /// Catalog tags used for lightweight filtering such as featured placement.
    public var tags: [String]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case author
        case description
        case category
        case previewImageName
        case downloadURL
        case bundle
        case tags
    }

    /// Creates a marketplace item.
    public init(
        id: UUID = UUID(),
        name: String,
        author: String,
        description: String,
        category: String,
        previewImageName: String? = nil,
        downloadURL: URL? = nil,
        bundle: TemplateBundle,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.category = category
        self.previewImageName = previewImageName
        self.downloadURL = downloadURL
        self.bundle = bundle
        self.tags = tags
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        author = try container.decode(String.self, forKey: .author)
        description = try container.decode(String.self, forKey: .description)
        category = try container.decode(String.self, forKey: .category)
        previewImageName = try container.decodeIfPresent(String.self, forKey: .previewImageName)
        downloadURL = try container.decodeIfPresent(URL.self, forKey: .downloadURL)
        bundle = try container.decode(TemplateBundle.self, forKey: .bundle)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(author, forKey: .author)
        try container.encode(description, forKey: .description)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(previewImageName, forKey: .previewImageName)
        try container.encodeIfPresent(downloadURL, forKey: .downloadURL)
        try container.encode(bundle, forKey: .bundle)
        try container.encode(tags, forKey: .tags)
    }
}

/// Difference between a local marketplace catalog and a remote catalog.
public struct CatalogDiff: Sendable {
    /// Items present remotely but not locally.
    public var added: [TemplateMarketplaceItem]

    /// Items present in both catalogs with changed metadata or bundle payloads.
    public var updated: [TemplateMarketplaceItem]

    /// Items present locally but no longer present remotely.
    public var removed: [TemplateMarketplaceItem]

    /// Creates catalog diff metadata.
    public init(
        added: [TemplateMarketplaceItem],
        updated: [TemplateMarketplaceItem],
        removed: [TemplateMarketplaceItem]
    ) {
        self.added = added
        self.updated = updated
        self.removed = removed
    }
}

/// Errors produced by remote marketplace operations.
public enum TemplateMarketplaceError: Error, Sendable, Equatable {
    case remoteCatalogURLMissing
    case invalidHTTPResponse(Int)
}

/// Local JSON-backed template marketplace facade.
public final class TemplateMarketplace: Sendable {
    private static let featuredTag = "featured"

    private let catalogURL: URL
    private let cacheURL: URL
    private let remoteCatalogURL: URL?
    private let store = TemplateStore()
    private let cachedItems = OSAllocatedUnfairLock(initialState: [TemplateMarketplaceItem]())

    /// Featured marketplace items from the cached catalog.
    public var featured: [TemplateMarketplaceItem] {
        cachedItems.withLock { $0 }.filter { item in
            item.tags.contains { tag in
                tag.caseInsensitiveCompare(Self.featuredTag) == .orderedSame
            }
        }
    }

    /// Marketplace items grouped by category.
    public var categories: [String: [TemplateMarketplaceItem]] {
        Dictionary(grouping: cachedItems.withLock { $0 }, by: \.category)
    }

    /// Creates a marketplace backed by the local template catalog.
    public convenience init() {
        self.init(remoteCatalogURL: nil)
    }

    /// Creates a marketplace backed by a remote catalog URL with local fallback.
    public init(remoteCatalogURL: URL?) {
        catalogURL = Self.defaultCatalogURL()
        cacheURL = Self.defaultCacheURL()
        self.remoteCatalogURL = remoteCatalogURL
        TemplateStore.builtInTemplates().forEach { store.add($0) }

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            do {
                try loadCatalog()
            } catch {
                generateCatalog()
            }
        } else {
            generateCatalog()
        }
    }

    /// Searches catalog items by name, description, or category.
    public func search(query: String) -> [TemplateMarketplaceItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cachedItems = cachedItems.withLock { $0 }
        guard !normalizedQuery.isEmpty else {
            return cachedItems
        }

        return cachedItems.filter { item in
            item.name.lowercased().contains(normalizedQuery)
                || item.description.lowercased().contains(normalizedQuery)
                || item.category.lowercased().contains(normalizedQuery)
        }
    }

    /// Returns the template bundle for a marketplace item.
    public func download(item: TemplateMarketplaceItem) -> TemplateBundle {
        item.bundle
    }

    /// Fetches the configured remote catalog.
    public func fetchRemoteCatalog() async throws -> [TemplateMarketplaceItem] {
        guard let remoteCatalogURL else {
            throw TemplateMarketplaceError.remoteCatalogURLMissing
        }

        let (data, response) = try await URLSession.shared.data(from: remoteCatalogURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw TemplateMarketplaceError.invalidHTTPResponse(httpResponse.statusCode)
        }

        return try JSONDecoder().decode([TemplateMarketplaceItem].self, from: data)
    }

    /// Writes a remote catalog cache to Application Support.
    public func cacheRemoteCatalog(_ items: [TemplateMarketplaceItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directoryURL = cacheURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(items)
        try data.write(to: cacheURL, options: [.atomic])
    }

    /// Diffs two marketplace catalogs by item identifier.
    public func diffCatalog(
        local: [TemplateMarketplaceItem],
        remote: [TemplateMarketplaceItem]
    ) -> CatalogDiff {
        var localByID: [UUID: TemplateMarketplaceItem] = [:]
        var remoteByID: [UUID: TemplateMarketplaceItem] = [:]

        local.forEach { item in localByID[item.id] = item }
        remote.forEach { item in remoteByID[item.id] = item }

        let added = remote.filter { item in
            localByID[item.id] == nil
        }
        .sorted { $0.name < $1.name }

        let updated = remote.filter { item in
            guard let localItem = localByID[item.id] else {
                return false
            }

            return localItem != item
        }
        .sorted { $0.name < $1.name }

        let removed = local.filter { item in
            remoteByID[item.id] == nil
        }
        .sorted { $0.name < $1.name }

        return CatalogDiff(added: added, updated: updated, removed: removed)
    }

    /// Downloads a remote template bundle with progress reporting.
    public func downloadTemplate(
        item: TemplateMarketplaceItem,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TemplateBundle {
        progress?(0)

        guard let downloadURL = item.downloadURL else {
            store.add(item.bundle)
            progress?(1)
            return item.bundle
        }

        let data = try await Self.downloadData(from: downloadURL, progress: progress)
        let decoder = JSONDecoder()
        let bundle: TemplateBundle

        if let decodedBundle = try? decoder.decode(TemplateBundle.self, from: data) {
            bundle = decodedBundle
        } else {
            bundle = try decoder.decode(TemplateMarketplaceItem.self, from: data).bundle
        }

        store.add(bundle)
        progress?(1)
        return bundle
    }

    /// Refreshes the marketplace from remote, cached, or generated local catalog data.
    public func refreshCatalog() async throws {
        if remoteCatalogURL != nil {
            do {
                let remoteItems = try await fetchRemoteCatalog()
                try cacheRemoteCatalog(remoteItems)
                applyCatalog(remoteItems)
                try? saveCatalog(remoteItems)
                return
            } catch {
                if let cachedRemoteItems = try? loadCachedRemoteCatalog() {
                    applyCatalog(cachedRemoteItems)
                    return
                }
            }
        }

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            try loadCatalog()
        } else {
            generateCatalog()
        }
    }

    private func applyCatalog(_ items: [TemplateMarketplaceItem]) {
        cachedItems.withLock { $0 = items }
        items.map(\.bundle).forEach { store.add($0) }
    }

    private func loadCatalog() throws {
        let data = try Data(contentsOf: catalogURL)
        let decoder = JSONDecoder()
        let items = try decoder.decode([TemplateMarketplaceItem].self, from: data)
        applyCatalog(items)
    }

    private func loadCachedRemoteCatalog() throws -> [TemplateMarketplaceItem] {
        let data = try Data(contentsOf: cacheURL)
        return try JSONDecoder().decode([TemplateMarketplaceItem].self, from: data)
    }

    private func saveCatalog(_ items: [TemplateMarketplaceItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directoryURL = catalogURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(items)
        try data.write(to: catalogURL, options: [.atomic])
    }

    private func generateCatalog() {
        let items = Self.generatedCatalogItems(from: store.bundles)
        cachedItems.withLock { $0 = items }
        items.map(\.bundle).forEach { store.add($0) }
        try? saveCatalog(items)
    }

    private static func defaultCatalogURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("template-catalog.json", isDirectory: false)
    }

    private static func defaultCacheURL() -> URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("MovieCut", isDirectory: true)
            .appendingPathComponent("marketplace-cache.json", isDirectory: false)
    }

    private static func downloadData(
        from url: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> Data {
        let delegate = TemplateDownloadDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer {
            session.finishTasksAndInvalidate()
        }

        return try await withCheckedThrowingContinuation { continuation in
            delegate.resume(with: continuation)
            session.downloadTask(with: url).resume()
        }
    }

    private static func generatedCatalogItems(from builtInTemplates: [TemplateBundle]) -> [TemplateMarketplaceItem] {
        let variations = [
            CatalogVariation(
                suffix: "Creator Spotlight",
                category: "Social",
                descriptionPrefix: "A creator-ready edit for short-form posts.",
                tags: ["featured", "social", "creator"]
            ),
            CatalogVariation(
                suffix: "Product Drop",
                category: "Business",
                descriptionPrefix: "A concise launch edit for announcements and promos.",
                tags: ["featured", "business", "launch"]
            ),
            CatalogVariation(
                suffix: "Travel Recap",
                category: "Travel",
                descriptionPrefix: "A fast-paced story layout for trips and location highlights.",
                tags: ["travel", "recap"]
            ),
            CatalogVariation(
                suffix: "Course Clip",
                category: "Education",
                descriptionPrefix: "A structured teaching cut for lessons and explainers.",
                tags: ["education", "tutorial"]
            )
        ]

        let identifiers = [
            "2AA52E09-B6AB-4D24-99B8-F27E456A8E7A",
            "0E95AE41-C1AF-4B4C-A872-9A6223E49431",
            "D501DC5D-7C17-4F5E-A3B1-0822FA236F49",
            "469953B5-0624-4E6F-9382-A2130828E25C",
            "29FEA18B-725F-4BF3-B77E-08B2CF8F4B65",
            "B3E027DD-4AF1-4C0F-962C-95755B06719D",
            "D5854C3D-084E-4F39-9542-B6CE91E7D5C5",
            "86A26582-B4BD-4985-A1BC-33E21DDA746B",
            "89E5E74D-552A-4E8E-A7EE-1FAD059FC26A",
            "72D54513-C74F-4600-B575-7B31DC90218E",
            "246D93A9-68DE-4C00-8CB2-84D4C1E86E1A",
            "6394816D-FF47-4483-A6CC-49C17E310079"
        ]

        var items: [TemplateMarketplaceItem] = []

        for (templateIndex, template) in builtInTemplates.prefix(3).enumerated() {
            for (variationIndex, variation) in variations.enumerated() {
                let itemIndex = templateIndex * variations.count + variationIndex
                let name = "\(template.name) \(variation.suffix)"
                let slugStr = slug(for: name)
                var bundle = template
                bundle.identifier = "\(template.identifier).marketplace.\(slug(for: variation.suffix))"
                bundle.name = name
                bundle.description = "\(variation.descriptionPrefix) Based on \(template.description)"

                items.append(
                    TemplateMarketplaceItem(
                        id: UUID(uuidString: identifiers[itemIndex]) ?? UUID(),
                        name: name,
                        author: template.author,
                        description: bundle.description,
                        category: variation.category,
                        previewImageName: "marketplace_\(slugStr.replacingOccurrences(of: "-", with: "_"))",
                        bundle: bundle,
                        tags: variation.tags
                    )
                )
            }
        }

        return items
    }

    private static func slug(for value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private struct CatalogVariation {
    var suffix: String
    var category: String
    var descriptionPrefix: String
    var tags: [String]
}

private final class TemplateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: (@Sendable (Double) -> Void)?
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Data, Error>?

    init(progress: (@Sendable (Double) -> Void)?) {
        self.progress = progress
    }

    func resume(with continuation: CheckedContinuation<Data, Error>) {
        lock.withLock {
            self.continuation = continuation
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else {
            return
        }

        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progress?(min(max(fraction, 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let data = try Data(contentsOf: location)
            finish(.success(data))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Data, Error>) {
        let continuation = lock.withLock {
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else {
            return
        }

        switch result {
        case let .success(data):
            continuation.resume(returning: data)
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}
