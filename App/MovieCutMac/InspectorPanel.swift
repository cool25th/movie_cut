import SwiftUI
import MovieCutCore

struct InspectorPanel: View {
    var viewModel: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Inspector")
                .font(.headline)
                .padding(12)

            Divider()

            if let clip = viewModel.selectedClip {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Clip Info
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Clip Info")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            LabeledContent("Type", value: clip.kind.rawValue)
                            LabeledContent("Duration", value: String(format: "%.2fs", clip.timelineRange.duration))
                        }

                        // Transform
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Transform")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            LabeledContent("X", value: String(format: "%.1f", clip.transform.position.x))
                            LabeledContent("Y", value: String(format: "%.1f", clip.transform.position.y))
                            LabeledContent("Scale", value: String(format: "%.2f", clip.transform.scale.width))
                            LabeledContent("Rotation", value: String(format: "%.1f\u{00B0}", clip.transform.rotation))
                        }

                        // Opacity
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Opacity")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            HStack {
                                Slider(value: Binding(
                                    get: { clip.opacity },
                                    set: { newValue in
                                        Task { await viewModel.updateSelectedOpacity(newValue) }
                                    }
                                ), in: 0 ... 1)
                                Text(String(format: "%.0f%%", clip.opacity * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44)
                            }
                        }

                        // Text Content
                        if let textContent = clip.textContent {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Text")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                TextField("Text", text: Binding(
                                    get: { textContent.text },
                                    set: { newValue in
                                        var updated = textContent
                                        updated.text = newValue
                                        Task { await viewModel.updateSelectedTextContent(updated) }
                                    }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                        }

                        // Effects
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Effects")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            if clip.effects.isEmpty {
                                Text("No effects")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            ForEach(clip.effects) { effect in
                                HStack {
                                    Text(effect.type.rawValue)
                                        .font(.caption)
                                    Spacer()
                                    ForEach(
                                        Array(effect.parameters.sorted(by: { $0.key < $1.key })),
                                        id: \.key
                                    ) { key, value in
                                        Text("\(key): \(String(format: "%.2f", value))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Select a clip to inspect")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 240)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
