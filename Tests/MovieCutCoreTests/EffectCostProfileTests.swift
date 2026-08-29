import Foundation
import Testing
@testable import MovieCutCore

/// G-28 — the cost profile schema and the measurement pipeline.
@Suite("Effect Cost Profile (G-28)")
struct EffectCostProfileTests {
    @Test("cost tiers map from measured ms/frame")
    func costTiers() {
        let instant = EffectCostProfile(effectType: .brightness, millisecondsPerFrame: 2.0, peakMemoryMegabytes: 1, computePath: .gpu)
        #expect(instant.costTier == .instant)
        #expect(instant.isRealTimeSafe)

        let moderate = EffectCostProfile(effectType: .blur, millisecondsPerFrame: 10.0, peakMemoryMegabytes: 5, computePath: .cpu)
        #expect(moderate.costTier == .moderate)
        #expect(moderate.isRealTimeSafe)

        let heavy = EffectCostProfile(effectType: .styleTransfer, millisecondsPerFrame: 40.0, peakMemoryMegabytes: 50, computePath: .cpu)
        #expect(heavy.costTier == .heavy)
        #expect(heavy.isRealTimeSafe == false)
    }

    @Test("the boundary between tiers is exact")
    func tierBoundaries() {
        // 5.0 is the instant/moderate boundary (inclusive — 5.0 IS instant).
        #expect(EffectCostProfile(effectType: .brightness, millisecondsPerFrame: 5.0, peakMemoryMegabytes: 0, computePath: .gpu).costTier == .instant)
        #expect(EffectCostProfile(effectType: .brightness, millisecondsPerFrame: 5.01, peakMemoryMegabytes: 0, computePath: .gpu).costTier == .moderate)
        // 15.0 is the moderate/heavy boundary (inclusive — 15.0 IS moderate).
        #expect(EffectCostProfile(effectType: .blur, millisecondsPerFrame: 15.0, peakMemoryMegabytes: 0, computePath: .cpu).costTier == .moderate)
        #expect(EffectCostProfile(effectType: .blur, millisecondsPerFrame: 15.01, peakMemoryMegabytes: 0, computePath: .cpu).costTier == .heavy)
    }

    @Test("profiles are identifiable per effect+version")
    func identity() {
        let v1 = EffectCostProfile(effectType: .brightness, millisecondsPerFrame: 2, peakMemoryMegabytes: 1, computePath: .gpu)
        let v2 = EffectCostProfile(effectType: .brightness, millisecondsPerFrame: 2, peakMemoryMegabytes: 1, computePath: .gpu, measurementVersion: 2)
        #expect(v1.id != v2.id)
        #expect(v1.id.contains("brightness"))
        #expect(v1.id.contains("v1"))
    }

    @Test("profiles round-trip through Codable")
    func roundTrip() throws {
        let profile = EffectCostProfile(effectType: .blur, millisecondsPerFrame: 8.5, peakMemoryMegabytes: 12, computePath: .cpu)
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(EffectCostProfile.self, from: data)
        #expect(decoded == profile)
    }

    @Test("the profiler produces finite, non-negative profiles for every built-in")
    func profilerAllBuiltIns() {
        let profiles = EffectCostProfiler.measureAllBuiltIns(iterations: 3)
        #expect(profiles.count == EffectType.allCases.count)
        for profile in profiles {
            #expect(profile.millisecondsPerFrame >= 0, "\(profile.effectType.rawValue) must be non-negative")
            #expect(profile.millisecondsPerFrame.isFinite, "\(profile.effectType.rawValue) must be finite")
        }
    }

    // MARK: - G-28 real memory measurement

    @Test("the footprint probe reads a plausible physical footprint")
    func footprintProbeSanity() throws {
        let footprint = try #require(EffectCostProfiler.currentFootprintBytes())
        #expect(footprint > 0)
        // The footprint can never exceed the machine's physical memory.
        #expect(Double(footprint) < Double(ProcessInfo.processInfo.physicalMemory))
    }

    @Test("the profiler measurement runs detached — off the main thread, finite profiles")
    func measurementRunsOffTheMainThread() async throws {
        // v4 (2026-08-24): the 'main stays responsive' probes (v2 wall-clock
        // median, v3 ordering) both false-failed under FULL-SUITE parallel
        // load — Swift Testing suites share one main actor per process, and
        // unrelated suites can keep it continuously busy for a minute+
        // (observed 61.5s), which is ambient contention, not a main-thread
        // measurement. The deterministic, self-contained properties are:
        // ① the measurement executes on a background thread, and
        // ② it completes with finite results while this test itself keeps
        //    the main actor busy — impossible if the profiler required it.
        // (The browser-side detached single-flight wiring is separately
        // pinned by EffectBrowserProfilingConcurrencyStaticContractTests.)
        // Thread.isMainThread is unavailable in async contexts; capture it
        // from a synchronous helper so the affinity fact is read on the
        // thread that actually runs the measurement.
        func currentThreadIsMain() -> Bool { Thread.isMainThread }
        let load = Task.detached(priority: .userInitiated) { () -> (onMainThread: Bool, profiles: [EffectCostProfile]) in
            let onMainThread = currentThreadIsMain()
            let profiles = EffectCostProfiler.measureAllBuiltIns(iterations: 1)
            return (onMainThread, profiles)
        }

        // Hold the main actor with a short busy block while the detached
        // measurement runs. 300ms starves other suites minimally yet is far
        // below the multi-second full measurement, so completion-during-hold
        // is not required — the affinity check (1) is the discriminator.
        let holdStart = Date()
        await MainActor.run {
            while Date().timeIntervalSince(holdStart) < 0.3 {}
        }

        let result = try await load.value
        #expect(result.onMainThread == false,
                "the detached measurement must not execute on the main thread")
        #expect(!result.profiles.isEmpty)
        for profile in result.profiles {
            #expect(profile.millisecondsPerFrame.isFinite)
        }
    }

    @Test("measured memory is the differential footprint, never the physicalMemory placeholder")
    func measuredMemoryIsNotThePlaceholder() {
        let profile = EffectCostProfiler.measure(
            effect: Effect(type: .blur, parameters: ["radius": 40]),
            iterations: 5
        )
        #expect(profile.millisecondsPerFrame > 0)
        #expect(profile.peakMemoryMegabytes >= 0)
        #expect(profile.peakMemoryMegabytes.isFinite)
        // The retired placeholder: physicalMemory/1e6 × 0.001 MB, IDENTICAL
        // for every effect. A measured differential hitting that exact
        // constant would mean the placeholder resurrected.
        let placeholder = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000 * 0.001
        #expect(profile.peakMemoryMegabytes != placeholder,
                "measured=\(profile.peakMemoryMegabytes) placeholder=\(placeholder)")
    }
}
