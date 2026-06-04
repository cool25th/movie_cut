#if os(iOS)
import SwiftUI
import MovieCutCore

struct IOSMaskCanvasView: View {
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

                shapeToolbar(currentMask: currentMask)
                    .padding(10)
            }
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
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
    }

    // MARK: - Toolbar

    private func shapeToolbar(currentMask: Mask) -> some View {
        HStack(spacing: 8) {
            ForEach(MaskShape.allCases, id: \.self) { shape in
                Button {
                    var updatedMask = currentMask
                    updatedMask.shape = shape
                    updateMask(updatedMask)
                } label: {
                    Image(systemName: shape.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(currentMask.shape == shape ? Color.white : Color.primary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(currentMask.shape == shape ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 24)

            Button {
                var updatedMask = currentMask
                updatedMask.inverted.toggle()
                updateMask(updatedMask)
            } label: {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(currentMask.inverted ? Color.white : Color.primary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(currentMask.inverted ? Color.orange : Color.clear)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
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
                let localDelta = inverseRotate(canvasDelta, degrees: startMask.rotation)
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
        let hw = max(currentMask.size.width * 0.5, 1)
        let hh = max(currentMask.size.height * 0.5, 1)
        return transformed([
            CGPoint(x: -hw, y: hh), CGPoint(x: hw, y: hh),
            CGPoint(x: hw, y: -hh), CGPoint(x: -hw, y: -hh)
        ], for: currentMask)
    }

    private func ellipsePoints(for currentMask: Mask) -> [CGPoint] {
        let hw = max(currentMask.size.width * 0.5, 1)
        let hh = max(currentMask.size.height * 0.5, 1)
        let localPoints = (0..<72).map { i in
            let angle = (CGFloat(i) / 72) * 2 * .pi
            return CGPoint(x: cos(angle) * hw, y: sin(angle) * hh)
        }
        return transformed(localPoints, for: currentMask)
    }

    private func trianglePoints(for currentMask: Mask) -> [CGPoint] {
        let hw = max(currentMask.size.width * 0.5, 1)
        let hh = max(currentMask.size.height * 0.5, 1)
        return transformed([
            CGPoint(x: 0, y: hh), CGPoint(x: -hw, y: -hh), CGPoint(x: hw, y: -hh)
        ], for: currentMask)
    }

    private func diamondPoints(for currentMask: Mask) -> [CGPoint] {
        let hw = max(currentMask.size.width * 0.5, 1)
        let hh = max(currentMask.size.height * 0.5, 1)
        return transformed([
            CGPoint(x: 0, y: hh), CGPoint(x: hw, y: 0),
            CGPoint(x: 0, y: -hh), CGPoint(x: -hw, y: 0)
        ], for: currentMask)
    }

    private func brushPoints(for currentMask: Mask) -> [CGPoint] {
        if currentMask.brushPoints.count > 1 {
            return currentMask.brushPoints
        }
        let hw = max(currentMask.size.width * 0.5, 1)
        return [
            CGPoint(x: currentMask.position.x - hw, y: currentMask.position.y),
            CGPoint(x: currentMask.position.x + hw, y: currentMask.position.y)
        ]
    }

    private func transformed(_ localPoints: [CGPoint], for currentMask: Mask) -> [CGPoint] {
        localPoints.map { point in
            let rotated = Self.rotate(CGVector(dx: point.x, dy: point.y), degrees: currentMask.rotation)
            return CGPoint(
                x: currentMask.position.x + rotated.dx,
                y: currentMask.position.y + rotated.dy
            )
        }
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
        let rotated = Self.rotate(local, degrees: currentMask.rotation)
        return metrics.viewPoint(for: CGPoint(
            x: currentMask.position.x + rotated.dx,
            y: currentMask.position.y + rotated.dy
        ))
    }

    // MARK: - Geometry Helpers

    private func inverseRotate(_ vector: CGVector, degrees: Double) -> CGVector {
        let radians = -degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        return CGVector(
            dx: vector.dx * cosA - vector.dy * sinA,
            dy: vector.dx * sinA + vector.dy * cosA
        )
    }

    private static func rotate(_ vector: CGVector, degrees: Double) -> CGVector {
        let radians = degrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        return CGVector(
            dx: vector.dx * cosA - vector.dy * sinA,
            dy: vector.dx * sinA + vector.dy * cosA
        )
    }
}

// MARK: - iOS Metrics

private struct IOSMaskMetrics {
    let viewSize: CGSize
    let canvasSize: CGSize
    let scale: CGFloat

    var isUsable: Bool { scale > 0 && viewSize.width > 0 && viewSize.height > 0 }
    var minimumMaskSize: CGFloat { 20 / scale }

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
        CGPoint(
            x: min(max(point.x, 0), canvasSize.width),
            y: min(max(point.y, 0), canvasSize.height)
        )
    }
}
#endif
