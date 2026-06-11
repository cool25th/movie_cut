import AppKit
import SwiftUI
import MovieCutCore
import UniformTypeIdentifiers

struct CanvasSettingsView: View {
    var canvas: CanvasPreset
    var background: CanvasBackground? = nil
    var onBackgroundChange: (CanvasBackground?) -> Void = { _ in }
    var onChange: (CanvasPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 8)
    ]

    private enum BackgroundKind: String, CaseIterable, Identifiable {
        case none = "None"
        case color = "Color"
        case blur = "Blur"
        case image = "Image"

        var id: String { rawValue }
    }

    private static let colorPresets: [(name: String, hex: String)] = [
        ("Black", "000000"),
        ("White", "FFFFFF"),
        ("Gray", "3A3A3C"),
        ("Navy", "0B1D3A")
    ]

    private var backgroundKind: BackgroundKind {
        switch background {
        case nil: return .none
        case .color: return .color
        case .sourceBlur: return .blur
        case .image: return .image
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Canvas")
                .font(.headline)

            CanvasPreview(canvas: canvas)
                .frame(height: 110)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(AspectRatio.allCases, id: \.self) { aspectRatio in
                    Button {
                        update { preset in
                            preset.aspectRatio = aspectRatio
                            if aspectRatio == .custom {
                                preset.customWidth = preset.customWidth ?? Int(AspectRatio.landscape16x9.size.width)
                                preset.customHeight = preset.customHeight ?? Int(AspectRatio.landscape16x9.size.height)
                            }
                        }
                    } label: {
                        VStack(spacing: 6) {
                            RatioPreview(aspectRatio: aspectRatio, canvas: canvas)
                                .frame(height: 36)
                            Text(aspectRatio.displayName)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(minHeight: 24)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(selectionBackground(for: aspectRatio))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("Frame Rate", selection: Binding(
                get: { canvas.frameRate },
                set: { frameRate in
                    update { $0.frameRate = frameRate }
                }
            )) {
                ForEach(ExportFrameRate.allCases, id: \.self) { frameRate in
                    Text(frameRate.displayName).tag(frameRate)
                }
            }

            if canvas.aspectRatio == .custom {
                HStack(spacing: 8) {
                    TextField("Width", value: Binding(
                        get: { canvas.customWidth ?? Int(AspectRatio.landscape16x9.size.width) },
                        set: { width in
                            update { $0.customWidth = max(1, width) }
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)

                    Text("x")
                        .foregroundStyle(.secondary)

                    TextField("Height", value: Binding(
                        get: { canvas.customHeight ?? Int(AspectRatio.landscape16x9.size.height) },
                        set: { height in
                            update { $0.customHeight = max(1, height) }
                        }
                    ), format: .number)
                    .textFieldStyle(.roundedBorder)
                }
            }

            Text(canvasSizeText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            backgroundSection
        }
        .padding(14)
        .frame(width: 360)
    }

    @ViewBuilder
    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("Background", comment: ""))
                .font(.subheadline)

            Picker(NSLocalizedString("Background Style", comment: ""), selection: Binding(
                get: { backgroundKind },
                set: { kind in
                    switch kind {
                    case .none:
                        onBackgroundChange(nil)
                    case .color:
                        onBackgroundChange(.color(hex: "000000"))
                    case .blur:
                        onBackgroundChange(.sourceBlur(radius: 24))
                    case .image:
                        chooseBackgroundImage()
                    }
                }
            )) {
                ForEach(BackgroundKind.allCases) { kind in
                    Text(NSLocalizedString(kind.rawValue, comment: "")).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel(NSLocalizedString("Canvas background style", comment: ""))

            switch background {
            case .color(let hex):
                HStack(spacing: 6) {
                    ForEach(Self.colorPresets, id: \.hex) { preset in
                        Button {
                            onBackgroundChange(.color(hex: preset.hex))
                        } label: {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle().stroke(
                                        hex == preset.hex ? Color.accentColor : Color.secondary.opacity(0.4),
                                        lineWidth: hex == preset.hex ? 2 : 1
                                    )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(
                            format: NSLocalizedString("%@ background color", comment: ""),
                            preset.name
                        ))
                    }
                    Text("#\(hex)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

            case .sourceBlur(let radius):
                HStack(spacing: 8) {
                    Slider(value: Binding(
                        get: { radius },
                        set: { onBackgroundChange(.sourceBlur(radius: $0)) }
                    ), in: 2...60)
                    .accessibilityLabel(NSLocalizedString("Background blur radius", comment: ""))
                    Text(String(format: "%.0f", radius))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 26, alignment: .trailing)
                }

            case .image(let url):
                HStack(spacing: 8) {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(NSLocalizedString("Change...", comment: "")) {
                        chooseBackgroundImage()
                    }
                    .font(.caption)
                }

            case nil:
                Text(NSLocalizedString("Letterbox areas render black.", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            onBackgroundChange(.image(url: url))
        }
    }

    private var canvasSizeText: String {
        let size = canvas.size
        return "\(Int(size.width)) x \(Int(size.height))"
    }

    private func update(_ mutate: (inout CanvasPreset) -> Void) {
        var updated = canvas
        mutate(&updated)
        onChange(updated)
    }

    private func selectionBackground(for aspectRatio: AspectRatio) -> Color {
        aspectRatio == canvas.aspectRatio ? Color.accentColor.opacity(0.18) : Color(nsColor: .separatorColor).opacity(0.12)
    }
}

private struct CanvasPreview: View {
    var canvas: CanvasPreset

    var body: some View {
        GeometryReader { proxy in
            let size = canvas.size
            let ratio = size.width / max(size.height, 1)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black)
                    .frame(width: width, height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }

                Text("\(Int(size.width)) x \(Int(size.height))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct RatioPreview: View {
    var aspectRatio: AspectRatio
    var canvas: CanvasPreset

    var body: some View {
        GeometryReader { proxy in
            let size = aspectRatio == .custom ? canvas.size : aspectRatio.size
            let ratio = size.width / max(size.height, 1)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .textBackgroundColor))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private extension ExportFrameRate {
    var displayName: String {
        switch self {
        case .fps24:
            return "24 fps"
        case .fps30:
            return "30 fps"
        case .fps60:
            return "60 fps"
        }
    }
}

private extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
