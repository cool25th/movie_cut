import MovieCutCore
import SwiftUI

/// Per-color-band HSL adjustment (G-02 Inc 5): eight hue bands (red…magenta),
/// each with its own hue-shift / saturation / luminance sliders. Values live
/// on the clip's `ColorGrade.hslBands` and render through the shared
/// `ColorGradePixelProcessor` chain, so preview and export match by
/// construction (the same processor drives both engines).
///
/// Commit discipline (undo transaction): a slider drag mutates local draft
/// state for responsiveness and commits the full band array once, when the
/// drag ends — the G-23 canvas-editor pattern: one undo step per gesture
/// instead of one per tick. Committing `nil` when every band is identity
/// keeps project JSON byte-stable for ungraded clips.
struct ColorHSLBandsView: View {
    /// Committed band values from the clip's current color grade.
    let bands: [HSLBand]
    /// Commits the full band array (nil when every band is identity).
    let onCommit: (_ bands: [HSLBand]?) -> Void

    @State private var selectedCenter: HSLBandCenter = .red
    @State private var draftBands: [HSLBand] = ColorHSLBandsView.eightBands(from: nil)

    init(bands: [HSLBand]?, onCommit: @escaping (_ bands: [HSLBand]?) -> Void) {
        self.bands = Self.eightBands(from: bands)
        self.onCommit = onCommit
        _draftBands = State(initialValue: Self.eightBands(from: bands))
    }

    private static func eightBands(from bands: [HSLBand]?) -> [HSLBand] {
        var byCenter: [HSLBandCenter: HSLBand] = [:]
        for band in bands ?? [] where !band.isIdentity {
            byCenter[band.center] = band
        }
        return HSLBandCenter.allCases.map { byCenter[$0] ?? HSLBand(center: $0) }
    }

    private var selectedIndex: Int {
        draftBands.firstIndex { $0.center == selectedCenter } ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HSL Bands")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Reset Band") {
                    draftBands[selectedIndex] = HSLBand(center: selectedCenter)
                    commit()
                }
                .controlSize(.small)
                .disabled(draftBands[selectedIndex].isIdentity)
            }

            HStack(spacing: 8) {
                ForEach(HSLBandCenter.allCases, id: \.self) { center in
                    bandChip(center)
                }
            }

            bandSlider(
                title: "Hue Shift",
                value: binding(\.hueShift),
                range: -60 ... 60,
                format: "{+.0f}°"
            )
            bandSlider(
                title: "Saturation",
                value: binding(\.saturation),
                range: -1 ... 1,
                format: "{+.2f}"
            )
            bandSlider(
                title: "Luminance",
                value: binding(\.luminance),
                range: -1 ... 1,
                format: "{+.2f}"
            )
        }
        .onChange(of: bands) { newBands in
            draftBands = Self.eightBands(from: newBands)
        }
    }

    private func bandChip(_ center: HSLBandCenter) -> some View {
        let isSelected = center == selectedCenter
        return Circle()
            .fill(Self.chipColor(center))
            .frame(width: 18, height: 18)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(.primary, lineWidth: 2)
                }
            }
            .opacity(draftBands.first { $0.center == center }?.isIdentity == false ? 1 : 0.45)
            .onTapGesture { selectedCenter = center }
            .accessibilityElement()
            .accessibilityLabel("\(Self.displayName(center)) band")
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Adjust this color band")
    }

    /// Slider binding into the selected band's draft value. Edits mutate draft
    /// state only; the commit happens on drag end via `onEditingChanged`.
    private func binding(_ keyPath: WritableKeyPath<HSLBand, Double>) -> Binding<Double> {
        Binding(
            get: { draftBands[selectedIndex][keyPath: keyPath] },
            set: { draftBands[selectedIndex][keyPath: keyPath] = $0 }
        )
    }

    private func bandSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: String
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Slider(
                value: value,
                in: range,
                step: range.upperBound > 10 ? 1 : 0.01
            ) { editing in
                if !editing {
                    commit()
                }
            }
            Text(String(format: format, value.wrappedValue))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(Self.displayName(selectedCenter)) band")
        .accessibilityValue(Text(String(format: format, value.wrappedValue)))
    }

    private func commit() {
        let active = draftBands.filter { !$0.isIdentity }
        onCommit(active.isEmpty ? nil : active)
    }

    static func displayName(_ center: HSLBandCenter) -> String {
        switch center {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .aqua: "Aqua"
        case .blue: "Blue"
        case .purple: "Purple"
        case .magenta: "Magenta"
        }
    }

    static func chipColor(_ center: HSLBandCenter) -> Color {
        switch center {
        case .red: Color(red: 1, green: 0, blue: 0)
        case .orange: Color(red: 1, green: 0.5, blue: 0)
        case .yellow: Color(red: 1, green: 1, blue: 0)
        case .green: Color(red: 0, green: 1, blue: 0)
        case .aqua: Color(red: 0, green: 1, blue: 1)
        case .blue: Color(red: 0, green: 0, blue: 1)
        case .purple: Color(red: 0.5, green: 0, blue: 0.5)
        case .magenta: Color(red: 1, green: 0, blue: 1)
        }
    }
}
