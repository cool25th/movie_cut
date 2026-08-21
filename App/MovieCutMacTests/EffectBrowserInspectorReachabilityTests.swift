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
}
