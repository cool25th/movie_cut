import AppKit
import SwiftUI
import MovieCutCore

enum MovieCutSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
}

enum MovieCutRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 8
    static let large: CGFloat = 12
}

enum MovieCutTheme {
    static let editorBackground: Color = rgb(0x0F, 0x0F, 0x10)
    static let panelBackground: Color = rgb(0x17, 0x18, 0x1A)
    static let panelBackgroundRaised: Color = rgb(0x1B, 0x1C, 0x1F)
    static let cardBackground: Color = rgb(0x1E, 0x1F, 0x22)
    static let elevatedCardBackground: Color = rgb(0x22, 0x23, 0x26)
    static let controlSurface: Color = rgb(0x24, 0x25, 0x28)
    static let previewBackground: Color = rgb(0x03, 0x03, 0x04)
    static let previewEmptyStateBackground: Color = rgb(0x16, 0x17, 0x19, opacity: 0.86)
    static let timelineBackground: Color = rgb(0x10, 0x11, 0x14)
    static let rulerBackground: Color = rgb(0x1C, 0x1D, 0x20)
    static let trackBackground: Color = rgb(0x14, 0x15, 0x18)
    static let trackHeaderBackground: Color = rgb(0x1B, 0x1C, 0x1F)
    static let timelineGrid: Color = rgb(0x38, 0x3A, 0x3F, opacity: 0.34)
    static let divider: Color = rgb(0x35, 0x36, 0x3A, opacity: 0.46)
    static let border: Color = rgb(0x3D, 0x40, 0x46, opacity: 0.34)
    static let accentCyan: Color = rgb(0x36, 0xD7, 0xFF)
    static let selectedFill: Color = accentCyan.opacity(0.22)
    static let mutedText: Color = rgb(0x9A, 0xA0, 0xA6)

    private static func rgb(_ red: Double, _ green: Double, _ blue: Double, opacity: Double = 1) -> Color {
        Color(.sRGB, red: red / 255.0, green: green / 255.0, blue: blue / 255.0, opacity: opacity)
    }
}

struct MovieCutIconTitle: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    var iconColor: Color = .secondary
    var titleFont: Font = .headline

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: MovieCutSpacing.small) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text(title)
                    .font(titleFont)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct MovieCutPanelHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    let trailing: Trailing

    init(
        title: String,
        systemImage: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: MovieCutSpacing.small) {
            MovieCutIconTitle(title: title, systemImage: systemImage, subtitle: subtitle)
            Spacer(minLength: MovieCutSpacing.small)
            trailing
        }
        .padding(.horizontal, MovieCutSpacing.medium)
        .padding(.vertical, MovieCutSpacing.xSmall)
        .background(MovieCutTheme.panelBackgroundRaised)
    }
}

extension MovieCutPanelHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.trailing = EmptyView()
    }
}

struct MovieCutSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            MovieCutIconTitle(title: title, systemImage: systemImage, titleFont: .caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .movieCutCard()
    }
}

private struct MovieCutCardModifier: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let background: Color
    let border: Color

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 0.5)
            )
    }
}

extension View {
    func movieCutCard(
        padding: CGFloat = MovieCutSpacing.small,
        cornerRadius: CGFloat = MovieCutRadius.medium,
        background: Color = MovieCutTheme.cardBackground,
        border: Color = MovieCutTheme.border
    ) -> some View {
        modifier(MovieCutCardModifier(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            border: border
        ))
    }

    func movieCutPanelBackground() -> some View {
        background(MovieCutTheme.panelBackground)
    }

    func movieCutScrollBackground(_ background: Color = MovieCutTheme.panelBackground) -> some View {
        scrollContentBackground(.hidden)
            .background(background)
    }

    func movieCutInputField() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .stroke(MovieCutTheme.border, lineWidth: 0.5)
            )
    }
}

struct EffectParameterDefinition: Identifiable {
    var id: String { key }
    var key: String
    var title: String
    var range: ClosedRange<Double>
    var defaultValue: Double
    var valueFormat: String = "%.2f"
}

struct EffectRowView: View {
    let effect: Effect
    let parameterDefinitions: [EffectParameterDefinition]
    let onRemove: () -> Void
    let onParameterChange: (String, Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.small) {
            HStack {
                Text(effect.type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            ForEach(parameterDefinitions) { definition in
                EffectParameterRow(
                    definition: definition,
                    value: effect.parameters[definition.key] ?? definition.defaultValue,
                    onChange: { newValue in
                        onParameterChange(definition.key, newValue)
                    }
                )
            }
        }
        .movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.elevatedCardBackground
        )
    }
}

struct EffectParameterRow: View {
    let definition: EffectParameterDefinition
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(definition.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: definition.valueFormat, value))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: { onChange($0) }
            ), in: definition.range)
        }
    }
}

enum EqualizerPresetOption: String, CaseIterable, Identifiable {
    case flat
    case bassBoost
    case trebleBoost
    case voice
    case cinema

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .voice: return "Voice"
        case .cinema: return "Cinema"
        }
    }
}

extension ClipKind {
    var supportsVolume: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }

    var supportsSpeed: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }

    var supportsSubtitles: Bool {
        switch self {
        case .video, .audio:
            return true
        case .image, .text:
            return false
        }
    }
}

extension EffectType {
    var displayName: String {
        switch self {
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .temperature: return "Temperature"
        case .exposure: return "Exposure"
        case .fadeIn: return "Fade In"
        case .fadeOut: return "Fade Out"
        case .crossDissolve: return "Cross Dissolve"
        case .grayscale: return "Grayscale"
        case .sepia: return "Sepia"
        case .blur: return "Blur"
        case .styleTransfer: return "Style Transfer"
        case .cinematicLUT: return "Cinematic LUT"
        case .vintageLUT: return "Vintage LUT"
        case .noirLUT: return "Noir LUT"
        case .vividLUT: return "Vivid LUT"
        case .coolLUT: return "Cool LUT"
        case .externalLUT: return "Imported LUT"
        }
    }
}

extension MaskShape {
    var displayName: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .triangle: return "Triangle"
        case .diamond: return "Diamond"
        case .linear: return "Linear"
        case .brush: return "Brush"
        }
    }
}

extension TransitionType {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .crossDissolve: return "Cross Dissolve"
        case .fadeThroughBlack: return "Fade Through Black"
        case .wipeRight: return "Wipe Right"
        case .wipeLeft: return "Wipe Left"
        case .wipeUp: return "Wipe Up"
        case .wipeDown: return "Wipe Down"
        case .slideLeft: return "Slide Left"
        case .slideRight: return "Slide Right"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .glitch: return "Glitch"
        }
    }
}
