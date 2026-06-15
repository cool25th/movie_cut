import Foundation

/// A source of catalog items (local bundle, remote service, etc.).
public protocol AssetCatalogProvider: Sendable {
    /// User-visible provider name.
    var providerName: String { get }

    /// Returns a page of items matching the query.
    func items(matching query: CatalogQuery) async throws -> CatalogPage
}

/// A catalog provider backed by an in-memory item list.
public struct LocalAssetCatalogProvider: AssetCatalogProvider {
    public let providerName: String
    private let allItems: [CatalogItem]

    /// Creates a local provider over the supplied items.
    public init(providerName: String = "Local", items: [CatalogItem]) {
        self.providerName = providerName
        self.allItems = items
    }

    public func items(matching query: CatalogQuery) async throws -> CatalogPage {
        CatalogSearch.page(allItems, query: query)
    }

    /// All items held by this provider (unfiltered).
    public var catalog: [CatalogItem] { allItems }

    /// A provider over the built-in starter catalog.
    public static let builtIn = LocalAssetCatalogProvider(
        providerName: "Built-in",
        items: BuiltInCatalog.items
    )
}

/// Fetches raw bytes for catalog payloads and asset downloads.
public protocol CatalogDataTransport: Sendable {
    /// Returns the bytes at a URL.
    func data(from url: URL) async throws -> Data
}

/// A `URLSession`-backed catalog transport.
public struct URLSessionCatalogTransport: CatalogDataTransport {
    private let session: URLSession

    /// Creates a URLSession catalog transport.
    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw CatalogError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.transport("Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CatalogError.transport("HTTP status \(http.statusCode)")
        }
        return data
    }
}

/// A catalog provider that fetches a JSON catalog document from a remote URL and
/// applies the same search/pagination as the local provider client-side.
public struct RemoteAssetCatalogProvider: AssetCatalogProvider {
    public let providerName = "Remote"
    private let catalogURL: URL
    private let transport: any CatalogDataTransport

    /// Creates a remote catalog provider.
    public init(catalogURL: URL, transport: any CatalogDataTransport = URLSessionCatalogTransport()) {
        self.catalogURL = catalogURL
        self.transport = transport
    }

    public func items(matching query: CatalogQuery) async throws -> CatalogPage {
        let data = try await transport.data(from: catalogURL)
        let items: [CatalogItem]
        do {
            items = try JSONDecoder().decode([CatalogItem].self, from: data)
        } catch {
            throw CatalogError.malformedCatalog(error.localizedDescription)
        }
        return CatalogSearch.page(items, query: query)
    }
}

/// Downloads catalog assets and caches them by content hash so repeated
/// downloads of identical content are deduplicated and served from disk.
public struct CatalogDownloader: Sendable {
    private let transport: any CatalogDataTransport
    private let cache: RenderCache

    /// Creates a catalog downloader backed by a content-hash cache.
    public init(transport: any CatalogDataTransport = URLSessionCatalogTransport(), cache: RenderCache) {
        self.transport = transport
        self.cache = cache
    }

    /// Downloads an item's asset (or returns the cached copy) and returns the
    /// on-disk file URL.
    public func download(_ item: CatalogItem) async throws -> URL {
        guard let url = item.downloadURL else {
            throw CatalogError.notDownloadable
        }
        let key = RenderContentHasher.key("catalog-asset", item.id, url.absoluteString)
        _ = try await cache.data(for: key) {
            try await transport.data(from: url)
        }
        return await cache.cachedFileURL(for: key)
    }
}

/// A small built-in starter catalog with explicit licensing, used before a
/// remote catalog service is configured.
public enum BuiltInCatalog {
    /// The starter items.
    public static let items: [CatalogItem] = [
        CatalogItem(
            id: "music.upbeat-loop",
            kind: .music,
            name: "Upbeat Loop",
            tags: ["upbeat", "energetic", "loop", "vlog"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true),
            durationSeconds: 30
        ),
        CatalogItem(
            id: "music.calm-piano",
            kind: .music,
            name: "Calm Piano",
            tags: ["calm", "piano", "ambient"],
            license: CatalogLicense(
                kind: .creativeCommons,
                allowsCommercialUse: true,
                requiresAttribution: true,
                attributionText: "Calm Piano — CC BY 4.0"
            ),
            durationSeconds: 45
        ),
        CatalogItem(
            id: "sfx.whoosh",
            kind: .soundEffect,
            name: "Whoosh",
            tags: ["transition", "whoosh", "swipe"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true),
            durationSeconds: 1
        ),
        CatalogItem(
            id: "font.display-bold",
            kind: .font,
            name: "Display Bold",
            tags: ["title", "bold", "display"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)
        ),
        CatalogItem(
            id: "filter.teal-orange",
            kind: .filter,
            name: "Teal & Orange",
            tags: ["cinematic", "lut", "teal", "orange"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)
        ),
        CatalogItem(
            id: "transition.glitch",
            kind: .transition,
            name: "Glitch",
            tags: ["glitch", "energetic"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)
        ),
        CatalogItem(
            id: "sticker.subscribe",
            kind: .sticker,
            name: "Subscribe Badge",
            tags: ["youtube", "subscribe", "badge"],
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)
        )
    ]
}
