#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSFilterPickerView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    private let filters: [FilterOption] = [
        FilterOption(name: "None", type: nil, color: .gray),
        FilterOption(name: "Grayscale", type: .grayscale, color: .white),
        FilterOption(name: "Sepia", type: .sepia, color: .brown),
        FilterOption(name: "Blur", type: .blur, color: .blue),
        FilterOption(name: "Style", type: .styleTransfer, color: .indigo),
        FilterOption(name: "Cinematic", type: .cinematicLUT, color: .teal),
        FilterOption(name: "Vintage", type: .vintageLUT, color: .orange),
        FilterOption(name: "Noir", type: .noirLUT, color: .black),
        FilterOption(name: "Vivid", type: .vividLUT, color: .pink),
        FilterOption(name: "Cool", type: .coolLUT, color: .cyan),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filters) { filter in
                        Button {
                            Task {
                                if let type = filter.type {
                                    await viewModel.applyEffect(type.rawValue)
                                } else {
                                    await viewModel.clearEffects()
                                }
                                dismiss()
                            }
                        } label: {
                            VStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(filter.color.gradient)
                                    .frame(height: 90)
                                    .overlay {
                                        if isSelected(filter) {
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
                        // A11Y-01: the checkmark overlay is invisible to
                        // VoiceOver — announce the selection state.
                        .accessibilityLabel(filter.name)
                        .accessibilityValue(isSelected(filter) ? "Selected" : "")
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

    private func isSelected(_ filter: FilterOption) -> Bool {
        guard let clip = viewModel.selectedClip else { return filter.type == nil }
        guard let type = filter.type else {
            return clip.effects.isEmpty
        }
        return clip.effects.contains { $0.type == type }
    }

    private struct FilterOption: Identifiable {
        var name: String
        var type: EffectType?
        var color: Color

        var id: String {
            type?.rawValue ?? "none"
        }
    }
}
#endif
