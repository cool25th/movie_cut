import SwiftUI
import MovieCutCore

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
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(8)
        .background(Color(nsColor: .separatorColor).opacity(0.12))
        .cornerRadius(6)
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
        }
    }
}
