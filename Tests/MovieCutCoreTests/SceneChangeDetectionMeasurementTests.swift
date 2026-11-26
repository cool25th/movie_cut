import AVFoundation
import Foundation
import Testing

@testable import MovieCutCore

/// CA-21 measurement step (백로그 §0.5.1 — "측정 단계만 승인"): Edit
/// Detection(SceneChangeProvider)의 precision/recall을 사전등록 임계값으로
/// 측정한다. UI 착수 승인은 이 보고의 통과 여부에 달려 있다(미통과 시
/// 명시적 실패 기록).
///
/// 사전등록(측정 실행 전 고정 — 결과를 보고 조정하지 않는다):
///   T1 recall    ≥ 0.80  — 경계 컷(이질 장면 교대) 회수, 매칭 허용오차
///                          ±1 샘플 간격(기본 2fps → ±0.5s: 검출 타임스탬프는
///                          컷 이후 첫 샘플에 찍힌다)
///   T2 precision ≥ 0.80  — 검출의 경계 컷 대응률
///   T3 무컷 대조 오검출 = 0 — 단색 10s에서 검출되면 안 됨
///   T4 실계열(모션 포함) 오검출 ≤ 세그먼트당 1 — 같은 장면 내 모션이
///                          컷으로 오판되면 안 됨(히스토그램은 모션에 둔감)
///   T5 RTF ≤ 1.0 — 측정 wall-time/재생 길이(2fps 샘플링·오프라인 분석)
///
/// 매니페스트(env CA21_MANIFEST, JSON 배열)가 없으면 스킵 — 일반 swift
/// test 회귀에 측정 비용을 물리지 않는다. 게이트 드라이버(셸)는 이 테스트의
/// 판정 라인이 실제 인쇄됐는지 검사해야 한다(0-tests 가짜그린 방지).
@Suite("CA-21 scene-change measurement")
struct SceneChangeDetectionMeasurementTests {
    /// A cut detection matches ground truth when it lands within one sample
    /// interval of the true cut (the provider timestamps the first sample
    /// AFTER the cut at the default 2 fps grid).
    private static let matchTolerance: TimeInterval = 0.5

    struct FixtureSpec: Decodable {
        var file: String
        var class_: String?
        var expectedCuts: [TimeInterval]

        enum CodingKeys: String, CodingKey {
            case file
            case class_ = "class"
            case expectedCuts = "expected_cuts"
        }
    }

    private func loadManifest() throws -> [FixtureSpec] {
        guard let path = ProcessInfo.processInfo.environment["CA21_MANIFEST"] else {
            return []
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode([FixtureSpec].self, from: data)
    }

    @Test("measures precision/recall against pre-registered thresholds",
          .enabled(if: ProcessInfo.processInfo.environment["CA21_MANIFEST"] != nil))
    func measure() async throws {
        let fixtures = try loadManifest()
        guard !fixtures.isEmpty else {
            Issue.record("CA21_MANIFEST set but empty/undecodable — the gate driver must provide fixtures")
            return
        }

        // Product path: default configuration (samplingFPS 2, threshold 0.3)
        // — exactly what detectAndSplitScenes ships.
        let provider = SceneChangeProvider()

        var totalGT = 0
        var totalMatched = 0
        var totalDetections = 0
        var worstRTF = 0.0
        var failures: [String] = []

        for spec in fixtures {
            let assetId = UUID()
            let asset = MediaAsset(id: assetId, originalURL: URL(fileURLWithPath: spec.file), kind: .video)
            let project = Project(
                name: "ca21",
                mediaLibrary: MediaLibrary(assets: [assetId: asset]),
                timeline: Timeline(canvasSize: CGSize(width: 320, height: 240), tracks: [])
            )

            let clock = ContinuousClock()
            let start = clock.now
            let result = try await provider.analyze(asset: asset, in: project)
            let elapsed = {
                let c = start.duration(to: .now).components
                return Double(c.seconds) + Double(c.attoseconds) / 1e18
            }()

            var detections: [TimeInterval] = []
            for suggestion in result.suggestions {
                if case .sceneChanges(let times) = suggestion {
                    detections = times
                }
            }
            let duration = try await AVURLAsset(url: asset.originalURL).load(.duration).seconds
            let rtf = elapsed / max(duration, 0.001)
            worstRTF = max(worstRTF, rtf)

            // Greedy nearest matching within tolerance, each GT matched once.
            var unmatchedGT = spec.expectedCuts
            var matched = 0
            for det in detections.sorted() {
                if let idx = unmatchedGT.firstIndex(where: { abs($0 - det) <= Self.matchTolerance }) {
                    unmatchedGT.remove(at: idx)
                    matched += 1
                }
            }
            let falsePositives = detections.count - matched

            totalGT += spec.expectedCuts.count
            totalMatched += matched
            totalDetections += detections.count

            let tag = spec.class_ ?? "unknown"
            print(String(format: "CA21MEASURE class=%@ file=%@ gt=%d det=%d matched=%d fp=%d rtf=%.3f dets=[%@]",
                         tag, (spec.file as NSString).lastPathComponent,
                         spec.expectedCuts.count, detections.count, matched, falsePositives, rtf,
                         detections.map { String(format: "%.2f", $0) }.joined(separator: ",")))

            // T3: a no-cut control must detect nothing.
            if tag == "no_cut" && detections.count > 0 {
                failures.append(String(format: "T3 no-cut control detected %d change(s)", detections.count))
            }
            // T4: real-content fixtures allow at most 1 false positive each
            // (motion within a scene must not read as a cut).
            if tag.hasPrefix("real") && falsePositives > 1 {
                failures.append(String(format: "T4 %@ false positives %d > 1", tag, falsePositives))
            }
        }

        let recall = totalGT > 0 ? Double(totalMatched) / Double(totalGT) : 1
        let precision = totalDetections > 0 ? Double(totalMatched) / Double(totalDetections) : 1

        print(String(format: "CA21SUMMARY recall=%.3f precision=%.3f worst_rtf=%.3f", recall, precision, worstRTF))
        if recall < 0.80 { failures.append(String(format: "T1 recall %.3f < 0.80", recall)) }
        if precision < 0.80 { failures.append(String(format: "T2 precision %.3f < 0.80", precision)) }
        if worstRTF > 1.0 { failures.append(String(format: "T5 RTF %.3f > 1.0", worstRTF)) }

        if failures.isEmpty {
            print("CA21 VERDICT: PASS — all pre-registered thresholds met")
        } else {
            print("CA21 VERDICT: FAIL — \(failures.joined(separator: "; "))")
            Issue.record("CA-21 pre-registered thresholds not met: \(failures.joined(separator: "; "))")
        }
        #expect(failures.isEmpty)
    }
}
