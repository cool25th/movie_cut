import SwiftUI
import MovieCutCore

struct StickerPickerView: View {
    var onSelect: (StickerAsset) -> Void

    @State private var searchText = ""
    @State private var library = StickerLibrary.builtIn()

    private let columns = [
        GridItem(.adaptive(minimum: 56), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search stickers", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredStickers) { sticker in
                        Button {
                            onSelect(sticker)
                        } label: {
                            VStack(spacing: 4) {
                                Text(sticker.emoji ?? "□")
                                    .font(.system(size: 28))
                                    .frame(width: 44, height: 36)
                                Text(sticker.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(Color(nsColor: .separatorColor).opacity(0.12))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
            }
        }
    }

    private var filteredStickers: [StickerAsset] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return library.stickers }

        return library.stickers.filter { sticker in
            sticker.name.lowercased().contains(query) || (sticker.emoji?.contains(query) ?? false)
        }
    }
}
