import Foundation

/// A source of catalog items (local bundle, built-in, etc.).
///
/// The app is fully offline / on-device (no `com.apple.security.network.client`
/// entitlement), so there is intentionally no remote provider. A bundled or
/// in-memory provider is the only kind.
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

/// A small built-in starter catalog with explicit licensing.
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
