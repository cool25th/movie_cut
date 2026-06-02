import Foundation

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

    /// The template payload returned on download.
    public var bundle: TemplateBundle

    /// Creates a marketplace item.
    public init(
        id: UUID = UUID(),
        name: String,
        author: String,
        description: String,
        category: String,
        previewImageName: String? = nil,
        bundle: TemplateBundle
    ) {
        self.id = id
        self.name = name
        self.author = author
        self.description = description
        self.category = category
        self.previewImageName = previewImageName
        self.bundle = bundle
    }
}

/// In-memory template marketplace facade.
public final class TemplateMarketplace: @unchecked Sendable {
    /// Featured marketplace items.
    public private(set) var featured: [TemplateMarketplaceItem]

    /// Marketplace items grouped by category.
    public private(set) var categories: [String: [TemplateMarketplaceItem]]

    /// Static mock marketplace items.
    public static var mockItems: [TemplateMarketplaceItem] {
        [
            TemplateMarketplaceItem(
                id: UUID(uuidString: "9E59F4F0-9D5F-4D9C-85C8-60464DE22E90") ?? UUID(),
                name: "Vertical Launch Reel",
                author: "MovieCut",
                description: "Fast portrait edit for product launches and announcements.",
                category: "Social",
                previewImageName: "marketplace_vertical_launch_reel",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.vertical-launch-reel",
                    name: "Vertical Launch Reel",
                    description: "Fast portrait edit for product launches and announcements.",
                    author: "MovieCut",
                    aspectRatio: .portrait9x16,
                    text: "Launch day",
                    textPosition: CGPoint(x: 540, y: 1460),
                    duration: 9
                )
            ),
            TemplateMarketplaceItem(
                id: UUID(uuidString: "862940D6-3041-4E64-9179-FD0346DB53F7") ?? UUID(),
                name: "Square Promo",
                author: "MovieCut",
                description: "Square social promo with headline and visual placeholders.",
                category: "Social",
                previewImageName: "marketplace_square_promo",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.square-promo",
                    name: "Square Promo",
                    description: "Square social promo with headline and visual placeholders.",
                    author: "MovieCut",
                    aspectRatio: .square1x1,
                    text: "New drop",
                    textPosition: CGPoint(x: 540, y: 900),
                    duration: 7
                )
            ),
            TemplateMarketplaceItem(
                id: UUID(uuidString: "D10A9913-65FC-4B38-901D-9EAAB58703DC") ?? UUID(),
                name: "Investor Update",
                author: "MovieCut",
                description: "Clean 16:9 business update with title and narration tracks.",
                category: "Business",
                previewImageName: "marketplace_investor_update",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.investor-update",
                    name: "Investor Update",
                    description: "Clean 16:9 business update with title and narration tracks.",
                    author: "MovieCut",
                    aspectRatio: .landscape16x9,
                    text: "Quarterly update",
                    textPosition: CGPoint(x: 180, y: 860),
                    duration: 14
                )
            ),
            TemplateMarketplaceItem(
                id: UUID(uuidString: "84C74883-3C66-47C5-B6E1-485EBBC49C55") ?? UUID(),
                name: "Client Case Study",
                author: "MovieCut",
                description: "Structured business story template for customer outcomes.",
                category: "Business",
                previewImageName: "marketplace_client_case_study",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.client-case-study",
                    name: "Client Case Study",
                    description: "Structured business story template for customer outcomes.",
                    author: "MovieCut",
                    aspectRatio: .landscape16x9,
                    text: "Customer story",
                    textPosition: CGPoint(x: 180, y: 850),
                    duration: 18
                )
            ),
            TemplateMarketplaceItem(
                id: UUID(uuidString: "14053C90-0A55-4615-B32B-09FB371B789F") ?? UUID(),
                name: "Weekend Travel Recap",
                author: "MovieCut",
                description: "Energetic travel recap with image, video, and caption tracks.",
                category: "Travel",
                previewImageName: "marketplace_weekend_travel_recap",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.weekend-travel-recap",
                    name: "Weekend Travel Recap",
                    description: "Energetic travel recap with image, video, and caption tracks.",
                    author: "MovieCut",
                    aspectRatio: .portrait9x16,
                    text: "Weekend away",
                    textPosition: CGPoint(x: 540, y: 1500),
                    duration: 12
                )
            ),
            TemplateMarketplaceItem(
                id: UUID(uuidString: "196715DA-96E6-4E6F-B2B5-C7D04B676E27") ?? UUID(),
                name: "City Guide",
                author: "MovieCut",
                description: "Wide travel guide layout with lower-third chapter titles.",
                category: "Travel",
                previewImageName: "marketplace_city_guide",
                bundle: mockBundle(
                    identifier: "com.moviecut.marketplace.city-guide",
                    name: "City Guide",
                    description: "Wide travel guide layout with lower-third chapter titles.",
                    author: "MovieCut",
                    aspectRatio: .landscape16x9,
                    text: "City guide",
                    textPosition: CGPoint(x: 180, y: 880),
                    duration: 16
                )
            )
        ]
    }

    /// Creates an in-memory marketplace.
    public init(featured: [TemplateMarketplaceItem]? = nil) {
        let items = featured ?? Self.mockItems
        self.featured = items
        self.categories = Dictionary(grouping: items, by: \.category)
    }

    /// Searches featured items by name, author, description, or category.
    public func search(query: String) -> [TemplateMarketplaceItem] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return featured
        }

        return featured.filter { item in
            item.name.lowercased().contains(normalizedQuery)
                || item.author.lowercased().contains(normalizedQuery)
                || item.description.lowercased().contains(normalizedQuery)
                || item.category.lowercased().contains(normalizedQuery)
        }
    }

    /// Returns the template bundle for a marketplace item.
    public func download(item: TemplateMarketplaceItem) -> TemplateBundle {
        item.bundle
    }

    private static func mockBundle(
        identifier: String,
        name: String,
        description: String,
        author: String,
        aspectRatio: AspectRatio,
        text: String,
        textPosition: CGPoint,
        duration: TimeInterval
    ) -> TemplateBundle {
        let textDefaults = TextClipContent(
            text: text,
            fontSize: 48,
            fontColor: "#FFFFFF",
            alignment: .center,
            backgroundColor: "#111111CC",
            position: textPosition
        )

        return TemplateBundle(
            identifier: identifier,
            name: name,
            description: description,
            author: author,
            canvasPreset: CanvasPreset(aspectRatio: aspectRatio, frameRate: .fps30),
            tracks: [
                TemplateTrack(
                    kind: .video,
                    name: "Video 1",
                    placeholderClips: [
                        TemplateClip(kind: .video, duration: duration)
                    ]
                ),
                TemplateTrack(
                    kind: .text,
                    name: "Text 1",
                    placeholderClips: [
                        TemplateClip(kind: .text, duration: min(duration, 8), textContent: textDefaults)
                    ]
                )
            ],
            textStyleDefaults: textDefaults,
            exportPreset: ExportSettings(resolution: .p1080, frameRate: .fps30)
        )
    }
}
