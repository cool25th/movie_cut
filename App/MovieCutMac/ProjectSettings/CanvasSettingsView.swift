import SwiftUI
import MovieCutCore

struct CanvasSettingsView: View {
    var canvas: CanvasPreset
    var onChange: (CanvasPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 88), spacing: 8)
    ]

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
        }
        .padding(14)
        .frame(width: 360)
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
