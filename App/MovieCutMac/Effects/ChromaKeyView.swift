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

    // @MainActor so the value-setting closures can call updateSettings: the
    // bare @Sendable form compiles on Swift 6.3 (which infers the MainActor
    // context) but Xcode 16 treats the closure as nonisolated and rejects the
    // MainActor call. A @MainActor closure is Sendable by definition.
    private func slider(title: String, value: Double, onChange: @escaping @MainActor (Double) -> Void) -> some View {
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
                // Slider writes arrive on the main thread; assumeIsolated hops
                // to the MainActor closure without a conversion the older
                // compiler crashes on.
                set: { newValue in MainActor.assumeIsolated { onChange(newValue) } }
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
        guard let rgb = HexColorMath.rgb(fromHex: hexRGB) else { return nil }
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    var hexRGB: String? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else {
            return nil
        }
        return HexColorMath.hexRGB(
            red: Double(color.redComponent),
            green: Double(color.greenComponent),
            blue: Double(color.blueComponent)
        )
    }
}
