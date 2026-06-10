import AppKit
import SwiftUI
import MovieCutCore

struct StickerPickerView: View {
    var onSelect: (StickerAsset) -> Void

    @State private var searchText = ""
    @State private var selectedFilter: StickerFilter = .all
    @State private var library = StickerLibrary.builtIn()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stickers")
                .font(.headline)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            StickerFilterPicker(selection: $selectedFilter)
                .padding(.horizontal, 8)

            TextField("Search stickers", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if visibleStickers.isEmpty {
                        Text("No stickers found")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else if searchQuery.isEmpty {
                        ForEach(stickerCategories) { category in
                            StickerCategorySection(category: category, onSelect: onSelect)
                        }
                    } else {
                        StickerGrid(stickers: visibleStickers, onSelect: onSelect)
                    }
                }
                .padding(8)
            }
        }
    }

    private var searchQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var visibleStickers: [StickerAsset] {
        filteredBySearch(filteredByKind(library.stickers))
    }

    private var stickerCategories: [StickerCategory] {
        let scopedStickers = visibleStickers
        var usedIDs: Set<UUID> = []
        var categories: [StickerCategory] = []

        if selectedFilter != .image {
            let groups: [(String, Set<String>)] = [
                ("Reactions", ["Smile", "Laugh", "Heart Eyes", "Cool", "Party"]),
                ("Emphasis", ["Fire", "Sparkles", "Star", "Warning", "Check"]),
                ("Social", ["Heart", "Thumbs Up", "Clap", "Eyes", "Rocket", "Crown"])
            ]

            for group in groups {
                let stickers = scopedStickers.filter { group.1.contains($0.name) && !$0.isImageBacked }
                guard !stickers.isEmpty else { continue }
                usedIDs.formUnion(stickers.map(\.id))
                categories.append(StickerCategory(name: group.0, stickers: stickers))
            }
        }

        if selectedFilter != .emoji {
            let imageStickers = scopedStickers.filter { $0.isImageBacked }
            if !imageStickers.isEmpty {
                usedIDs.formUnion(imageStickers.map(\.id))
                categories.append(StickerCategory(name: "Badges/Image", stickers: imageStickers))
            }
        }

        let remaining = scopedStickers.filter { !usedIDs.contains($0.id) }
        if !remaining.isEmpty {
            categories.append(StickerCategory(name: "Other", stickers: remaining))
        }

        return categories
    }

    private func filteredByKind(_ stickers: [StickerAsset]) -> [StickerAsset] {
        switch selectedFilter {
        case .all:
            return stickers
        case .emoji:
            return stickers.filter { !$0.isImageBacked && $0.emoji != nil }
        case .image:
            return stickers.filter(\.isImageBacked)
        }
    }

    private func filteredBySearch(_ stickers: [StickerAsset]) -> [StickerAsset] {
        let query = searchQuery
        guard !query.isEmpty else { return stickers }

        return stickers.filter { sticker in
            sticker.searchTokens.contains { $0.contains(query) }
        }
    }
}

private enum StickerFilter: String, CaseIterable, Identifiable {
    case all
    case emoji
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .emoji:
            return "Emoji"
        case .image:
            return "Badges/Image"
        }
    }
}

private struct StickerFilterPicker: View {
    @Binding var selection: StickerFilter

    var body: some View {
        Picker("Sticker kind", selection: $selection) {
            ForEach(StickerFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

private struct StickerCategorySection: View {
    let category: StickerCategory
    let onSelect: (StickerAsset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(category.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            StickerGrid(stickers: category.stickers, onSelect: onSelect)
        }
    }
}

private struct StickerGrid: View {
    let stickers: [StickerAsset]
    let onSelect: (StickerAsset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(stickers) { sticker in
                StickerTile(sticker: sticker, onSelect: onSelect)
            }
        }
    }
}

private struct StickerTile: View {
    let sticker: StickerAsset
    let onSelect: (StickerAsset) -> Void

    var body: some View {
        Button {
            onSelect(sticker)
        } label: {
            VStack(spacing: 5) {
                StickerPreviewGlyph(sticker: sticker)
                    .frame(width: 48, height: 42)

                Text(sticker.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                HStack(spacing: 3) {
                    Image(systemName: sticker.kindIconName)
                        .font(.caption2)
                    Text(sticker.kindLabel)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 78)
            .background(Color(nsColor: .separatorColor).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(sticker.name) \(sticker.kindLabel.lowercased()) sticker")
    }
}

private struct StickerPreviewGlyph: View {
    let sticker: StickerAsset

    var body: some View {
        if let emoji = sticker.emoji, !sticker.isImageBacked {
            Text(emoji)
                .font(.system(size: 30))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let image = StickerImageProvider.previewImage(for: sticker) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.16))
                Image(systemName: "seal.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StickerCategory: Identifiable {
    let name: String
    let stickers: [StickerAsset]

    var id: String { name }
}

private extension StickerAsset {
    var kindLabel: String {
        isImageBacked ? "Badge" : "Emoji"
    }

    var kindIconName: String {
        isImageBacked ? "photo.on.rectangle" : "face.smiling"
    }

    var searchTokens: [String] {
        var tokens = [
            name.lowercased(),
            kindLabel.lowercased(),
            "sticker"
        ]

        if let emoji {
            tokens.append(emoji.lowercased())
            tokens.append("emoji")
        }

        if isImageBacked {
            tokens.append(contentsOf: ["image", "badge", "visual", "png"])
        }

        return tokens
    }
}

@MainActor
enum StickerImageProvider {
    static func ensureImageURL(for sticker: StickerAsset) -> URL? {
        guard let imageURL = sticker.imageURL else {
            return nil
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: imageURL.path) {
            return imageURL
        }

        if let style = builtInBadgeStyle(for: imageURL) {
            try? fileManager.createDirectory(at: imageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? renderBadge(style, to: imageURL)
        }

        return imageURL
    }

    static func readableImageURL(for sticker: StickerAsset) -> URL? {
        guard let imageURL = ensureImageURL(for: sticker),
              FileManager.default.isReadableFile(atPath: imageURL.path)
        else {
            return nil
        }

        return imageURL
    }

    static func previewImage(for sticker: StickerAsset) -> NSImage? {
        guard let imageURL = ensureImageURL(for: sticker) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
    }

    private static func builtInBadgeStyle(for imageURL: URL) -> BadgeStyle? {
        badgeStyles[imageURL.deletingPathExtension().lastPathComponent]
    }

    private static let badgeStyles: [String: BadgeStyle] = [
        "sale-badge": BadgeStyle(text: "SALE", fill: NSColor(srgbRed: 0.96, green: 0.16, blue: 0.25, alpha: 1), stroke: .white),
        "new-badge": BadgeStyle(text: "NEW", fill: NSColor(srgbRed: 0.12, green: 0.42, blue: 0.95, alpha: 1), stroke: .white),
        "like-badge": BadgeStyle(text: "LIKE", fill: NSColor(srgbRed: 0.08, green: 0.62, blue: 0.44, alpha: 1), stroke: .white),
        "verified-badge": BadgeStyle(text: "OK", fill: NSColor(srgbRed: 0.02, green: 0.62, blue: 0.90, alpha: 1), stroke: .white),
        "vip-badge": BadgeStyle(text: "VIP", fill: NSColor(srgbRed: 0.55, green: 0.28, blue: 0.88, alpha: 1), stroke: .white),
        "arrow-badge": BadgeStyle(text: "GO", fill: NSColor(srgbRed: 1.00, green: 0.57, blue: 0.10, alpha: 1), stroke: .white)
    ]

    private static func renderBadge(_ style: BadgeStyle, to url: URL) throws {
        let size = CGSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: NSPoint(x: 0, y: 0), size: size).fill()

        let badgeRect = NSRect(x: 50, y: 132, width: 412, height: 248)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -8)
        shadow.set()

        let path = NSBezierPath(roundedRect: badgeRect, xRadius: 58, yRadius: 58)
        style.fill.setFill()
        path.fill()
        NSShadow().set()

        style.stroke.setStroke()
        path.lineWidth = 16
        path.stroke()

        let textLength = max(style.text.count, 1)
        let fontSize = textLength > 3 ? 82.0 : 104.0
        let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
            .kern: 2.0
        ]
        let textRect = badgeRect.insetBy(dx: 30, dy: (badgeRect.height - fontSize) * 0.5 - 8)
        style.text.draw(in: textRect, withAttributes: attributes)

        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try pngData.write(to: url, options: .atomic)
    }
}

private struct BadgeStyle {
    let text: String
    let fill: NSColor
    let stroke: NSColor
}
