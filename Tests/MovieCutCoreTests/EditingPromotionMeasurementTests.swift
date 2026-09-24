import Foundation
import Testing
@testable import MovieCutCore

/// P3 increment 5 — the promotion measurement over a scripted 100-scenario
/// corpus. Pre-registered criteria (unchanged since the direction consult):
///
///   plan validity            ≥ 95% of VALID scenarios produce actions that
///                            pass kernel validation
///   intent match             ≥ 90% of ALL scenarios resolve to exactly the
///                            authored expectation (action equality, or the
///                            exact typed rejection for invalid scenarios)
///   destructive-unrecoverable 0 scenarios whose apply+undo leaves the
///                            project different (beyond updatedAt)
///   undo recovery            100% (the same axis, stated positively)
///
/// The corpus is DETERMINISTIC (fixed clip IDs, parameter grids over the
/// documented v1 grammar) so "intent match" is exact-equality against
/// authored ground truth — a machine proxy. The HUMAN intent axis (real
/// users' free-form phrasing variety) is explicitly deferred to the beta
/// workflow measurement, same transfer as N1 — no modeled proxy is reported
/// as the human number.
@Suite("Editing promotion measurement (P3 increment 5)")
struct EditingPromotionMeasurementTests {

    // Fixed IDs so authored expectations can name the exact target clip.
    private static let clipA = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!  // audio  0-4s
    private static let clipB = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!  // video  4-10s (longest → default)
    private static let clipC = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!  // video 10-12s

    private static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private enum Fixture { case standard, duck, silence }

    private struct Scenario {
        enum Expectation: Equatable {
            case actions([EditingActionDSL.Action])
            case fails(EditingIntentPlanner.PlannerError)
        }
        let instruction: String
        let expectation: Expectation
        let fixture: Fixture
    }

    private static func standardProject() -> Project {
        let spans: [(UUID, Double, Double, ClipKind)] = [
            (clipA, 0, 4, .audio), (clipB, 4, 10, .video), (clipC, 10, 12, .video),
        ]
        let clips = spans.map { id, start, end, kind in
            Clip(
                id: id, assetId: UUID(), kind: kind,
                sourceRange: TimeRange(start: 0, duration: end - start),
                timelineRange: TimeRange(start: start, duration: end - start)
            )
        }
        return Project(name: "promo", timeline: Timeline(
            canvasSize: CGSize(width: 320, height: 240),
            tracks: [Track(kind: .video, name: "V", zIndex: 0, clips: clips)]))
    }

    /// Voice(1s tone)+BGM(4s) overlapping — real on-device ducking analysis.
    private static func duckProject() -> Project {
        let voice = MediaAsset(
            originalURL: repoRoot.appendingPathComponent("Tests/Fixtures/duck_voice_1000hz_1s_mono.wav"),
            kind: .audio, duration: 1)
        let bgm = MediaAsset(
            originalURL: repoRoot.appendingPathComponent("Tests/Fixtures/duck_bgm_220hz_4s_mono.wav"),
            kind: .audio, duration: 4)
        let voiceClip = Clip(id: clipA, assetId: voice.id, kind: .audio,
                             sourceRange: TimeRange(start: 0, duration: 1),
                             timelineRange: TimeRange(start: 0, duration: 1))
        let bgmClip = Clip(id: clipB, assetId: bgm.id, kind: .audio,
                           sourceRange: TimeRange(start: 0, duration: 4),
                           timelineRange: TimeRange(start: 0, duration: 4))
        return Project(
            name: "promo-duck",
            mediaLibrary: MediaLibrary(assets: [voice.id: voice, bgm.id: bgm]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [voiceClip, bgmClip]),
            ]))
    }

    /// loud(0.5s)–silence(0.8s)–loud(0.5s) — the proven synthesis shape from
    /// SilenceDetectionProviderTests (0.8s stays above the 0.35s minimum
    /// even after chunk quantization).
    private static func silenceProject(url: URL) throws -> Project {
        let sampleRate = 44_100.0
        func tone(_ count: Int, freq: Double) -> [Float] {
            (0..<count).map { i in Float(sin(2 * .pi * freq * Double(i) / sampleRate) * 0.5) }
        }
        let samples = tone(22_050, freq: 440)
            + Array(repeating: Float(0), count: 35_280)
            + tone(22_050, freq: 440)
        var data = Data()
        func le16(_ v: Int16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func le32(_ v: Int32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        let dataSize = samples.count * 2
        data.append(contentsOf: "RIFF".utf8); le32(Int32(36 + dataSize)); data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8); le32(16); le16(1); le16(1)
        le32(Int32(sampleRate)); le32(Int32(sampleRate * 2)); le16(2); le16(16)
        data.append(contentsOf: "data".utf8); le32(Int32(dataSize))
        samples.forEach { le16(Int16(max(-1, min(1, $0)) * 32767)) }
        try data.write(to: url)

        let asset = MediaAsset(originalURL: url, kind: .audio, duration: 1.8)
        let clip = Clip(id: clipA, assetId: asset.id, kind: .audio,
                        sourceRange: TimeRange(start: 0, duration: 1.8),
                        timelineRange: TimeRange(start: 0, duration: 1.8))
        return Project(
            name: "promo-silence",
            mediaLibrary: MediaLibrary(assets: [asset.id: asset]),
            timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [
                Track(kind: .audio, name: "A", zIndex: 0, clips: [clip]),
            ]))
    }

    // MARK: - The 100-scenario corpus

    private static func corpus() -> [Scenario] {
        var s: [Scenario] = []
        func add(_ i: String, _ e: Scenario.Expectation, _ f: Fixture = .standard) {
            s.append(Scenario(instruction: i, expectation: e, fixture: f))
        }
        let A = clipA, B = clipB, C = clipC

        // 12 range deletions (ko 6 / en 6); the last ko pair exercises
        // compound 분/초 literals (authoring intent 90/100).
        let koDeletes: [(String, Double, Double)] = [
            ("2초부터 6초까지 삭제해줘", 2, 6),
            ("0.5초부터 3.5초까지 지워줘", 0.5, 3.5),
            ("3초부터 8초까지 삭제", 3, 8),
            ("6초부터 9.5초까지 잘라내서 삭제", 6, 9.5),
            ("10초부터 11초까지 삭제", 10, 11),
            ("1분 30초부터 1분 40초까지 삭제해줘", 90, 100),
        ]
        for (instruction, lo, hi) in koDeletes {
            add(instruction, .actions([.deleteTimelineRange(start: lo, end: hi)]))
        }
        let enDeletes: [(Double, Double)] = [(2, 6), (0.5, 3.5), (3, 8), (6, 9.5), (10, 11), (90, 100)]
        for (lo, hi) in enDeletes {
            add("please delete from \(lo)s to \(hi)s", .actions([.deleteTimelineRange(start: lo, end: hi)]))
        }

        // 8 keep-only.
        let keepPairs: [(Double, Double)] = [(2, 6), (1, 9), (0.5, 2), (8, 11)]
        for (lo, hi) in keepPairs {
            add("\(lo)초부터 \(hi)초까지만 남겨줘", .actions([.keepTimelineRange(start: lo, end: hi)]))
            add("keep only \(lo)s to \(hi)s", .actions([.keepTimelineRange(start: lo, end: hi)]))
        }

        // 8 splits (default target = clipB 4-10s; "first clip" = clipA 0-4s).
        for t in [5.0, 7.5] {
            add("\(t)초에서 잘라줘", .actions([.splitClip(clipId: B, time: t)]))
            add("split at \(t)s", .actions([.splitClip(clipId: B, time: t)]))
        }
        for t in [1.0, 3.0] {
            add("첫 번째 클립 \(t)초에서 잘라", .actions([.splitClip(clipId: A, time: t)]))
            add("split the first clip at \(t)s", .actions([.splitClip(clipId: A, time: t)]))
        }

        // 14 volumes.
        add("볼륨 절반으로", .actions([.setVolume(clipId: B, volume: 0.5)]))
        add("볼륨 50%로 낮춰줘", .actions([.setVolume(clipId: B, volume: 0.5)]))
        add("첫 번째 클립 볼륨 30%", .actions([.setVolume(clipId: A, volume: 0.3)]))
        add("볼륨 0.8로", .actions([.setVolume(clipId: B, volume: 0.8)]))
        add("마지막 클립 볼륨 150%", .actions([.setVolume(clipId: C, volume: 1.5)]))
        add("clip 2 volume 25%", .actions([.setVolume(clipId: B, volume: 0.25)]))
        add("set volume to 0.3", .actions([.setVolume(clipId: B, volume: 0.3)]))
        add("volume 75%", .actions([.setVolume(clipId: B, volume: 0.75)]))
        add("volume of the 2nd clip to 40%", .actions([.setVolume(clipId: B, volume: 0.4)]))
        add("clip 3 volume 10%", .actions([.setVolume(clipId: C, volume: 0.1)]))
        add("set volume to 1.5", .actions([.setVolume(clipId: B, volume: 1.5)]))
        add("volume 200%", .actions([.setVolume(clipId: B, volume: 2)]))
        add("set volume of clip 1 to 0.05", .actions([.setVolume(clipId: A, volume: 0.05)]))
        add("볼륨 1로 설정해줘", .actions([.setVolume(clipId: B, volume: 1)]))

        // 10 speeds.
        add("2배속으로", .actions([.setSpeed(clipId: B, rate: 2)]))
        add("첫 번째 클립 0.5배속", .actions([.setSpeed(clipId: A, rate: 0.5)]))
        add("마지막 클립 3배속", .actions([.setSpeed(clipId: C, rate: 3)]))
        add("1.5배속 적용", .actions([.setSpeed(clipId: B, rate: 1.5)]))
        add("속도 50%", .actions([.setSpeed(clipId: B, rate: 0.5)]))
        add("set speed to 2x", .actions([.setSpeed(clipId: B, rate: 2)]))
        add("speed of the 3rd clip to 0.5x", .actions([.setSpeed(clipId: C, rate: 0.5)]))
        add("set speed to 1.5", .actions([.setSpeed(clipId: B, rate: 1.5)]))
        add("clip 1 speed 4x", .actions([.setSpeed(clipId: A, rate: 4)]))
        add("speed 75%", .actions([.setSpeed(clipId: B, rate: 0.75)]))

        // 8 presets (4 × 2 languages).
        let presets: [(EqualizerPresetID, String, String)] = [
            (.voiceEnhance, "음성 강조 적용해줘", "apply voice enhance"),
            (.bassBoost, "베이스 부스트로", "apply bass boost"),
            (.trebleBoost, "고음 부스트 적용", "apply treble boost"),
            (.flat, "이퀄라이저 플랫으로 초기화", "reset eq to flat"),
        ]
        for (preset, ko, en) in presets {
            add(ko, .actions([.applyAudioPreset(clipId: B, preset: preset)]))
            add(en, .actions([.applyAudioPreset(clipId: B, preset: preset)]))
        }

        // 6 ducking (real analysis fixture; ordinals name the voice clip).
        add("첫 번째 클립 배경음악 덕킹해줘", .actions([.duckBackground(speechClipId: A)]), .duck)
        add("1번째 클립에 덕킹 적용", .actions([.duckBackground(speechClipId: A)]), .duck)
        add("덕킹해줘", .actions([.duckBackground(speechClipId: B)]), .duck)
        add("duck the background under the first clip", .actions([.duckBackground(speechClipId: A)]), .duck)
        add("duck under clip 1", .actions([.duckBackground(speechClipId: A)]), .duck)
        add("please duck", .actions([.duckBackground(speechClipId: B)]), .duck)

        // 4 silence removal (real analysis fixture; clip A is the only clip).
        add("무음 제거해줘", .actions([.removeSilence(clipId: A)]), .silence)
        add("첫 번째 클립 무음 제거", .actions([.removeSilence(clipId: A)]), .silence)
        add("remove the silence", .actions([.removeSilence(clipId: A)]), .silence)
        add("remove the silence in the last clip", .actions([.removeSilence(clipId: A)]), .silence)

        // 10 ordinal-mixed property intents.
        add("clip 2 volume 20%", .actions([.setVolume(clipId: B, volume: 0.2)]))
        add("3rd clip volume 60%", .actions([.setVolume(clipId: C, volume: 0.6)]))
        add("첫 번째 클립 음성 강조", .actions([.applyAudioPreset(clipId: A, preset: .voiceEnhance)]))
        add("마지막 클립 트레블 부스트", .actions([.applyAudioPreset(clipId: C, preset: .trebleBoost)]))
        add("2nd clip speed 0.5x", .actions([.setSpeed(clipId: B, rate: 0.5)]))
        add("첫 번째 클립 속도 2배속", .actions([.setSpeed(clipId: A, rate: 2)]))
        add("1st clip volume 45%", .actions([.setVolume(clipId: A, volume: 0.45)]))
        add("마지막 클립 볼륨 0.1로", .actions([.setVolume(clipId: C, volume: 0.1)]))
        add("clip 3 bass boost", .actions([.applyAudioPreset(clipId: C, preset: .bassBoost)]))
        add("두 번째 클립 볼륨 절반", .actions([.setVolume(clipId: B, volume: 0.5)]))

        // 20 invalid (typed rejections).
        add("오늘 날씨 어때?", .fails(.unrecognized("오늘 날씨 어때?")))
        add("what is the weather", .fails(.unrecognized("what is the weather")))
        add("ffmpeg로 인코딩해줘", .fails(.unrecognized("ffmpeg로 인코딩해줘")))
        add("make it cinematic", .fails(.unrecognized("make it cinematic")))
        add("삭제해줘", .fails(.unrecognized("삭제해줘")))
        add("delete something", .fails(.unrecognized("delete something")))
        add("잘라줘", .fails(.noTime))
        add("split it", .fails(.noTime))
        add("5번째 클립 볼륨 50%", .fails(.clipOrdinal(5, count: 3)))
        add("volume of the 99th clip to 10%", .fails(.clipOrdinal(99, count: 3)))
        add("4th clip speed 2x", .fails(.clipOrdinal(4, count: 3)))
        add("10번째 클립 음성 강조", .fails(.clipOrdinal(10, count: 3)))
        add("split at 0.5배속", .fails(.noTime))
        add("잘라줘 근데 언제?", .fails(.noTime))
        // Volume/edge rejections the grammar must not paper over.
        add("볼륨을 좀 적당히 해줘", .fails(.unrecognized("볼륨을 좀 적당히 해줘")))
        add("speed up a bit", .fails(.unrecognized("speed up a bit")))
        // Empty-timeline rejections (fixture override happens at run time).
        add("무음 제거해줘", .fails(.noClips))
        add("remove the silence", .fails(.noClips))
        add("덕킹해줘", .fails(.noClips))
        add("2초부터 6초까지 삭제해줘", .fails(.noClips))

        return s
    }

    // MARK: - The four axes

    @Test("Promotion axes: validity ≥95%, intent match ≥90%, unrecoverable 0, undo 100%")
    func promotionMeasurement() async throws {
        let scenarios = Self.corpus()
        #expect(scenarios.count == 100, "the corpus is exactly 100 scenarios (got \(scenarios.count))")

        // Fixtures: the two invalid "noClips" rows run against an empty project.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("p3_promo_silence_\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        func project(for fixture: Fixture, expectation: Scenario.Expectation) throws -> Project {
            switch fixture {
            case .standard:
                // The noClips rejections reuse the standard row but must see
                // an empty timeline — the corpus marks them by expectation.
                if case .fails(.noClips) = expectation {
                    return Project(name: "empty", timeline: Timeline(
                        canvasSize: CGSize(width: 320, height: 240),
                        tracks: [Track(kind: .video, name: "V", zIndex: 0, clips: [])]))
                }
                return Self.standardProject()
            case .duck: return Self.duckProject()
            case .silence: return try Self.silenceProject(url: tempURL)
            }
        }

        var validTotal = 0, validValid = 0
        var match = 0
        var applyTotal = 0, undoRestored = 0
        var failures: [String] = []

        for scenario in scenarios {
            let project = try project(for: scenario.fixture, expectation: scenario.expectation)

            // --- plan + intent axes ---
            switch scenario.expectation {
            case .actions(let expected):
                validTotal += 1
                do {
                    let planned = try EditingIntentPlanner.plan(instruction: scenario.instruction, for: project)
                    let kernelValid = planned.actions.allSatisfy {
                        (try? EditingActionDSL.plan($0, for: project)) != nil
                    }
                    if kernelValid { validValid += 1 }
                    if planned.actions == expected { match += 1 }
                    else { failures.append("intent mismatch: \(scenario.instruction)") }

                    // --- apply/undo axis (valid scenarios only) ---
                    applyTotal += 1
                    let session = EditorSession(project: project)
                    do {
                        try await EditingActionApplier.apply(planned.actions, to: session)
                        try await session.undo()
                        var before = project
                        var after = await session.snapshot()
                        before.updatedAt = .distantPast
                        after.updatedAt = .distantPast
                        if before == after { undoRestored += 1 }
                        else { failures.append("undo mismatch: \(scenario.instruction)") }
                    } catch {
                        failures.append("apply threw: \(scenario.instruction) — \(error)")
                    }
                } catch {
                    failures.append("planner threw on valid row: \(scenario.instruction) — \(error)")
                }
            case .fails(let expected):
                do {
                    _ = try EditingIntentPlanner.plan(instruction: scenario.instruction, for: project)
                    failures.append("invalid row planned: \(scenario.instruction)")
                } catch let error as EditingIntentPlanner.PlannerError {
                    if error == expected { match += 1 }
                    else { failures.append("wrong rejection: \(scenario.instruction) — \(error)") }
                } catch {
                    failures.append("unexpected error type: \(scenario.instruction) — \(error)")
                }
            }
        }

        let validity = Double(validValid) / Double(validTotal)
        let intentMatchRate = Double(match) / Double(scenarios.count)
        let undoRate = Double(undoRestored) / Double(applyTotal)

        // Pre-registered thresholds.
        #expect(validity >= 0.95, "plan validity \(validValid)/\(validTotal) = \(validity)")
        #expect(intentMatchRate >= 0.90, "intent match \(match)/\(scenarios.count) = \(intentMatchRate)")
        #expect(undoRestored == applyTotal, "undo recovery \(undoRestored)/\(applyTotal) = \(undoRate)")
        print("P3 promotion axes: validity \(validValid)/\(validTotal)=\(validity) intentMatch \(match)/\(scenarios.count)=\(intentMatchRate) undoRecovery \(undoRestored)/\(applyTotal)=\(undoRate)")

        if !failures.isEmpty {
            let head = failures.prefix(8).joined(separator: "\n")
            Issue.record("axis failures (\(failures.count)):\n\(head)")
        }
    }
}
