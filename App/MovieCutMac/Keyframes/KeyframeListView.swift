import SwiftUI
import MovieCutCore

struct KeyframeListView: View {
    var clip: Clip
    var selectedKeyframeId: UUID?
    var onSelect: (UUID?) -> Void
    var onChange: ([Keyframe]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if clip.keyframes.isEmpty {
                Text("No keyframes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(AnimatableProperty.allCases, id: \.self) { property in
                    let keyframes = keyframes(for: property)
                    if !keyframes.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(property.keyframeDisplayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(property.keyframeColor)

                            ForEach(keyframes) { keyframe in
                                keyframeRow(keyframe)
                                // When the selected keyframe uses a custom curve,
                                // reveal the bezier handle editor beneath its row.
                                if keyframe.id == selectedKeyframeId, keyframe.interpolation == .custom {
                                    BezierCurveEditorView(
                                        control: keyframe.customCurve ?? CubicBezierControl(x1: 0.42, y1: 0, x2: 0.58, y2: 1),
                                        property: keyframe.property,
                                        onChange: { newCurve in
                                            setCustomCurve(keyframeId: keyframe.id, curve: newCurve)
                                        }
                                    )
                                    .padding(.leading, 14)  // align under the row, past the selection dot
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func keyframeRow(_ keyframe: Keyframe) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelect(keyframe.id)
            } label: {
                Circle()
                    .fill(keyframe.property.keyframeColor)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(keyframe.id == selectedKeyframeId ? 0.8 : 0), lineWidth: 1.5)
                    }
            }
            .buttonStyle(.plain)

            TextField("Time", value: doubleBinding(for: keyframe.id, keyPath: \.time), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 52)

            TextField("Value", value: doubleBinding(for: keyframe.id, keyPath: \.value), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)

            Picker("Interpolation", selection: interpolationBinding(for: keyframe.id)) {
                ForEach(InterpolationMode.allCases, id: \.self) { mode in
                    Text(mode.keyframeDisplayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 92)

            Button {
                deleteKeyframe(keyframe.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    private func keyframes(for property: AnimatableProperty) -> [Keyframe] {
        clip.keyframes
            .filter { $0.property == property }
            .sorted { $0.time < $1.time }
    }

    private func doubleBinding(for id: UUID, keyPath: WritableKeyPath<Keyframe, Double>) -> Binding<Double> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?[keyPath: keyPath] ?? 0
            },
            set: { newValue in
                var keyframes = clip.keyframes
                guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
                keyframes[index][keyPath: keyPath] = keyPath == \.time ? max(0, newValue) : newValue
                onChange(keyframes)
            }
        )
    }

    private func interpolationBinding(for id: UUID) -> Binding<InterpolationMode> {
        Binding(
            get: {
                clip.keyframes.first { $0.id == id }?.interpolation ?? .linear
            },
            set: { mode in
                var keyframes = clip.keyframes
                guard let index = keyframes.firstIndex(where: { $0.id == id }) else { return }
                keyframes[index].interpolation = mode
                // Seed a sensible default curve when switching to .custom so the
                // editor has something to render and drag; otherwise leave nil.
                if mode == .custom, keyframes[index].customCurve == nil {
                    keyframes[index].customCurve = CubicBezierControl(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
                }
                onChange(keyframes)
            }
        )
    }

    /// Writes a new bezier control to the selected keyframe via the undo-able
    /// `onChange` path (same route as every other keyframe edit).
    private func setCustomCurve(keyframeId: UUID, curve: CubicBezierControl) {
        var keyframes = clip.keyframes
        guard let index = keyframes.firstIndex(where: { $0.id == keyframeId }) else { return }
        keyframes[index].customCurve = curve
        onChange(keyframes)
    }

    private func deleteKeyframe(_ id: UUID) {
        onChange(clip.keyframes.filter { $0.id != id })
        if selectedKeyframeId == id {
            onSelect(nil)
        }
    }
}
