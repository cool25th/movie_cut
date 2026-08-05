import Foundation

/// Sticker/emoji detection shared by the Mac and iOS export engines.
///
/// Both engines kept near-verbatim copies of the emoji-regex and sticker-text
/// extraction. These touch only Foundation + the core `TextClipContent` model,
/// so they live here once.
public enum StickerDetection {
    /// Returns the trimmed emoji text when `textContent` represents a single-emoji
    /// sticker (modern `isSticker` flag or legacy `Apple Color Emoji` font family).
    public static func stickerEmoji(from textContent: TextClipContent) -> String? {
        guard textContent.isSticker || isLegacyStickerContent(textContent) else {
            return nil
        }

        let trimmedText = textContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSingleEmoji(trimmedText) else {
            return nil
        }

        return trimmedText
    }

    /// Whether `textContent` is a legacy single-emoji sticker (font family heuristic).
    public static func isLegacyStickerContent(_ textContent: TextClipContent) -> Bool {
        textContent.fontFamily == "Apple Color Emoji"
    }

    /// Whether `text` is exactly one emoji grapheme cluster (including ZWJ sequences,
    /// regional indicator pairs, modifiers, and variation selectors).
    public static func isSingleEmoji(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let variationSelector = "\u{FE0F}"
        let zeroWidthJoiner = "\u{200D}"
        let emojiAtom = "(?:\\p{Emoji_Presentation}|\\p{Extended_Pictographic}\(variationSelector)?)(?:\\p{Emoji_Modifier})?"
        let pattern = "^(?:(?:\\p{Regional_Indicator}{2})|\(emojiAtom))(?:\(zeroWidthJoiner)\(emojiAtom))*$"
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.count == 1 && text.unicodeScalars.contains { scalar in
                scalar.properties.isEmojiPresentation
            }
        }

        return regex.firstMatch(in: text, range: range)?.range == range
    }
}
