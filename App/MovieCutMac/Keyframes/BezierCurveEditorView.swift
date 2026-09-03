import SwiftUI
import MovieCutCore

/// A mini cubic-bezier curve editor for the keyframe Inspector (G-06 Inc 3).
///
/// Renders the easing curve P0=(0,0)→P3=(1,1) with two draggable control
/// handles (P1, P2) in the CSS cubic-bezier convention. Presets cover the
/// common Pro curves; overshoot presets are disabled for clamped properties
/// (opacity/volume) since the compositor clips them.
///
/// `onChange` fires with the new `CubicBezierControl` on every handle release
/// (and during drag for live feedback). The caller is responsible for writing
/// it back through the undo-able `updateSelectedKeyframes` path.
struct BezierCurveEditorView: View {
    /// The current curve (P1, P2). P0=(0,0) and P3=(1,1) are implicit.
    @State private var control: CubicBezierControl
    /// The property being animated — used to disable overshoot on clamped
    /// properties (opacity, volume).
    private let property: AnimatableProperty
    private let onChange: (CubicBezierControl) -> Void

    /// Square plot size (points). Kept modest to fit the Inspector column.
    private let plot = CGSize(width: 160, height: 160)
    private let handleRadius: Double = 7

    init(control: CubicBezierControl, property: AnimatableProperty, onChange: @escaping (CubicBezierControl) -> Void) {
        self._control = State(initialValue: control)
        self.property = property
        self.onChange = onChange
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            canvas
            presets
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        ZStack {
            // Grid: center diagonal (linear reference) + frame.
            Canvas { ctx, size in
                let diagonal = Path { p in
                    p.move(to: CGPoint(x: 0, y: size.height))
                    p.addLine(to: CGPoint(x: size.width, y: 0))
                }
                ctx.stroke(diagonal, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            }
            .frame(width: plot.width, height: plot.height)
            .background(RoundedRectangle(cornerRadius: 6).fill(.black.opacity(0.15)))

            // The bezier curve + control handles.
            Canvas { ctx, size in
                // The curve path. Sample densely because the bezier may overshoot.
                var curve = Path()
                let samples = 64
                for i in 0...samples {
                    let t = Double(i) / Double(samples)
                    let pt = bezierPoint(t: t)
                    let ui = toUI(pt, size: size)
                    if i == 0 { curve.move(to: ui) } else { curve.addLine(to: ui) }
                }
                ctx.stroke(curve, with: .color(.accentColor), lineWidth: 2)

                // Control handle lines P0-P1 and P2-P3.
                let p0UI = toUI(CGPoint(x: 0, y: 0), size: size)
                let p1UI = toUI(control.p1, size: size)
                let p2UI = toUI(control.p2, size: size)
                let p3UI = toUI(CGPoint(x: 1, y: 1), size: size)
                ctx.stroke(Path { p in
                    p.move(to: p0UI); p.addLine(to: p1UI)
                }, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
                ctx.stroke(Path { p in
                    p.move(to: p2UI); p.addLine(to: p3UI)
                }, with: .color(.secondary.opacity(0.5)), lineWidth: 1)

                // Anchor dots P0, P3.
                for anchor in [p0UI, p3UI] {
                    ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 3, y: anchor.y - 3, width: 6, height: 6)),
                             with: .color(.secondary))
                }
            }
            .frame(width: plot.width, height: plot.height)

            // Draggable handle layers (hit targets drawn as SwiftUI, not Canvas).
            handleView(for: .p1)
            handleView(for: .p2)
        }
        .frame(width: plot.width, height: plot.height)
    }

    private func handleView(for handle: Handle) -> some View {
        let center = toUI(handle.point(on: control), size: plot)
        return Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: handleRadius * 2, height: handleRadius * 2)
            .position(center)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let unit = fromUI(value.location, size: plot)
                        // Clamp x to [0,1] (well-formed time axis); y may overshoot.
                        let clampedX = min(max(unit.x, 0), 1)
                        let clamped = CGPoint(x: clampedX, y: unit.y)
                        switch handle {
                        case .p1: control.p1 = clamped
                        case .p2: control.p2 = clamped
                        }
                    }
                    .onEnded { _ in
                        onChange(control)
                    }
            )
    }

    // MARK: - Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Presets")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                presetButton("Smooth", CubicBezierControl(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1.0))
                presetButton("Snappy", CubicBezierControl(x1: 0.85, y1: 0.0, x2: 0.15, y2: 1.0))
                presetButton("Ease", CubicBezierControl(x1: 0.42, y1: 0.0, x2: 0.58, y2: 1.0))
            }
            HStack(spacing: 6) {
                presetButton("Anticipate", CubicBezierControl(x1: 0.5, y1: -0.3, x2: 0.9, y2: 1.0), overshoot: true)
                presetButton("Overshoot", CubicBezierControl(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1.0), overshoot: true)
            }
        }
    }

    private func presetButton(_ title: String, _ curve: CubicBezierControl, overshoot: Bool = false) -> some View {
        Button {
            control = curve
            onChange(curve)
        } label: {
            Text(title).font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(overshoot && property.isValueClamped)
        .help(overshoot && property.isValueClamped
              ? "Overshoot is clipped for \(property.keyframeDisplayName)"
              : title)
    }

    // MARK: - Coordinate conversion

    /// Unit space (x: 0..1 time, y: 0..1+ value, origin bottom-left) → UI (origin top-left).
    /// We allow y slightly beyond [0,1] for overshoot visualization by mapping a
    /// slightly wider y range to the plot height.
    private let yRange: Double = 2.0  // map [-0.5, 1.5] → plot height for overshoot headroom

    private func toUI(_ p: CGPoint, size: CGSize) -> CGPoint {
        // Map y from [-0.5, 1.5] → [height, 0].
        let yOffset = 0.5
        let yNorm = (p.y + yOffset) / yRange
        return CGPoint(x: p.x * size.width, y: (1 - yNorm) * size.height)
    }

    private func fromUI(_ p: CGPoint, size: CGSize) -> CGPoint {
        let yNorm = 1 - (p.y / size.height)
        let y = yNorm * yRange - 0.5
        return CGPoint(x: p.x / size.width, y: y)
    }

    /// Cubic-bezier point at parameter t (P0=(0,0), P3=(1,1)).
    private func bezierPoint(t: Double) -> CGPoint {
        let mt = 1 - t
        let x = 3 * mt * mt * t * control.p1.x + 3 * mt * t * t * control.p2.x + t * t * t
        let y = 3 * mt * mt * t * control.p1.y + 3 * mt * t * t * control.p2.y + t * t * t
        return CGPoint(x: x, y: y)
    }

    private enum Handle {
        case p1, p2
        func point(on c: CubicBezierControl) -> CGPoint {
            switch self {
            case .p1: return c.p1
            case .p2: return c.p2
            }
        }
    }
}
