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
