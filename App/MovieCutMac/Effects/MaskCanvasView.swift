import AppKit
import SwiftUI
import MovieCutCore

struct MaskCanvasView: View {
    @Binding var mask: Mask?
    var canvasSize: CGSize

    @State private var draftMask: Mask?
    @State private var gestureStartMask: Mask?
    @State private var isInteracting = false

    private static let coordinateSpaceName = "MaskCanvasViewCoordinateSpace"

    var body: some View {
        GeometryReader { proxy in
            editorOverlay(in: proxy.size)
        }
        .onChange(of: mask) { _, newValue in
            guard !isInteracting else { return }
            if newValue == nil || draftMask != newValue {
                draftMask = nil
            }
        }
    }

    @ViewBuilder
    private func editorOverlay(in viewSize: CGSize) -> some View {
        let metrics = MaskCanvasMetrics(viewSize: viewSize, canvasSize: canvasSize)

        if metrics.isUsable, let currentMask = draftMask ?? mask {
            let path = maskPath(for: currentMask, metrics: metrics)

            ZStack(alignment: .topLeading) {
                maskHitTarget(for: path)
                    .gesture(moveGesture(currentMask: currentMask, metrics: metrics))

                Canvas { context, _ in
                    drawMaskOverlay(currentMask, path: path, metrics: metrics, in: &context)
                }
                .allowsHitTesting(false)

                centerHandle(for: currentMask, metrics: metrics)

                ForEach(MaskCorner.allCases, id: \.self) { corner in
                    resizeHandle(for: corner, currentMask: currentMask, metrics: metrics)
                }

                rotationHandle(for: currentMask, metrics: metrics)

                shapeToolbar(currentMask: currentMask)
                    .padding(10)
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mask visual editor")
            .accessibilityValue(maskAccessibilityValue(for: currentMask))
            .accessibilityHint("Move the center handle, resize with corner handles, rotate with the top handle, or choose a mask shape from the toolbar.")
            .accessibilitySortPriority(0)
        }
    }

    private func drawMaskOverlay(
        _ currentMask: Mask,
        path: Path,
        metrics: MaskCanvasMetrics,
        in context: inout GraphicsContext
    ) {
        let accentColor = currentMask.inverted ? Color.orange : Color.cyan
        let featherWidth = metrics.featherStrokeWidth(for: currentMask.feather)

        if featherWidth > 0 {
            context.stroke(
                path,
                with: .color(accentColor.opacity(0.20)),
                style: StrokeStyle(lineWidth: featherWidth, lineCap: .round, lineJoin: .round)
            )
        }

        context.stroke(
            path,
            with: .color(accentColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
        )

        if currentMask.shape == .linear {
            let line = linearDirectionPath(for: currentMask, metrics: metrics)
            context.stroke(
                line,
                with: .color(Color.white.opacity(0.65)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }

        let center = metrics.viewPoint(for: currentMask.position)
        let rotationHandlePoint = rotationHandlePoint(for: currentMask, metrics: metrics)
        let topCenter = topCenterPoint(for: currentMask, metrics: metrics)

        var rotationStem = Path()
        rotationStem.move(to: topCenter)
        rotationStem.addLine(to: rotationHandlePoint)
        context.stroke(rotationStem, with: .color(Color.white.opacity(0.45)), lineWidth: 1.5)

        let radius = hypot(rotationHandlePoint.x - center.x, rotationHandlePoint.y - center.y)
        if radius.isFinite, radius > 8, abs(currentMask.rotation) > 0.1 {
            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(-90),
                endAngle: .degrees(-90 - currentMask.rotation),
                clockwise: currentMask.rotation > 0
            )
            context.stroke(
                arc,
                with: .color(Color.white.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func maskHitTarget(for path: Path) -> some View {
        let bounds = path.boundingRect.insetBy(dx: -24, dy: -24)
        return Color.clear
            .frame(width: max(bounds.width, 44), height: max(bounds.height, 44))
            .position(x: bounds.midX, y: bounds.midY)
            .contentShape(Rectangle())
    }

    private func centerHandle(for currentMask: Mask, metrics: MaskCanvasMetrics) -> some View {
        let center = metrics.viewPoint(for: currentMask.position)

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 18, height: 18)
            Rectangle()
                .fill(Color.white)
                .frame(width: 16, height: 1.5)
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: 16)
        }
        .position(center)
        .gesture(moveGesture(currentMask: currentMask, metrics: metrics))
        .accessibilityLabel("Mask center")
        .accessibilityValue(positionAccessibilityValue(for: currentMask.position))
        .accessibilityHint("Drag to move the mask on the canvas, or use VoiceOver actions to nudge the mask one percent at a time")
        .accessibilityAction(named: "Nudge mask left") {
            nudgeMask(currentMask, by: CGVector(dx: -metrics.accessibilityNudgeStepX, dy: 0), metrics: metrics)
        }
        .accessibilityAction(named: "Nudge mask right") {
            nudgeMask(currentMask, by: CGVector(dx: metrics.accessibilityNudgeStepX, dy: 0), metrics: metrics)
        }
        .accessibilityAction(named: "Nudge mask up") {
            nudgeMask(currentMask, by: CGVector(dx: 0, dy: metrics.accessibilityNudgeStepY), metrics: metrics)
        }
        .accessibilityAction(named: "Nudge mask down") {
            nudgeMask(currentMask, by: CGVector(dx: 0, dy: -metrics.accessibilityNudgeStepY), metrics: metrics)
        }
        .accessibilitySortPriority(4)
    }

    private func resizeHandle(
        for corner: MaskCorner,
        currentMask: Mask,
        metrics: MaskCanvasMetrics
    ) -> some View {
        let point = cornerPoint(for: corner, mask: currentMask, metrics: metrics)

        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .position(point)
            .gesture(resizeGesture(corner: corner, currentMask: currentMask, metrics: metrics))
            .accessibilityLabel(corner.accessibilityLabel)
            .accessibilityValue(sizeAccessibilityValue(for: currentMask.size))
            .accessibilityHint("Drag to resize the mask, hold Shift to preserve aspect ratio, or use VoiceOver actions to adjust width and height one percent at a time")
            .accessibilityAction(named: "Increase mask width") {
                resizeMask(currentMask, by: CGSize(width: metrics.accessibilityResizeStepX, height: 0), metrics: metrics)
            }
            .accessibilityAction(named: "Decrease mask width") {
                resizeMask(currentMask, by: CGSize(width: -metrics.accessibilityResizeStepX, height: 0), metrics: metrics)
            }
            .accessibilityAction(named: "Increase mask height") {
                resizeMask(currentMask, by: CGSize(width: 0, height: metrics.accessibilityResizeStepY), metrics: metrics)
            }
            .accessibilityAction(named: "Decrease mask height") {
                resizeMask(currentMask, by: CGSize(width: 0, height: -metrics.accessibilityResizeStepY), metrics: metrics)
            }
            .accessibilitySortPriority(3)
    }

    private func rotationHandle(for currentMask: Mask, metrics: MaskCanvasMetrics) -> some View {
        let point = rotationHandlePoint(for: currentMask, metrics: metrics)

        return Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .position(point)
            .gesture(rotationGesture(currentMask: currentMask, metrics: metrics))
            .accessibilityLabel("Rotate mask")
            .accessibilityValue(rotationAccessibilityValue(for: currentMask.rotation))
            .accessibilityHint("Drag to rotate the mask, or use VoiceOver actions to rotate five degrees at a time")
            .accessibilityAction(named: "Rotate mask counterclockwise") {
                rotateMask(currentMask, by: -5)
            }
            .accessibilityAction(named: "Rotate mask clockwise") {
                rotateMask(currentMask, by: 5)
            }
            .accessibilitySortPriority(2)
    }

    private func shapeToolbar(currentMask: Mask) -> some View {
        HStack(spacing: 6) {
            ForEach(MaskShape.allCases, id: \.self) { shape in
                toolbarButton(
                    systemImage: shape.systemImage,
                    isSelected: currentMask.shape == shape,
                    accessibilityLabel: shape.displayName
                ) {
                    var updatedMask = currentMask
                    updatedMask.shape = shape
                    if shape == .brush, updatedMask.brushPoints.count < 2 {
                        updatedMask.brushPoints = defaultBrushPoints(for: updatedMask)
                    }
                    updateMask(updatedMask)
                }
            }

            Divider()
                .frame(height: 20)

            toolbarButton(
                systemImage: "circle.lefthalf.filled",
                isSelected: currentMask.inverted,
                accessibilityLabel: "Invert mask"
            ) {
                var updatedMask = currentMask
                updatedMask.inverted.toggle()
                updateMask(updatedMask)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        .accessibilitySortPriority(1)
    }

    private func toolbarButton(
        systemImage: String,
        isSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Current mask option" : "Activate to apply this mask option")
    }

    private func maskAccessibilityValue(for currentMask: Mask) -> String {
        let shape = currentMask.shape.displayName
        let mode = currentMask.inverted ? "inverted" : "normal"
        return "\(shape), \(mode), \(positionAccessibilityValue(for: currentMask.position)), \(sizeAccessibilityValue(for: currentMask.size)), \(rotationAccessibilityValue(for: currentMask.rotation))"
    }

    private func positionAccessibilityValue(for position: CGPoint) -> String {
        "x \(rounded(position.x)), y \(rounded(position.y))"
    }

    private func sizeAccessibilityValue(for size: CGSize) -> String {
        "width \(rounded(size.width)), height \(rounded(size.height))"
    }

    private func rotationAccessibilityValue(for rotation: Double) -> String {
        "rotation \(rounded(rotation)) degrees"
    }

    private func rounded(_ value: CGFloat) -> String {
        String(format: "%.0f", Double(value))
    }

    private func rounded(_ value: Double) -> String {
        String(format: "%.0f", value)
    }

    private func moveGesture(currentMask: Mask, metrics: MaskCanvasMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                beginInteraction(with: currentMask)
                guard let startMask = gestureStartMask else { return }

                let delta = metrics.canvasVector(for: value.translation)
                var updatedMask = startMask
                updatedMask.position = metrics.clampedCanvasPoint(CGPoint(
                    x: startMask.position.x + delta.dx,
                    y: startMask.position.y + delta.dy
                ))

                if updatedMask.shape == .brush, startMask.brushPoints.count > 1 {
                    updatedMask.brushPoints = offset(startMask.brushPoints, by: delta)
                }

                updateMask(updatedMask)
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    private func resizeGesture(
        corner: MaskCorner,
        currentMask: Mask,
        metrics: MaskCanvasMetrics
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                beginInteraction(with: currentMask)
                guard let startMask = gestureStartMask else { return }

                let canvasDelta = metrics.canvasVector(for: value.translation)
                let localDelta = inverseRotate(canvasDelta, degrees: startMask.rotation)
                let minimumSize = metrics.minimumMaskSize
                let originalAspect = max(startMask.size.width / max(startMask.size.height, 1), 0.01)

                var width = startMask.size.width + (2 * corner.xSign * localDelta.dx)
                var height = startMask.size.height + (2 * corner.ySign * localDelta.dy)

                width = min(max(width, minimumSize), metrics.canvasSize.width)
                height = min(max(height, minimumSize), metrics.canvasSize.height)

                if isShiftPressed {
                    let widthDelta = abs(width - startMask.size.width)
                    let heightDelta = abs(height - startMask.size.height)

                    if widthDelta >= heightDelta * originalAspect {
                        height = width / originalAspect
                    } else {
                        width = height * originalAspect
                    }

                    width = min(max(width, minimumSize), metrics.canvasSize.width)
                    height = min(max(height, minimumSize), metrics.canvasSize.height)
                }

                var updatedMask = startMask
                updatedMask.size = CGSize(width: width, height: height)

                if updatedMask.shape == .brush, startMask.brushPoints.count > 1 {
                    updatedMask.brushPoints = scaleBrushPoints(
                        startMask.brushPoints,
                        around: startMask.position,
                        from: startMask.size,
                        to: updatedMask.size
                    )
                }

                updateMask(updatedMask)
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    private func rotationGesture(currentMask: Mask, metrics: MaskCanvasMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                beginInteraction(with: currentMask)
                guard let startMask = gestureStartMask else { return }

                var updatedMask = startMask
                updatedMask.rotation = rotationDegrees(for: value.location, around: startMask.position, metrics: metrics)

                if updatedMask.shape == .brush, startMask.brushPoints.count > 1 {
                    let delta = normalizedDegrees(updatedMask.rotation - startMask.rotation)
                    updatedMask.brushPoints = rotate(startMask.brushPoints, degrees: delta, around: startMask.position)
                }

                updateMask(updatedMask)
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    private func beginInteraction(with currentMask: Mask) {
        if gestureStartMask == nil {
            gestureStartMask = currentMask
        }
        isInteracting = true
    }

    private func finishInteraction() {
        gestureStartMask = nil
        isInteracting = false
    }

    private func updateMask(_ updatedMask: Mask) {
        draftMask = updatedMask
        mask = updatedMask
    }

    private func nudgeMask(_ currentMask: Mask, by requestedDelta: CGVector, metrics: MaskCanvasMetrics) {
        let newPosition = metrics.clampedCanvasPoint(CGPoint(
            x: currentMask.position.x + requestedDelta.dx,
            y: currentMask.position.y + requestedDelta.dy
        ))
        let appliedDelta = CGVector(
            dx: newPosition.x - currentMask.position.x,
            dy: newPosition.y - currentMask.position.y
        )

        var updatedMask = currentMask
        updatedMask.position = newPosition

        if updatedMask.shape == .brush, currentMask.brushPoints.count > 1 {
            updatedMask.brushPoints = offset(currentMask.brushPoints, by: appliedDelta)
        }

        updateMask(updatedMask)
    }

    private func resizeMask(_ currentMask: Mask, by deltaSize: CGSize, metrics: MaskCanvasMetrics) {
        var updatedMask = currentMask
        updatedMask.size = CGSize(
            width: min(max(currentMask.size.width + deltaSize.width, metrics.minimumMaskSize), metrics.canvasSize.width),
            height: min(max(currentMask.size.height + deltaSize.height, metrics.minimumMaskSize), metrics.canvasSize.height)
        )

        if updatedMask.shape == .brush, currentMask.brushPoints.count > 1 {
            updatedMask.brushPoints = scaleBrushPoints(
                currentMask.brushPoints,
                around: currentMask.position,
                from: currentMask.size,
                to: updatedMask.size
            )
        }

        updateMask(updatedMask)
    }

    private func rotateMask(_ currentMask: Mask, by deltaDegrees: Double) {
        var updatedMask = currentMask
        updatedMask.rotation = normalizedDegrees(currentMask.rotation + deltaDegrees)

        if updatedMask.shape == .brush, currentMask.brushPoints.count > 1 {
            updatedMask.brushPoints = rotate(currentMask.brushPoints, degrees: deltaDegrees, around: currentMask.position)
        }

        updateMask(updatedMask)
    }

    private func maskPath(for currentMask: Mask, metrics: MaskCanvasMetrics) -> Path {
        switch currentMask.shape {
        case .rectangle, .linear:
            return closedPath(points: rectanglePoints(for: currentMask).map(metrics.viewPoint(for:)))
        case .ellipse:
            return closedPath(points: ellipsePoints(for: currentMask).map(metrics.viewPoint(for:)))
        case .triangle:
            return closedPath(points: trianglePoints(for: currentMask).map(metrics.viewPoint(for:)))
        case .diamond:
            return closedPath(points: diamondPoints(for: currentMask).map(metrics.viewPoint(for:)))
        case .brush:
            return openPath(points: brushPoints(for: currentMask).map(metrics.viewPoint(for:)))
        }
    }

    private func linearDirectionPath(for currentMask: Mask, metrics: MaskCanvasMetrics) -> Path {
        let halfHeight = max(currentMask.size.height * 0.5, 1)
        let startVector = rotate(CGVector(dx: 0, dy: halfHeight), degrees: currentMask.rotation)
        let endVector = rotate(CGVector(dx: 0, dy: -halfHeight), degrees: currentMask.rotation)
        let start = metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + startVector.dx,
            y: currentMask.position.y + startVector.dy
        ))
        let end = metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + endVector.dx,
            y: currentMask.position.y + endVector.dy
        ))

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    private func closedPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func openPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func rectanglePoints(for currentMask: Mask) -> [CGPoint] {
        MaskShapeGeometry.rectanglePoints(for: currentMask)
    }

    private func ellipsePoints(for currentMask: Mask) -> [CGPoint] {
        MaskShapeGeometry.ellipsePoints(for: currentMask)
    }

    private func trianglePoints(for currentMask: Mask) -> [CGPoint] {
        MaskShapeGeometry.trianglePoints(for: currentMask)
    }

    private func diamondPoints(for currentMask: Mask) -> [CGPoint] {
        MaskShapeGeometry.diamondPoints(for: currentMask)
    }

    private func brushPoints(for currentMask: Mask) -> [CGPoint] {
        MaskShapeGeometry.brushPoints(for: currentMask)
    }

    private func cornerPoint(
        for corner: MaskCorner,
        mask currentMask: Mask,
        metrics: MaskCanvasMetrics
    ) -> CGPoint {
        let local = CGVector(
            dx: corner.xSign * currentMask.size.width * 0.5,
            dy: corner.ySign * currentMask.size.height * 0.5
        )
        let rotated = MaskShapeGeometry.rotate(local, degrees: currentMask.rotation)
        return metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + rotated.dx,
            y: currentMask.position.y + rotated.dy
        ))
    }

    private func topCenterPoint(for currentMask: Mask, metrics: MaskCanvasMetrics) -> CGPoint {
        let local = CGVector(dx: 0, dy: currentMask.size.height * 0.5)
        let rotated = MaskShapeGeometry.rotate(local, degrees: currentMask.rotation)
        return metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + rotated.dx,
            y: currentMask.position.y + rotated.dy
        ))
    }

    private func rotationHandlePoint(for currentMask: Mask, metrics: MaskCanvasMetrics) -> CGPoint {
        let center = metrics.viewPoint(for: currentMask.position)
        let topCenter = topCenterPoint(for: currentMask, metrics: metrics)
        let dx = topCenter.x - center.x
        let dy = topCenter.y - center.y
        let length = max(hypot(dx, dy), 1)
        let handleDistance: CGFloat = 36

        return CGPoint(
            x: topCenter.x + (dx / length) * handleDistance,
            y: topCenter.y + (dy / length) * handleDistance
        )
    }

    private func rotationDegrees(
        for location: CGPoint,
        around center: CGPoint,
        metrics: MaskCanvasMetrics
    ) -> Double {
        let centerPoint = metrics.viewPoint(for: center)
        let dx = (location.x - centerPoint.x) / metrics.scaleX
        let dy = (centerPoint.y - location.y) / metrics.scaleY
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > 0.001 else {
            return 0
        }
        return MaskShapeGeometry.normalizedDegrees(Double(atan2(-dx, dy) * 180 / CGFloat.pi))
    }

    private var isShiftPressed: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }
}

private struct MaskCanvasMetrics {
    var viewSize: CGSize
    var canvasSize: CGSize

    var isUsable: Bool {
        viewSize.width > 0 &&
            viewSize.height > 0 &&
            canvasSize.width > 0 &&
            canvasSize.height > 0
    }

    var scaleX: CGFloat {
        viewSize.width / max(canvasSize.width, 1)
    }

    var scaleY: CGFloat {
        viewSize.height / max(canvasSize.height, 1)
    }

    var minimumMaskSize: CGFloat {
        max(min(canvasSize.width, canvasSize.height) * 0.02, 12)
    }

    var accessibilityNudgeStepX: CGFloat {
        max(canvasSize.width * 0.01, 1)
    }

    var accessibilityNudgeStepY: CGFloat {
        max(canvasSize.height * 0.01, 1)
    }

    var accessibilityResizeStepX: CGFloat {
        max(canvasSize.width * 0.01, 1)
    }

    var accessibilityResizeStepY: CGFloat {
        max(canvasSize.height * 0.01, 1)
    }

    func viewPoint(for canvasPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: canvasPoint.x * scaleX,
            y: viewSize.height - (canvasPoint.y * scaleY)
        )
    }

    func canvasVector(for translation: CGSize) -> CGVector {
        CGVector(
            dx: translation.width / max(scaleX, .leastNonzeroMagnitude),
            dy: -translation.height / max(scaleY, .leastNonzeroMagnitude)
        )
    }

    func clampedCanvasPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }

    func featherStrokeWidth(for feather: Double) -> CGFloat {
        guard feather > 0 else { return 0 }
        let scaledRadius = CGFloat(feather) * 10 * min(scaleX, scaleY)
        return max(4, scaledRadius * 2)
    }
}

private enum MaskCorner: CaseIterable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var xSign: CGFloat {
        switch self {
        case .topLeft, .bottomLeft:
            return -1
        case .topRight, .bottomRight:
            return 1
        }
    }

    var ySign: CGFloat {
        switch self {
        case .topLeft, .topRight:
            return 1
        case .bottomRight, .bottomLeft:
            return -1
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .topLeft:
            return "Top left resize handle"
        case .topRight:
            return "Top right resize handle"
        case .bottomRight:
            return "Bottom right resize handle"
        case .bottomLeft:
            return "Bottom left resize handle"
        }
    }
}

private extension MaskShape {
    var systemImage: String {
        switch self {
        case .rectangle:
            return "rectangle"
        case .ellipse:
            return "circle"
        case .triangle:
            return "triangle"
        case .diamond:
            return "diamond"
        case .linear:
            return "line.diagonal"
        case .brush:
            return "paintbrush"
        }
    }
}
