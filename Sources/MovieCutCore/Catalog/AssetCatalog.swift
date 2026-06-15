import Foundation

/// The category of a downloadable catalog asset.
public enum CatalogItemKind: String, Codable, Sendable, Equatable, CaseIterable {
    case music
    case soundEffect
    case font
    case filter
    case sticker
    case template
    case transition
}

/// Licensing metadata for a catalog asset.
public struct CatalogLicense: Codable, Sendable, Equatable {
    /// License family.
    public enum Kind: String, Codable, Sendable, Equatable {
        case royaltyFree
        case creativeCommons
        case premium
        case proprietary
    }

    /// The license family.
    public var kind: Kind
    /// Whether the asset may be used in commercial projects.
    public var allowsCommercialUse: Bool
    /// Whether use requires visible attribution.
    public var requiresAttribution: Bool
    /// Attribution text to display when required.
    public var attributionText: String?
    /// A link to the full license terms.
    public var detailsURL: URL?

    /// Creates license metadata.
    public init(
        kind: Kind,
        allowsCommercialUse: Bool,
        requiresAttribution: Bool = false,
        attributionText: String? = nil,
        detailsURL: URL? = nil
    ) {
        self.kind = kind
        self.allowsCommercialUse = allowsCommercialUse
        self.requiresAttribution = requiresAttribution
        self.attributionText = attributionText
        self.detailsURL = detailsURL
    }
}

/// A single downloadable asset in the catalog (music, font, effect, etc.).
public struct CatalogItem: Codable, Sendable, Identifiable, Equatable {
    /// Stable identifier.
    public var id: String
    /// Asset category.
    public var kind: CatalogItemKind
    /// User-visible name.
    public var name: String
    /// Free-text search tags.
    public var tags: [String]
    /// Licensing terms.
    public var license: CatalogLicense
    /// Where to download the asset, when available.
    public var downloadURL: URL?
    /// A preview/thumbnail URL, when available.
    public var previewURL: URL?
    /// Duration in seconds for time-based assets (music, SFX).
    public var durationSeconds: Double?
    /// File size in bytes, when known.
    public var fileSizeBytes: Int?

    /// Creates a catalog item.
    public init(
        id: String,
        kind: CatalogItemKind,
        name: String,
        tags: [String] = [],
        license: CatalogLicense,
        downloadURL: URL? = nil,
        previewURL: URL? = nil,
        durationSeconds: Double? = nil,
        fileSizeBytes: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.tags = tags
        self.license = license
        self.downloadURL = downloadURL
        self.previewURL = previewURL
        self.durationSeconds = durationSeconds
        self.fileSizeBytes = fileSizeBytes
    }
}

/// A search/filter query against the catalog with pagination.
public struct CatalogQuery: Sendable, Equatable {
    /// Restrict to one category, or nil for all.
    public var kind: CatalogItemKind?
    /// Case-insensitive substring matched against name and tags.
    public var searchText: String?
    /// All of these tags must be present (case-insensitive).
    public var tags: [String]
    /// When true, only commercial-use-allowed assets are returned.
    public var commercialUseOnly: Bool
    /// Zero-based page index.
    public var page: Int
    /// Items per page.
    public var pageSize: Int

    /// Creates a catalog query.
    public init(
        kind: CatalogItemKind? = nil,
        searchText: String? = nil,
        tags: [String] = [],
        commercialUseOnly: Bool = false,
        page: Int = 0,
        pageSize: Int = 20
    ) {
        self.kind = kind
        self.searchText = searchText
        self.tags = tags
        self.commercialUseOnly = commercialUseOnly
        self.page = page
        self.pageSize = pageSize
    }
}

/// A single page of catalog results.
public struct CatalogPage: Sendable, Equatable {
    /// Items on this page.
    public var items: [CatalogItem]
    /// Total number of items matching the query across all pages.
    public var totalCount: Int
    /// Zero-based page index of this result.
    public var page: Int
    /// Items per page used for this result.
    public var pageSize: Int

    /// Creates a catalog page.
    public init(items: [CatalogItem], totalCount: Int, page: Int, pageSize: Int) {
        self.items = items
        self.totalCount = totalCount
        self.page = page
        self.pageSize = pageSize
    }

    /// Whether more pages exist after this one.
    public var hasMore: Bool {
        (page + 1) * pageSize < totalCount
    }
}

/// Errors surfaced by catalog providers and the downloader.
public enum CatalogError: Error, Sendable, Equatable {
    /// A transport failure or non-success HTTP status.
    case transport(String)
    /// The item has no download URL.
    case notDownloadable
    /// The catalog payload could not be decoded.
    case malformedCatalog(String)
}

/// Pure search and pagination over an in-memory catalog. Shared by the local and
/// remote providers so filtering behavior is identical and testable.
public enum CatalogSearch {
    /// Filters items by a query (without pagination).
    public static func filter(_ items: [CatalogItem], with query: CatalogQuery) -> [CatalogItem] {
        items.filter { item in
            if let kind = query.kind, item.kind != kind {
                return false
            }
            if query.commercialUseOnly, !item.license.allowsCommercialUse {
                return false
            }
            if let text = query.searchText?.lowercased(), !text.isEmpty {
                let haystack = ([item.name] + item.tags).joined(separator: " ").lowercased()
                if !haystack.contains(text) {
                    return false
                }
            }
            if !query.tags.isEmpty {
                let itemTags = Set(item.tags.map { $0.lowercased() })
                if !query.tags.allSatisfy({ itemTags.contains($0.lowercased()) }) {
                    return false
                }
            }
            return true
        }
    }

    /// Filters and paginates items into a `CatalogPage`.
    public static func page(_ items: [CatalogItem], query: CatalogQuery) -> CatalogPage {
        let filtered = filter(items, with: query)
        let pageSize = max(1, query.pageSize)
        let page = max(0, query.page)
        let start = page * pageSize
        let slice: [CatalogItem]
        if start < filtered.count {
            slice = Array(filtered[start..<min(start + pageSize, filtered.count)])
        } else {
            slice = []
        }
        return CatalogPage(items: slice, totalCount: filtered.count, page: page, pageSize: pageSize)
    }
}
