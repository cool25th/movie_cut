// QAUTO-06 seed promotion E2E (34th-cycle) — the promotion PIPELINE proof.
//
// 42nd-cycle refactor: the judgment functions (domain, torture runner,
// replay executor) moved to SeedPromotionSupport.swift so the E2E proof and
// the production wiring tests (SeedPromotionProductionTests) exercise the
// SAME implementation — production/test judgment sharing is exit criterion
// 6 of the wiring.

import Foundation
import Testing
@testable import MovieCutCore

struct SeedPromotionE2ETests {
    @Test("seed failure is captured, serialized, and reproduced from the fixture file alone")
    func promotionPipeline() throws {
        // Phase A — random torture: ONLY the armed (seed, step) fails.
        let armedSeed: UInt64 = 7
        let armedStep = 73
        var failures: [(seed: UInt64, step: Int)] = []
        for seed: UInt64 in 1...10 {
            let outcome = SeedPromotionSupport.runTorture(
                seed: seed, steps: 120, injectAt: (armedSeed, armedStep)
            )
            if outcome.failed, let step = outcome.failingStep {
                failures.append((seed, step))
            }
        }
        #expect(failures.count == 1, "fault injector must fire exactly once across seeds — got \(failures)")
        #expect(failures.first?.seed == armedSeed)
        #expect(failures.first?.step == armedStep)

        // Phase B — capture + serialize the IMMUTABLE fixture.
        let fixture = try #require(
            SeedPromotionSupport.runTorture(
                seed: armedSeed, steps: 120, injectAt: (armedSeed, armedStep)
            ).fixture
        )
        #expect(fixture.origin_seed == armedSeed)
        #expect(fixture.failing_step == armedStep)
        #expect(fixture.expected_invariant == "throwing_dispatch_must_not_mutate")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(fixture)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("promoted-\(armedSeed)-\(armedStep).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // Phase C — independent replay FROM THE FILE with no runner state.
        let decoded = try JSONDecoder().decode(
            SPRegressionFixture.self, from: try Data(contentsOf: url)
        )
        let violationStep = try SeedPromotionSupport.replayFixture(decoded) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(
                command, to: &doc, armed: index == decoded.failing_step
            )
        }
        #expect(violationStep == decoded.failing_step,
                "the promoted fixture must reproduce the violation at its own failing step")

        // Phase D — "after the fix": the SAME fixture passes under the clean
        // dispatcher (no violation anywhere in the promoted sequence).
        let cleanViolation = try SeedPromotionSupport.replayFixture(decoded) { command, _, doc in
            try SeedPromotionSupport.applyClean(command, to: &doc)
        }
        #expect(cleanViolation == nil,
                "clean dispatcher must hold the contract for the whole promoted sequence")
    }

    @Test("fixture replay is deterministic and RNG-free — fixture execution is not generator execution")
    func replayIsDeterministicAndRunnerFree() throws {
        let fixture = try #require(
            SeedPromotionSupport.runTorture(seed: 7, steps: 120, injectAt: (7, 73)).fixture
        )
        // RNG-free by signature: replayFixture takes no generator. Two
        // replays must agree exactly.
        let a = try SeedPromotionSupport.replayFixture(fixture) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(command, to: &doc, armed: index == 73)
        }
        let b = try SeedPromotionSupport.replayFixture(fixture) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(command, to: &doc, armed: index == 73)
        }
        #expect(a == b)
        #expect(a == fixture.failing_step)

        // The fixture carries NO runner internals: assert the exact JSON key
        // set (origin/step/state/commands/invariant/commit — nothing else,
        // no wall clock or machine fields).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let obj = try JSONSerialization.jsonObject(with: encoder.encode(fixture)) as! [String: Any]
        let keys = Set(obj.keys)
        #expect(keys == ["fixture_id", "origin_seed", "failing_step",
                         "initial_project_state", "command_sequence",
                         "expected_invariant", "discovered_at_commit"])
    }
}
