import AppKit
import CoreImage
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

private final class RenderPermitTestState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peakActive = 0
    private var labels: [String] = []

    func enter() {
        lock.lock()
        defer { lock.unlock() }
        active += 1
        peakActive = max(peakActive, active)
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        active -= 1
    }

    func record(_ label: String) {
        lock.lock()
        defer { lock.unlock() }
        labels.append(label)
    }

    var maxActive: Int {
        lock.lock()
        defer { lock.unlock() }
        return peakActive
    }

    var recordedLabels: [String] {
        lock.lock()
        defer { lock.unlock() }
        return labels
    }
}

@Suite("Effect Browser Inspector Reachability", .serialized)
struct EffectBrowserInspectorReachabilityTests {
    @Test("effect browser is reachable from the visible Adjustment inspector")
    func adjustmentModeShowsBrowser() {
        #expect(InspectorEffectsMode.adjustment.showsEffectBrowser)
        #expect(InspectorEffectsMode.full.showsEffectBrowser)
        #expect(!InspectorEffectsMode.mask.showsEffectBrowser)
        #expect(!InspectorEffectsMode.animation.showsEffectBrowser)
    }

    @Test("browser renderer emits a bounded surface with project-canvas aspect")
    func rendererUsesCanvasAspect() throws {
        let context = CIContext(options: RenderColorConfiguration.contextOptions)
        let source = CIImage(color: CIColor(red: 0.8, green: 0.2, blue: 0.1))
            .cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        guard let sourceData = context.pngRepresentation(
            of: source,
            format: .RGBA8,
            colorSpace: RenderColorConfiguration.destinationColorSpace,
            options: [:]
        ) else {
            Issue.record("failed to create source PNG")
            return
        }

        let clip = Clip(
            kind: .image,
            sourceRange: TimeRange(start: 0, duration: 1),
            timelineRange: TimeRange(start: 0, duration: 1),
            cropRect: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        )
        let outputData = EffectBrowserPreviewRenderer.render(
            sourceData: sourceData,
            clip: clip,
            effects: [Effect(type: .saturation, parameters: ["amount": 1.2])],
            canvasSize: CGSize(width: 1080, height: 1920)
        )
        let bitmap = outputData.flatMap(NSBitmapImageRep.init(data:))

        #expect(bitmap?.pixelsWide == 180)
        #expect(bitmap?.pixelsHigh == 320)
    }

    @Test("preview render permit serializes work across independent workers")
    func renderPermitIsProcessWideSingleFlight() {
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "g28.render-permit-test", attributes: .concurrent)
        let state = RenderPermitTestState()

        for _ in 0..<2 {
            group.enter()
            queue.async {
                EffectBrowserPreviewRenderer.withRenderPermit {
                    state.enter()

                    Thread.sleep(forTimeInterval: 0.05)

                    state.leave()
                }
                group.leave()
            }
        }

        #expect(group.wait(timeout: .now() + 2) == .success)
        #expect(state.maxActive == 1)
    }

    @Test("superseded preview waiter is dropped before render permit")
    func latestPreviewCoalescesQueuedWaiters() {
        let queue = DispatchQueue(label: "g28.latest-render-permit-test", attributes: .concurrent)
        let holderStarted = DispatchSemaphore(value: 0)
        let releaseHolder = DispatchSemaphore(value: 0)
        let staleFinished = DispatchSemaphore(value: 0)
        let latestFinished = DispatchSemaphore(value: 0)
        let state = RenderPermitTestState()

        queue.async {
            EffectBrowserPreviewRenderer.withRenderPermit {
                holderStarted.signal()
                _ = releaseHolder.wait(timeout: .now() + 2)
            }
        }

        #expect(holderStarted.wait(timeout: .now() + 1) == .success)

        // Reserve tokens before scheduling the workers. This models the
        // product queue, where the latest request is known before detached
        // task scheduling can reorder which worker starts first.
        let stalePermit = EffectBrowserPreviewRenderer.reserveLatestRenderPermit()
        let latestPermit = EffectBrowserPreviewRenderer.reserveLatestRenderPermit()

        queue.async {
            _ = EffectBrowserPreviewRenderer.withLatestRenderPermit(stalePermit) {
                state.record("stale")
                return true
            }
            staleFinished.signal()
        }

        queue.async {
            _ = EffectBrowserPreviewRenderer.withLatestRenderPermit(latestPermit) {
                state.record("latest")
                return true
            }
            latestFinished.signal()
        }

        #expect(staleFinished.wait(timeout: .now() + 1) == .success)
        releaseHolder.signal()
        #expect(latestFinished.wait(timeout: .now() + 1) == .success)
        #expect(state.recordedLabels == ["latest"])
    }
}
