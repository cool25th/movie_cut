import Foundation
import Testing
@testable import MovieCutMac

/// CA-25 onboarding instrumentation: first-only timestamps in local defaults,
/// dismiss-once semantics for the welcome card, and the first-export-within-
/// 10-minutes target number. Uses an isolated defaults suite so tests never
/// touch the host app's real onboarding state.
@Suite("Onboarding metrics")
struct OnboardingMetricsTests {
    private func makeMetrics() -> OnboardingMetrics {
        let suiteName = "onboarding-metrics-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return OnboardingMetrics(defaults: defaults)
    }

    @Test("first event records, second call is a no-op")
    func firstOnlySemantics() {
        let metrics = makeMetrics()
        let first = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(metrics.record(.firstLaunch, at: first) == true, "first call records")
        #expect(metrics.record(.firstLaunch, at: first.addingTimeInterval(999)) == false, "second call is a no-op")
        #expect(metrics.timestamp(for: .firstLaunch) == first, "original timestamp survives")
    }

    @Test("minutes to first export needs both endpoints")
    func minutesToFirstExport() {
        let metrics = makeMetrics()
        metrics.record(.firstLaunch, at: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(metrics.minutesToFirstExport == nil, "no export yet → nil")

        metrics.record(.firstExport, at: Date(timeIntervalSince1970: 1_700_000_000 + 8 * 60))
        #expect(abs((metrics.minutesToFirstExport ?? -1) - 8) < 0.001, "launch +8min → 8.0 minutes")
    }

    @Test("welcome card dismissal is sticky")
    func dismissalIsSticky() {
        let metrics = makeMetrics()
        #expect(metrics.isDismissed == false)
        metrics.isDismissed = true
        #expect(metrics.isDismissed == true)
    }

    @Test("summary names recorded events and stays empty-safe")
    func summaryLines() {
        let metrics = makeMetrics()
        #expect(metrics.summary.contains("no events"))

        metrics.record(.sampleOpened, at: Date(timeIntervalSince1970: 1_700_000_000))
        metrics.record(.firstLaunch, at: Date(timeIntervalSince1970: 1_700_000_000))
        metrics.record(.firstExport, at: Date(timeIntervalSince1970: 1_700_000_060))
        let summary = metrics.summary
        #expect(summary.contains("sampleOpened"))
        #expect(summary.contains("minutesToFirstExport=1.0"))
    }
}
