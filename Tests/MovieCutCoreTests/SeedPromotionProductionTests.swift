// QAUTO-06 (42nd-cycle): seed promotion PRODUCTION wiring — P1~P6 acceptance
// from the 41st-cycle feedback. The wiring closes the chain:
//
//   random failure → capture (staging) → RNG-free replay → dedup by
//   semantic identity → registry (permanent asset, cardinality 1 per
//   identity) → pre-fix FAIL / post-fix PASS proven on the same fixture.
//
// The judgment functions are the SHARED implementation
// (SeedPromotionSupport) — production wiring and the 34th-cycle E2E use one
// implementation (exit criterion 6: no divergence point).
//
// Scope: MEDIUM. No auto-fix. Staging is cleaned at test end — the synthetic
// fixture is never committed to the repository (32nd-cycle contract).

import CryptoKit
import Foundation
import Testing

struct SeedPromotionProductionTests {
    // MARK: - production staging + registry

    /// The production staging path for promotion candidates — the runner
    /// writes HERE first; promotion to the permanent fixture directory is a
    /// separate, reviewed step (32nd-cycle: capture is automatic, promotion
    /// is reviewed).
    static func stagingDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qauto/promotion-candidates", isDirectory: true)
    }

    /// A candidate's semantic identity: SHA256 over the canonical JSON of
    /// the MEANINGFUL failure fields (run-start state + command sequence +
    /// expected invariant). Seed and step are provenance, not identity —
    /// two discoveries of the same defect share one identity.
    static func semanticIdentity(_ candidate: SPRegressionFixture) throws -> String {
        struct Core: Codable {
            var initial_project_state: SPMiniDoc
            var command_sequence: [SPMiniCommand]
            var expected_invariant: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let core = try encoder.encode(Core(
            initial_project_state: candidate.initial_project_state,
            command_sequence: candidate.command_sequence,
            expected_invariant: candidate.expected_invariant
        ))
        let digest = SHA256.hash(data: core)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// The registry: semantic_identity → canonical fixture + seed
    /// observations. Uniqueness invariant: each identity maps to exactly one
    /// entry; re-discovery APPENDS an observation, never a new entry (P1).
    struct Registry: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var semantic_identity: String
            var canonical_fixture: SPRegressionFixture
            var seed_observations: [String]
        }
        var entries: [Entry] = []

        /// Returns (registry, deduped) — deduped=true means the identity was
        /// already registered and only an observation was appended.
        func register(_ candidate: SPRegressionFixture, identity: String) -> (Registry, Bool) {
            if let idx = entries.firstIndex(where: { $0.semantic_identity == identity }) {
                var copy = self
                copy.entries[idx].seed_observations.append(
                    "seed \(candidate.origin_seed) step \(candidate.failing_step)"
                )
                return (copy, true)
            }
            var copy = self
            copy.entries.append(Entry(
                semantic_identity: identity,
                canonical_fixture: candidate,
                seed_observations: ["seed \(candidate.origin_seed) step \(candidate.failing_step)"]
            ))
            return (copy, false)
        }
    }

    /// Production capture: run the torture and WRITE the candidate JSON to
    /// the staging path — the same persist call the real promotion would use,
    /// only the destination differs (37th-cycle: one code path, destination
    /// swapped).
    @discardableResult
    static func captureCandidate(
        seed: UInt64, steps: Int, injectAt: (seed: UInt64, step: Int),
        stagingDir: URL
    ) throws -> (candidate: SPRegressionFixture, identity: String, url: URL) {
        guard let candidate = SeedPromotionSupport.runTorture(
            seed: seed, steps: steps, injectAt: injectAt
        ).fixture else {
            throw FixtureCaptureError.notReproduced(seed: seed, step: injectAt.step)
        }
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let url = stagingDir.appendingPathComponent("\(candidate.fixture_id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(candidate).write(to: url)
        return (candidate, try semanticIdentity(candidate), url)
    }

    enum FixtureCaptureError: Error {
        case notReproduced(seed: UInt64, step: Int)
    }

    // MARK: - P2 + P4: unknown failure captured to staging, replays FAIL RNG-free

    @Test("P2+P4: unknown failure captured to staging reproduces its violation RNG-free (pre-fix FAIL)")
    func captureAndPreFixFail() throws {
        let staging = Self.stagingDir()
        try? FileManager.default.removeItem(at: staging)

        let captured = try Self.captureCandidate(
            seed: 7, steps: 120, injectAt: (7, 73), stagingDir: staging
        )
        #expect(FileManager.default.fileExists(atPath: captured.url.path),
                "candidate JSON must be persisted to the staging path")

        // Load ONLY from the staging file — no in-memory state carries over.
        let decoded = try JSONDecoder().decode(
            SPRegressionFixture.self, from: try Data(contentsOf: captured.url)
        )
        let violation = try SeedPromotionSupport.replayFixture(decoded) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(
                command, to: &doc, armed: index == decoded.failing_step
            )
        }
        #expect(violation == decoded.failing_step,
                "pre-fix: the staged candidate must reproduce the violation RNG-free")
    }

    // MARK: - P1 + P5 + P6: dedup, post-fix PASS, registry uniqueness

    @Test("P1+P5+P6: same defect re-discovered → dedup (no new fixture), post-fix PASS, registry cardinality 1")
    func dedupPostFixAndUniqueness() throws {
        let staging = Self.stagingDir()
        try? FileManager.default.removeItem(at: staging)

        // Two captures of the SAME defect (same seed → same run → same
        // semantic identity; a different seed finding the same identity
        // would dedup identically).
        var registry = Registry()
        var dedupCount = 0
        for _ in 0..<2 {
            let captured = try Self.captureCandidate(
                seed: 7, steps: 120, injectAt: (7, 73), stagingDir: staging
            )
            let identity = try Self.semanticIdentity(captured.candidate)
            let (updated, wasDeduped) = registry.register(captured.candidate, identity: identity)
            registry = updated
            if wasDeduped { dedupCount += 1 }
        }
        #expect(dedupCount == 1, "the second discovery must dedup, not create a new fixture")
        #expect(registry.entries.count == 1, "P6: semantic_identity cardinality == 1")
        #expect(registry.entries[0].seed_observations.count == 2,
                "re-discovery appends a seed observation to the existing entry")

        // P5 post-fix PASS: the registered fixture, replayed with the clean
        // dispatcher (the defect "fixed"), holds the contract everywhere.
        let cleanViolation = try SeedPromotionSupport.replayFixture(
            registry.entries[0].canonical_fixture
        ) { command, _, doc in
            try SeedPromotionSupport.applyClean(command, to: &doc)
        }
        #expect(cleanViolation == nil, "post-fix: the registered fixture must PASS")

        // Registry JSON round-trip (the registry is the permanent asset).
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(registry)
        let decoded = try JSONDecoder().decode(Registry.self, from: data)
        #expect(decoded == registry, "registry round-trip must be lossless")

        try? FileManager.default.removeItem(at: staging)
    }

    @Test("P4 negative: a DIFFERENT defect gets its own identity — no false dedup")
    func differentDefectDifferentIdentity() throws {
        let first = try Self.captureCandidate(
            seed: 7, steps: 120, injectAt: (7, 73), stagingDir: FileManager.default.temporaryDirectory
        )
        // Different inject point → different command history → different
        // state → different identity (no false dedup).
        let second = try Self.captureCandidate(
            seed: 7, steps: 120, injectAt: (7, 90), stagingDir: FileManager.default.temporaryDirectory
        )
        let idA = try Self.semanticIdentity(first.candidate)
        let idB = try Self.semanticIdentity(second.candidate)
        #expect(idA != idB, "different failures must not share a semantic identity")
        // cleanup
        try? FileManager.default.removeItem(at: first.url)
        try? FileManager.default.removeItem(at: second.url)
    }
}
