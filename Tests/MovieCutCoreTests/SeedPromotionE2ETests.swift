// QAUTO-06 (32nd-cycle): seed failure PROMOTION path — the feedback-specified
// proof that "stochastic discovery becomes a deterministic regression asset".
//
// System under test is the PROMOTION PIPELINE itself, not the session
// contract (the session contracts are CommandTortureTests' job). The pipeline:
//
//   random torture run (seeded RNG)
//     → failure detected at exactly one (seed, step)
//     → capture: seed + step + command history + initial state
//     → immutable regression fixture serialized to JSON (minimal fields —
//       NO wall clock, NO machine name, NO runner internals)
//     → fixture loaded FROM THE FILE and replayed WITHOUT any RNG
//       → the same violation reproduces at the same step
//     → with the defect "fixed" (clean dispatcher), the same fixture PASSES
//
// Invariant: regression fixture execution != random generator execution —
// the replay path takes only fixture contents; if the fixture had to call
// the seed runner again, nothing was promoted.
//
// A test-only fault injector arms for exactly one (seed, step) pair and
// simulates the classic contract violation: a dispatch that MUTATES the
// document and THEN throws. Generation itself stays always-valid so the
// injected failure is the only failure in the run.

import Foundation
import Testing

struct SeedPromotionE2ETests {
    // MARK: - mini domain (Codable so the fixture is a real serialization)

    struct MiniDoc: Codable, Equatable {
        var markers: [String] = []
        var volume: Double = 1.0
    }

    enum MiniCommand: Codable, Equatable {
        case addMarker(String)
        case setVolume(Double)
        case removeMarker(String)
    }

    enum FixtureError: Error {
        case injectedFault
    }

    struct RegressionFixture: Codable, Equatable {
        var fixture_id: String
        var origin_seed: UInt64
        var failing_step: Int
        var initial_project_state: MiniDoc
        var command_sequence: [MiniCommand]
        var expected_invariant: String
        var discovered_at_commit: String
    }

    struct TortureOutcome {
        var failed: Bool
        var failingStep: Int?
        var fixture: RegressionFixture?
    }

    // MARK: - SplitMix64 (same family as the session torture runner)

    struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - dispatchers

    /// The CLEAN dispatcher: never mutates when it throws (the contract).
    func applyClean(_ command: MiniCommand, to doc: inout MiniDoc) throws {
        switch command {
        case .addMarker(let name):
            doc.markers.append(name)
        case .setVolume(let v):
            guard v >= 0 else { throw FixtureError.injectedFault }
            doc.volume = v
        case .removeMarker(let name):
            guard let idx = doc.markers.firstIndex(of: name) else {
                throw FixtureError.injectedFault
            }
            doc.markers.remove(at: idx)
        }
    }

    /// The test-only FAULT dispatcher: when armed, mutates FIRST and throws
    /// AFTER — the classic "throwing dispatch mutated the project" violation.
    func applyFaulty(
        _ command: MiniCommand, to doc: inout MiniDoc, armed: Bool
    ) throws {
        if armed {
            doc.volume = 0.999  // mutation BEFORE the throw = the violation
            throw FixtureError.injectedFault
        }
        try applyClean(command, to: &doc)
    }

    // MARK: - the random torture runner (always-valid generation)

    func nextCommand(for doc: MiniDoc, rng: inout SeededRNG) -> MiniCommand {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0:
            return .addMarker("m\(Int.random(in: 0..<99, using: &rng))")
        case 1:
            return .setVolume(Double.random(in: 0...2, using: &rng))
        default:
            if let pick = doc.markers.randomElement(using: &rng) {
                return .removeMarker(pick)
            }
            return .addMarker("m0")
        }
    }

    func runTorture(
        seed: UInt64, steps: Int,
        injectAt: (seed: UInt64, step: Int)?,
        discoveredAtCommit: String = "synthetic-e2e"
    ) -> TortureOutcome {
        var rng = SeededRNG(state: seed &* 0x2545_F491_4F6C_DD1D)
        var doc = MiniDoc(markers: ["seed-marker"], volume: 1.0)
        // The fixture pairs RUN-START state with command_sequence[0..fail] —
        // capturing the just-before-failure state instead would make the
        // recorded history replay from the wrong world (the first failing
        // replay run caught exactly that harness defect).
        let runStartState = doc
        var history: [MiniCommand] = []

        for step in 0..<steps {
            let command = nextCommand(for: doc, rng: &rng)
            history.append(command)

            let armed = injectAt != nil
                && injectAt!.seed == seed && injectAt!.step == step
            let before = doc
            do {
                try applyFaulty(command, to: &doc, armed: armed)
            } catch {
                // The invariant the fixture must preserve as evidence: did
                // this throwing step mutate the document anyway?
                if doc != before {
                    let fixture = RegressionFixture(
                        fixture_id: "promoted_\(seed)_\(step)",
                        origin_seed: seed,
                        failing_step: step,
                        initial_project_state: runStartState,
                        command_sequence: history,
                        expected_invariant: "throwing_dispatch_must_not_mutate",
                        discovered_at_commit: discoveredAtCommit
                    )
                    return TortureOutcome(failed: true, failingStep: step, fixture: fixture)
                }
                // The reduced vocabulary is always-valid, so a throw without
                // mutation here would mean generation is broken — keep the
                // harness strict instead of silently continuing.
                Issue.record("unexpected clean throw at seed \(seed) step \(step)")
                return TortureOutcome(failed: false, failingStep: nil, fixture: nil)
            }
        }
        return TortureOutcome(failed: false, failingStep: nil, fixture: nil)
    }

    // MARK: - the promotion pipeline under test

    /// The ONLY replay executor: fixture contents + a dispatcher choice —
    /// no RNG, no seed state, no runner. Returns the index of a detected
    /// contract violation (throw WITH mutation), or nil when the sequence
    /// holds the contract. A clean throw (without mutation) stops the replay
    /// with nil — the contract held and the recorded suffix is unreachable.
    func replayFixture(
        _ fixture: RegressionFixture,
        dispatcher: (MiniCommand, Int, inout MiniDoc) throws -> Void
    ) rethrows -> Int? {
        var doc = fixture.initial_project_state
        for (index, command) in fixture.command_sequence.enumerated() {
            let before = doc
            do {
                try dispatcher(command, index, &doc)
            } catch {
                return doc != before ? index : nil
            }
        }
        return nil
    }

    // MARK: - tests

    @Test("seed failure is captured, serialized, and reproduced from the fixture file alone")
    func promotionPipeline() throws {
        // Phase A — random torture: ONLY the armed (seed, step) fails.
        let armedSeed: UInt64 = 7
        let armedStep = 73
        var failures: [(seed: UInt64, step: Int)] = []
        for seed: UInt64 in 1...10 {
            let outcome = runTorture(seed: seed, steps: 120, injectAt: (armedSeed, armedStep))
            if outcome.failed, let step = outcome.failingStep {
                failures.append((seed, step))
            }
        }
        #expect(failures.count == 1, "fault injector must fire exactly once across seeds — got \(failures)")
        #expect(failures.first?.seed == armedSeed)
        #expect(failures.first?.step == armedStep)

        // Phase B — capture + serialize the IMMUTABLE fixture.
        let fixture = try #require(
            runTorture(seed: armedSeed, steps: 120, injectAt: (armedSeed, armedStep)).fixture
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

        // Phase C — independent replay FROM THE FILE with no runner state:
        // the dispatcher is armed purely by the fixture's own failing_step.
        let decoded = try JSONDecoder().decode(
            RegressionFixture.self, from: try Data(contentsOf: url)
        )
        let violationStep = try replayFixture(decoded) { command, index, doc in
            try self.applyFaulty(command, to: &doc, armed: index == decoded.failing_step)
        }
        #expect(violationStep == decoded.failing_step,
                "the promoted fixture must reproduce the violation at its own failing step")

        // Phase D — "after the fix": the SAME fixture passes under the clean
        // dispatcher (no violation anywhere in the promoted sequence).
        let cleanViolation = try replayFixture(decoded) { command, _, doc in
            try self.applyClean(command, to: &doc)
        }
        #expect(cleanViolation == nil,
                "clean dispatcher must hold the contract for the whole promoted sequence")
    }

    @Test("fixture replay is deterministic and RNG-free — fixture execution is not generator execution")
    func replayIsDeterministicAndRunnerFree() throws {
        let fixture = try #require(
            runTorture(seed: 7, steps: 120, injectAt: (7, 73)).fixture
        )
        // RNG-free by signature: replayFixture takes no generator. Prove
        // determinism empirically — two replays agree exactly.
        let a = try replayFixture(fixture) { command, index, doc in
            try self.applyFaulty(command, to: &doc, armed: index == 73)
        }
        let b = try replayFixture(fixture) { command, index, doc in
            try self.applyFaulty(command, to: &doc, armed: index == 73)
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
