#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSTextClipSheet: View {
    @Bindable var viewModel: IOSEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var text = "Title"
    @State private var fontName = "Helvetica"
    @State private var fontSize: Double = 36
    @State private var textColor: Color = .white
    @State private var bgColor: Color = .clear
    @State private var hasBackground = false

    private let fontOptions = ["Helvetica", "Georgia", "Courier", "Avenir"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Text") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80)
                }

                Section("Style") {
                    Picker("Font", selection: $fontName) {
                        ForEach(fontOptions, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(fontSize))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $fontSize, in: 12...120, step: 1)
                    }

                    ColorPicker("Text Color", selection: $textColor)

                    Toggle("Background", isOn: $hasBackground)

                    if hasBackground {
                        ColorPicker("Background Color", selection: $bgColor)
                    }
                }

                Section {
                    Button {
                        let simdColor = colorToSIMD(textColor)
                        Task {
                            await viewModel.addTextClip(
                                text: text,
                                fontName: fontName,
                                fontSize: fontSize,
                                color: simdColor
                            )
                            dismiss()
                        }
                    } label: {
                        Text("Add Text Clip")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                }
            }
            .navigationTitle("Add Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func colorToSIMD(_ color: Color) -> SIMD4<Float> {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4<Float>(Float(r), Float(g), Float(b), Float(a))
    }
}
#endif
