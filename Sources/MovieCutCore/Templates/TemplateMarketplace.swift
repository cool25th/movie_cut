import Foundation
import os

/// Marketplace metadata for a template.
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

    /// The template payload.
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
        bundle: TemplateBundle,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.category = category
        self.previewImageName = previewImageName
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
        try container.encode(bundle, forKey: .bundle)
        try container.encode(tags, forKey: .tags)
    }
}

/// Local JSON-backed template marketplace facade.
///
/// The app is fully offline / on-device (no `com.apple.security.network.client`
/// entitlement), so the marketplace has no remote catalog or download path:
/// it is generated from and persisted against the built-in template bundles.
public final class TemplateMarketplace: Sendable {
    private static let featuredTag = "featured"

    private let catalogURL: URL
    private let store = TemplateStore()
    private let cachedItems = OSAllocatedUnfairLock(initialState: [TemplateMarketplaceItem]())

    /// Featured marketplace items from the catalog.
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
    public init() {
        catalogURL = Self.defaultCatalogURL()
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

    private func loadCatalog() throws {
        let data = try Data(contentsOf: catalogURL)
        let decoder = JSONDecoder()
        let items = try decoder.decode([TemplateMarketplaceItem].self, from: data)
        applyCatalog(items)
    }

    private func saveCatalog(_ items: [TemplateMarketplaceItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let directoryURL = catalogURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(items)
        try data.write(to: catalogURL, options: [.atomic])
    }

    private func applyCatalog(_ items: [TemplateMarketplaceItem]) {
        cachedItems.withLock { $0 = items }
        items.map(\.bundle).forEach { store.add($0) }
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
