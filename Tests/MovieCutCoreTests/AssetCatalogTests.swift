import Foundation
import Testing
@testable import MovieCutCore

@Suite("Asset Catalog")
struct AssetCatalogTests {
    private func sampleItems() -> [CatalogItem] {
        [
            CatalogItem(id: "m1", kind: .music, name: "Upbeat Loop", tags: ["upbeat", "vlog"],
                        license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)),
            CatalogItem(id: "m2", kind: .music, name: "Calm Piano", tags: ["calm", "piano"],
                        license: CatalogLicense(kind: .creativeCommons, allowsCommercialUse: false, requiresAttribution: true)),
            CatalogItem(id: "s1", kind: .soundEffect, name: "Whoosh", tags: ["transition"],
                        license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true)),
            CatalogItem(id: "f1", kind: .font, name: "Display Bold", tags: ["title", "bold"],
                        license: CatalogLicense(kind: .premium, allowsCommercialUse: true))
        ]
    }

    // MARK: - Search & pagination

    @Test("Kind filter restricts results to one category")
    func kindFilter() {
        let filtered = CatalogSearch.filter(sampleItems(), with: CatalogQuery(kind: .music))
        #expect(filtered.map(\.id) == ["m1", "m2"])
    }

    @Test("Search text matches name and tags case-insensitively")
    func searchText() {
        #expect(CatalogSearch.filter(sampleItems(), with: CatalogQuery(searchText: "PIANO")).map(\.id) == ["m2"])
        #expect(CatalogSearch.filter(sampleItems(), with: CatalogQuery(searchText: "whoosh")).map(\.id) == ["s1"])
        #expect(CatalogSearch.filter(sampleItems(), with: CatalogQuery(searchText: "vlog")).map(\.id) == ["m1"])
    }

    @Test("Commercial-only filter drops non-commercial licenses")
    func commercialFilter() {
        let filtered = CatalogSearch.filter(sampleItems(), with: CatalogQuery(commercialUseOnly: true))
        #expect(filtered.contains { $0.id == "m2" } == false)
        #expect(filtered.count == 3)
    }

    @Test("Tag filter requires all requested tags")
    func tagFilter() {
        #expect(CatalogSearch.filter(sampleItems(), with: CatalogQuery(tags: ["title", "bold"])).map(\.id) == ["f1"])
        #expect(CatalogSearch.filter(sampleItems(), with: CatalogQuery(tags: ["title", "missing"])).isEmpty)
    }

    @Test("Pagination slices results and reports hasMore")
    func pagination() {
        let page0 = CatalogSearch.page(sampleItems(), query: CatalogQuery(page: 0, pageSize: 2))
        #expect(page0.items.map(\.id) == ["m1", "m2"])
        #expect(page0.totalCount == 4)
        #expect(page0.hasMore)

        let page1 = CatalogSearch.page(sampleItems(), query: CatalogQuery(page: 1, pageSize: 2))
        #expect(page1.items.map(\.id) == ["s1", "f1"])
        #expect(page1.hasMore == false)

        let page2 = CatalogSearch.page(sampleItems(), query: CatalogQuery(page: 2, pageSize: 2))
        #expect(page2.items.isEmpty)
    }

    // MARK: - Providers

    @Test("Local provider applies queries and exposes its catalog")
    func localProvider() async throws {
        let provider = LocalAssetCatalogProvider(items: sampleItems())
        let page = try await provider.items(matching: CatalogQuery(kind: .music))
        #expect(page.items.map(\.id) == ["m1", "m2"])
        #expect(provider.catalog.count == 4)
    }

    @Test("Built-in catalog is non-empty and every item is licensed")
    func builtInCatalog() {
        #expect(BuiltInCatalog.items.isEmpty == false)
        for item in BuiltInCatalog.items {
            #expect(item.id.isEmpty == false)
            // Attribution-required CC items must carry attribution text.
            if item.license.requiresAttribution {
                #expect(item.license.attributionText != nil)
            }
        }
    }

    @Test("Remote provider decodes a JSON catalog and searches it")
    func remoteProvider() async throws {
        let data = try JSONEncoder().encode(sampleItems())
        let transport = StubCatalogTransport(payload: data)
        let provider = RemoteAssetCatalogProvider(
            catalogURL: URL(string: "https://example.com/catalog.json")!,
            transport: transport
        )
        let page = try await provider.items(matching: CatalogQuery(searchText: "calm"))
        #expect(page.items.map(\.id) == ["m2"])
    }

    @Test("Catalog item survives a Codable round trip")
    func codableRoundTrip() throws {
        let item = sampleItems()[1]
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(CatalogItem.self, from: data)
        #expect(decoded == item)
    }

    // MARK: - Downloader

    @Test("Downloader caches assets by content hash and avoids refetching")
    func downloaderCaches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutCatalogTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = RenderCache(directory: directory)
        let transport = StubCatalogTransport(payload: Data("asset-bytes".utf8))
        let downloader = CatalogDownloader(transport: transport, cache: cache)

        let item = CatalogItem(
            id: "m1",
            kind: .music,
            name: "Upbeat Loop",
            license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true),
            downloadURL: URL(string: "https://example.com/m1.m4a")!
        )

        let firstURL = try await downloader.download(item)
        #expect(FileManager.default.fileExists(atPath: firstURL.path))
        #expect(try Data(contentsOf: firstURL) == Data("asset-bytes".utf8))

        let secondURL = try await downloader.download(item)
        #expect(secondURL.path == firstURL.path)
        // The asset was fetched from the network only once; the second call hit the cache.
        #expect(await transport.callCount == 1)
    }

    @Test("Downloading an item without a URL throws")
    func downloaderRejectsMissingURL() async {
        let cache = RenderCache(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
        let downloader = CatalogDownloader(transport: StubCatalogTransport(payload: Data()), cache: cache)
        let item = CatalogItem(id: "x", kind: .filter, name: "No URL",
                               license: CatalogLicense(kind: .royaltyFree, allowsCommercialUse: true))
        await #expect(throws: CatalogError.notDownloadable) {
            _ = try await downloader.download(item)
        }
    }
}

/// A transport that returns a fixed payload and counts calls.
private actor StubCatalogTransport: CatalogDataTransport {
    private let payload: Data
    private(set) var count = 0

    init(payload: Data) {
        self.payload = payload
    }

    var callCount: Int { count }

    func data(from url: URL) async throws -> Data {
        count += 1
        return payload
    }
}
