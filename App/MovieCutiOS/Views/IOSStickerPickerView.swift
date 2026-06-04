#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSStickerPickerView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    var onSelect: (StickerAsset) -> Void

    @State private var searchText = ""
    @State private var library = StickerLibrary.builtIn()

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextField("Search stickers", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredStickers) { sticker in
                            Button {
                                onSelect(sticker)
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Text(sticker.emoji ?? "□")
                                        .font(.system(size: 34))
                                        .frame(height: 44)

                                    Text(sticker.name)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, minHeight: 86)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
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
#endif
