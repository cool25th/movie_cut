#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSCanvasSettingsView: View {
    var canvas: CanvasPreset
    var onChange: (CanvasPreset) -> Void

    private let presetColumns = [
        GridItem(.adaptive(minimum: 82), spacing: 10)
    ]

    var body: some View {
        Form {
            Section("Canvas") {
                IOSCanvasPreview(canvas: canvas)
                    .frame(height: 150)
                    .listRowInsets(SwiftUI.EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                LabeledContent("Output Size", value: canvasSizeText)
            }

            Section("Resolution Preset") {
                LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 10) {
                    ForEach(IOSCanvasResolutionPreset.allCases) { preset in
                        Button {
                            update { preset.apply(to: &$0) }
                        } label: {
                            VStack(spacing: 8) {
                                IOSRatioPreview(size: preset.size)
                                    .frame(height: 42)

                                Text(preset.displayName)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .frame(minHeight: 28)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(selectionBackground(isSelected: preset.matches(canvas)))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(preset.accessibilityLabel)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Aspect Ratio") {
                Picker("Aspect Ratio", selection: Binding(
                    get: { IOSCanvasAspectSelection(canvas: canvas) },
                    set: { selection in
                        update { selection.apply(to: &$0) }
                    }
                )) {
                    ForEach(IOSCanvasAspectSelection.allCases, id: \.self) { selection in
                        Text(selection.displayName).tag(selection)
                    }
                }
                .pickerStyle(.menu)
            }

            if canvas.aspectRatio == .custom {
                Section("Custom Size") {
                    HStack(spacing: 10) {
                        TextField("Width", value: Binding(
                            get: { canvas.customWidth ?? Int(AspectRatio.landscape16x9.size.width) },
                            set: { width in
                                update {
                                    $0.aspectRatio = .custom
                                    $0.customWidth = max(1, width)
                                }
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)

                        Text("x")
                            .foregroundStyle(.secondary)

                        TextField("Height", value: Binding(
                            get: { canvas.customHeight ?? Int(AspectRatio.landscape16x9.size.height) },
                            set: { height in
                                update {
                                    $0.aspectRatio = .custom
                                    $0.customHeight = max(1, height)
                                }
                            }
                        ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    }
                }
            }

            Section("Playback") {
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
                .pickerStyle(.menu)
            }
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

    private func selectionBackground(isSelected: Bool) -> Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemGroupedBackground)
    }
}

private enum IOSCanvasResolutionPreset: CaseIterable, Identifiable {
    case landscape16x9
    case portrait9x16
    case square1x1
    case standard4x3

    var id: Self { self }

    var displayName: String {
        switch self {
        case .landscape16x9:
            return "16:9"
        case .portrait9x16:
            return "9:16"
        case .square1x1:
            return "1:1"
        case .standard4x3:
            return "4:3"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .landscape16x9:
            return "16 by 9 landscape canvas"
        case .portrait9x16:
            return "9 by 16 portrait canvas"
        case .square1x1:
            return "1 by 1 square canvas"
        case .standard4x3:
            return "4 by 3 canvas"
        }
    }

    var size: CGSize {
        switch self {
        case .landscape16x9:
            return AspectRatio.landscape16x9.size
        case .portrait9x16:
            return AspectRatio.portrait9x16.size
        case .square1x1:
            return AspectRatio.square1x1.size
        case .standard4x3:
            return CGSize(width: 1440, height: 1080)
        }
    }

    func apply(to canvas: inout CanvasPreset) {
        switch self {
        case .landscape16x9:
            canvas.aspectRatio = .landscape16x9
            canvas.customWidth = nil
            canvas.customHeight = nil
        case .portrait9x16:
            canvas.aspectRatio = .portrait9x16
            canvas.customWidth = nil
            canvas.customHeight = nil
        case .square1x1:
            canvas.aspectRatio = .square1x1
            canvas.customWidth = nil
            canvas.customHeight = nil
        case .standard4x3:
            canvas.aspectRatio = .custom
            canvas.customWidth = Int(size.width)
            canvas.customHeight = Int(size.height)
        }
    }

    func matches(_ canvas: CanvasPreset) -> Bool {
        switch self {
        case .landscape16x9:
            return canvas.aspectRatio == .landscape16x9
        case .portrait9x16:
            return canvas.aspectRatio == .portrait9x16
        case .square1x1:
            return canvas.aspectRatio == .square1x1
        case .standard4x3:
            return canvas.aspectRatio == .custom &&
                Int(canvas.size.width) == Int(size.width) &&
                Int(canvas.size.height) == Int(size.height)
        }
    }
}

private enum IOSCanvasAspectSelection: Hashable, CaseIterable {
    case landscape16x9
    case portrait9x16
    case square1x1
    case standard4x3
    case custom

    init(canvas: CanvasPreset) {
        switch canvas.aspectRatio {
        case .landscape16x9:
            self = .landscape16x9
        case .portrait9x16:
            self = .portrait9x16
        case .square1x1:
            self = .square1x1
        case .custom where
            Int(canvas.size.width) == Int(IOSCanvasResolutionPreset.standard4x3.size.width) &&
            Int(canvas.size.height) == Int(IOSCanvasResolutionPreset.standard4x3.size.height):
            self = .standard4x3
        default:
            self = .custom
        }
    }

    var displayName: String {
        switch self {
        case .landscape16x9:
            return "16:9 Landscape"
        case .portrait9x16:
            return "9:16 Portrait"
        case .square1x1:
            return "1:1 Square"
        case .standard4x3:
            return "4:3 Standard"
        case .custom:
            return "Custom"
        }
    }

    func apply(to canvas: inout CanvasPreset) {
        switch self {
        case .landscape16x9:
            IOSCanvasResolutionPreset.landscape16x9.apply(to: &canvas)
        case .portrait9x16:
            IOSCanvasResolutionPreset.portrait9x16.apply(to: &canvas)
        case .square1x1:
            IOSCanvasResolutionPreset.square1x1.apply(to: &canvas)
        case .standard4x3:
            IOSCanvasResolutionPreset.standard4x3.apply(to: &canvas)
        case .custom:
            canvas.aspectRatio = .custom
            canvas.customWidth = canvas.customWidth ?? Int(AspectRatio.landscape16x9.size.width)
            canvas.customHeight = canvas.customHeight ?? Int(AspectRatio.landscape16x9.size.height)
        }
    }
}

private struct IOSCanvasPreview: View {
    var canvas: CanvasPreset

    var body: some View {
        GeometryReader { proxy in
            let size = canvas.size
            let ratio = size.width / max(size.height, 1)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black)
                    .frame(width: width, height: height)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                    }

                Text("\(Int(size.width)) x \(Int(size.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct IOSRatioPreview: View {
    var size: CGSize

    var body: some View {
        GeometryReader { proxy in
            let ratio = size.width / max(size.height, 1)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio

            RoundedRectangle(cornerRadius: 4)
                .fill(Color(uiColor: .systemBackground))
                .frame(width: width, height: height)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
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
#endif
