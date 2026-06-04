#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSFilterPickerView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private let filters: [(name: String, id: String, color: Color)] = [
        ("None", "none", .gray),
        ("Sepia", "CISepiaTone", .brown),
        ("Noir", "CIPhotoEffectNoir", .black),
        ("Chrome", "CIPhotoEffectChrome", .cyan),
        ("Fade", "CIPhotoEffectFade", .secondary),
        ("Instant", "CIPhotoEffectInstant", .orange),
        ("Mono", "CIPhotoEffectMono", .white),
        ("Tonal", "CIPhotoEffectTonal", .gray.opacity(0.6)),
        ("Transfer", "CIPhotoEffectTransfer", .indigo),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filters, id: \.id) { filter in
                        Button {
                            Task {
                                await viewModel.applyEffect(filter.id)
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(filter.color.gradient)
                                    .frame(height: 90)
                                    .overlay {
                                        if isSelected(filter.id) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title2)
                                                .foregroundStyle(.white)
                                                .shadow(radius: 2)
                                        }
                                    }

                                Text(filter.name)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func isSelected(_ filterId: String) -> Bool {
        guard let clip = viewModel.selectedClip else { return filterId == "none" }
        if filterId == "none" {
            return clip.effects.isEmpty
        }
        return clip.effects.contains { $0.type == .custom && $0.parameters["filterId"] as? String == filterId }
    }
}
#endif
