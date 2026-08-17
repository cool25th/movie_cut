import MovieCutCore
import SwiftUI

/// Value-time keyframe graph (G-06): the selected property's curve drawn from
/// the same `Keyframe.interpolate` math the renderer evaluates, so the drawn
/// shape IS the animation — `hold` reads as a right-angle step, eased modes as
/// arcs, linear as straight runs. Keyframes can be selected, dragged (time +
/// value), added on empty canvas, and deleted, all through the same
/// `updateSelectedKeyframes` command the list editor uses.
///
/// Undo discipline (G-23 canvas pattern): a drag mutates a local draft and
/// commits the whole keyframe array once, when the gesture ends — one undo
/// step per drag instead of per tick.
struct KeyframeGraphView: View {
    var clip: Clip
    var playheadTime: TimeInterval
    var selectedKeyframeId: UUID?
    var onSelect: (UUID?) -> Void
    var onChange: ([Keyframe]) -> Void

    @State private var selectedProperty: AnimatableProperty = .opacity
    @State private var dragDraft: [Keyframe]?
    @State private var draggingKeyframeId: UUID?
    @State private var dragStartedOnKeyframe = false
    @State private var didDrag = false
    @State private var canvasSize: CGSize = .zero

    private var effectiveKeyframes: [Keyframe] {
        dragDraft ?? clip.keyframes
    }

    private var propertyKeyframes: [Keyframe] {
        effectiveKeyframes
            .filter { $0.property == selectedProperty }
            .sorted { $0.time < $1.time }
    }

    private var selectedKeyId: UUID? {
        guard let selectedKeyframeId,
              effectiveKeyframes.contains(where: { $0.id == selectedKeyframeId }) else {
            return nil
        }
        return selectedKeyframeId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Picker("Property", selection: $selectedProperty) {
                    ForEach(AnimatableProperty.allCases, id: \.self) { property in
                        Text(property.keyframeDisplayName)
                            .foregroundStyle(property.keyframeColor)
                            .tag(property)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)

                Spacer()

                Button {
                    deleteSelected()
                } label: {
                    Image(systemName: "minus.diamond")
                }
                .buttonStyle(.borderless)
                .help("Delete the selected keyframe")
                .disabled(selectedKeyId == nil)
            }

            GeometryReader { proxy in
                canvas(size: proxy.size)
            }
            .frame(height: 150)
            .background(Color(nsColor: .separatorColor).opacity(0.12))
            .cornerRadius(6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(selectedProperty.keyframeDisplayName) keyframe graph")
            .accessibilityHint("Click to add a keyframe, drag one to move it")
        }
        .onAppear(perform: adoptDefaultProperty)
        .onChange(of: clip.id) { _ in
            adoptDefaultProperty()
            dragDraft = nil
            draggingKeyframeId = nil
            didDrag = false
        }
    }

    /// Opens on a property that actually has keyframes when one exists.
    private func adoptDefaultProperty() {
        if clip.keyframes.first(where: { $0.property == selectedProperty }) == nil,
           let first = clip.keyframes.sorted(by: { $0.property.rawValue < $1.property.rawValue }).first {
            selectedProperty = first.property
        }
    }

    // MARK: - Canvas

    private func canvas(size: CGSize) -> some View {
        Canvas { context, drawSize in
            draw(context: context, size: drawSize)
        }
        .contentShape(Rectangle())
        .onAppear { canvasSize = size }
        .onChange(of: size) { canvasSize = $0 }
        .gesture(dragGesture)
    }

    private func draw(context: GraphicsContext, size: CGSize) {
        let domain = timeDomain
        let range = KeyframeGraphMath.displayRange(for: propertyKeyframes)
        let toPoint: (TimeInterval, Double) -> CGPoint = { time, value in
            CGPoint(
                x: (time - domain.lowerBound) / max(domain.upperBound - domain.lowerBound, .ulpOfOne) * size.width,
                y: (1 - (value - range.lowerBound) / max(range.upperBound - range.lowerBound, .ulpOfOne)) * size.height
            )
        }

        // Grid: quarter lines in both axes.
        var grid = Path()
        for step in 1...3 {
            let x = size.width * CGFloat(step) / 4
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            let y = size.height * CGFloat(step) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(.primary.opacity(0.08)), lineWidth: 1)

        // Playhead (source-time domain, the same conversion the editors use).
        let playheadSource = clip.keyframeSourceTime(at: playheadTime)
        if domain.contains(playheadSource) {
            let x = toPoint(playheadSource, range.lowerBound).x
            var playhead = Path()
            playhead.move(to: CGPoint(x: x, y: 0))
            playhead.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(playhead, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        // The curve: the renderer's own interpolation math, sampled.
        let curvePoints = KeyframeGraphMath.polyline(for: propertyKeyframes)
            .map { toPoint($0.time, $0.value) }
        if curvePoints.count > 1 {
            var curve = Path()
            curve.move(to: curvePoints[0])
            curvePoints.dropFirst().forEach { curve.addLine(to: $0) }
            context.stroke(
                curve,
                with: .color(selectedProperty.keyframeColor),
                style: StrokeStyle(lineWidth: 2, lineJoin: .round)
            )
        }

        // Keyframe markers: diamonds in the property color; the selected one
        // gets a stroke ring.
        for keyframe in propertyKeyframes {
            let center = toPoint(keyframe.time, keyframe.value)
            let diamond = Path { path in
                path.move(to: CGPoint(x: center.x, y: center.y - 5))
                path.addLine(to: CGPoint(x: center.x + 5, y: center.y))
                path.addLine(to: CGPoint(x: center.x, y: center.y + 5))
                path.addLine(to: CGPoint(x: center.x - 5, y: center.y))
                path.closeSubpath()
            }
            context.fill(diamond, with: .color(selectedProperty.keyframeColor))
            if keyframe.id == selectedKeyId {
                context.stroke(diamond, with: .color(.primary), lineWidth: 2)
            }
        }
    }

    // MARK: - Interaction

    /// One zero-minimum-distance drag gesture covers tap (select / add) and
    /// drag (move) — the committed result always routes through `onChange`
    /// exactly once per gesture.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !didDrag, abs(value.translation.width) > 4 || abs(value.translation.height) > 4 {
                    didDrag = true
                }
                guard draggingKeyframeId == nil else {
                    applyDrag(to: value.location)
                    return
                }
                // First event: hit test for a potential drag target (and
                // selection).
                let data = dataPoint(at: value.location)
                let hit = KeyframeGraphMath.hitTest(
                    time: data.time,
                    value: data.value,
                    keyframes: propertyKeyframes,
                    timeTolerance: timeTolerance,
                    valueTolerance: valueTolerance
                )
                if let hit {
                    onSelect(hit.id)
                    dragStartedOnKeyframe = true
                    draggingKeyframeId = hit.id
                }
            }
            .onEnded { value in
                defer {
                    dragDraft = nil
                    draggingKeyframeId = nil
                    dragStartedOnKeyframe = false
                    didDrag = false
                }
                if didDrag {
                    if dragStartedOnKeyframe, draggingKeyframeId != nil, let draft = dragDraft {
                        // Commit the whole moved array once — single undo.
                        onChange(draft)
                    }
                    return
                }
                // Tap without a hit: add a keyframe at the tapped time/value.
                if !dragStartedOnKeyframe {
                    let data = dataPoint(at: value.location)
                    let added = KeyframeGraphMath.added(
                        keyframes: effectiveKeyframes,
                        property: selectedProperty,
                        time: data.time,
                        value: data.value
                    )
                    onChange(added)
                }
            }
    }

    /// Moves the drag target within the canvas bounds (local draft only).
    private func applyDrag(to location: CGPoint) {
        guard let id = draggingKeyframeId else { return }
        if dragDraft == nil { dragDraft = clip.keyframes }
        let clamped = CGPoint(
            x: min(max(location.x, 0), max(canvasSize.width, 1)),
            y: min(max(location.y, 0), max(canvasSize.height, 1))
        )
        let data = dataPoint(at: clamped)
        dragDraft = KeyframeGraphMath.moved(
            keyframes: dragDraft ?? [],
            id: id,
            time: data.time,
            value: data.value
        )
    }

    // MARK: - Coordinates

    private var timeDomain: ClosedRange<Double> {
        let lastKeyframe = propertyKeyframes.map(\.time).max() ?? 0
        let duration = max(clip.sourceRange.duration, lastKeyframe, 0.5)
        return 0...(duration * 1.05)
    }

    private func dataPoint(at point: CGPoint) -> (time: TimeInterval, value: Double) {
        let domain = timeDomain
        let range = KeyframeGraphMath.displayRange(for: propertyKeyframes)
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        let time = domain.lowerBound + Double(point.x / width) * (domain.upperBound - domain.lowerBound)
        let value = range.upperBound - Double(point.y / height) * (range.upperBound - range.lowerBound)
        return (min(max(time, domain.lowerBound), domain.upperBound),
                min(max(value, range.lowerBound), range.upperBound))
    }

    /// Hit tolerances in data space: 10px in time, 12px in value.
    private var timeTolerance: TimeInterval {
        max((timeDomain.upperBound - timeDomain.lowerBound) * 10.0 / Double(max(canvasSize.width, 1)), .ulpOfOne)
    }

    private var valueTolerance: Double {
        let range = KeyframeGraphMath.displayRange(for: propertyKeyframes)
        return max((range.upperBound - range.lowerBound) * 12.0 / Double(max(canvasSize.height, 1)), .ulpOfOne)
    }

    private func deleteSelected() {
        guard let id = selectedKeyId else { return }
        onChange(KeyframeGraphMath.removed(keyframes: effectiveKeyframes, id: id))
        onSelect(nil)
    }
}
