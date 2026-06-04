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
        let hex = hexRGB.hasPrefix("#") ? String(hexRGB.dropFirst()) : hexRGB
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red = CGFloat((value >> 16) & 0xFF) / 255.0
        let green = CGFloat((value >> 8) & 0xFF) / 255.0
        let blue = CGFloat(value & 0xFF) / 255.0

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgColor = CGColor(colorSpace: colorSpace, components: [red, green, blue, 1.0])
        else {
            return nil
        }

        self.init(cgColor: cgColor)
    }

    var hexRGB: String? {
        guard
            let sourceColor = self.cgColor,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else {
            return nil
        }

        let color = sourceColor.converted(to: colorSpace, intent: .defaultIntent, options: nil) ?? sourceColor
        guard let components = color.components else {
            return nil
        }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        switch color.numberOfComponents {
        case 2:
            red = components[0]
            green = components[0]
            blue = components[0]
        case 4:
            red = components[0]
            green = components[1]
            blue = components[2]
        default:
            return nil
        }

        return "#\(Self.hexPair(for: red))\(Self.hexPair(for: green))\(Self.hexPair(for: blue))"
    }

    private static func hexPair(for component: CGFloat) -> String {
        let clamped = min(max(component, 0), 1)
        let value = Int((clamped * 255).rounded())
        let digits = String(value, radix: 16, uppercase: true)
        return digits.count == 1 ? "0\(digits)" : digits
    }
}
#endif
