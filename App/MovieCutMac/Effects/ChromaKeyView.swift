import AppKit
import SwiftUI
import MovieCutCore

struct ChromaKeyView: View {
    var clip: Clip
    var isEyedropperActive: Bool = false
    var onChange: (ChromaKeySettings?) -> Void
    var onPickColor: () -> Void = {}

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup("Chroma Key / Green Screen", isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
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

                    HStack(spacing: 6) {
                        Button("Green") {
                            onChange(.greenScreen())
                        }
                        Button("Blue") {
                            onChange(.blueScreen())
                        }
                        Button {
                            onPickColor()
                        } label: {
                            Label("Pick", systemImage: "eyedropper")
                        }
                        .tint(isEyedropperActive ? .accentColor : nil)
                        .help("Click the preview to sample the key color from the frame.")
                        .accessibilityLabel("Pick key color with eyedropper")
                    }
                    .controlSize(.small)

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
                        title: "Edge Shrink",
                        value: activeSettings.edgeShrink,
                        onChange: { newValue in
                            updateSettings { $0.edgeShrink = newValue }
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
            .padding(.top, 4)
        }
    }

    private var activeSettings: ChromaKeySettings {
        clip.chromaKey ?? .greenScreen()
    }

    private func slider(title: String, value: Double, onChange: @escaping @Sendable (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", value * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { value },
                set: onChange
            ), in: 0 ... 1)
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
        let hex = hexRGB.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else {
            return nil
        }

        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }

    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
