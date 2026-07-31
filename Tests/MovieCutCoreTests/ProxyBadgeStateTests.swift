import Foundation
import MovieCutCore
import Testing

/// Behavioral tests for the timeline proxy badge decision (R5 / benchmark B-I7).
///
/// The badge answers two questions at once — "does a proxy exist for this clip"
/// and "is that proxy what preview is playing" — because MovieCut splits proxy
/// generation from proxy consumption while CapCut's Proxy Mode does not.
@Suite("ProxyBadgeState")
struct ProxyBadgeStateTests {
    private let ready = ProxyInfo(
        proxyURL: URL(fileURLWithPath: "/tmp/asset-proxy.mp4"),
        resolution: CGSize(width: 960, height: 540)
    )

    @Test("no proxy metadata shows no badge")
    func noProxyNoBadge() {
        #expect(ProxyBadgeState.resolve(proxy: nil, useProxyPlayback: false) == nil)
        // The setting being on must not conjure a badge for an asset that has
        // no proxy file — otherwise every clip would light up the moment the
        // user ticked the checkbox.
        #expect(ProxyBadgeState.resolve(proxy: nil, useProxyPlayback: true) == nil)
    }

    @Test("proxy metadata without a URL counts as no proxy")
    func emptyProxyInfoNoBadge() {
        // ProxyInfo exists as a value before generation writes a file, so the
        // URL — not the struct — is what makes a proxy real.
        let pending = ProxyInfo(proxyURL: nil, resolution: CGSize(width: 960, height: 540))
        #expect(ProxyBadgeState.resolve(proxy: pending, useProxyPlayback: true) == nil)
        #expect(ProxyBadgeState.resolve(proxy: pending, useProxyPlayback: false) == nil)
    }

    @Test("a ready proxy shows idle while proxy playback is off")
    func readyProxyIdleWhenPlaybackOff() {
        // B-I7's literal requirement: the badge appears once generation
        // completes, regardless of whether it is being consumed yet.
        #expect(ProxyBadgeState.resolve(proxy: ready, useProxyPlayback: false) == .idle)
    }

    @Test("a ready proxy shows active while proxy playback is on")
    func readyProxyActiveWhenPlaybackOn() {
        #expect(ProxyBadgeState.resolve(proxy: ready, useProxyPlayback: true) == .active)
    }

    @Test("toggling proxy playback flips state without changing badge visibility")
    func togglingPlaybackKeepsBadgeVisible() {
        // The badge must not appear and disappear as the setting is toggled —
        // only its meaning changes. This is what lets a user see that a proxy
        // exists but is not in use, which is the state that would otherwise be
        // invisible.
        let off = ProxyBadgeState.resolve(proxy: ready, useProxyPlayback: false)
        let on = ProxyBadgeState.resolve(proxy: ready, useProxyPlayback: true)
        #expect(off != nil)
        #expect(on != nil)
        #expect(off != on)
    }
}

/// Requirement 5.4 — quality-degradation cause display priority.
///
/// The badge must show a SINGLE cause (the highest-priority active one), while
/// every simultaneously-active cause is reported in the accessibility label /
/// tooltip. This suite pins the priority table and the multi-cause aggregation
/// through the pure `ProxyBadgeState.resolve(...previewQuality:)` entry point,
/// with no GUI or device involvement.
@Suite("ProxyBadgeState cause priority")
struct ProxyBadgeCausePriorityTests {
    private let ready = ProxyInfo(
        proxyURL: URL(fileURLWithPath: "/tmp/asset-proxy.mp4"),
        resolution: CGSize(width: 960, height: 540)
    )

    // MARK: - Single-cause cases (baseline priority)

    @Test("Only manual preview quality reduced -> previewQualityReduced, single cause")
    func onlyPreviewQualityReduced() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: false, autoDowngraded: false, previewQuality: .half
        )
        #expect(display.primaryState == .previewQualityReduced)
        #expect(display.activeCauses == [.manualPreviewQuality])
    }

    @Test("Only manual proxy -> active, single cause")
    func onlyManualProxy() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: true, autoDowngraded: false, previewQuality: .full
        )
        #expect(display.primaryState == .active)
        #expect(display.activeCauses == [.manualProxy])
    }

    @Test("Only thermal downgrade -> thermalActive, single cause")
    func onlyThermalDowngrade() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: false, autoDowngraded: true, previewQuality: .full
        )
        #expect(display.primaryState == .thermalActive)
        #expect(display.activeCauses == [.thermalDowngrade])
    }

    @Test("Nothing active but proxy ready -> idle hint, no degradation causes")
    func nothingActiveIdleHint() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: false, autoDowngraded: false, previewQuality: .full
        )
        #expect(display.primaryState == .idle)
        #expect(display.activeCauses == [])
    }

    @Test("No proxy and full quality -> no badge at all")
    func noProxyFullQualityNoBadge() {
        let display = ProxyBadgeState.resolve(
            proxy: nil, useProxyPlayback: false, autoDowngraded: false, previewQuality: .full
        )
        #expect(display.primaryState == nil)
        #expect(display.activeCauses == [])
    }

    // MARK: - Combination cases (priority resolution + full cause list)

    @Test("Manual proxy + preview quality: proxy wins, both causes reported")
    func proxyBeatsPreviewQuality() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: true, autoDowngraded: false, previewQuality: .half
        )
        // Badge shows the single higher-priority cause (manual proxy).
        #expect(display.primaryState == .active)
        // Accessibility label reports BOTH causes, priority-ordered.
        #expect(display.activeCauses == [.manualProxy, .manualPreviewQuality])
    }

    @Test("Thermal downgrade + preview quality: thermal wins, both causes reported")
    func thermalBeatsPreviewQuality() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: false, autoDowngraded: true, previewQuality: .quarter
        )
        #expect(display.primaryState == .thermalActive)
        #expect(display.activeCauses == [.thermalDowngrade, .manualPreviewQuality])
    }

    @Test("Thermal downgrade + manual proxy: thermal wins, both causes reported")
    func thermalBeatsManualProxy() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: true, autoDowngraded: true, previewQuality: .full
        )
        #expect(display.primaryState == .thermalActive)
        #expect(display.activeCauses == [.thermalDowngrade, .manualProxy])
    }

    @Test("All three causes active: thermal wins, all causes reported in order")
    func allThreeCausesThermalWins() {
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: true, autoDowngraded: true, previewQuality: .half
        )
        // The badge draws exactly one glyph — the highest-priority cause.
        #expect(display.primaryState == .thermalActive)
        // The accessibility label / tooltip carries every active cause, in the
        // canonical priority order, regardless of how inputs were supplied.
        #expect(display.activeCauses == [.thermalDowngrade, .manualProxy, .manualPreviewQuality])
    }

    @Test("Cause list order follows canonical priority, not input order")
    func causeListOrderIsCanonical() {
        // Supply the inputs in a scrambled spirit (all active): the result must
        // still be thermal > proxy > preview quality.
        let display = ProxyBadgeState.resolve(
            proxy: ready, useProxyPlayback: true, autoDowngraded: true, previewQuality: .quarter
        )
        #expect(display.activeCauses.first == .thermalDowngrade)
        #expect(display.activeCauses.last == .manualPreviewQuality)
    }

    // MARK: - Preview quality is independent of proxy existence

    @Test("Preview quality reduction shows a badge even with no proxy file")
    func previewQualityIndependentOfProxy() {
        // The performance-priority dial must work on projects that never
        // generated a proxy. This is the key difference from proxy-derived
        // causes, which all require a proxy file.
        let display = ProxyBadgeState.resolve(
            proxy: nil, useProxyPlayback: false, autoDowngraded: false, previewQuality: .half
        )
        #expect(display.primaryState == .previewQualityReduced)
        #expect(display.activeCauses == [.manualPreviewQuality])
    }

    @Test("Preview quality reduction with a thermal downgrade and no proxy still reports both")
    func previewQualityWithThermalNoProxy() {
        // Even when thermal fired but no proxy file exists yet, the preview
        // quality cause keeps the badge meaningful and both are reported.
        let display = ProxyBadgeState.resolve(
            proxy: nil, useProxyPlayback: false, autoDowngraded: true, previewQuality: .half
        )
        #expect(display.primaryState == .thermalActive)
        #expect(display.activeCauses == [.thermalDowngrade, .manualPreviewQuality])
    }

    // MARK: - The badge never stacks

    @Test("The primary state is always exactly one value, never a stack")
    func primaryStateIsAlwaysSingle() {
        // Across every input combination the badge carries one state; the
        // multi-cause information lives only in activeCauses.
        let combos: [(Bool, Bool, PreviewQuality)] = [
            (false, false, .full), (true, false, .full), (false, true, .full),
            (false, false, .half), (true, true, .quarter), (true, false, .half)
        ]
        for (useProxy, autoDown, quality) in combos {
            let display = ProxyBadgeState.resolve(
                proxy: ready, useProxyPlayback: useProxy,
                autoDowngraded: autoDown, previewQuality: quality
            )
            // primaryState is a single optional enum value by construction; this
            // asserts it is a known single case (never an aggregate).
            if let state = display.primaryState {
                #expect(ProxyBadgeState.allCases.contains(state), "primary state must be a single valid case")
            }
        }
    }
}
