import SwiftUI
import MovieCutCore

/// Luma waveform (luma distribution vs. x), rendered as a green intensity field.
struct WaveformView: View {
    let waveform: [[Int]]

    private var peak: Double {
        Double(max(1, waveform.flatMap { $0 }.max() ?? 1))
    }

    var body: some View {
        Canvas { context, size in
            let columns = waveform.count
            guard columns > 0, let levels = waveform.first?.count, levels > 0 else { return }
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(levels)
            let scale = peak
            for (column, levelsCounts) in waveform.enumerated() {
                for (level, count) in levelsCounts.enumerated() where count > 0 {
                    let intensity = min(1, Double(count) / scale)
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: size.height - CGFloat(level + 1) * cellHeight,
                        width: cellWidth + 0.5,
                        height: cellHeight + 0.5
                    )
                    context.fill(Path(rect), with: .color(.green.opacity(0.12 + 0.75 * intensity)))
                }
            }
        }
        .frame(height: 56)
        .background(MovieCutTheme.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MovieCutTheme.border, lineWidth: 0.5))
        .accessibilityLabel("Luma waveform")
    }
}

/// Vectorscope: chroma scatter on a circle. Neutral pixels cluster at the center,
/// saturated hues spread outward.
struct VectorscopeView: View {
    let vectorscope: ScopeAnalyzer.Vectorscope

    private var peak: Double {
        Double(max(1, vectorscope.counts.max() ?? 1))
    }

    var body: some View {
        Canvas { context, size in
            let n = vectorscope.size
            guard n > 0 else { return }
            let dimension = min(size.width, size.height)
            let cell = dimension / CGFloat(n)
            let originX = (size.width - dimension) / 2
            let originY = (size.height - dimension) / 2

            context.stroke(
                Path(ellipseIn: CGRect(x: originX, y: originY, width: dimension, height: dimension)),
                with: .color(MovieCutTheme.border),
                lineWidth: 0.5
            )

            let scale = peak
            for gy in 0..<n {
                for gx in 0..<n {
                    let count = vectorscope.counts[gy * n + gx]
                    guard count > 0 else { continue }
                    let intensity = min(1, Double(count) / scale)
                    let rect = CGRect(
                        x: originX + CGFloat(gx) * cell,
                        y: originY + CGFloat(n - 1 - gy) * cell,
                        width: cell + 0.5,
                        height: cell + 0.5
                    )
                    context.fill(Path(rect), with: .color(.white.opacity(0.1 + 0.8 * intensity)))
                }
            }
        }
        .frame(width: 56, height: 56)
        .background(MovieCutTheme.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MovieCutTheme.border, lineWidth: 0.5))
        .accessibilityLabel("Vectorscope")
    }
}

/// RGB parade (CA-28): the waveform's per-channel form — red, green, and blue
/// panels side by side, each showing that channel's value distribution vs. x.
/// A white-balance skew or channel clip shows as one panel's trace shifting
/// against the others.
struct RGBParadeView: View {
    let parade: ScopeAnalyzer.RGBParade

    var body: some View {
        HStack(spacing: 2) {
            paradePanel(parade.red, tint: .red)
            paradePanel(parade.green, tint: .green)
            paradePanel(parade.blue, tint: .blue)
        }
        .frame(height: 56)
        .background(MovieCutTheme.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(MovieCutTheme.border, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(NSLocalizedString("RGB parade", comment: "")))
        .accessibilityValue(Text(NSLocalizedString(
            "Red, green, and blue channel waveforms side by side", comment: ""
        )))
    }

    /// One channel's intensity field — the same rendering contract as
    /// ``WaveformView``, tinted per channel.
    private func paradePanel(_ waveform: [[Int]], tint: Color) -> some View {
        Canvas { context, size in
            let columns = waveform.count
            guard columns > 0, let levels = waveform.first?.count, levels > 0 else { return }
            let cellWidth = size.width / CGFloat(columns)
            let cellHeight = size.height / CGFloat(levels)
            let scale = Double(max(1, waveform.flatMap { $0 }.max() ?? 1))
            for (column, levelsCounts) in waveform.enumerated() {
                for (level, count) in levelsCounts.enumerated() where count > 0 {
                    let intensity = min(1, Double(count) / scale)
                    let rect = CGRect(
                        x: CGFloat(column) * cellWidth,
                        y: size.height - CGFloat(level + 1) * cellHeight,
                        width: cellWidth + 0.5,
                        height: cellHeight + 0.5
                    )
                    context.fill(Path(rect), with: .color(tint.opacity(0.12 + 0.75 * intensity)))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
