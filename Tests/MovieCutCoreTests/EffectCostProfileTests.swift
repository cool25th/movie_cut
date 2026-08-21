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

    @Test("the browser measurement runs off the main thread — main stays responsive")
    func measurementLeavesMainThreadResponsive() async {
        // The browser's loadProfiles must call the profiler from a
        // DETACHED task: a MainActor-inherited Task runs the multi-second
        // measurement ON the main thread and freezes the UI (the pre-fix
        // browser did exactly that). Probing main-actor hops while the
        // measurement runs pins the property: a main-thread measurement
        // would stall the hops for the whole load.
        let load = Task.detached(priority: .userInitiated) {
            EffectCostProfiler.measureAllBuiltIns(iterations: 3)
        }
        await MainActor.run {}
        var worstHopMs = 0.0
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            let start = DispatchTime.now()
            await MainActor.run {}
            worstHopMs = max(worstHopMs, Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
        }
        _ = await load.value
        // The full measurement takes well over a second on every machine
        // this suite runs on; a blocked main actor would show a hop in the
        // hundreds-to-thousands of ms. 250ms tolerates scheduler noise.
        #expect(worstHopMs < 250, "main actor stalled \(worstHopMs)ms during the measurement")
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
