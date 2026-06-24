import SwiftUI
import MovieCutCore

/// Renders an RGB histogram (overlaid per-channel curves) for the grading panel.
struct HistogramView: View {
    let histogram: ScopeAnalyzer.Histogram

    private var peak: Double {
        let maxRed = histogram.red.max() ?? 0
        let maxGreen = histogram.green.max() ?? 0
        let maxBlue = histogram.blue.max() ?? 0
        return Double(max(1, max(maxRed, max(maxGreen, maxBlue))))
    }

    var body: some View {
        Canvas { context, size in
            channelPath(histogram.red, size: size).map { context.fill($0, with: .color(.red.opacity(0.55))) }
            channelPath(histogram.green, size: size).map { context.fill($0, with: .color(.green.opacity(0.55))) }
            channelPath(histogram.blue, size: size).map { context.fill($0, with: .color(.blue.opacity(0.55))) }
        }
        .frame(height: 56)
        .background(MovieCutTheme.previewBackground)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4).stroke(MovieCutTheme.border, lineWidth: 0.5)
        )
        .accessibilityLabel("RGB histogram")
    }

    private func channelPath(_ counts: [Int], size: CGSize) -> Path? {
        guard counts.count > 1 else { return nil }
        let scale = peak
        let stepX = size.width / CGFloat(counts.count - 1)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, count) in counts.enumerated() {
            let normalized = min(1, Double(count) / scale)
            let x = CGFloat(index) * stepX
            let y = size.height - CGFloat(normalized) * size.height
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        return path
    }
}
