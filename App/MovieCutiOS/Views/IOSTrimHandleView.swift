#if os(iOS)
import MovieCutCore
import SwiftUI

struct IOSTrimHandleView: View {
    @Bindable var viewModel: IOSEditorViewModel
    var clip: Clip
    var clipWidth: CGFloat

    @State private var dragOffset: CGFloat = 0
    @State private var isDraggingLeft = false
    @State private var isDraggingRight = false

    private let handleWidth: CGFloat = 20
    private let handleColor: Color = .yellow

    var body: some View {
        ZStack(alignment: .leading) {
            // Trim area indicator
            Color.clear

            // Left handle
            leftHandle

            // Right handle
            rightHandle

            // Duration overlay while dragging
            if isDraggingLeft || isDraggingRight {
                durationOverlay
            }
        }
        .frame(width: clipWidth, height: 64)
    }

    private var leftHandle: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(handleColor.opacity(isDraggingLeft ? 0.9 : 0.5))
            .frame(width: handleWidth, height: 64)
            .overlay {
                Image(systemName: "chevron.compact.right")
                    .font(.caption2)
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingLeft = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        isDraggingLeft = false
                        let timeDelta = Double(value.translation.width) / 38.0
                        let newStart = max(0, clip.timelineRange.start + timeDelta)
                        let newDuration = max(0.5, clip.timelineRange.duration - timeDelta)
                        Task {
                            await viewModel.trimClip(
                                clipId: clip.id,
                                newStart: newStart,
                                newDuration: newDuration
                            )
                        }
                        dragOffset = 0
                    }
            )
    }

    private var rightHandle: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(handleColor.opacity(isDraggingRight ? 0.9 : 0.5))
            .frame(width: handleWidth, height: 64)
            .overlay {
                Image(systemName: "chevron.compact.left")
                    .font(.caption2)
                    .foregroundStyle(.black)
            }
            .contentShape(Rectangle())
            .offset(x: clipWidth - handleWidth)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingRight = true
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        isDraggingRight = false
                        let timeDelta = Double(value.translation.width) / 38.0
                        let newDuration = max(0.5, clip.timelineRange.duration + timeDelta)
                        Task {
                            await viewModel.trimClip(
                                clipId: clip.id,
                                newStart: clip.timelineRange.start,
                                newDuration: newDuration
                            )
                        }
                        dragOffset = 0
                    }
            )
    }

    private var durationOverlay: some View {
        let currentDuration: Double
        if isDraggingLeft {
            let timeDelta = Double(dragOffset) / 38.0
            currentDuration = max(0.5, clip.timelineRange.duration - timeDelta)
        } else {
            let timeDelta = Double(dragOffset) / 38.0
            currentDuration = max(0.5, clip.timelineRange.duration + timeDelta)
        }

        return Text(String(format: "%.1fs", currentDuration))
            .font(.caption.monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
