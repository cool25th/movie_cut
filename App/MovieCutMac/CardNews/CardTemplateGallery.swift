import AppKit
import MovieCutCore
import SwiftUI

/// G-19's two-action template chooser plus atomic master-style editor.
struct CardTemplateGallery: View {
    @Bindable var viewModel: EditorViewModel
    @State private var selectedTemplateID = BuiltinCardTemplates.all.first?.id

    private let columns = [
        GridItem(.flexible(), spacing: MovieCutSpacing.small),
        GridItem(.flexible(), spacing: MovieCutSpacing.small)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MovieCutPanelHeader(
                title: "Template Sets",
                systemImage: "square.grid.2x2",
                subtitle: "10 complete five-page sets"
            )

            ScrollView {
                VStack(alignment: .leading, spacing: MovieCutSpacing.large) {
                    LazyVGrid(columns: columns, spacing: MovieCutSpacing.small) {
                        ForEach(BuiltinCardTemplates.all) { template in
                            templateCard(template)
                        }
                    }

                    Button {
                        guard let selectedTemplate else { return }
                        Task { await viewModel.applyCardTemplate(selectedTemplate) }
                    } label: {
                        Label("Apply Template", systemImage: "rectangle.stack.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MovieCutTheme.accentCyan)
                    .disabled(selectedTemplate == nil)
                    .accessibilityIdentifier("cardTemplate.apply")
                    .accessibilityLabel("Apply selected card template")
                    .accessibilityHint("Replaces the card draft with five editable pages in the second action and can be undone once.")

                    Divider()
                        .overlay(MovieCutTheme.divider)

                    CardMasterStylePanel(viewModel: viewModel)
                }
                .padding(MovieCutSpacing.medium)
            }
            .movieCutScrollBackground(MovieCutTheme.panelBackground)
        }
        .background(MovieCutTheme.panelBackground)
        .accessibilityIdentifier("cardTemplate.gallery")
    }

    private var selectedTemplate: CardTemplateSet? {
        BuiltinCardTemplates.all.first { $0.id == selectedTemplateID }
    }

    private func templateCard(_ template: CardTemplateSet) -> some View {
        let selected = template.id == selectedTemplateID
        return Button {
            selectedTemplateID = template.id
        } label: {
            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                templatePreview(template)

                Text(template.name)
                    .font(MovieCutTypography.cardTitle)
                    .lineLimit(1)

                Text(template.defaultMasterStyle.fontFamily)
                    .font(MovieCutTypography.micro)
                    .foregroundStyle(MovieCutTheme.mutedText)
                    .lineLimit(1)

                HStack(spacing: 3) {
                    ForEach(Array(template.pages.enumerated()), id: \.offset) { _, page in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(roleColor(page.role, template: template))
                            .frame(height: 5)
                    }
                }
            }
            .padding(MovieCutSpacing.xSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                    .fill(selected ? MovieCutTheme.selectedFill : MovieCutTheme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                    .stroke(selected ? MovieCutTheme.accentCyan : MovieCutTheme.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("cardTemplate.set.\(template.id)")
        .accessibilityLabel("\(template.name), five page template, \(template.defaultMasterStyle.fontFamily)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityHint("Selects this complete set. Use Apply Template for the second and final action.")
    }

    private func templatePreview(_ template: CardTemplateSet) -> some View {
        let style = template.defaultMasterStyle
        return ZStack(alignment: .bottomLeading) {
            Color(cardHex: style.secondaryColorHex)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(cardHex: style.primaryColorHex))
                .frame(width: 62, height: 15)
                .offset(x: 8, y: -27)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(cardHex: style.primaryColorHex).opacity(0.72))
                .frame(width: 42, height: 7)
                .offset(x: 8, y: -14)

            Text("Aa")
                .font(.custom(style.fontFamily, size: 17).weight(.bold))
                .foregroundStyle(Color(cardHex: style.primaryColorHex))
                .padding(8)

            if let placement = style.logoPlacement {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color(cardHex: style.primaryColorHex))
                        .frame(
                            width: max(10, CGFloat(placement.width) * proxy.size.width),
                            height: max(4, CGFloat(placement.height) * proxy.size.height)
                        )
                        .position(
                            x: CGFloat(placement.x + placement.width / 2) * proxy.size.width,
                            y: CGFloat(placement.y + placement.height / 2) * proxy.size.height
                        )
                }
            }
        }
        .frame(height: 74)
        .clipShape(RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func roleColor(_ role: CardPageRole, template: CardTemplateSet) -> Color {
        switch role {
        case .cover, .closing:
            Color(cardHex: template.defaultMasterStyle.primaryColorHex)
        case .body:
            Color(cardHex: template.defaultMasterStyle.secondaryColorHex)
        case .emphasis:
            MovieCutTheme.accentCyan
        }
    }
}

private struct CardMasterStylePanel: View {
    @Bindable var viewModel: EditorViewModel
    @State private var fontFamily: String
    @State private var primaryColor: Color
    @State private var secondaryColor: Color
    @State private var logoPlacement: LogoPlacementChoice
    @State private var selectedPresetID: String

    init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
        let style = viewModel.currentProject.cardDocument?.masterStyle
            ?? BuiltinCardTemplates.all[0].defaultMasterStyle
        _fontFamily = State(initialValue: style.fontFamily)
        _primaryColor = State(initialValue: Color(cardHex: style.primaryColorHex))
        _secondaryColor = State(initialValue: Color(cardHex: style.secondaryColorHex))
        _logoPlacement = State(initialValue: LogoPlacementChoice(placement: style.logoPlacement))
        _selectedPresetID = State(initialValue: Self.presetID(matching: style) ?? "custom")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.medium) {
            MovieCutIconTitle(
                title: "Master Style",
                systemImage: "paintbrush.pointed",
                subtitle: "Inherited across every page"
            )

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text("Master look")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                Picker("Master look", selection: $selectedPresetID) {
                    Text("Current / Custom").tag("custom")
                    ForEach(BuiltinCardTemplates.all) { template in
                        Text(template.name).tag(template.id)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("cardMaster.preset")
                .accessibilityLabel("Master style preset")
                .accessibilityHint("Choose one look to set font colors and logo placement together, then Apply within three actions.")
            }

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text("Font family")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                Picker("Font family", selection: $fontFamily) {
                    ForEach(fontOptions, id: \.self) { font in
                        Text(font).tag(font)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("cardMaster.font")
                .accessibilityLabel("Master font family")
                .accessibilityHint("Changes the draft master font; Apply Master Style confirms it across inherited text.")
            }

            colorRow(
                title: "Primary color",
                identifier: "cardMaster.primaryColor",
                color: $primaryColor
            )

            colorRow(
                title: "Secondary color",
                identifier: "cardMaster.secondaryColor",
                color: $secondaryColor
            )

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text("Logo placement")
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                Picker("Logo placement", selection: $logoPlacement) {
                    ForEach(LogoPlacementChoice.allCases) { placement in
                        Text(placement.title).tag(placement)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier("cardMaster.logoPlacement")
                .accessibilityLabel("Master logo placement")
                .accessibilityHint("Chooses where inheriting logos appear on every page.")
            }

            Button {
                let style = CardMasterStyle(
                    fontFamily: fontFamily,
                    primaryColorHex: primaryColor.cardHexString,
                    secondaryColorHex: secondaryColor.cardHexString,
                    logoPlacement: logoPlacement.normalizedRect
                )
                Task { await viewModel.setCardMasterStyle(style) }
            } label: {
                Label("Apply Master Style", systemImage: "paintbrush.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(MovieCutTheme.accentCyan)
            .accessibilityIdentifier("cardMaster.apply")
            .accessibilityLabel("Apply master font colors and logo placement")
            .accessibilityHint("Confirms all master attributes together as one command and one undo step within the three-action limit.")
        }
        .padding(MovieCutSpacing.medium)
        .background(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .fill(MovieCutTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: MovieCutRadius.medium, style: .continuous)
                .stroke(MovieCutTheme.border, lineWidth: 1)
        )
        .accessibilityIdentifier("cardMaster.panel")
        .onChange(of: selectedPresetID) { _, presetID in
            guard let template = BuiltinCardTemplates.all.first(where: { $0.id == presetID }) else { return }
            load(template.defaultMasterStyle)
        }
        .onChange(of: viewModel.currentProject.cardDocument?.masterStyle) { _, style in
            guard let style else { return }
            load(style)
            selectedPresetID = Self.presetID(matching: style) ?? "custom"
        }
    }

    private var fontOptions: [String] {
        var values = [fontFamily, "System"]
        for template in BuiltinCardTemplates.all
        where !values.contains(template.defaultMasterStyle.fontFamily) {
            values.append(template.defaultMasterStyle.fontFamily)
        }
        return values
    }

    private func colorRow(
        title: String,
        identifier: String,
        color: Binding<Color>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
                Text(title)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(MovieCutTheme.mutedText)
                Text(color.wrappedValue.cardHexString)
                    .font(MovieCutTypography.micro.monospaced())
            }
            Spacer()
            ColorPicker(title, selection: color, supportsOpacity: false)
                .labelsHidden()
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(title)
                .accessibilityHint("Sets the master \(title.lowercased()) applied with the master style command.")
        }
    }

    private func load(_ style: CardMasterStyle) {
        fontFamily = style.fontFamily
        primaryColor = Color(cardHex: style.primaryColorHex)
        secondaryColor = Color(cardHex: style.secondaryColorHex)
        logoPlacement = LogoPlacementChoice(placement: style.logoPlacement)
    }

    private static func presetID(matching style: CardMasterStyle) -> String? {
        BuiltinCardTemplates.all.first { $0.defaultMasterStyle == style }?.id
    }
}

private enum LogoPlacementChoice: String, CaseIterable, Identifiable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing
    case hidden

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeading: "Top Left"
        case .topTrailing: "Top Right"
        case .bottomLeading: "Bottom Left"
        case .bottomCenter: "Bottom Center"
        case .bottomTrailing: "Bottom Right"
        case .hidden: "Hidden"
        }
    }

    var normalizedRect: NormalizedRect? {
        switch self {
        case .topLeading: NormalizedRect(x: 0.08, y: 0.07, width: 0.2, height: 0.09)
        case .topTrailing: NormalizedRect(x: 0.72, y: 0.07, width: 0.2, height: 0.09)
        case .bottomLeading: NormalizedRect(x: 0.08, y: 0.84, width: 0.2, height: 0.09)
        case .bottomCenter: NormalizedRect(x: 0.4, y: 0.84, width: 0.2, height: 0.09)
        case .bottomTrailing: NormalizedRect(x: 0.72, y: 0.84, width: 0.2, height: 0.09)
        case .hidden: nil
        }
    }

    init(placement: NormalizedRect?) {
        guard let placement else {
            self = .hidden
            return
        }
        let centerX = placement.x + placement.width / 2
        let centerY = placement.y + placement.height / 2
        if centerY < 0.5 {
            self = centerX < 0.5 ? .topLeading : .topTrailing
        } else if centerX < 0.34 {
            self = .bottomLeading
        } else if centerX > 0.66 {
            self = .bottomTrailing
        } else {
            self = .bottomCenter
        }
    }
}

private extension Color {
    var cardHexString: String {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        return String(
            format: "#%02X%02X%02X",
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded())
        )
    }
}
