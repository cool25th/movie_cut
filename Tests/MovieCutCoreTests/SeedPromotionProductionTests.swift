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

    /// The OPERATIVE canonical serialization — the exact bytes whose SHA256
    /// is the semantic identity. Split out so the QAUTO-08 golden test can
    /// observe the real normalization output (not a test-side re-derivation):
    /// sorted object keys, preserved sequence order, minimal-decimal numbers.
    static func canonicalCoreJSON(_ candidate: SPRegressionFixture) throws -> Data {
        struct Core: Codable {
            var initial_project_state: SPMiniDoc
            var command_sequence: [SPMiniCommand]
            var expected_invariant: String
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(Core(
            initial_project_state: candidate.initial_project_state,
            command_sequence: candidate.command_sequence,
            expected_invariant: candidate.expected_invariant
        ))
    }

    /// A candidate's semantic identity: SHA256 over the canonical JSON of
    /// the MEANINGFUL failure fields (run-start state + command sequence +
    /// expected invariant). Seed and step are provenance, not identity —
    /// two discoveries of the same defect share one identity.
    static func semanticIdentity(_ candidate: SPRegressionFixture) throws -> String {
        SeedPromotionSupport.sha256Hex(try canonicalCoreJSON(candidate))
    }

    /// The registry: semantic_identity → canonical fixture + seed
    /// observations. Uniqueness invariant: each identity maps to exactly one
    /// entry; re-discovery APPENDS an observation, never a new entry (P1).
    struct Registry: Codable, Equatable {
        struct Entry: Codable, Equatable {
            var semantic_identity: String
            var canonical_fixture: SPRegressionFixture
            var seed_observations: [String]
            // Provenance fields (the ⑥ closure contract, 45th-cycle
            // judgment): a record must survive the staging wipe AND its
            // promoted evidence must remain usable after a disk reload.
            var status: String? = nil               // "known" | "unknown"
            var disposition: String? = nil          // "promoted" | "discarded"
            var pre_fix_violation_step: Int? = nil  // the intended invariant violation the faulty replay hits
            var post_fix_passed: Bool? = nil        // the clean replay holds the contract
            var fixture_path: String? = nil         // where the fixture evidence lives NOW
            var registry_target_path: String? = nil // promoted fixture path — nil for discarded synthetics
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

    // MARK: - ⑥ lifecycle: atomic registry persistence + explicit promotion

    /// The registry file the promotion pipeline owns — written atomically
    /// (45th-cycle judgment D: a failed write must never leave a truncated
    /// registry behind, and staging is never cleaned before this record and
    /// the promoted fixture exist).
    static func save(_ registry: Registry, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(registry).write(to: url, options: .atomic)
    }

    static func loadRegistry(from url: URL) throws -> Registry {
        try JSONDecoder().decode(Registry.self, from: Data(contentsOf: url))
    }

    /// Explicit promotion (32nd-cycle contract: capture is automatic,
    /// promotion is a reviewed step) — copy the staged fixture to the
    /// PERMANENT directory so its evidence outlives the staging wipe.
    static func promoteFixture(at stagedURL: URL, to promotedDir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: promotedDir, withIntermediateDirectories: true)
        let destination = promotedDir.appendingPathComponent(stagedURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: stagedURL, to: destination)
        return destination
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

    // MARK: - ⑥ (closure condition, 45th-cycle judgment): the registry and its
    // promoted evidence survive the staging wipe across a disk reload.

    @Test("P6 lifecycle: save → staging wipe → registry reload → identity + provenance survive; promoted fixture still replays")
    func registrySurvivesStagingWipeAndReload() throws {
        // Isolated staging path: the sibling tests wipe the shared stagingDir()
        // at their start/end, and Swift Testing runs suites in parallel.
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("qauto/promotion-candidates-lifecycle", isDirectory: true)
        let promotedDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qauto/promotion-fixtures", isDirectory: true)
        let registryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qauto/seed-promotion-registry.json")
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.removeItem(at: promotedDir)
        try? FileManager.default.removeItem(at: registryURL)

        // Two distinct defects: A is promoted (permanent evidence), B stays a
        // synthetic staging candidate that is discarded by design.
        let a = try Self.captureCandidate(seed: 7, steps: 120, injectAt: (7, 73), stagingDir: staging)
        let b = try Self.captureCandidate(seed: 7, steps: 120, injectAt: (7, 90), stagingDir: staging)
        let idA = try Self.semanticIdentity(a.candidate)
        let idB = try Self.semanticIdentity(b.candidate)
        #expect(idA != idB)

        // A: pre-fix FAIL must be the INTENDED invariant violation (not any
        // error), post-fix PASS must be a real clean replay — then promote.
        let preViolation = try SeedPromotionSupport.replayFixture(a.candidate) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(
                command, to: &doc, armed: index == a.candidate.failing_step
            )
        }
        #expect(preViolation == a.candidate.failing_step)
        let cleanViolation = try SeedPromotionSupport.replayFixture(a.candidate) { command, _, doc in
            try SeedPromotionSupport.applyClean(command, to: &doc)
        }
        #expect(cleanViolation == nil)
        let promotedURL = try Self.promoteFixture(at: a.url, to: promotedDir)

        var reg = Registry()
        (reg, _) = reg.register(a.candidate, identity: idA)
        if let i = reg.entries.firstIndex(where: { $0.semantic_identity == idA }) {
            reg.entries[i].status = "unknown"
            reg.entries[i].disposition = "promoted"
            reg.entries[i].pre_fix_violation_step = preViolation
            reg.entries[i].post_fix_passed = (cleanViolation == nil)
            reg.entries[i].fixture_path = promotedURL.path
            reg.entries[i].registry_target_path = promotedURL.path
        }
        (reg, _) = reg.register(b.candidate, identity: idB)
        if let i = reg.entries.firstIndex(where: { $0.semantic_identity == idB }) {
            reg.entries[i].status = "unknown"
            reg.entries[i].disposition = "discarded"
            reg.entries[i].fixture_path = b.url.path // staging only — wiped below
            reg.entries[i].registry_target_path = nil
        }
        try Self.save(reg, to: registryURL)

        // THE ⑥ EVENT: wipe staging, drop the in-memory registry instance.
        try FileManager.default.removeItem(at: staging)
        #expect(!FileManager.default.fileExists(atPath: b.url.path),
                "the synthetic staging candidate is gone by design")
        reg = Registry() // the old in-memory instance is discarded

        // Reload from disk — the registry file is now the ONLY source of truth.
        let reloaded = try Self.loadRegistry(from: registryURL)
        #expect(reloaded.entries.count == 2,
                "both dispositions keep their record across the reload")

        // A: identity + full provenance survived, and the promoted fixture is
        // READABLE and still reproduces its violation — evidence usable, not
        // just a dangling path string.
        guard let ea = reloaded.entries.first(where: { $0.semantic_identity == idA }) else {
            Issue.record("promoted entry lost across the staging-wipe reload")
            return
        }
        #expect(ea.disposition == "promoted")
        #expect(ea.status == "unknown")
        #expect(ea.pre_fix_violation_step == a.candidate.failing_step)
        #expect(ea.post_fix_passed == true)
        let promotedPath = try #require(ea.registry_target_path,
                                        "a promoted entry must carry its permanent target path")
        #expect(FileManager.default.fileExists(atPath: promotedPath),
                "the promoted fixture must survive the staging wipe")
        let promotedFixture = try JSONDecoder().decode(
            SPRegressionFixture.self, from: Data(contentsOf: URL(fileURLWithPath: promotedPath))
        )
        #expect(try Self.semanticIdentity(promotedFixture) == ea.semantic_identity,
                "identity recomputed from the reloaded fixture must match the stored identity")
        let promotedPreViolation = try SeedPromotionSupport.replayFixture(promotedFixture) { command, index, doc in
            try SeedPromotionSupport.applyFaulty(
                command, to: &doc, armed: index == promotedFixture.failing_step
            )
        }
        #expect(promotedPreViolation == promotedFixture.failing_step,
                "the promoted fixture still reproduces its violation after the wipe+reload")
        let promotedCleanViolation = try SeedPromotionSupport.replayFixture(promotedFixture) { command, _, doc in
            try SeedPromotionSupport.applyClean(command, to: &doc)
        }
        #expect(promotedCleanViolation == nil,
                "the promoted fixture still PASSES with the clean dispatcher")

        // B: discarded — the entry keeps its disposition and history, and is
        // NOT presented as replayable (no dangling promoted target).
        guard let eb = reloaded.entries.first(where: { $0.semantic_identity == idB }) else {
            Issue.record("discarded entry lost across the staging-wipe reload")
            return
        }
        #expect(eb.disposition == "discarded")
        #expect(eb.registry_target_path == nil,
                "a discarded synthetic candidate must not be presented as replayable")
        #expect(!FileManager.default.fileExists(atPath: eb.fixture_path ?? ""))

        // cleanup
        try? FileManager.default.removeItem(at: promotedDir)
        try? FileManager.default.removeItem(at: registryURL)
    }

    // MARK: - QAUTO-08: golden identity contract (45th-cycle judgment, ⑤ follow-up)
    //
    // The golden canonical bytes were HAND-WRITTEN from the normalization
    // contract (sorted object keys / preserved sequence order / minimal-decimal
    // numbers) and their digest was fixed with an EXTERNAL tool —
    // `shasum -a 256 -b` on a 168-byte file with no trailing newline. The
    // first draft assumed Swift's flat single-payload enum encoding; the
    // golden test itself caught the mismatch — THIS compiler synthesizes
    // single-payload enum cases as nested {"case":{"_0":value}} — and the
    // reviewed bytes were re-confirmed against that specification. The test
    // does NOT pre-normalize its inputs: the reordered-key case is decoded
    // through the real Codable entry so the OPERATIVE path does the
    // normalization.

    @Test("QAUTO-08 golden identity: reviewed canonical bytes + shasum-fixed digest + relations incl. sequence order")
    func goldenIdentityContract() throws {
        // The reviewed baseline candidate — hand-constructed, NOT from runTorture.
        var doc = SPMiniDoc()
        doc.markers = []
        doc.volume = 0.75
        let base = SPRegressionFixture(
            fixture_id: "qauto08-golden-base", origin_seed: 0, failing_step: 1,
            initial_project_state: doc,
            command_sequence: [.addMarker("m1"), .setVolume(0.5)],
            expected_invariant: "markers_keep_order",
            discovered_at_commit: "qauto08-golden"
        )
        let reviewedCanonical =
            #"{"command_sequence":[{"addMarker":{"_0":"m1"}},{"setVolume":{"_0":0.5}}],"expected_invariant":"markers_keep_order","initial_project_state":{"markers":[],"volume":0.75}}"#
        // `shasum -a 256 -b qauto08-reviewed-canonical.json` — fixed 2026-10-11.
        let goldenDigest = "a27b38f0b2b3f906f2403c0b95f6509bc66cfea1cbc5e19bd43f4a151996cdcf"

        // Relation 1: the OPERATIVE canonicalization produces the reviewed
        // bytes, and the operative identity matches the externally fixed digest.
        #expect(String(decoding: try Self.canonicalCoreJSON(base), as: UTF8.self) == reviewedCanonical,
                "operative canonical bytes must equal the hand-reviewed bytes")
        #expect(try Self.semanticIdentity(base) == goldenDigest,
                "operative identity must equal the shasum-fixed golden digest")

        // Relation 2: same meaning, different surface key order (the reordered
        // JSON also carries a DIFFERENT fixture_id/seed — identity-irrelevant
        // provenance) → identical canonical bytes and identity. The input goes
        // through the real decode path; the test pre-sorts nothing.
        let reorderedJSON =
            #"{"discovered_at_commit":"qauto08-other-writer","expected_invariant":"markers_keep_order","command_sequence":[{"addMarker":{"_0":"m1"}},{"setVolume":{"_0":0.5}}],"initial_project_state":{"volume":0.75,"markers":[]},"origin_seed":9,"failing_step":42,"fixture_id":"qauto08-reordered"}"#
        let decoded = try JSONDecoder().decode(
            SPRegressionFixture.self, from: Data(reorderedJSON.utf8)
        )
        #expect(String(decoding: try Self.canonicalCoreJSON(decoded), as: UTF8.self) == reviewedCanonical,
                "surface key order must not leak into the canonical bytes")
        #expect(try Self.semanticIdentity(decoded) == goldenDigest,
                "same meaning must map to the same identity regardless of key order")

        // Relation 3a: a changed MEANING field (invariant) → different bytes
        // and identity.
        var invariantChanged = base
        invariantChanged.expected_invariant = "volume_clamped"
        #expect(String(decoding: try Self.canonicalCoreJSON(invariantChanged), as: UTF8.self) != reviewedCanonical)
        #expect(try Self.semanticIdentity(invariantChanged) != goldenDigest)

        // Relation 3b: sequence ORDER swapped (order-meaningful commands) →
        // different identity — targets a regression where the canonicalizer
        // wrongly sorts the array like object keys.
        var sequenceSwapped = base
        sequenceSwapped.command_sequence = [.setVolume(0.5), .addMarker("m1")]
        #expect(try Self.semanticIdentity(sequenceSwapped) != goldenDigest,
                "sequence order is meaning; swapping commands must change the identity")

        // Relation 3c: changed state → different identity.
        var stateChanged = base
        stateChanged.initial_project_state.volume = 0.8
        #expect(try Self.semanticIdentity(stateChanged) != goldenDigest)
    }
}
