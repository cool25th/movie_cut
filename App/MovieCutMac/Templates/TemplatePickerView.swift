import SwiftUI
import MovieCutCore

struct TemplatePickerView: View {
    var viewModel: EditorViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTemplateID: String?

    private var templates: [TemplateBundle] {
        viewModel.templateStore.bundles
    }

    private var selectedTemplate: TemplateBundle? {
        if let selectedTemplateID,
           let template = templates.first(where: { $0.identifier == selectedTemplateID }) {
            return template
        }

        return templates.first
    }

    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Templates")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(templates, id: \.identifier) { template in
                        templateCard(template)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 260)

            HStack {
                if let selectedTemplate {
                    Text(selectedTemplate.canvasPreset.aspectRatio.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    guard let selectedTemplate else { return }
                    Task {
                        await viewModel.createProjectFromTemplate(selectedTemplate)
                        dismiss()
                    }
                } label: {
                    Label("Create from Template", systemImage: "doc.badge.plus")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedTemplate == nil)
            }
        }
        .padding(18)
        .frame(width: 680, height: 430)
        .onAppear {
            selectedTemplateID = selectedTemplate?.identifier
        }
    }

    private func templateCard(_ template: TemplateBundle) -> some View {
        Button {
            selectedTemplateID = template.identifier
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(template.canvasPreset.aspectRatio.shortDisplayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color(nsColor: .separatorColor).opacity(0.16))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            .background(cardBackground(for: template))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(cardBorderColor(for: template), lineWidth: selectedTemplateID == template.identifier ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func cardBackground(for template: TemplateBundle) -> Color {
        selectedTemplateID == template.identifier
            ? Color.accentColor.opacity(0.12)
            : Color(nsColor: .controlBackgroundColor)
    }

    private func cardBorderColor(for template: TemplateBundle) -> Color {
        selectedTemplateID == template.identifier
            ? Color.accentColor
            : Color(nsColor: .separatorColor)
    }
}

private extension AspectRatio {
    var shortDisplayName: String {
        switch self {
        case .landscape16x9:
            return "16:9"
        case .portrait9x16:
            return "9:16"
        case .square1x1:
            return "1:1"
        case .wide21x9:
            return "21:9"
        case .custom:
            return "Custom"
        }
    }
}
