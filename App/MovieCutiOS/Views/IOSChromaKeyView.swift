#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSChromaKeyView: View {
    var clip: Clip
    var onChange: (ChromaKeySettings?) -> Void

    var body: some View {
        Section("Chroma Key / Green Screen") {
            Toggle("Enable Chroma Key", isOn: Binding(
                get: { clip.chromaKey != nil },
                set: { isEnabled in
                    onChange(isEnabled ? clip.chromaKey ?? .greenScreen() : nil)
                }
            ))

            if clip.chromaKey != nil {
                ColorPicker("Key Color", selection: Binding(
                    get: { Color(hexRGB: activeSettings.keyColor) ?? .green },
                    set: { color in
                        updateSettings { settings in
                            settings.keyColor = color.hexRGB ?? settings.keyColor
                        }
                    }
                ))

                HStack(spacing: 8) {
                    Button("Green") {
                        onChange(.greenScreen())
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)

                    Button("Blue") {
                        onChange(.blueScreen())
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                slider(
                    title: "Tolerance",
                    value: activeSettings.tolerance,
                    onChange: { newValue in
                        updateSettings { $0.tolerance = newValue }
                    }
                )

                slider(
                    title: "Softness",
                    value: activeSettings.softness,
                    onChange: { newValue in
                        updateSettings { $0.softness = newValue }
                    }
                )

                slider(
                    title: "Spill Suppression",
                    value: activeSettings.spillSuppression,
                    onChange: { newValue in
                        updateSettings { $0.spillSuppression = newValue }
                    }
                )
            }
        }
    }

    private var activeSettings: ChromaKeySettings {
        clip.chromaKey ?? .greenScreen()
    }

    private func slider(title: String, value: Double, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: Binding(
                get: { value },
                set: onChange
            ), in: 0 ... 1)
            .frame(minHeight: 44)
            // A11Y-01: explicit label/value — the visible title is a sibling
            // Text, so without this VoiceOver announces a bare "slider".
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text("\(Int((value * 100).rounded()))%"))
        }
    }

    private func updateSettings(_ update: (inout ChromaKeySettings) -> Void) {
        var settings = activeSettings
        update(&settings)
        onChange(settings)
    }
}

private extension Color {
    init?(hexRGB: String) {
        guard let rgb = HexColorMath.rgb(fromHex: hexRGB) else { return nil }
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    var hexRGB: String? {
        guard let components = self.cgColor?.components else { return nil }
        switch self.cgColor?.numberOfComponents {
        case 2:
            return HexColorMath.hexRGB(
                red: Double(components[0]),
                green: Double(components[0]),
                blue: Double(components[0])
            )
        case 4:
            return HexColorMath.hexRGB(
                red: Double(components[0]),
                green: Double(components[1]),
                blue: Double(components[2])
            )
        default:
            return nil
        }
    }
}
#endif
