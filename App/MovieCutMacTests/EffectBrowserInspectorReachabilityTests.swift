import AppKit
import CoreImage
import Foundation
import MovieCutCore
import Testing
@testable import MovieCutMac

@Suite("Effect Browser Inspector Reachability")
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
        let stateLock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "g28.render-permit-test", attributes: .concurrent)
        var active = 0
        var maxActive = 0

        for _ in 0..<2 {
            group.enter()
            queue.async {
                EffectBrowserPreviewRenderer.withRenderPermit {
                    stateLock.lock()
                    active += 1
                    maxActive = max(maxActive, active)
                    stateLock.unlock()

                    Thread.sleep(forTimeInterval: 0.05)

                    stateLock.lock()
                    active -= 1
                    stateLock.unlock()
                }
                group.leave()
            }
        }

        #expect(group.wait(timeout: .now() + 2) == .success)
        #expect(maxActive == 1)
    }
}
