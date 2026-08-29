import MovieCutCore
import SwiftUI

/// Tone-curve editor (G-02 Inc 6): a draggable control-point curve per
/// channel (master / red / green / blue). Points live on the clip's
/// `ColorGrade.curves` and render through the shared `CurveEvaluator` LUT
/// chain, so preview and export match by construction (the same
/// `ColorGradePixelProcessor` cube drives both engines).
///
/// Commit discipline (undo transaction): identical to the HSL band editor
/// (G-02 Inc 5) — a drag mutates local draft state for responsiveness and
/// commits the whole `ColorCurves` once, when the gesture ends: one undo
/// step per gesture instead of one per tick. Committing `nil` when every
/// channel is identity keeps project JSON byte-stable for ungraded clips.
struct ColorCurvesView: View {
    /// Committed curve values from the clip's current color grade.
    let curves: ColorCurves
    /// Commits the full curve set (nil when every channel is identity).
    let onCommit: (_ curves: ColorCurves?) -> Void

    enum Channel: String, CaseIterable, Identifiable {
        case master, red, green, blue

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .master: "Master"
            case .red: "Red"
            case .green: "Green"
            case .blue: "Blue"
            }
        }

        var tint: Color {
            switch self {
            case .master: .primary
            case .red: Color(red: 1, green: 0, blue: 0)
            case .green: Color(red: 0, green: 0.8, blue: 0)
            case .blue: Color(red: 0, green: 0.4, blue: 1)
            }
        }
    }

    @State private var selectedChannel: Channel = .master
    @State private var draft: ColorCurves
    /// Index of the interior point being dragged (nil when idle).
    @State private var dragIndex: Int?

    init(curves: ColorCurves?, onCommit: @escaping (_ curves: ColorCurves?) -> Void) {
        self.curves = curves ?? .identity
        self.onCommit = onCommit
        _draft = State(initialValue: curves ?? .identity)
    }

    private var channelPoints: [CurvePoint] {
        switch selectedChannel {
        case .master: draft.master
        case .red: draft.red
        case .green: draft.green
        case .blue: draft.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tone Curves")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Button("Add Point") { addPoint() }
                    .controlSize(.small)
                Button("Remove Point") { removePoint() }
                    .controlSize(.small)
                    .disabled(interiorCount == 0)
                Button("Reset Channel") { resetChannel() }
                    .controlSize(.small)
            }

            HStack(spacing: 8) {
                ForEach(Channel.allCases) { channel in
                    channelButton(channel)
                }
            }

            curveCanvas
                .frame(height: 160)
                .aspectRatio(1, contentMode: .fit)
        }
        .onChange(of: curves) { newCurves in
            draft = newCurves ?? .identity
        }
    }

    private func channelButton(_ channel: Channel) -> some View {
        let isIdentity = points(for: channel) == ColorCurves.identityPoints
        let isSelected = channel == selectedChannel
        return Text(channel.displayName)
            .font(.caption2.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(channel.tint)
            .opacity(isSelected || !isIdentity ? 1 : 0.45)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background {
                if isSelected {
                    Capsule().fill(.quaternary)
                }
            }
            .onTapGesture { selectedChannel = channel }
            .accessibilityElement()
            .accessibilityLabel("\(channel.displayName) curve")
            .accessibilityValue(
                isIdentity ? "Identity" : "\(points(for: channel).count - 2) control points"
            )
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Edit this channel's tone curve")
    }

    /// The draggable curve surface. Endpoints (0,0)/(1,1) are locked — the
    /// `ColorCurves` normalizer pins them — and interior points drag with x
    /// clamped between their neighbors so the point sequence stays monotone.
    private var curveCanvas: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                // Grid: quarters + the identity diagonal reference.
                Path { path in
                    for fraction in [0.25, 0.5, 0.75] {
                        path.move(to: CGPoint(x: size.width * fraction, y: 0))
                        path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                        path.move(to: CGPoint(x: 0, y: size.height * fraction))
                        path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                    }
                }
                .stroke(.quaternary, lineWidth: 0.5)

                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                }
                .stroke(.quaternary, style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                // The curve, sampled through the SAME evaluator the renderer
                // consumes — what you drag is what renders.
                Path { path in
                    let samples = 64
                    for index in 0...samples {
                        let x = Double(index) / Double(samples)
                        let y = CurveEvaluator.evaluate(points: channelPoints, at: x)
                        let point = CGPoint(x: size.width * x, y: size.height * (1 - y))
                        if index == 0 {
                            path.move(to: point)
                        } else {
                            path.addLine(to: point)
                        }
                    }
                }
                .stroke(selectedChannel.tint, lineWidth: 2)

                ForEach(Array(channelPoints.enumerated()), id: \.offset) { index, point in
                    let position = CGPoint(
                        x: size.width * point.x,
                        y: size.height * (1 - point.y)
                    )
                    let isEndpoint = index == 0 || index == channelPoints.count - 1
                    Circle()
                        .fill(isEndpoint ? Color.clear : selectedChannel.tint)
                        .overlay {
                            if isEndpoint {
                                Circle().strokeBorder(selectedChannel.tint, lineWidth: 1)
                            }
                        }
                        .frame(width: isEndpoint ? 7 : 11, height: isEndpoint ? 7 : 11)
                        .contentShape(Circle().inset(by: -6))
                        .position(position)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard dragIndex != nil || hitTestInterior(value.startLocation, in: size) != nil else {
                            return
                        }
                        if dragIndex == nil {
                            dragIndex = hitTestInterior(value.startLocation, in: size)
                        }
                        drag(to: value.location, in: size)
                    }
                    .onEnded { _ in
                        if dragIndex != nil {
                            dragIndex = nil
                            commit()
                        }
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Tone curve canvas, \(selectedChannel.displayName)")
        .accessibilityValue(
            channelPoints == ColorCurves.identityPoints
                ? "Identity"
                : "\(channelPoints.count - 2) control points"
        )
        .accessibilityHint("Drag control points to adjust the curve; use Add Point and Remove Point for accessibility editing")
    }

    /// Nearest interior point within the grab radius, if any.
    private func hitTestInterior(_ location: CGPoint, in size: CGSize) -> Int? {
        let points = channelPoints
        guard points.count > 2 else { return nil }
        let radius: CGFloat = 16
        var best: (index: Int, distance: CGFloat)?
        for index in points.indices where index != 0 && index != points.count - 1 {
            let point = points[index]
            let center = CGPoint(x: size.width * point.x, y: size.height * (1 - point.y))
            let distance = hypot(location.x - center.x, location.y - center.y)
            if distance <= radius && (best == nil || distance < best!.distance) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// Moves the dragged point, clamping x between its neighbors so the
    /// sequence stays monotone in x (the evaluator's normalization contract).
    private func drag(to location: CGPoint, in size: CGSize) {
        guard let index = dragIndex else { return }
        let points = channelPoints
        let lowerBound = index > 0 ? points[index - 1].x + 0.01 : 0
        let upperBound = index < points.count - 1 ? points[index + 1].x - 0.01 : 1
        guard lowerBound <= upperBound else { return }
        let x = min(max(Double(location.x / max(size.width, 1)), lowerBound), upperBound)
        let y = min(max(1 - Double(location.y / max(size.height, 1)), 0), 1)
        var updated = points
        updated[index] = CurvePoint(x: x, y: y)
        assign(updated, to: selectedChannel)
    }

    /// Adds a control point at the midpoint of the widest x gap of the
    /// selected channel — deterministic (unlike free-canvas taps) and
    /// reachable without a pointer drag.
    private func addPoint() {
        var points = channelPoints
        guard points.count >= 2 else { return }
        var widest = (index: 0, gap: 0.0)
        for index in points.indices.dropLast() {
            let gap = points[index + 1].x - points[index].x
            if gap > widest.gap {
                widest = (index, gap)
            }
        }
        let left = points[widest.index]
        let right = points[widest.index + 1]
        let inserted = CurvePoint(
            x: (left.x + right.x) / 2,
            y: CurveEvaluator.evaluate(
                points: points,
                at: (left.x + right.x) / 2
            )
        )
        points.append(inserted)
        points.sort { $0.x < $1.x }
        assign(points, to: selectedChannel)
        commit()
    }

    private func removePoint() {
        var points = channelPoints
        guard points.count > 2 else { return }
        points.remove(at: points.count - 2)
        assign(points, to: selectedChannel)
        commit()
    }

    private func resetChannel() {
        assign(ColorCurves.identityPoints, to: selectedChannel)
        commit()
    }

    private var interiorCount: Int {
        max(channelPoints.count - 2, 0)
    }

    private func commit() {
        onCommit(Self.committedValue(draft))
    }

    /// The editor's commit mapping: an all-identity curve set commits `nil`
    /// so ungraded project JSON stays byte-stable (the same contract as the
    /// HSL band editor's identity normalization).
    static func committedValue(_ draft: ColorCurves) -> ColorCurves? {
        draft.isIdentity ? nil : draft
    }

    private func points(for channel: Channel) -> [CurvePoint] {
        switch channel {
        case .master: draft.master
        case .red: draft.red
        case .green: draft.green
        case .blue: draft.blue
        }
    }

    private func assign(_ points: [CurvePoint], to channel: Channel) {
        switch channel {
        case .master: draft.master = points
        case .red: draft.red = points
        case .green: draft.green = points
        case .blue: draft.blue = points
        }
    }
}
