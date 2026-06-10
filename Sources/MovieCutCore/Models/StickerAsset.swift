import Foundation

/// A built-in or custom sticker asset that can be added as an image overlay.
public struct StickerAsset: Codable, Sendable, Equatable, Identifiable {
    /// The sticker identifier.
    public var id: UUID

    /// User-visible sticker name.
    public var name: String

    /// Emoji payload for built-in emoji stickers.
    public var emoji: String?

    /// Image URL for custom or generated sticker files.
    public var imageURL: URL?

    /// Whether this sticker is backed by an image source instead of an emoji payload.
    public var isImageBacked: Bool {
        imageURL != nil
    }

    /// Creates a sticker asset.
    public init(id: UUID = UUID(), name: String, emoji: String? = nil, imageURL: URL? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.imageURL = imageURL
    }
}

/// A sticker collection.
public struct StickerLibrary: Codable, Sendable, Equatable {
    /// Available stickers.
    public var stickers: [StickerAsset]

    /// Creates a sticker library.
    public init(stickers: [StickerAsset] = []) {
        self.stickers = stickers
    }

    /// Returns the built-in sticker set.
    public static func builtIn() -> StickerLibrary {
        StickerLibrary(stickers: [
            StickerAsset(id: builtInID(1), name: "Smile", emoji: "😀"),
            StickerAsset(id: builtInID(2), name: "Laugh", emoji: "😂"),
            StickerAsset(id: builtInID(3), name: "Heart Eyes", emoji: "😍"),
            StickerAsset(id: builtInID(4), name: "Cool", emoji: "😎"),
            StickerAsset(id: builtInID(5), name: "Party", emoji: "🥳"),
            StickerAsset(id: builtInID(6), name: "Fire", emoji: "🔥"),
            StickerAsset(id: builtInID(7), name: "Sparkles", emoji: "✨"),
            StickerAsset(id: builtInID(8), name: "Star", emoji: "⭐️"),
            StickerAsset(id: builtInID(9), name: "Heart", emoji: "❤️"),
            StickerAsset(id: builtInID(10), name: "Thumbs Up", emoji: "👍"),
            StickerAsset(id: builtInID(11), name: "Clap", emoji: "👏"),
            StickerAsset(id: builtInID(12), name: "Eyes", emoji: "👀"),
            StickerAsset(id: builtInID(13), name: "Rocket", emoji: "🚀"),
            StickerAsset(id: builtInID(14), name: "Crown", emoji: "👑"),
            StickerAsset(id: builtInID(15), name: "Check", emoji: "✅"),
            StickerAsset(id: builtInID(16), name: "Warning", emoji: "⚠️"),
            StickerAsset(id: builtInID(17), name: "Sale Badge", imageURL: builtInImageURL("sale-badge")),
            StickerAsset(id: builtInID(18), name: "New Badge", imageURL: builtInImageURL("new-badge")),
            StickerAsset(id: builtInID(19), name: "Like Badge", imageURL: builtInImageURL("like-badge")),
            StickerAsset(id: builtInID(20), name: "Verified Badge", imageURL: builtInImageURL("verified-badge")),
            StickerAsset(id: builtInID(21), name: "VIP Badge", imageURL: builtInImageURL("vip-badge")),
            StickerAsset(id: builtInID(22), name: "Arrow Badge", imageURL: builtInImageURL("arrow-badge"))
        ])
    }

    private static func builtInID(_ index: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index)) ?? UUID()
    }

    private static func builtInImageURL(_ slug: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MovieCutBuiltInStickers", isDirectory: true)
            .appendingPathComponent("\(slug).png")
    }
}
