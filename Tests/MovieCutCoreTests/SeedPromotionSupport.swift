// QAUTO-06 seed promotion — SHARED judgment functions (42nd-cycle refactor).
//
// Extracted from SeedPromotionE2ETests so the promotion E2E (proof) and the
// production wiring tests (P1~P6) exercise the SAME judgment code — the
// 37th-cycle feedback's exit criterion 6: production and test must share one
// judgment implementation, otherwise the wiring creates a new divergence
// point.

import CryptoKit
import Foundation
import Testing

/// Mini domain (Codable so fixtures are real serializations).
public struct SPMiniDoc: Codable, Equatable {
    public var markers: [String] = []
    public var volume: Double = 1.0

    public init(markers: [String] = [], volume: Double = 1.0) {
        self.markers = markers
        self.volume = volume
    }
}

public enum SPMiniCommand: Codable, Equatable {
    case addMarker(String)
    case setVolume(Double)
    case removeMarker(String)
}

public enum SPFixtureError: Error {
    case injectedFault
}

/// The promoted regression fixture: minimal fields only — fixture_id,
/// origin seed/step, run-start state, command history [0..fail], the
/// expected invariant, and the discovering commit. NO wall clock, NO machine
/// name, NO runner internals.
public struct SPRegressionFixture: Codable, Equatable {
    public var fixture_id: String
    public var origin_seed: UInt64
    public var failing_step: Int
    public var initial_project_state: SPMiniDoc
    public var command_sequence: [SPMiniCommand]
    public var expected_invariant: String
    public var discovered_at_commit: String

    /// Canonical JSON (sorted keys) — the basis of the semantic identity.
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// semantic identity = SHA256 over the canonical JSON of the fields that
    /// MEANINGFULLY define the failure (state + command sequence + invariant)
    /// — excluding fixture_id (an artifact of first discovery) and
    /// discovered_at_commit (provenance). Two discoveries of the same defect
    /// must produce the SAME identity regardless of seed.
    public func semanticIdentity() throws -> String {
        struct Core: Codable {
            var initial_project_state: SPMiniDoc
            var command_sequence: [SPMiniCommand]
            var expected_invariant: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let core = try encoder.encode(Core(
            initial_project_state: initial_project_state,
            command_sequence: command_sequence,
            expected_invariant: expected_invariant
        ))
        return SeedPromotionSupport.sha256Hex(core)
    }
}

public struct SPTortureOutcome {
    public var failed: Bool
    public var failingStep: Int?
    public var fixture: SPRegressionFixture?
}

public struct SPSeededRNG: RandomNumberGenerator {
    public var state: UInt64
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum SeedPromotionSupport {
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The CLEAN dispatcher: never mutates when it throws (the contract).
    public static func applyClean(_ command: SPMiniCommand, to doc: inout SPMiniDoc) throws {
        switch command {
        case .addMarker(let name):
            doc.markers.append(name)
        case .setVolume(let v):
            guard v >= 0 else { throw SPFixtureError.injectedFault }
            doc.volume = v
        case .removeMarker(let name):
            guard let idx = doc.markers.firstIndex(of: name) else {
                throw SPFixtureError.injectedFault
            }
            doc.markers.remove(at: idx)
        }
    }

    /// The FAULT dispatcher: when armed, mutates FIRST and throws AFTER —
    /// the classic "throwing dispatch mutated the project" violation.
    public static func applyFaulty(
        _ command: SPMiniCommand, to doc: inout SPMiniDoc, armed: Bool
    ) throws {
        if armed {
            doc.volume = 0.999
            throw SPFixtureError.injectedFault
        }
        try applyClean(command, to: &doc)
    }

    /// Always-valid generation over the reduced vocabulary.
    public static func nextCommand(for doc: SPMiniDoc, rng: inout SPSeededRNG) -> SPMiniCommand {
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

    /// The random torture runner. Returns the promoted fixture when the
    /// armed (seed, step) produces a throwing-with-mutation violation.
    public static func runTorture(
        seed: UInt64, steps: Int,
        injectAt: (seed: UInt64, step: Int)?,
        discoveredAtCommit: String = "synthetic-e2e"
    ) -> SPTortureOutcome {
        var rng = SPSeededRNG(state: seed &* 0x2545_F491_4F6C_DD1D)
        var doc = SPMiniDoc(markers: ["seed-marker"], volume: 1.0)
        // The fixture pairs RUN-START state with command_sequence[0..fail].
        let runStartState = doc
        var history: [SPMiniCommand] = []

        for step in 0..<steps {
            let command = nextCommand(for: doc, rng: &rng)
            history.append(command)

            let armed = injectAt != nil
                && injectAt!.seed == seed && injectAt!.step == step
            let before = doc
            do {
                try applyFaulty(command, to: &doc, armed: armed)
            } catch {
                if doc != before {
                    let fixture = SPRegressionFixture(
                        fixture_id: "promoted_\(seed)_\(step)",
                        origin_seed: seed,
                        failing_step: step,
                        initial_project_state: runStartState,
                        command_sequence: history,
                        expected_invariant: "throwing_dispatch_must_not_mutate",
                        discovered_at_commit: discoveredAtCommit
                    )
                    return SPTortureOutcome(failed: true, failingStep: step, fixture: fixture)
                }
                // Always-valid vocabulary: a clean throw means generation is
                // broken — strict, never silently continue.
                Issue.record("unexpected clean throw at seed \(seed) step \(step)")
                return SPTortureOutcome(failed: false, failingStep: nil, fixture: nil)
            }
        }
        return SPTortureOutcome(failed: false, failingStep: nil, fixture: nil)
    }

    /// The ONLY replay executor: fixture contents + a dispatcher choice —
    /// no RNG, no seed state, no runner. Returns the index of a detected
    /// contract violation (throw WITH mutation), or nil when the sequence
    /// holds the contract. A clean throw stops the replay with nil.
    public static func replayFixture(
        _ fixture: SPRegressionFixture,
        dispatcher: (SPMiniCommand, Int, inout SPMiniDoc) throws -> Void
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
}
