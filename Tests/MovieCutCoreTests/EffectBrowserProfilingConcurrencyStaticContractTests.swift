import Foundation
import Testing

/// G-28 regression contract: opening the effect browser must not synchronously
/// benchmark every built-in effect on the SwiftUI/MainActor path.
@Suite("G-28 Effect Browser Profiling Concurrency StaticContract")
struct EffectBrowserProfilingConcurrencyStaticContractTests {
    private func source(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    private func section(in source: String, from start: String, to end: String) throws -> String {
        guard let startRange = source.range(of: start) else {
            throw EffectBrowserProfilingConcurrencyStaticContractError.missingMarker(start)
        }
        guard let endRange = source.range(of: end, range: startRange.upperBound..<source.endIndex) else {
            throw EffectBrowserProfilingConcurrencyStaticContractError.missingMarker(end)
        }
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

    @Test("effect cost measurement runs in a detached utility task")
    func effectCostMeasurementRunsOffMainActor() throws {
        let browser = try source("App/MovieCutMac/Inspector/EffectBrowserView.swift")

        #expect(browser.contains(".task { await loadProfiles() }"))
        #expect(browser.contains("private func loadProfiles() async"))

        let detachedMeasurement = try section(
            in: browser,
            from: "let all = await Task.detached(priority: .utility)",
            to: "        }.value"
        )
        #expect(detachedMeasurement.contains("EffectCostProfiler.measureAllBuiltIns(iterations: 3)"))
    }

    @Test("profile state is committed after detached measurement returns")
    func profileStateCommitStaysOutsideDetachedWork() throws {
        let browser = try source("App/MovieCutMac/Inspector/EffectBrowserView.swift")
        let loadProfiles = try section(
            in: browser,
            from: "private func loadProfiles() async",
            to: "    private func displayName"
        )

        #expect(loadProfiles.contains("guard !Task.isCancelled else { return }"))
        #expect(loadProfiles.contains("profiles = map"))

        let detachedMeasurement = try section(
            in: loadProfiles,
            from: "Task.detached(priority: .utility)",
            to: "        }.value"
        )
        #expect(!detachedMeasurement.contains("profiles ="))
    }
}

private enum EffectBrowserProfilingConcurrencyStaticContractError: Error {
    case missingMarker(String)
}
