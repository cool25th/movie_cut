#if os(iOS)
import SwiftUI
import MovieCutCore

struct IOSMaskCanvasView: View {
    private static let coordinateSpaceName = "IOSMaskCanvasViewSpace"

    @Binding var mask: Mask?
    var canvasSize: CGSize

    @State private var draftMask: Mask?
    @State private var gestureStartMask: Mask?
    @State private var isInteracting = false

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
        let metrics = IOSMaskMetrics(viewSize: viewSize, canvasSize: canvasSize)

        if metrics.isUsable, let currentMask = draftMask ?? mask {
            let path = maskPath(for: currentMask, metrics: metrics)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: viewSize.width, height: viewSize.height)
                    .contentShape(Rectangle())
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
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
            .coordinateSpace(name: Self.coordinateSpaceName)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mask visual editor")
            .accessibilityValue(maskAccessibilityValue(for: currentMask))
            .accessibilityHint("Move the center handle, resize with corner handles, rotate with the top handle, or choose a mask shape from the toolbar.")
            .accessibilitySortPriority(0)
        }
    }

    // MARK: - Drawing

    private func drawMaskOverlay(
        _ currentMask: Mask,
        path: Path,
        metrics: IOSMaskMetrics,
        in context: inout GraphicsContext
    ) {
        let accentColor = currentMask.inverted ? Color.orange : Color.cyan

        context.stroke(
            path,
            with: .color(accentColor),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 4])
        )

        let topCenter = topCenterPoint(for: currentMask, metrics: metrics)
        let rotationHandlePoint = rotationHandlePoint(for: currentMask, metrics: metrics)
        var rotationStem = Path()
        rotationStem.move(to: topCenter)
        rotationStem.addLine(to: rotationHandlePoint)
        context.stroke(rotationStem, with: .color(Color.white.opacity(0.45)), lineWidth: 1.5)
    }

    // MARK: - Handles

    private func centerHandle(for currentMask: Mask, metrics: IOSMaskMetrics) -> some View {
        let center = metrics.viewPoint(for: currentMask.position)

        return ZStack {
            Circle()
                .fill(Color.black.opacity(0.35))
                .frame(width: 24, height: 24)
            Rectangle()
                .fill(Color.white)
                .frame(width: 20, height: 1.5)
            Rectangle()
                .fill(Color.white)
                .frame(width: 1.5, height: 20)
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
            nudgeMask(currentMask, by: CGVector(dx: 0, dy: -metrics.accessibilityNudgeStepY), metrics: metrics)
        }
        .accessibilityAction(named: "Nudge mask down") {
            nudgeMask(currentMask, by: CGVector(dx: 0, dy: metrics.accessibilityNudgeStepY), metrics: metrics)
        }
        .accessibilitySortPriority(4)
    }

    private func resizeHandle(
        for corner: MaskCorner,
        currentMask: Mask,
        metrics: IOSMaskMetrics
    ) -> some View {
        let point = cornerPoint(for: corner, mask: currentMask, metrics: metrics)

        return Circle()
            .fill(Color.white)
            .frame(width: 16, height: 16)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 2)
            .position(point)
            .gesture(resizeGesture(corner: corner, currentMask: currentMask, metrics: metrics))
            .accessibilityLabel(corner.accessibilityLabel)
            .accessibilityValue(sizeAccessibilityValue(for: currentMask.size))
            .accessibilityHint("Drag to resize the mask, or use VoiceOver actions to adjust width and height one percent at a time")
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

    private func rotationHandle(for currentMask: Mask, metrics: IOSMaskMetrics) -> some View {
        let point = rotationHandlePoint(for: currentMask, metrics: metrics)

        return Circle()
            .fill(Color.white)
            .frame(width: 18, height: 18)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 2)
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

    // MARK: - Toolbar

    private func shapeToolbar(currentMask: Mask) -> some View {
        HStack(spacing: 8) {
            ForEach(MaskShape.allCases, id: \.self) { shape in
                toolbarButton(
                    systemImage: shape.systemImage,
                    isSelected: currentMask.shape == shape,
                    accessibilityLabel: shape.accessibilityLabel
                ) {
                    var updatedMask = currentMask
                    updatedMask.shape = shape
                    updateMask(updatedMask)
                }
            }

            Divider()
                .frame(height: 24)

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
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(isSelected ? "Current mask option" : "Activate to apply this mask option")
    }

    private func maskAccessibilityValue(for currentMask: Mask) -> String {
        let mode = currentMask.inverted ? "inverted" : "normal"
        return "\(currentMask.shape.accessibilityLabel), \(mode), \(positionAccessibilityValue(for: currentMask.position)), \(sizeAccessibilityValue(for: currentMask.size)), \(rotationAccessibilityValue(for: currentMask.rotation))"
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

    // MARK: - Gestures (iOS touch)

    private func moveGesture(currentMask: Mask, metrics: IOSMaskMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0)
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
                    updatedMask.brushPoints = MaskShapeGeometry.offset(startMask.brushPoints, by: delta)
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
        metrics: IOSMaskMetrics
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                beginInteraction(with: currentMask)
                guard let startMask = gestureStartMask else { return }

                let canvasDelta = metrics.canvasVector(for: value.translation)
                let localDelta = MaskShapeGeometry.inverseRotate(canvasDelta, degrees: startMask.rotation)
                let minimumSize = metrics.minimumMaskSize

                var width = startMask.size.width + (2 * corner.xSign * localDelta.dx)
                var height = startMask.size.height + (2 * corner.ySign * localDelta.dy)

                width = min(max(width, minimumSize), metrics.canvasSize.width)
                height = min(max(height, minimumSize), metrics.canvasSize.height)

                var updatedMask = startMask
                updatedMask.size = CGSize(width: width, height: height)
                updateMask(updatedMask)
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    private func rotationGesture(currentMask: Mask, metrics: IOSMaskMetrics) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                beginInteraction(with: currentMask)
                guard let startMask = gestureStartMask else { return }

                var updatedMask = startMask
                updatedMask.rotation = rotationDegrees(for: value.location, around: startMask.position, metrics: metrics)

                if updatedMask.shape == .brush, startMask.brushPoints.count > 1 {
                    let delta = MaskShapeGeometry.normalizedDegrees(updatedMask.rotation - startMask.rotation)
                    updatedMask.brushPoints = MaskShapeGeometry.rotate(startMask.brushPoints, degrees: delta, around: startMask.position)
                }

                updateMask(updatedMask)
            }
            .onEnded { _ in
                finishInteraction()
            }
    }

    // MARK: - Interaction State

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

    private func nudgeMask(_ currentMask: Mask, by requestedDelta: CGVector, metrics: IOSMaskMetrics) {
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
            updatedMask.brushPoints = MaskShapeGeometry.offset(currentMask.brushPoints, by: appliedDelta)
        }

        updateMask(updatedMask)
    }

    private func rotateMask(_ currentMask: Mask, by deltaDegrees: Double) {
        var updatedMask = currentMask
        updatedMask.rotation = MaskShapeGeometry.normalizedDegrees(currentMask.rotation + deltaDegrees)

        if updatedMask.shape == .brush, currentMask.brushPoints.count > 1 {
            updatedMask.brushPoints = MaskShapeGeometry.rotate(currentMask.brushPoints, degrees: deltaDegrees, around: currentMask.position)
        }

        updateMask(updatedMask)
    }

    private func resizeMask(_ currentMask: Mask, by deltaSize: CGSize, metrics: IOSMaskMetrics) {
        var updatedMask = currentMask
        updatedMask.size = CGSize(
            width: min(max(currentMask.size.width + deltaSize.width, metrics.minimumMaskSize), metrics.canvasSize.width),
            height: min(max(currentMask.size.height + deltaSize.height, metrics.minimumMaskSize), metrics.canvasSize.height)
        )
        updateMask(updatedMask)
    }

    // MARK: - Path Generation

    private func maskPath(for currentMask: Mask, metrics: IOSMaskMetrics) -> Path {
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

    // MARK: - Shape Points

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
        metrics: IOSMaskMetrics
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

    private func topCenterPoint(for currentMask: Mask, metrics: IOSMaskMetrics) -> CGPoint {
        let local = CGVector(dx: 0, dy: currentMask.size.height * 0.5)
        let rotated = MaskShapeGeometry.rotate(local, degrees: currentMask.rotation)
        return metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + rotated.dx,
            y: currentMask.position.y + rotated.dy
        ))
    }

    private func rotationHandlePoint(for currentMask: Mask, metrics: IOSMaskMetrics) -> CGPoint {
        let center = metrics.viewPoint(for: currentMask.position)
        let topCenter = topCenterPoint(for: currentMask, metrics: metrics)
        let dx = topCenter.x - center.x
        let dy = topCenter.y - center.y
        let length = max(hypot(dx, dy), 1)
        let handleDistance: CGFloat = 40

        return CGPoint(
            x: topCenter.x + (dx / length) * handleDistance,
            y: topCenter.y + (dy / length) * handleDistance
        )
    }

    // MARK: - Geometry Helpers

    private func rotationDegrees(for location: CGPoint, around center: CGPoint, metrics: IOSMaskMetrics) -> Double {
        let centerPoint = metrics.viewPoint(for: center)
        let dx = (location.x - centerPoint.x) / metrics.scale
        let dy = (location.y - centerPoint.y) / metrics.scale
        guard dx.isFinite, dy.isFinite, hypot(dx, dy) > 0.001 else { return 0 }
        return MaskShapeGeometry.normalizedDegrees(Double(atan2(-dx, dy) * 180 / CGFloat.pi))
    }
}

// MARK: - iOS Metrics

private struct IOSMaskMetrics {
    let viewSize: CGSize
    let canvasSize: CGSize
    let scale: CGFloat

    var isUsable: Bool { scale > 0 && viewSize.width > 0 && viewSize.height > 0 }
    var minimumMaskSize: CGFloat { 20 / scale }
    var accessibilityNudgeStepX: CGFloat { max(canvasSize.width * 0.01, 1) }
    var accessibilityNudgeStepY: CGFloat { max(canvasSize.height * 0.01, 1) }
    var accessibilityResizeStepX: CGFloat { max(canvasSize.width * 0.01, 1) }
    var accessibilityResizeStepY: CGFloat { max(canvasSize.height * 0.01, 1) }

    init(viewSize: CGSize, canvasSize: CGSize) {
        self.viewSize = viewSize
        self.canvasSize = canvasSize
        let scaleX = viewSize.width / max(canvasSize.width, 1)
        let scaleY = viewSize.height / max(canvasSize.height, 1)
        self.scale = min(scaleX, scaleY)
    }

    func viewPoint(for canvasPoint: CGPoint) -> CGPoint {
        let offsetX = (viewSize.width - canvasSize.width * scale) * 0.5
        let offsetY = (viewSize.height - canvasSize.height * scale) * 0.5
        return CGPoint(
            x: canvasPoint.x * scale + offsetX,
            y: canvasPoint.y * scale + offsetY
        )
    }

    func canvasVector(for viewTranslation: CGSize) -> CGVector {
        CGVector(dx: viewTranslation.width / scale, dy: viewTranslation.height / scale)
    }

    func clampedCanvasPoint(_ point: CGPoint) -> CGPoint {
        CanvasGeometry.clampedCanvasPoint(point, canvasSize: canvasSize)
    }
}

// MaskCorner and MaskShape.systemImage live in MovieCutCore (Models/Mask.swift).

private extension MaskShape {
    var accessibilityLabel: String {
        switch self {
        case .rectangle:
            return "Rectangle mask"
        case .ellipse:
            return "Ellipse mask"
        case .triangle:
            return "Triangle mask"
        case .diamond:
            return "Diamond mask"
        case .linear:
            return "Linear mask"
        case .brush:
            return "Brush mask"
        }
    }
}
#endif
