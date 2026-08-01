#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSTemplatePickerView: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateID: String?

    private var templates: [TemplateBundle] {
        TemplateStore.shared.bundles
    }

    private var selectedTemplate: TemplateBundle? {
        if let selectedTemplateID,
           let template = templates.first(where: { $0.identifier == selectedTemplateID }) {
            return template
        }

        return templates.first
    }

    private let columns = [
        GridItem(.adaptive(minimum: 148), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let selectedTemplate {
                    IOSTemplatePreview(template: selectedTemplate)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .secondarySystemBackground))
                }

                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                        ForEach(templates, id: \.identifier) { template in
                            templateCard(template)
                        }
                    }
                    .padding(16)
                }

                Divider()

                HStack(spacing: 12) {
                    if let selectedTemplate {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selectedTemplate.canvasPreset.aspectRatio.displayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(durationText(for: selectedTemplate))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Button {
                        guard let selectedTemplate else { return }
                        Task {
                            await applyTemplate(selectedTemplate)
                            dismiss()
                        }
                    } label: {
                        Label("Use Template", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedTemplate == nil)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .navigationTitle("Templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedTemplateID = selectedTemplate?.identifier
            }
        }
    }

    private func templateCard(_ template: TemplateBundle) -> some View {
        Button {
            selectedTemplateID = template.identifier
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(template.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(template.canvasPreset.aspectRatio.shortDisplayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.14))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(template.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)

                IOSTemplateTrackSummary(template: template)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(cardBackground(for: template))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(cardBorderColor(for: template), lineWidth: selectedTemplateID == template.identifier ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func applyTemplate(_ template: TemplateBundle) async {
        let project = TemplateStore.shared.createProject(from: template)
        viewModel.currentProject = project
        viewModel.selectedClipId = nil
        viewModel.playheadTime = 0
        viewModel.isPlaying = false
        viewModel.lastErrorMessage = nil
    }

    private func cardBackground(for template: TemplateBundle) -> Color {
        selectedTemplateID == template.identifier
            ? Color.accentColor.opacity(0.14)
            : Color(uiColor: .secondarySystemGroupedBackground)
    }

    private func cardBorderColor(for template: TemplateBundle) -> Color {
        selectedTemplateID == template.identifier
            ? Color.accentColor
            : Color.secondary.opacity(0.22)
    }

    private func durationText(for template: TemplateBundle) -> String {
        let duration = template.tracks
            .map { track in
                track.placeholderClips.map(\.duration).reduce(0, +)
            }
            .reduce(0, max)

        guard duration > 0 else { return "No clips" }
        return "\(Int(duration.rounded()))s template"
    }
}

private struct IOSTemplatePreview: View {
    var template: TemplateBundle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(template.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Text(template.canvasPreset.aspectRatio.shortDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack(alignment: .center, spacing: 14) {
                IOSTemplateCanvasPreview(template: template)
                    .frame(width: 116, height: 92)

                VStack(alignment: .leading, spacing: 8) {
                    IOSTemplateTrackSummary(template: template)

                    Text(trackText(for: template))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func trackText(for template: TemplateBundle) -> String {
        let trackNames = template.tracks.map(\.name)
        guard !trackNames.isEmpty else { return "Empty template" }
        return trackNames.joined(separator: ", ")
    }
}

private struct IOSTemplateCanvasPreview: View {
    var template: TemplateBundle

    var body: some View {
        GeometryReader { proxy in
            let size = template.canvasPreset.size
            let ratio = size.width / max(size.height, 1)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)

                ForEach(Array(template.tracks.enumerated()), id: \.offset) { index, track in
                    templateLayer(for: track.kind, index: index)
                }

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func templateLayer(for kind: TrackKind, index: Int) -> some View {
        let inset = CGFloat(index) * 8

        return RoundedRectangle(cornerRadius: 5)
            .fill(layerColor(for: kind).opacity(0.78))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(SwiftUI.EdgeInsets(top: 14 + inset, leading: 14 + inset, bottom: 14 + inset, trailing: 14 + inset))
            .overlay {
                Image(systemName: iconName(for: kind))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.86))
            }
    }

    private func layerColor(for kind: TrackKind) -> Color {
        switch kind {
        case .video:
            return .blue
        case .audio:
            return .green
        case .text:
            return .orange
        }
    }

    private func iconName(for kind: TrackKind) -> String {
        switch kind {
        case .video:
            return "play.rectangle.fill"
        case .audio:
            return "waveform"
        case .text:
            return "textformat"
        }
    }
}

private struct IOSTemplateTrackSummary: View {
    var template: TemplateBundle

    var body: some View {
        HStack(spacing: 6) {
            ForEach(template.tracks.indices, id: \.self) { index in
                let track = template.tracks[index]

                Label("\(track.placeholderClips.count)", systemImage: iconName(for: track.kind))
                    .font(.caption2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func iconName(for kind: TrackKind) -> String {
        switch kind {
        case .video:
            return "video.fill"
        case .audio:
            return "waveform"
        case .text:
            return "textformat"
        }
    }
}
#endif
