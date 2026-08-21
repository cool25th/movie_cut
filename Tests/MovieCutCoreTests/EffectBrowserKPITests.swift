import Foundation
import Testing
@testable import MovieCutCore

/// G-28 — the browser KPI measurement model.
@Suite("Effect Browser KPI (G-28)")
struct EffectBrowserKPITests {
    @Test("search success rate: searches that lead to apply")
    func searchSuccessRate() {
        var kpi = EffectBrowserKPI()
        kpi.recordSearch()
        kpi.recordSearch()
        kpi.recordSearch()
        kpi.recordSearchLedToApply()
        kpi.recordSearchLedToApply()

        #expect(kpi.totalSearches == 3)
        #expect(abs(kpi.searchSuccessRate - 2.0 / 3.0) < 0.001)
    }

    @Test("reuse rate: re-applies over total applies")
    func reuseRate() {
        var kpi = EffectBrowserKPI()
        kpi.recordApply(isReApply: false)
        kpi.recordApply(isReApply: true)
        kpi.recordApply(isReApply: true)
        kpi.recordApply(isReApply: false)

        #expect(kpi.totalApplies == 4)
        #expect(abs(kpi.reuseRate - 0.5) < 0.001)
    }

    @Test("empty KPI is safe (zero rates, not NaN)")
    func emptySafe() {
        let kpi = EffectBrowserKPI()
        #expect(kpi.searchSuccessRate == 0)
        #expect(kpi.reuseRate == 0)
        #expect(!kpi.meetsTargets())
    }

    @Test("meets targets when both rates are high enough")
    func meetsTargets() {
        var kpi = EffectBrowserKPI()
        // 80% search success.
        kpi.recordSearch(); kpi.recordSearchLedToApply()
        kpi.recordSearch(); kpi.recordSearchLedToApply()
        kpi.recordSearch(); kpi.recordSearchLedToApply()
        kpi.recordSearch(); kpi.recordSearchLedToApply()
        kpi.recordSearch()  // one miss
        // 50% reuse.
        kpi.recordApply(isReApply: true)
        kpi.recordApply(isReApply: false)

        #expect(abs(kpi.searchSuccessRate - 0.8) < 0.001)
        #expect(abs(kpi.reuseRate - 0.5) < 0.001)
        #expect(kpi.meetsTargets(minSearchSuccess: 0.6, minReuse: 0.2))
    }

    @Test("Codable round-trip")
    func codable() throws {
        var kpi = EffectBrowserKPI()
        kpi.recordSearch()
        kpi.recordSearchLedToApply()
        kpi.recordApply(isReApply: true)
        let data = try JSONEncoder().encode(kpi)
        let decoded = try JSONDecoder().decode(EffectBrowserKPI.self, from: data)
        #expect(decoded == kpi)
    }

}

