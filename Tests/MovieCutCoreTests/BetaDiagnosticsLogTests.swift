import Foundation
import Testing
@testable import MovieCutCore

/// CA-30 Local Beta Diagnostics — the log's contract: append-only funnel
/// order, a FIXED record schema (the PII guarantee is structural — there is
/// no free-text field to abuse), bounded rotation, and disabled-mode no-op
/// (harness suppression).
@Suite("Beta diagnostics log (CA-30)")
struct BetaDiagnosticsLogTests {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ca30-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Funnel events append in order with the fixed schema and one session id")
    func funnelOrderAndSchema() async throws {
        let dir = tempDir()
        let log = BetaDiagnosticsLog(directory: dir, osVersion: "26.5", deviceClass: "mac")

        await log.record(.importStart)
        await log.record(.firstClipOnTimeline)
        await log.record(.firstEdit)
        await log.record(.exportStart)
        await log.record(.exportSuccess, durationMs: 4_120)

        let events = await log.recordedEvents()
        #expect(events == [
            .importStart, .firstClipOnTimeline, .firstEdit, .exportStart, .exportSuccess,
        ])

        let contents = try #require(await log.fileContents())
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 5)

        // The schema is a fixed contract: required keys always present,
        // optional keys (durationMS/errorCode) only when set (JSONEncoder
        // omits nils) — and NOTHING outside the schema can appear, which is
        // the structural no-PII guarantee.
        let requiredKeys: Set<String> = [
            "schemaVersion", "event", "ts", "sessionID", "osVersion", "deviceClass",
        ]
        let optionalKeys: Set<String> = ["durationMS", "errorCode"]
        for line in lines {
            let object = try #require(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            let keys = Set(object.keys)
            #expect(keys.isSuperset(of: requiredKeys), "missing required keys: \(requiredKeys.subtracting(keys))")
            #expect(keys.subtracting(requiredKeys).isSubset(of: optionalKeys),
                    "keys outside the schema: \(keys.subtracting(requiredKeys).subtracting(optionalKeys))")
            // No value carries free text beyond the fixed enums/numbers.
            for (key, value) in object {
                if key == "event" || key == "errorCode" {
                    if let text = value as? String {
                        #expect(!text.contains("/"), "path-like value in \(key): \(text)")
                    }
                }
            }
        }

        // durationMS lands only where provided; errorCode only on failures.
        let successLine = lines[4]
        #expect(successLine.contains("\"durationMS\":4120"))
        #expect(!successLine.contains("errorCode"))
    }

    @Test("export_fail carries a machine error code, never a message")
    func exportFailErrorCode() async throws {
        let dir = tempDir()
        let log = BetaDiagnosticsLog(directory: dir, osVersion: "17.0", deviceClass: "iOS-mid")
        await log.record(.exportStart)
        await log.record(.exportFail, errorCode: "FileOperationError.diskFull")
        let contents = try #require(await log.fileContents())
        #expect(contents.contains("export_fail"))
        #expect(contents.contains("FileOperationError.diskFull"))
        // A caller cannot smuggle a message: the only string inputs are the
        // event enum and the code parameter, asserted path-free above.
        #expect(!contents.contains("username"))
        #expect(!contents.contains("file:"))
    }

    @Test("A nil directory disables recording (harness suppression)")
    func disabledLogIsNoOp() async {
        let log = BetaDiagnosticsLog(directory: nil, osVersion: "26.5", deviceClass: "mac")
        await log.record(.importStart)
        let events = await log.recordedEvents()
        #expect(events.isEmpty)
        let contents = await log.fileContents()
        #expect(contents == nil)
    }

    @Test("recordOnce fires only the first time per session (first_edit semantics)")
    func recordOnceSemantics() async throws {
        let dir = tempDir()
        let log = BetaDiagnosticsLog(directory: dir, osVersion: "26.5", deviceClass: "mac")
        await log.recordOnce(.firstEdit)
        await log.recordOnce(.firstEdit)
        await log.recordOnce(.firstEdit)
        await log.recordOnce(.firstClipOnTimeline)
        let events = await log.recordedEvents()
        #expect(events == [.firstEdit, .firstClipOnTimeline],
                "recordOnce must not repeat within a session")
    }

    @Test("Rotation caps the footprint: an oversized active file archives to one .old sibling")
    func rotationCap() async throws {
        let dir = tempDir()
        // Tiny cap so the second event trips rotation.
        let log = BetaDiagnosticsLog(directory: dir, osVersion: "26.5", deviceClass: "mac", rotationCapBytes: 1)
        await log.record(.importStart)
        await log.record(.firstEdit)

        let archived = dir.appendingPathComponent("beta-diagnostics.old.jsonl")
        #expect(FileManager.default.fileExists(atPath: archived.path),
                "oversized file must archive to the .old sibling")
        let events = await log.recordedEvents()
        #expect(events == [.firstEdit], "the fresh file holds only post-rotation events")
    }
}
