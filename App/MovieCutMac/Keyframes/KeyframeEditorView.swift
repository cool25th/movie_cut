import SwiftUI
import MovieCutCore

struct KeyframeEditorView: View {
    var clip: Clip
    var playheadTime: TimeInterval
    var selectedKeyframeId: UUID?
    var onSelect: (UUID?) -> Void
    var onChange: ([Keyframe]) -> Void

    @State private var propertyToAdd: AnimatableProperty = .opacity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Property", selection: $propertyToAdd) {
                    ForEach(AnimatableProperty.allCases, id: \.self) { property in
                        Text(property.keyframeDisplayName).tag(property)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)

                Button {
                    addKeyframe()
                } label: {
                    Image(systemName: "plus.diamond")
                }
                .help("Add keyframe")

                Button {
                    removeKeyframe()
                } label: {
                    Image(systemName: "minus.diamond")
                }
                .help("Remove keyframe")
                .disabled(clip.keyframes.isEmpty)
            }

            keyframeTimeline
                .frame(height: 64)
                .background(Color(nsColor: .separatorColor).opacity(0.12))
                .cornerRadius(6)
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
                    .stroke(property.keyframeColor.opacity(0.25), lineWidth: 1)
                }

                ForEach(sortedKeyframes) { keyframe in
                    let point = point(for: keyframe, in: proxy.size)
                    Button {
                        onSelect(keyframe.id)
                    } label: {
                        Circle()
                            .fill(keyframe.property.keyframeColor)
                            .frame(width: keyframe.id == selectedKeyframeId ? 11 : 8, height: keyframe.id == selectedKeyframeId ? 11 : 8)
                            .overlay {
                                Circle()
                                    .stroke(Color.white.opacity(keyframe.id == selectedKeyframeId ? 0.9 : 0), lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .position(point)
                }
            }
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

    private var currentSourceTime: TimeInterval {
        // Route through the canonical mapping so the keyframe playhead reports
        // the correct source offset at any rate or speed ramp (Step 3).
        if let mapping = clip.makeTimeMapping() {
            let absolute = mapping.sourceTime(forTimelineTime: playheadTime)
            let local = absolute - clip.sourceRange.start
            return min(max(0, local), clip.sourceRange.duration)
        }
        let timelineOffset = max(0, playheadTime - clip.timelineRange.start)
        let sourceOffset = timelineOffset * max(clip.playbackRate, 0.25)
        return min(max(0, sourceOffset), clip.sourceRange.duration)
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
        let duration = max(clip.sourceRange.duration, 0.1)
        let progress = min(max(keyframe.time / duration, 0), 1)
        let laneIndex = AnimatableProperty.allCases.firstIndex(of: keyframe.property) ?? 0
        let laneHeight = size.height / CGFloat(AnimatableProperty.allCases.count)
        let x = 6 + (CGFloat(progress) * max(size.width - 12, 1))
        let y = (CGFloat(laneIndex) * laneHeight) + (laneHeight / 2)
        return CGPoint(x: x, y: y)
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
}
