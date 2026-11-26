import SwiftUI
import MovieCutCore

/// A 3-way color-grading wheel: the puck sets the per-channel RGB balance
/// (chroma), and a luma slider sets the overall level for that tonal range. The
/// stored value is `chroma + luma` per channel, decomposed back via the average.
struct ColorGradeWheel: View {
    let title: String
    let red: Double
    let green: Double
    let blue: Double
    let chromaScale: Double
    let lumaRange: ClosedRange<Double>
    let onChange: (_ red: Double, _ green: Double, _ blue: Double) -> Void

    @State private var draftRGB: (red: Double, green: Double, blue: Double)?

    private let diameter: CGFloat = 92

    private var effectiveRed: Double { draftRGB?.red ?? red }
    private var effectiveGreen: Double { draftRGB?.green ?? green }
    private var effectiveBlue: Double { draftRGB?.blue ?? blue }

    private var luma: Double { (effectiveRed + effectiveGreen + effectiveBlue) / 3 }
    private var chromaRed: Double { effectiveRed - luma }
    private var chromaGreen: Double { effectiveGreen - luma }
    private var chromaBlue: Double { effectiveBlue - luma }

    private var puck: (x: Double, y: Double) {
        ColorWheelMath.position(red: chromaRed, green: chromaGreen, blue: chromaBlue, scale: chromaScale)
    }

    var body: some View {
        VStack(spacing: 6) {
            wheel
            HStack(spacing: 6) {
                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { luma },
                        set: { newLuma in
                            draftRGB = (chromaRed + newLuma, chromaGreen + newLuma, chromaBlue + newLuma)
                        }
                    ),
                    in: lumaRange,
                    step: 0.01
                ) { isEditing in
                    if !isEditing, let committed = draftRGB {
                        draftRGB = nil
                        onChange(committed.red, committed.green, committed.blue)
                    }
                }
            }
            .frame(width: diameter + 14)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var wheel: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let puckPoint = CGPoint(
                x: center.x + CGFloat(puck.x) * radius,
                y: center.y - CGFloat(puck.y) * radius
            )

            ZStack {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [.red, .pink, .blue, .cyan, .green, .yellow, .red],
                            center: .center,
                            angle: .degrees(-90)
                        ),
                        lineWidth: 6
                    )
                    .opacity(0.55)
                Circle()
                    .fill(MovieCutTheme.controlSurface)
                    .padding(7)
                Circle()
                    .stroke(MovieCutTheme.border, lineWidth: 0.5)
                    .padding(7)
                Circle()
                    .fill(Color.white)
                    .frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .position(puckPoint)
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let nx = Double((value.location.x - center.x) / radius)
                        let ny = Double(-(value.location.y - center.y) / radius)
                        let clamped = ColorWheelMath.clampedToDisk(x: nx, y: ny)
                        let chroma = ColorWheelMath.channelOffsets(x: clamped.x, y: clamped.y, scale: chromaScale)
                        draftRGB = (chroma.red + luma, chroma.green + luma, chroma.blue + luma)
                    }
                    .onEnded { value in
                        let nx = Double((value.location.x - center.x) / radius)
                        let ny = Double(-(value.location.y - center.y) / radius)
                        let clamped = ColorWheelMath.clampedToDisk(x: nx, y: ny)
                        let chroma = ColorWheelMath.channelOffsets(x: clamped.x, y: clamped.y, scale: chromaScale)
                        let committed = draftRGB ?? (chroma.red + luma, chroma.green + luma, chroma.blue + luma)
                        draftRGB = nil
                        onChange(committed.red, committed.green, committed.blue)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel("\(title) color wheel")
            .accessibilityValue(String(format: "red %.2f, green %.2f, blue %.2f", effectiveRed, effectiveGreen, effectiveBlue))
        }
        .frame(width: diameter, height: diameter)
    }
}
