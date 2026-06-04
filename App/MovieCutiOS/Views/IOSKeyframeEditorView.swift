#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSKeyframeEditorView: View {
    var clip: Clip
    var playheadTime: TimeInterval
    var selectedKeyframeId: UUID?
    var onSelect: (UUID?) -> Void
    var onChange: ([Keyframe]) -> Void

    @State private var propertyToAdd: AnimatableProperty = .opacity

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Picker("Property", selection: $propertyToAdd) {
                    ForEach(AnimatableProperty.allCases, id: \.self) { property in
                        Text(property.iosKeyframeDisplayName).tag(property)
                    }
                }
                .pickerStyle(.menu)

                Spacer(minLength: 8)

                Button {
                    addKeyframe()
                } label: {
                    Image(systemName: "plus.diamond.fill")
                }
                .buttonStyle(.bordered)
                .tint(propertyToAdd.iosKeyframeColor)
                .accessibilityLabel("Add Keyframe")

                Button(role: .destructive) {
                    removeKeyframe()
                } label: {
                    Image(systemName: "minus.diamond.fill")
                }
                .buttonStyle(.bordered)
                .disabled(clip.keyframes.isEmpty)
                .accessibilityLabel("Remove Keyframe")
            }

            keyframeTimeline
                .frame(height: 88)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let selectedKeyframe {
                selectedKeyframeControls(selectedKeyframe)
            }

            IOSKeyframeListView(
                clip: clip,
                selectedKeyframeId: selectedKeyframeId,
                onSelect: onSelect,
                onChange: onChange
            )
        }
    }

    private var keyframeTimeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ForEach(AnimatableProperty.allCases, id: \.self) { property in
                    let laneIndex = AnimatableProperty.allCases.firstIndex(of: property) ?? 0
                    let laneHeight = proxy.size.height / CGFloat(AnimatableProperty.allCases.count)
                    let y = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)

                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(property.iosKeyframeColor.opacity(0.25), lineWidth: 1)
                }

                Path { path in
                    let x = xPosition(for: currentSourceTime, in: proxy.size.width)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                }
                .stroke(Color.primary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                ForEach(sortedKeyframes) { keyframe in
                    keyframePin(for: keyframe)
                        .position(point(for: keyframe, in: proxy.size))
                        .gesture(pinDragGesture(for: keyframe, in: proxy.size))
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func keyframePin(for keyframe: Keyframe) -> some View {
        let isSelected = keyframe.id == selectedKeyframeId

        return Circle()
            .fill(keyframe.property.iosKeyframeColor)
            .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
            .overlay {
                Circle()
                    .stroke(Color.white.opacity(isSelected ? 0.95 : 0), lineWidth: 2)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(keyframe.id)
            }
            .accessibilityLabel("\(keyframe.property.iosKeyframeDisplayName) Keyframe")
            .accessibilityValue("\(timeText(keyframe.time)), \(valueText(keyframe.value, for: keyframe.property))")
    }

    private func pinDragGesture(for keyframe: Keyframe, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onSelect(keyframe.id)
                updateKeyframe(keyframe.id) { editableKeyframe in
                    editableKeyframe.time = time(forX: value.location.x, in: size.width)
                }
            }
    }

    private func selectedKeyframeControls(_ keyframe: Keyframe) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(keyframe.property.iosKeyframeColor)
                    .frame(width: 10, height: 10)

                Text(keyframe.property.iosKeyframeDisplayName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(timeText(keyframe.time))  \(valueText(keyframe.value, for: keyframe.property))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            sliderRow(
                title: "Time",
                value: timeBinding(for: keyframe.id),
                range: 0...sourceDuration,
                step: 0.01,
                valueText: timeText(keyframe.time)
            )

            sliderRow(
                title: "Value",
                value: valueBinding(for: keyframe.id),
                range: valueRange(for: keyframe.property),
                step: valueStep(for: keyframe.property),
                valueText: valueText(keyframe.value, for: keyframe.property)
            )

            Picker("Interpolation", selection: interpolationBinding(for: keyframe.id)) {
                ForEach(InterpolationMode.allCases, id: \.self) { mode in
                    Text(mode.iosKeyframeDisplayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
                .frame(minHeight: 36)
        }
    }

    private var sortedKeyframes: [Keyframe] {
        clip.keyframes.sorted {
            if $0.property.rawValue == $1.property.rawValue {
                return $0.time < $1.time
            }
            return $0.property.rawValue < $1.property.rawValue
        }
    }

    private var selectedKeyframe: Keyframe? {
        guard let selectedKeyframeId else { return nil }
        return clip.keyframes.first { $0.id == selectedKeyframeId }
    }

    private var sourceDuration: Double {
        max(clip.sourceRange.duration, 0.1)
    }

    private var currentSourceTime: TimeInterval {
        let timelineOffset = max(0, playheadTime - clip.timelineRange.start)
        let sourceOffset = timelineOffset * max(clip.playbackRate, 0.25)
        return min(max(0, sourceOffset), sourceDuration)
    }

    private func addKeyframe() {
        var keyframes = clip.keyframes
        let keyframe = Keyframe(
            property: propertyToAdd,
            time: currentSourceTime,
            value: currentValue(for: propertyToAdd)
        )

        keyframes.append(keyframe)
        onSelect(keyframe.id)
        onChange(keyframes)
    }

    private func removeKeyframe() {
        var keyframes = clip.keyframes

        if let selectedKeyframeId {
            keyframes.removeAll { $0.id == selectedKeyframeId }
            onSelect(nil)
            onChange(keyframes)
            return
        }

        let time = currentSourceTime
        keyframes.removeAll {
            $0.property == propertyToAdd && abs($0.time - time) <= 0.05
        }
        onChange(keyframes)
    }

    private func point(for keyframe: Keyframe, in size: CGSize) -> CGPoint {
        let laneIndex = AnimatableProperty.allCases.firstIndex(of: keyframe.property) ?? 0
        let laneHeight = size.height / CGFloat(AnimatableProperty.allCases.count)
        let x = xPosition(for: keyframe.time, in: size.width)
        let y = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        return CGPoint(x: x, y: y)
    }

    private func xPosition(for time: TimeInterval, in width: CGFloat) -> CGFloat {
        let progress = min(max(time / sourceDuration, 0), 1)
        return 8 + (CGFloat(progress) * max(width - 16, 1))
    }

    private func time(forX x: CGFloat, in width: CGFloat) -> TimeInterval {
        let usableWidth = max(width - 16, 1)
        let progress = min(max((x - 8) / usableWidth, 0), 1)
        return TimeInterval(progress) * sourceDuration
    }

    private func currentValue(for property: AnimatableProperty) -> Double {
        switch property {
        case .positionX:
            return Double(clip.transform.position.x)
        case .positionY:
            return Double(clip.transform.position.y)
        case .scaleX:
            return Double(clip.transform.scale.width)
        case .scaleY:
            return Double(clip.transform.scale.height)
        case .rotation:
            return clip.transform.rotation
        case .opacity:
            return clip.opacity
        case .volume:
            return clip.volume
        }
    }

    private func timeBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.time ?? 0
            },
            set: { newValue in
                updateKeyframe(id) { keyframe in
                    keyframe.time = min(max(0, newValue), sourceDuration)
                }
            }
        )
    }

    private func valueBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.value ?? 0
            },
            set: { newValue in
                updateKeyframe(id) { keyframe in
                    keyframe.value = min(max(newValue, valueRange(for: keyframe.property).lowerBound), valueRange(for: keyframe.property).upperBound)
                }
            }
        )
    }

    private func interpolationBinding(for id: UUID) -> Binding<InterpolationMode> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.interpolation ?? .linear
            },
            set: { mode in
                updateKeyframe(id) { keyframe in
                    keyframe.interpolation = mode
                }
            }
        )
    }

    private func updateKeyframe(_ id: UUID, update: (inout Keyframe) -> Void) {
        var keyframes = clip.keyframes
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        update(&keyframes[index])
        onChange(keyframes)
    }

    private func valueRange(for property: AnimatableProperty) -> ClosedRange<Double> {
        switch property {
        case .positionX, .positionY:
            return -1000...1000
        case .scaleX, .scaleY:
            return 0...4
        case .rotation:
            return -180...180
        case .opacity:
            return 0...1
        case .volume:
            return 0...2
        }
    }

    private func valueStep(for property: AnimatableProperty) -> Double {
        switch property {
        case .positionX, .positionY, .rotation:
            return 1
        case .scaleX, .scaleY, .opacity, .volume:
            return 0.01
        }
    }

    private func timeText(_ time: TimeInterval) -> String {
        String(format: "%.2fs", max(0, time))
    }

    private func valueText(_ value: Double, for property: AnimatableProperty) -> String {
        switch property {
        case .positionX, .positionY, .rotation:
            return String(format: "%.0f", value)
        case .scaleX, .scaleY:
            return String(format: "%.2fx", value)
        case .opacity, .volume:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}

private struct IOSKeyframeListView: View {
    var clip: Clip
    var selectedKeyframeId: UUID?
    var onSelect: (UUID?) -> Void
    var onChange: ([Keyframe]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if clip.keyframes.isEmpty {
                Text("No keyframes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(AnimatableProperty.allCases, id: \.self) { property in
                    let keyframes = keyframes(for: property)
                    if !keyframes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(property.iosKeyframeDisplayName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(property.iosKeyframeColor)

                            ForEach(keyframes) { keyframe in
                                keyframeRow(keyframe)
                            }
                        }
                    }
                }
            }
        }
    }

    private func keyframeRow(_ keyframe: Keyframe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onSelect(keyframe.id)
                } label: {
                    Circle()
                        .fill(keyframe.property.iosKeyframeColor)
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .stroke(Color.primary.opacity(keyframe.id == selectedKeyframeId ? 0.8 : 0), lineWidth: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select Keyframe")

                Text(timeText(keyframe.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Text(valueText(keyframe.value, for: keyframe.property))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    deleteKeyframe(keyframe.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete Keyframe")
            }

            Slider(
                value: valueBinding(for: keyframe.id),
                in: valueRange(for: keyframe.property),
                step: valueStep(for: keyframe.property)
            )
            .frame(minHeight: 32)
            .accessibilityLabel("\(keyframe.property.iosKeyframeDisplayName) Value")

            Picker("Interpolation", selection: interpolationBinding(for: keyframe.id)) {
                ForEach(InterpolationMode.allCases, id: \.self) { mode in
                    Text(mode.iosKeyframeDisplayName).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(keyframe.id)
        }
    }

    private func keyframes(for property: AnimatableProperty) -> [Keyframe] {
        clip.keyframes
            .filter { $0.property == property }
            .sorted { $0.time < $1.time }
    }

    private func valueBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.value ?? 0
            },
            set: { newValue in
                updateKeyframe(id) { keyframe in
                    keyframe.value = min(max(newValue, valueRange(for: keyframe.property).lowerBound), valueRange(for: keyframe.property).upperBound)
                }
            }
        )
    }

    private func interpolationBinding(for id: UUID) -> Binding<InterpolationMode> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.interpolation ?? .linear
            },
            set: { mode in
                updateKeyframe(id) { keyframe in
                    keyframe.interpolation = mode
                }
            }
        )
    }

    private func updateKeyframe(_ id: UUID, update: (inout Keyframe) -> Void) {
        var keyframes = clip.keyframes
        guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
        update(&keyframes[index])
        onChange(keyframes)
    }

    private func deleteKeyframe(_ id: UUID) {
        onChange(clip.keyframes.filter { $0.id != id })
        if selectedKeyframeId == id {
            onSelect(nil)
        }
    }

    private func valueRange(for property: AnimatableProperty) -> ClosedRange<Double> {
        switch property {
        case .positionX, .positionY:
            return -1000...1000
        case .scaleX, .scaleY:
            return 0...4
        case .rotation:
            return -180...180
        case .opacity:
            return 0...1
        case .volume:
            return 0...2
        }
    }

    private func valueStep(for property: AnimatableProperty) -> Double {
        switch property {
        case .positionX, .positionY, .rotation:
            return 1
        case .scaleX, .scaleY, .opacity, .volume:
            return 0.01
        }
    }

    private func timeText(_ time: TimeInterval) -> String {
        String(format: "%.2fs", max(0, time))
    }

    private func valueText(_ value: Double, for property: AnimatableProperty) -> String {
        switch property {
        case .positionX, .positionY, .rotation:
            return String(format: "%.0f", value)
        case .scaleX, .scaleY:
            return String(format: "%.2fx", value)
        case .opacity, .volume:
            return "\(Int((value * 100).rounded()))%"
        }
    }
}

private extension AnimatableProperty {
    var iosKeyframeDisplayName: String {
        switch self {
        case .positionX:
            return "Position X"
        case .positionY:
            return "Position Y"
        case .scaleX:
            return "Scale X"
        case .scaleY:
            return "Scale Y"
        case .rotation:
            return "Rotation"
        case .opacity:
            return "Opacity"
        case .volume:
            return "Volume"
        }
    }

    var iosKeyframeColor: Color {
        switch self {
        case .positionX, .positionY:
            return .blue
        case .scaleX, .scaleY:
            return .purple
        case .rotation:
            return .orange
        case .opacity:
            return .teal
        case .volume:
            return .green
        }
    }
}

private extension InterpolationMode {
    var iosKeyframeDisplayName: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease In Out"
        case .hold:
            return "Hold"
        }
    }
}
#endif
