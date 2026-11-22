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
        ChromaKeyParameterSlider(title: title, value: value, onChange: onChange)
    }

    private func updateSettings(_ update: (inout ChromaKeySettings) -> Void) {
        var settings = activeSettings
        update(&settings)
        onChange(settings)
    }
}

private struct ChromaKeyParameterSlider: View {
    let title: String
    let value: Double
    let onChange: @MainActor (Double) -> Void

    @State private var draftValue: Double?

    private var effectiveValue: Double {
        draftValue ?? value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", effectiveValue * 100))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Slider(value: Binding(
                get: { effectiveValue },
                set: { newValue in draftValue = newValue }
            ), in: 0 ... 1) { isEditing in
                if !isEditing, let committed = draftValue {
                    draftValue = nil
                    MainActor.assumeIsolated { onChange(committed) }
                }
            }
        }
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
