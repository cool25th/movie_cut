import AppKit
import SwiftUI
import MovieCutCore

/// G-23 Inc 2 canvas crop editor. Overlays the preview canvas while active and
/// shows the UNCROPPED source frame (asset thumbnail, aspect-fit) with a
/// movable/resizable crop window — the CapCut-style full-frame context the
/// baked-in preview cannot provide, because the composition already crops.
///
/// Following the CanvasTransformOverlay commit model: gestures update a local
/// draft (the backdrop + dimming render live), and one `onCommit` fires when
/// the gesture ends, so a whole drag is a single undo step via
/// `SetClipPropertyCommand.cropRect`.
struct CropCanvasView: View {
    var cropRect: NormalizedRect?
    var thumbnailData: Data?
    var sourceAspect: Double
    var canvasSize: CGSize
    var onCommit: (NormalizedRect?) -> Void
    var onDone: () -> Void

    @State private var draftCropRect: NormalizedRect?
    @State private var gestureStart: (rect: NormalizedRect, handle: CropRectEditingMath.Handle)?

    private static let coordinateSpaceName = "CropCanvasViewCoordinateSpace"

    /// Pixel aspect of the crop window the gesture must keep when Shift is
    /// held: the canvas ratio, so the cropped clip fills the render canvas
    /// with no additional aspect-fill cut. Expressed over NORMALIZED units
    /// (the CropRectEditingMath convention): width/height in source pixels
    /// equals (width·sourceAspect)/height.
    private var shiftLockAspect: Double? {
        guard canvasSize.height > 0, sourceAspect.isFinite, sourceAspect > 0 else { return nil }
        let canvasAspect = Double(canvasSize.width / canvasSize.height)
        return canvasAspect / sourceAspect
    }

    private var currentRect: NormalizedRect {
        draftCropRect ?? cropRect ?? NormalizedRect(x: 0, y: 0, width: 1, height: 1)!
    }

    var body: some View {
        GeometryReader { proxy in
            editorOverlay(in: proxy.size)
        }
        .onChange(of: cropRect) { _, newValue in
            guard gestureStart == nil else { return }
            draftCropRect = nil
        }
    }

    @ViewBuilder
    private func editorOverlay(in viewSize: CGSize) -> some View {
        let metrics = CropCanvasMetrics(viewSize: viewSize, sourceAspect: sourceAspect)

        if metrics.isUsable {
            let rect = currentRect
            let cropFrame = metrics.viewRect(for: rect)
            let fitted = metrics.fittedSourceFrame

            ZStack(alignment: .topLeading) {
                backdrop(thumbnailData: thumbnailData, in: fitted)

                dimmingOverlay(around: cropFrame, in: viewSize)

                cropWindow(cropFrame)

                interiorHitTarget(cropFrame, rect: rect, metrics: metrics)

                ForEach(CropRectEditingMath.Handle.allCases, id: \.self) { handle in
                    if handle != .interior {
                        handleView(handle, rect: rect, metrics: metrics)
                    }
                }

                editorToolbar
                    .padding(10)
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Crop visual editor")
            .accessibilityValue(cropAccessibilityValue(for: rect))
            .accessibilityHint("Drag the corner or edge handles to crop, drag inside to move the crop window. Hold Shift to keep the canvas ratio.")
        }
    }

    // MARK: backdrop

    @ViewBuilder
    private func backdrop(thumbnailData: Data?, in fitted: CGRect) -> some View {
        ZStack(alignment: .center) {
            Color.black.opacity(0.85)

            if let data = thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
            } else {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
            }
        }
        .allowsHitTesting(false)
    }

    /// Dims everything outside the crop window (the classic crop matte).
    private func dimmingOverlay(around cropFrame: CGRect, in viewSize: CGSize) -> some View {
        Canvas { context, _ in
            var matte = Path(CGRect(origin: .zero, size: viewSize))
            matte.addRect(cropFrame)
            context.fill(matte, with: .color(.black.opacity(0.55)), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }

    private func cropWindow(_ cropFrame: CGRect) -> some View {
        ZStack {
            Rectangle()
                .stroke(Color.white, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

            // Rule-of-thirds guides inside the window.
            Path { path in
                for fraction in [1.0 / 3.0, 2.0 / 3.0] {
                    var vertical = Path()
                    vertical.move(to: CGPoint(x: cropFrame.minX + cropFrame.width * fraction, y: cropFrame.minY))
                    vertical.addLine(to: CGPoint(x: cropFrame.minX + cropFrame.width * fraction, y: cropFrame.maxY))
                    path.addPath(vertical)

                    var horizontal = Path()
                    horizontal.move(to: CGPoint(x: cropFrame.minX, y: cropFrame.minY + cropFrame.height * fraction))
                    horizontal.addLine(to: CGPoint(x: cropFrame.maxX, y: cropFrame.minY + cropFrame.height * fraction))
                    path.addPath(horizontal)
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 1)
        }
        .frame(width: cropFrame.width, height: cropFrame.height)
        .position(x: cropFrame.midX, y: cropFrame.midY)
        .allowsHitTesting(false)
    }

    // MARK: gestures

    private func interiorHitTarget(
        _ cropFrame: CGRect,
        rect: NormalizedRect,
        metrics: CropCanvasMetrics
    ) -> some View {
        Color.clear
            .frame(width: cropFrame.width, height: cropFrame.height)
            .position(x: cropFrame.midX, y: cropFrame.midY)
            .contentShape(Rectangle())
            .gesture(dragGesture(.interior, metrics: metrics))
            .accessibilityLabel("Crop window")
            .accessibilityValue(cropAccessibilityValue(for: rect))
            .accessibilityHint("Drag to move the crop region within the source frame")
    }

    private func handleView(
        _ handle: CropRectEditingMath.Handle,
        rect: NormalizedRect,
        metrics: CropCanvasMetrics
    ) -> some View {
        let point = metrics.viewPoint(
            for: handlePosition(handle, in: rect)
        )

        return Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .position(point)
            .gesture(dragGesture(handle, metrics: metrics))
            .accessibilityLabel(handle.accessibilityLabel)
            .accessibilityHint("Drag to resize the crop from the \(handle.accessibilityLabel)")
    }

    private func handlePosition(
        _ handle: CropRectEditingMath.Handle,
        in rect: NormalizedRect
    ) -> (x: Double, y: Double) {
        switch handle {
        case .topLeft: (rect.x, rect.y)
        case .top: (rect.x + rect.width / 2, rect.y)
        case .topRight: (rect.maxX, rect.y)
        case .right: (rect.maxX, rect.y + rect.height / 2)
        case .bottomRight: (rect.maxX, rect.maxY)
        case .bottom: (rect.x + rect.width / 2, rect.maxY)
        case .bottomLeft: (rect.x, rect.maxY)
        case .left: (rect.x, rect.y + rect.height / 2)
        case .interior: (rect.x + rect.width / 2, rect.y + rect.height / 2)
        }
    }

    private func dragGesture(
        _ handle: CropRectEditingMath.Handle,
        metrics: CropCanvasMetrics
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if gestureStart == nil {
                    gestureStart = (rect: currentRect, handle: handle)
                }
                guard let start = gestureStart, start.handle == handle else { return }

                let delta = metrics.normalizedDelta(for: value.translation)
                let updated: NormalizedRect
                if handle == .interior {
                    updated = CropRectEditingMath.move(start.rect, dx: delta.dx, dy: delta.dy)
                } else {
                    updated = CropRectEditingMath.resize(
                        start.rect,
                        from: handle,
                        dx: delta.dx,
                        dy: delta.dy,
                        aspect: isShiftPressed ? shiftLockAspect : nil
                    )
                }
                draftCropRect = updated
            }
            .onEnded { _ in
                commitDraft()
            }
    }

    private func commitDraft() {
        if let draft = draftCropRect {
            onCommit(CropPixelProcessor.isFullFrame(draft) ? nil : draft)
        }
        draftCropRect = nil
        gestureStart = nil
    }

    // MARK: toolbar

    private var editorToolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(
                systemImage: "arrow.counterclockwise",
                accessibilityLabel: "Reset crop to full frame"
            ) {
                onCommit(nil)
            }

            toolbarButton(
                systemImage: "checkmark",
                accessibilityLabel: "Finish cropping"
            ) {
                onDone()
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
    }

    private func toolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(accessibilityLabel)
    }

    private func cropAccessibilityValue(for rect: NormalizedRect) -> String {
        String(
            format: "region %.0f%% × %.0f%% at (%.0f%%, %.0f%%)",
            rect.width * 100,
            rect.height * 100,
            rect.x * 100,
            rect.y * 100
        )
    }

    private var isShiftPressed: Bool {
        NSEvent.modifierFlags.contains(.shift)
    }
}

private extension CropRectEditingMath.Handle {
    var accessibilityLabel: String {
        switch self {
        case .topLeft: "Top left crop handle"
        case .top: "Top crop handle"
        case .topRight: "Top right crop handle"
        case .right: "Right crop handle"
        case .bottomRight: "Bottom right crop handle"
        case .bottom: "Bottom crop handle"
        case .bottomLeft: "Bottom left crop handle"
        case .left: "Left crop handle"
        case .interior: "Crop window"
        }
    }
}

/// View-space geometry for the crop editor. The source frame is fitted
/// (contain, centered) inside the canvas-shaped overlay area; normalized crop
/// coordinates map onto that fitted rect. Crop coordinates count y from the
/// top (NormalizedRect convention) while SwiftUI counts from the top too —
/// no flip is needed here, unlike the pixel processor.
private struct CropCanvasMetrics {
    var viewSize: CGSize
    var sourceAspect: Double

    var isUsable: Bool {
        viewSize.width > 0 && viewSize.height > 0 && sourceAspect.isFinite && sourceAspect > 0
    }

    /// The aspect-fit rect of the uncropped source inside the overlay.
    var fittedSourceFrame: CGRect {
        let viewAspect = Double(viewSize.width / viewSize.height)
        let fittedSize: CGSize
        if sourceAspect > viewAspect {
            fittedSize = CGSize(width: viewSize.width, height: viewSize.width / CGFloat(sourceAspect))
        } else {
            fittedSize = CGSize(width: viewSize.height * CGFloat(sourceAspect), height: viewSize.height)
        }
        return CGRect(
            origin: CGPoint(
                x: (viewSize.width - fittedSize.width) / 2,
                y: (viewSize.height - fittedSize.height) / 2
            ),
            size: fittedSize
        )
    }

    func viewPoint(for normalized: (x: Double, y: Double)) -> CGPoint {
        let frame = fittedSourceFrame
        return CGPoint(
            x: frame.minX + frame.width * CGFloat(normalized.x),
            y: frame.minY + frame.height * CGFloat(normalized.y)
        )
    }

    func viewRect(for rect: NormalizedRect) -> CGRect {
        let origin = viewPoint(for: (rect.x, rect.y))
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: fittedSourceFrame.width * CGFloat(rect.width),
            height: fittedSourceFrame.height * CGFloat(rect.height)
        )
    }

    /// Converts a view-space drag translation into normalized source-space
    /// deltas (unflipped: both SwiftUI and NormalizedRect count y downward).
    func normalizedDelta(for translation: CGSize) -> (dx: Double, dy: Double) {
        let frame = fittedSourceFrame
        guard frame.width > 0, frame.height > 0 else { return (0, 0) }
        return (
            dx: Double(translation.width / frame.width),
            dy: Double(translation.height / frame.height)
        )
    }
}
