import Foundation

/// CA-30 Local Beta Diagnostics — a session-scoped funnel event log,
/// append-only JSONL, fully local. This type must never reference a
/// networking API: the offline contract (CA-01 socket-capture zero) holds
/// because diagnostics leave the device only through a user-visible
/// share/copy surface, never automatically.
///
/// PII discipline (design §1): the record schema below is FIXED. There is
/// no free-text field except `errorCode`, which is a machine code — media
/// names, transcripts, and project content cannot enter the log by
/// construction.
///
/// Funnel (design §2): import_start → first_clip_on_timeline → first_edit
/// → export_start → export_success / export_fail.
public actor BetaDiagnosticsLog {

    /// The funnel events. Raw values are the wire names in the JSONL.
    public enum Event: String, Codable, CaseIterable, Sendable {
        case importStart = "import_start"
        case firstClipOnTimeline = "first_clip_on_timeline"
        case firstEdit = "first_edit"
        case exportStart = "export_start"
        case exportSuccess = "export_success"
        case exportFail = "export_fail"
    }

    /// One JSONL line. The key set is the whole contract — adding a key is
    /// a schema bump (`schemaVersion`), not an ad-hoc edit.
    struct Record: Codable, Equatable, Sendable {
        var schemaVersion: Int = 1
        var event: String
        var ts: Double
        var sessionID: String
        var durationMS: Int?
        var errorCode: String?
        var osVersion: String
        var deviceClass: String
    }

    /// Shared per-process session identity (one app launch = one session).
    private let sessionID: UUID
    private let osVersion: String
    private let deviceClass: String
    private let fileURL: URL?
    private let rotationCapBytes: Int
    /// In-memory once-per-session guard for `recordOnce` (process lifetime,
    /// not file lifetime — a relaunched app is a new session by design).
    private var onceRecorded: Set<Event> = []

    /// A nil `directory` disables recording entirely (unit-test and UI-test
    /// harness suppression — the CA-25 pattern).
    public init(
        directory: URL?,
        osVersion: String,
        deviceClass: String,
        rotationCapBytes: Int = 1_048_576
    ) {
        self.sessionID = UUID()
        self.osVersion = osVersion
        self.deviceClass = deviceClass
        self.rotationCapBytes = max(0, rotationCapBytes)
        guard let directory else {
            self.fileURL = nil
            return
        }
        let url = directory.appendingPathComponent("beta-diagnostics.jsonl")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Bounded rotation: an oversized active file archives to one `.old`
        // sibling (replacing it), so total footprint ≤ 2× cap.
        if
            rotationCapBytes > 0,
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int,
            size > rotationCapBytes
        {
            let archived = directory.appendingPathComponent("beta-diagnostics.old.jsonl")
            try? FileManager.default.removeItem(at: archived)
            try? FileManager.default.moveItem(at: url, to: archived)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        self.fileURL = url
    }

    /// Records the event only once per session (the "first_*" funnel
    /// semantics — first clip, first edit). Repeat calls are no-ops.
    public func recordOnce(_ event: Event, at date: Date = Date()) {
        guard !onceRecorded.contains(event) else { return }
        onceRecorded.insert(event)
        record(event, at: date)
    }

    /// Appends one funnel event. A disabled log (nil directory) is a no-op.
    public func record(
        _ event: Event,
        durationMs: Int? = nil,
        errorCode: String? = nil,
        at date: Date = Date()
    ) {
        guard let fileURL else { return }
        rotateIfNeeded(activeURL: fileURL)
        let record = Record(
            event: event.rawValue,
            ts: date.timeIntervalSince1970,
            sessionID: sessionID.uuidString,
            durationMS: durationMs,
            errorCode: errorCode,
            osVersion: osVersion,
            deviceClass: deviceClass
        )
        guard
            let data = try? JSONEncoder().encode(record),
            let handle = FileHandle(forWritingAtPath: fileURL.path)
        else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        _ = try? handle.write(contentsOf: data + Data([0x0A]))
    }

    /// Bounded rotation: when the active file exceeds the cap, it archives
    /// to one `.old` sibling (replacing it) and a fresh file starts, so the
    /// total footprint never exceeds 2× cap.
    private func rotateIfNeeded(activeURL: URL) {
        guard rotationCapBytes > 0 else { return }
        guard
            let size = (try? FileManager.default.attributesOfItem(atPath: activeURL.path)[.size]) as? Int,
            size > rotationCapBytes
        else { return }
        let archived = activeURL.deletingLastPathComponent()
            .appendingPathComponent("beta-diagnostics.old.jsonl")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: activeURL, to: archived)
        FileManager.default.createFile(atPath: activeURL.path, contents: nil)
    }

    /// The active JSONL file for opt-in export surfaces (nil when the log
    /// is disabled). Reading it never writes.
    public func exportFileURL() -> URL? {
        fileURL
    }

    /// Events recorded so far (active file only), in order — the test and
    /// export surface. Corrupt lines are skipped, never fatal.
    public func recordedEvents() -> [Event] {
        lines().compactMap { Event(rawValue: $0.event) }
    }

    /// The active file's raw JSONL contents (opt-in export surface reads
    /// this or the file URL directly).
    public func fileContents() -> String? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func lines() -> [Record] {
        guard let contents = fileContents(), !contents.isEmpty else { return [] }
        return contents
            .split(separator: "\n")
            .compactMap { try? JSONDecoder().decode(Record.self, from: Data($0.utf8)) }
    }
}
