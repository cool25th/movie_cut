import AppKit
import SwiftUI

/// Captures ⌘+scroll-wheel over the timeline to drive zoom (S9).
///
/// SwiftUI's `ScrollView` does not expose the raw scroll-wheel event, so this
/// transparent `NSView` overlay intercepts `scrollWheel`. When the ⌘ modifier
/// is held, it converts the vertical deltaY into a zoom delta and forwards it
/// to `onZoom`; otherwise it returns `super` so normal panning works.
struct TimelineScrollZoomReader: NSViewRepresentable {
    /// Called with the zoom delta (positive = zoom in) only on ⌘+scroll.
    let onZoom: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelCapturingView {
        let view = ScrollWheelCapturingView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: ScrollWheelCapturingView, context: Context) {
        nsView.onZoom = onZoom
    }
}

/// Transparent view that only reacts to scroll-wheel events with ⌘ held.
final class ScrollWheelCapturingView: NSView {
    var onZoom: ((CGFloat) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Transparent and non-opaque so it overlays the SwiftUI content.
        layer = NSLayer()
        layer?.backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Only ⌘+scroll zooms; let everything else pan normally.
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        // Trackpad scroll momentum can be noisy; guard against tiny deltas.
        let delta = event.deltaY
        guard abs(delta) > 0.01 else { return }
        onZoom?(delta)
    }
}

/// SwiftUI bridge: sets the NSCursor over a view (S9 blade-tool feedback).
extension View {
    /// When `cursor` is non-nil, the system uses that cursor while the pointer
    /// is over the view; nil restores the default.
    func cursor(_ cursor: NSCursor?) -> some View {
        background(CursorOverlay(cursor: cursor))
    }
}

private struct CursorOverlay: NSViewRepresentable {
    let cursor: NSCursor?

    func makeNSView(context: Context) -> CursorTrackingView {
        CursorTrackingView()
    }

    func updateNSView(_ nsView: CursorTrackingView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorTrackingView: NSView {
    var cursor: NSCursor? {
        didSet { updateCursor() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Keep a tracking area so cursor updates fire on enter/exit.
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        if let cursor {
            addCursorRect(bounds, cursor: cursor)
        } else {
            super.resetCursorRects()
        }
    }

    private func updateCursor() {
        if NSMouseInRect(NSEvent.mouseLocation, window?.frame ?? .zero, false) {
            cursor?.set()
        }
    }

    override func mouseEntered(with event: NSEvent) { cursor?.set() }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }
}

private final class NSLayer: CALayer {}
