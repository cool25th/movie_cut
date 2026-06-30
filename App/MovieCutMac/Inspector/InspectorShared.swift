import AppKit
import SwiftUI
import MovieCutCore

enum MovieCutSpacing {
    static let xxSmall: CGFloat = 2
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

enum MovieCutTypography {
    static let panelTitle: Font = .caption.weight(.semibold)
    static let panelSubtitle: Font = .caption2
    static let cardTitle: Font = .caption.weight(.semibold)
    static let cardBody: Font = .caption2
    static let metadata: Font = .caption2
    static let toolbar: Font = .caption
    static let micro: Font = .system(size: 9, weight: .medium)
}

enum MovieCutTheme {
    static let editorBackground: Color = rgb(0x0F, 0x0F, 0x10)
    static let panelBackground: Color = rgb(0x17, 0x18, 0x1A)
    static let panelBackgroundRaised: Color = rgb(0x20, 0x21, 0x24)
    static let cardBackground: Color = rgb(0x18, 0x19, 0x1B)
    static let elevatedCardBackground: Color = rgb(0x1B, 0x1C, 0x1E)
    static let controlSurface: Color = rgb(0x1A, 0x1B, 0x1D)
    static let libraryWellBackground: Color = rgb(0x2A, 0x2B, 0x2F)
    static let libraryRailButtonBackground: Color = rgb(0x36, 0x37, 0x3C)
    static let libraryCardBackground: Color = rgb(0x3A, 0x3B, 0x3F)
    static let libraryRaisedCardBackground: Color = rgb(0x44, 0x45, 0x49)
    static let librarySourceRowBackground: Color = rgb(0x34, 0x35, 0x39)
    static let librarySkeletonFill: Color = rgb(0x50, 0x52, 0x58, opacity: 0.60)
    static let libraryThumbnailBackground: Color = rgb(0x42, 0x44, 0x49)
    static let libraryThumbnailStripe: Color = rgb(0x5D, 0x60, 0x66, opacity: 0.38)
    static let inspectorSelectedPanelBackground: Color = rgb(0x21, 0x22, 0x25)
    static let inspectorSelectedCardBackground: Color = rgb(0x22, 0x23, 0x26)
    static let inspectorSelectedRowBackground: Color = rgb(0x26, 0x27, 0x2A)
    static let inspectorSelectedControlSurface: Color = rgb(0x2A, 0x2C, 0x30)
    static let inspectorSelectedBorder: Color = rgb(0x46, 0x49, 0x50, opacity: 0.10)
    static let previewBackground: Color = rgb(0x03, 0x03, 0x04)
    static let previewWellBackground: Color = rgb(0x0F, 0x10, 0x12)
    static let previewLoop4WellSurface: Color = rgb(0x20, 0x22, 0x26)
    static let previewLoop4MatteBase: Color = rgb(0x24, 0x27, 0x2C)
    static let previewLoop4MatteBlock: Color = rgb(0x62, 0x66, 0x6E, opacity: 0.86)
    static let previewLoop4MatteLine: Color = rgb(0x9A, 0xA3, 0xAE, opacity: 0.42)
    static let previewControlBackground: Color = rgb(0x13, 0x14, 0x16, opacity: 0.82)
    static let previewEmptyStateBackground: Color = rgb(0x12, 0x13, 0x15, opacity: 0.94)
    static let timelineBackground: Color = rgb(0x24, 0x26, 0x2B)
    static let rulerBackground: Color = rgb(0x2B, 0x2D, 0x32)
    static let trackBackground: Color = rgb(0x22, 0x24, 0x28)
    static let trackHeaderBackground: Color = rgb(0x35, 0x38, 0x3E)
    static let timelineGrid: Color = rgb(0x4A, 0x4D, 0x55, opacity: 0.34)
    static let timelineVideoClip: Color = rgb(0x1D, 0x30, 0x38)
    static let timelineAudioClip: Color = rgb(0x22, 0x33, 0x29)
    static let timelineTextClip: Color = rgb(0x3A, 0x2B, 0x1F)
    static let timelineStickerClip: Color = rgb(0x38, 0x25, 0x35)
    static let timelineSelectedClipFill: Color = rgb(0x36, 0xD7, 0xFF, opacity: 0.10)
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
    var titleFont: Font = MovieCutTypography.panelTitle

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: MovieCutSpacing.small) {
            Image(systemName: systemImage)
                .font(MovieCutTypography.toolbar.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: MovieCutSpacing.xSmall) {
                Text(title)
                    .font(titleFont)
                    .lineSpacing(0)
                if let subtitle {
                    Text(subtitle)
                        .font(MovieCutTypography.panelSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .lineSpacing(0)
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
            MovieCutIconTitle(title: title, systemImage: systemImage, titleFont: MovieCutTypography.cardTitle)
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
            .font(MovieCutTypography.cardBody)
            .padding(.horizontal, MovieCutSpacing.small)
            .padding(.vertical, MovieCutSpacing.xSmall)
            .background(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .fill(MovieCutTheme.inspectorSelectedControlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MovieCutRadius.small, style: .continuous)
                    .stroke(MovieCutTheme.inspectorSelectedBorder, lineWidth: 0.5)
            )
    }

    func movieCutInspectorSelectedCard() -> some View {
        movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.medium,
            background: MovieCutTheme.inspectorSelectedCardBackground,
            border: MovieCutTheme.inspectorSelectedBorder
        )
    }

    func movieCutInspectorSelectedFlatRow() -> some View {
        movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.inspectorSelectedRowBackground.opacity(0.74),
            border: MovieCutTheme.inspectorSelectedBorder.opacity(0.18)
        )
    }

    func movieCutInspectorSelectedHeader() -> some View {
        movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: MovieCutTheme.inspectorSelectedCardBackground.opacity(0.66),
            border: MovieCutTheme.inspectorSelectedBorder.opacity(0.22)
        )
    }

    func movieCutInspectorOverviewGroup(
        background: Color = MovieCutTheme.controlSurface.opacity(0.42),
        border: Color = MovieCutTheme.border.opacity(0.12)
    ) -> some View {
        movieCutCard(
            padding: MovieCutSpacing.small,
            cornerRadius: MovieCutRadius.small,
            background: background,
            border: border
        )
    }

    func movieCutLibraryBrowserCard(
        padding: CGFloat = MovieCutSpacing.small,
        background: Color = MovieCutTheme.libraryCardBackground,
        border: Color = MovieCutTheme.border.opacity(0.18),
        isSelected: Bool = false
    ) -> some View {
        movieCutCard(
            padding: padding,
            cornerRadius: MovieCutRadius.small,
            background: background,
            border: isSelected ? MovieCutTheme.accentCyan.opacity(0.50) : border
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
                    .font(MovieCutTypography.cardTitle)
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
            background: MovieCutTheme.inspectorSelectedControlSurface.opacity(0.62),
            border: MovieCutTheme.inspectorSelectedBorder.opacity(0.18)
        )
    }
}

struct EffectParameterRow: View {
    let definition: EffectParameterDefinition
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: MovieCutSpacing.xxSmall) {
            HStack {
                Text(definition.title)
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: definition.valueFormat, value))
                    .font(MovieCutTypography.metadata)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
    case voiceEnhance
    case bassBoost
    case trebleBoost
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return "Flat"
        case .voiceEnhance: return "Voice Enhance"
        case .bassBoost: return "Bass Boost"
        case .trebleBoost: return "Treble Boost"
        case .custom: return "Custom"
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
