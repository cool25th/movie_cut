import Foundation

/// A built-in or custom sticker asset that can be added as an image overlay.
public struct StickerAsset: Codable, Sendable, Equatable, Identifiable {
    /// The sticker identifier.
    public var id: UUID

    /// User-visible sticker name.
    public var name: String

    /// Emoji payload for built-in emoji stickers.
    public var emoji: String?

    /// Image URL for custom sticker files.
    public var imageURL: URL?

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

    /// Returns the built-in emoji sticker set.
    public static func builtIn() -> StickerLibrary {
        StickerLibrary(stickers: [
            StickerAsset(name: "Smile", emoji: "😀"),
            StickerAsset(name: "Laugh", emoji: "😂"),
            StickerAsset(name: "Heart Eyes", emoji: "😍"),
            StickerAsset(name: "Cool", emoji: "😎"),
            StickerAsset(name: "Party", emoji: "🥳"),
            StickerAsset(name: "Fire", emoji: "🔥"),
            StickerAsset(name: "Sparkles", emoji: "✨"),
            StickerAsset(name: "Star", emoji: "⭐️"),
            StickerAsset(name: "Heart", emoji: "❤️"),
            StickerAsset(name: "Thumbs Up", emoji: "👍"),
            StickerAsset(name: "Clap", emoji: "👏"),
            StickerAsset(name: "Eyes", emoji: "👀"),
            StickerAsset(name: "Rocket", emoji: "🚀"),
            StickerAsset(name: "Crown", emoji: "👑"),
            StickerAsset(name: "Check", emoji: "✅"),
            StickerAsset(name: "Warning", emoji: "⚠️")
        ])
    }
}
