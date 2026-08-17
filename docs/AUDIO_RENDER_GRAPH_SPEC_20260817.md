# G-25 오디오 렌더 그래프 설계 명세 — AudioRenderGraphSpec (초안 v1, 2026-08-17)

> **문서 지위**: `DEVELOPMENT_DIRECTION_20260815.md` §4.1을 구현 가능한 명세로 전개한 초안이다.
> **승인 요청 상태** — 사용자 승인 후 EXECUTION_PLAN §3 Inc 7(Core 모델)·Inc 8(엔진 생성기+null test)·Inc 9(UI·미터)가 착수된다(§8 에스컬레이션 지점).
> 승인 전 수정 요청은 이 문서에 반영 후 재요청한다. 원칙: 프리뷰와 출력은 **같은 명세에서 각자 그래프를 생성**하며, 그 외 어떤 경로도 오디오 픽셀(샘플)을 만들지 않는다.

---

## 0. 목표와 비목표

**목표(1단계 G-25)**: 게인/페이드/팬/채널 매핑/믹싱/미터(LUFS·true-peak)의 프리뷰↔출력 동일성을 구조로 보장한다.
**비목표(2단계 G-26)**: 컴프레서·리미터·리버브 등 프로세서 확장. 기존 EQ/NR/덕킹의 **destructive 파생 미디어 경로는 현행 유지** — 그래프는 파생 미디어를 Source의 하나로 취급해 소비만 한다(교체는 G-26).

## 1. 그래프 구조 (방향 문서 §4.1 그대로, 명세화)

```text
AudioRenderGraphSpec
 ├─ sources[]        : 원본 미디어 또는 버전 기록된 파생 미디어(스템 등 ML 결과)
 ├─ clipStrips[]     : 클립 단위 처리 체인
 │    채널 매핑 → 게인/페이드 → [정리(NR·ML)*] → [EQ]* → [컴프레서]* → [크리에이티브 FX]* → 팬
 ├─ trackBuses[]     : 트랙 단위
 │    서밍 → 사이드체인 덕킹 → [트랙 프로세서]* → 페이더 → 미터
 └─ masterBus        : [마스터 EQ]* → [리미터]* → LUFS/true-peak 미터 → 인코더
```
`*` 표기 노드는 1단계 명세에는 **자리만 존재**(빈 배열 직렬화)하고 소비 엔진은 미구현 노드를 만나면 거부한다(§5. 스키마 `nodeKind` 참조). 이 규칙이 "명세가 구현을 앞서 거짓 프리뷰"를 만드는 것을 막는다.

## 2. 직렬화 스키마 (Swift Codable, Project 스키마와 별개 파일)

```swift
// Sources/MovieCutCore/Audio/AudioRenderGraphSpec.swift (Inc 7 산출물 예정)
public struct AudioRenderGraphSpec: Codable, Sendable, Equatable {
    public var version: Int                      // 스키마 버전, 1로 시작
    public var sources: [AudioGraphSource]       // id, kind(original|derived), url, derivedFrom?, algorithmVersion?
    public var clipStrips: [AudioGraphClipStrip] // clipId, sourceId, channelMapping, gain automation, fades, pan, disabledNodeKinds[]
    public var trackBuses: [AudioGraphTrackBus]  // trackId, inputStripIds, fader automation, mute, solo, ducking?
    public var masterBus: AudioGraphMasterBus    // fader automation, limiter?, targetLoudness?
    public var timebase: AudioGraphTimebase      // §3
    public var rendering: AudioGraphRenderRules  // §4 latency 규칙 포함
}
```

- **Codable 규칙**: 모든 선택 노드 배열은 `encodeIfPresent`+`decodeIfPresent`(빈 그래프 프로젝트의 JSON 바이트 안정 — 프로젝트 스키마 체인과 동일 원칙). 스키마 변경 시 `version` 상향 + 마이그레이션 테스트.
- 자동화 값은 아래 타임베이스 좌표로만 저장된다.

## 3. 샘플 시간 타임베이스 (설계 규칙 ①)

모든 자동화 지점(게인·페이더·팬)의 시간 좌표는 **오디오 샘플 위치(Int64, 그래프 기준 sample rate의 샘플 수)**로 저장한다. **초 단위 저장 금지**.

```swift
public struct AudioGraphAutomationPoint: Codable, Sendable, Equatable {
    public var samplePosition: Int64   // 그래프 시점(0)부터의 샘플 수
    public var value: Double           // 게인 dB, 팬 -1…1 등
}
```

- 이유: 혼합 sample rate(48k/44.1k) 프로젝트에서 초 좌표는 반올림으로 프리뷰↔출력 샘플 정렬이 어긋난다(방향 문서 "60분 drift ≤ 1프레임" 게이트의 원천). 샘플 좌표는 정수라 재현 가능.
- **타임베이스 선언**: `AudioGraphTimebase { sampleRate: Double, origin: CMTime }(직렬화는 origin을 rational 문자열 "num/den"으로)`. 엔진은 재생/출력 시각을 이 타임베이스로 변환 후 그래프를 평가한다. 혼합 rate 소스는 각 source에 `nativeSampleRate`를 선언하고 엔진이 그래프 rate로 리샘플(정책: 그래프 rate = 마스터 출력 rate, 기본 48k).

## 4. 노드 latency 선언·look-ahead 보상 (설계 규칙 ②)

```swift
public struct AudioGraphNodeLatency: Codable, Sendable, Equatable {
    public var nodeKind: AudioGraphNodeKind   // .eq, .limiter, …
    public var algorithmVersion: String       // §6 프리셋 버전과 동일 체계
    public var reportedLatencySamples: Int64  // 노드가 선언하는 고정 latency
    public var lookAheadSamples: Int64        // 미래 샘플 필요량(컴프레서 등)
}
```

- 각 프로세서 노드는 `rendering.declaredLatencies[]`에 latency를 **선언**한다. 엔진은 그래프 빌드 시 **최대 look-ahead만큼 전체 파이프라인을 시점 앞당겨 읽고 출력 시점에 되돌린다**(단일 글로벌 보상 — 노드별 개별 보상은 정렬 오류 원인).
- 프리뷰=출력 보장: 두 엔진이 같은 `declaredLatencies`에서 같은 보상값을 계산한다(보상 계산은 Core의 순수 함수).
- 1단계 구현 노드(믹서·페이드·팬·매핑)는 latency 0이지만 **경로가 처음부터 존재**해야 2단계 프로세서 추가가 스키마 변경 없이 가능하다.

## 5. 노드 종류와 지원 선언

```swift
public enum AudioGraphNodeKind: String, Codable, Sendable {
    case channelMapping, gainFade, pan, summing, ducking, fader, meter, encoder   // 1단계 지원
    case noiseReduction, mlStem, eq, compressor, creativeFX, masterEQ, limiter    // 자리만(미구현 → 소비 시 거부)
}
```
엔진 생성기는 그래프에 미지원 `nodeKind`가 있으면 **명시적 오류**(조용한 무시 금지 — 미지원 케이스 품질 강등 금지 원칙).

## 6. 프리셋 알고리즘 버전 (설계 규칙 ④)

모든 프리셋(덕킹·SNS 라우드니스 등)은 `presetAlgorithmVersion: String`(semantic: "1.0.0")을 포함하고 파생 미디어·그래프 저장 시 기록된다. 재오픈 시 버전이 다르면: 같은 파생 미디어를 재사용(재현성 우선)하고 UI에 "이전 알고리즘으로 렌더됨" 표시. 재생성은 사용자 명시 실행만.

## 7. SNS "좋은 소리" 프리셋 목표 (내부 기준, 방향 문서 그대로)

마스터 -16~-14 LUFS-I / true peak ≤ -1 dBTP / 장면 내 대사 short-term ±2~3 LU / BGM 대사보다 -8~-16 dB. 플랫폼 공식 아님 — 미터 표시용 기준선이며 자동 강제 아님.

## 8. AAC 사후 검사 (설계 규칙 ③, 출력 품질 관문)

출력 완료 후 인코딩된 파일을 **재디코딩**해 검사한다(인코더 전 PCM이 아닌 실제 파일):

```text
1. 재디코드 PCM ↔ 그래프 렌더 PCM 대조: 길이(±1 샘플), RMS 차이 보고
2. LUFS-I / true-peak 측정 → 목표 초과 시 경고(차단 아님, 1단계)
3. 클리핑(연속 0dBFS 샘플) 검사 → 발견 시 경고
```
구현: AVAudioFile 재디코드 + Core 측정 함수(단위 테스트로 고정). E2E 스크립트(`run_e2e_export.sh`)에 게이트로 편입.

## 9. 프리뷰↔출력 null test 절차 (설계 규칙 ⑤, Inc 8 게이트)

1. **동일 그래프**로 (a) 프리뷰 엔진 렌더 PCM(`renderCurrentPreviewAudio` 확장), (b) 출력 엔진 렌더 PCM(인코더 입력 단계) 생성.
2. 정렬: latency 보상 후 샘플 오프셋 탐색(±1 샘플 내 최적) → **±1 샘플 정렬** 게이트.
3. 차이: 전 구간에서 최대 절대 편차 ≤ 1 LSB(16비트 기준) → null test PASS.
4. 드리프트: 혼합 sample rate 60분 더미 프로젝트로 종료점 샘플 위치 오차 ≤ 1 비디오 프레임에 해당하는 샘플 수.
5. 자동화: 상시 테스트(정확히는 위 절차를 `swift test`와 E2E 양쪽에 두되, 실측 판정은 E2E만).

## 10. 구현 증분 매핑 (EXECUTION_PLAN §3)

| 증분 | 산출 | 이 문서의 절 |
|---|---|---|
| Inc 7 | `AudioRenderGraphSpec.swift` Core 모델 + Codable + 단위 테스트(렌더링 없음) | §2·§3·§5 |
| Inc 8 | AVAudioEngine(프리뷰)·출력 인코더 생성기 + null test 자동화 + latency 보상 Core 함수 | §4·§9 |
| Inc 9 | 트랙/마스터 미터·mute/solo·팬 UI + 재구성 비용 측정 + §8 AAC 사후 검사 게이트 | §7·§8 |

## 11. 완료 판정(방향 문서 1단계 게이트 직결)

① 프리뷰↔출력 null test 통과(±1 샘플) ② 동일 PCM ③ 60분 drift ≤ 1프레임 ④ LUFS/true-peak 미터 실측값 표시 ⑤ 기존 오디오 E2E(EQ/NR/덕킹 RMS·Goertzel) 무회귀.

---

**사용자 승인 요청**: 위 명세(특히 §3 샘플 타임베이스, §4 글로벌 latency 보상, §5 미지원 노드 거부 정책, §8 사후 검사 경고-차단 구분)에 대한 승인 또는 수정 지시를 요청한다. 승인 시 Inc 7부터 착수.
