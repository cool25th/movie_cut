import Foundation
import Testing

/// G-28 regression contract: opening the effect browser must not synchronously
/// benchmark every built-in effect on the SwiftUI/MainActor path, and repeated
/// browser presentations must coalesce onto one process-local measurement.
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

    @Test("effect cost measurement is a detached process-wide single flight")
    func effectCostMeasurementRunsOffMainActorAndCoalesces() throws {
        let browser = try source("App/MovieCutMac/Inspector/EffectBrowserView.swift")

        #expect(browser.contains(".task { await loadProfiles() }"))
        #expect(browser.contains("private func loadProfiles() async"))
        #expect(browser.contains("private static let profileMeasurementTask = Task.detached(priority: .utility)"))

        let sharedMeasurement = try section(
            in: browser,
            from: "private static let profileMeasurementTask = Task.detached(priority: .utility)",
            to: "    @State private var searchText"
        )
        #expect(sharedMeasurement.contains("EffectCostProfiler.measureAllBuiltIns(iterations: 3)"))
    }

    @Test("browser instances await the shared task and only commit UI state after return")
    func profileStateCommitStaysOutsideDetachedWork() throws {
        let browser = try source("App/MovieCutMac/Inspector/EffectBrowserView.swift")
        let loadProfiles = try section(
            in: browser,
            from: "private func loadProfiles() async",
            to: "    private func displayName"
        )

        #expect(loadProfiles.contains("let all = await Self.profileMeasurementTask.value"))
        #expect(loadProfiles.contains("guard !Task.isCancelled else { return }"))
        #expect(loadProfiles.contains("profiles = map"))
        #expect(!loadProfiles.contains("Task.detached"))
        #expect(!loadProfiles.contains("EffectCostProfiler.measureAllBuiltIns"))
    }
}

private enum EffectBrowserProfilingConcurrencyStaticContractError: Error {
    case missingMarker(String)
}
