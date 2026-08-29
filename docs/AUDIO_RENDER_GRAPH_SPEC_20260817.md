> (2026-08-22) **이행 완료** — G-25 믹싱 골격(세션29·null test·드리프트 0), G-26 프로세서 기본선(세션50), 그래프 직렬화(세션57), 마스터 체인 UI(세션59)까지 반영 완료. 본 문서는 이제 구현 사양의 원천이며 새 기능 확장 시에만 갱신한다.

# G-25 오디오 렌더 그래프 설계 명세 — AudioRenderGraphSpec (v1.1, 2026-08-18)

> **문서 지위**: `DEVELOPMENT_DIRECTION_20260815.md` §4.1을 구현 가능한 명세로 전개한 문서. v1(2026-08-17) 승인으로 Inc 7·8·9 완료. **v1.1(2026-08-18) 승인됨** — 제품 경로 전환 증분이 이 의미론으로 착수된다: ① 덕킹의 그래프 내 위치(§1.1 신설), ② EQ/NR 소비 규칙(§0), ③ 소스 정규화 정책(§3.1 신설). **스키마(Codable)는 불변 — `version: 1` 유지, 마이그레이션 없음.**
> 원칙(불변): 프리뷰와 출력은 **같은 명세에서 각자 그래프를 생성**하며, 그 외 어떤 경로도 오디오 픽셀(샘플)을 만들지 않는다.

## 변경 이력

- **v1.1(2026-08-18, 승인됨)**: ① §1.1 신설 — 1단계 덕킹은 플래너 산출물의 **스트립 게인 자동화 구체화**로 확정(버스 사이드체인 노드·`AudioGraphDucking`은 G-26 슬롯으로 명시). ② §0의 "EQ/NR 파생 미디어 경로 현행 유지"를 실상에 맞게 수정 — EQ/NR은 프리뷰(실시간 tap)·출력(파생 미디어) 이중 경로였고, 그래프는 클립의 **유효 오디오 미디어**를 소스로 소비하며 프리뷰 tap은 폐지. ③ §3.1 신설 — 소스 정규화(비디오 컨테이너 디코드·리샘플·속도/리버스 사전 렌더)는 엔진 어댑터가 소유하고 렌더러의 비율 판독은 합성 더미 폴백으로 한정. §8 과도기 기준·§11⑤ 무회귀 판정 기준 명시.
- **v1(2026-08-17)**: 초안 승인 → Inc 7(Core 모델)·Inc 8(엔진 생성기+null test)·Inc 9(미터·solo·§8 게이트) 완료.

---

## 0. 목표와 비목표

**목표(1단계 G-25)**: 게인/페이드/팬/채널 매핑/믹싱/미터(LUFS·true-peak)의 프리뷰↔출력 동일성을 구조로 보장한다.
**비목표(2단계 G-26)**: 컴프레서·리미터·리버브 등 프로세서 확장. 기존 EQ/NR/덕킹의 **destructive 파생 미디어 경로는 현행 유지** — 그래프는 파생 미디어를 Source의 하나로 취급해 소비만 한다(교체는 G-26).

**EQ/NR 소비 규칙(v1.1 — §0 본문 수정)**: v1의 "파생 미디어 경로 현행 유지"는 출력 경로에만 부합하는 서술이었다. 실상은 이중 경로다 — 프리뷰는 실시간 처리(EQ: `MTAudioProcessingTap`, NR: AVAudioEngine 필터), 출력은 파생 미디어 렌더(EQ: `MovieCutEQ-*.caf` 임시 파일). v1.1부터:

- 그래프 소스는 클립의 **유효 오디오 미디어**다. EQ/NR이 적용된 클립의 유효 미디어는 그 적용 결과물(파생)이며, `AudioGraphSource(kind: .derived, derivedFrom: 원본 id, algorithmVersion: §6 체계)`로 표현한다. 적용 없음 = 원본(`kind: .original`).
- 파생 산출은 **엔진 어댑터가 렌더 시점에 수행**한다(현 출력 경로와 동일한 알고리즘·프리셋 버전 기록). 그래프가 파생을 다시 계산하지 않는다는 §0 원칙은 유지된다.
- **프리뷰의 실시간 tap/필터 경로는 audioMix 경로 은퇴와 함께 폐지한다.** 이중 경로가 곧 프리뷰↔출력 불일치의 원인이며, "그 외 어떤 경로도 샘플을 만들지 않는다" 원칙이 실시간 처리 경로의 존속을 허용하지 않는다.

## 1. 그래프 구조 (방향 문서 §4.1 그대로, 명세화)

```text
AudioRenderGraphSpec
 ├─ sources[]        : 원본 미디어 또는 버전 기록된 파생 미디어(스템 등 ML 결과)
 ├─ clipStrips[]     : 클립 단위 처리 체인
 │    채널 매핑 → 게인/페이드 → [정리(NR·ML)*] → [EQ]* → [컴프레서]* → [크리에이티브 FX]* → 팬
 ├─ trackBuses[]     : 트랙 단위
 │    서밍 → 사이드체인 덕킹(G-26 자리†) → [트랙 프로세서]* → 페이더 → 미터
 └─ masterBus        : [마스터 EQ]* → [리미터]* → LUFS/true-peak 미터 → 인코더
```
`*` 표기 노드는 1단계 명세에는 **자리만 존재**(빈 배열 직렬화)하고 소비 엔진은 미구현 노드를 만나면 거부한다(§5. 스키마 `nodeKind` 참조). 이 규칙이 "명세가 구현을 앞서 거짓 프리뷰"를 만드는 것을 막는다.
`†` 1단계 덕킹은 버스 사이드체인이 아니라 **§1.1의 스트립 게인 자동화 구체화**로 렌더된다 — 버스의 `ducking` 슬롯은 미사용(G-26용 자리).

### 1.1 덕킹의 1단계 의미론(v1.1 신설 — 구체화 방식으로 확정)

v1의 "트랙 버스 사이드체인 덕킹(엔진이 배선 소유)"은 이 제품의 실제 덕킹 모델과 맞지 않음이 제품 경로 전환(빌더 작성)에서 확인되었다. 이 제품의 덕킹은 실시간 사이드체인이 아니라 **편집 시점에 `AudioDuckingPlanner`가 계산해 클립에 저장된 클립 로컬 range 집합**이며, 버스의 `AudioGraphDucking`은 `levelDb` 하나뿐이라 range 정보를 재현할 수 없다. 1단계 덕킹은 다음과 같이 **구체화(materialization)** 한다:

- **위치**: 버스 페이더가 아니라 **클립 스트립의 게인 자동화**로 구체화한다. 덕킹은 클립 단위 속성(`Clip.duckingRanges`·`duckingLevel`)이므로 트랙 단위 페이더로는 한 버스에 섞인 여러 클립의 서로 다른 range를 표현할 수 없다.
- **좌표**: 제품 모델의 덕킹 range는 클립 로컬이지만, 그래프 자동화는 절대 그래프 샘플 좌표(§3)로만 저장한다. 빌더가 `클립 타임라인 시작 + range.start`로 리베이스한다.
- **램프 타이밍**: 현 제품 동작을 계승한다 — attack `[range.start, range.start+0.12s]`, hold, release `[range.end−0.25s, range.end]`(램프가 range **내부**에서 끝난다).
- **램프 모양**: 그래프 자동화의 표준인 **dB-선형 보간**을 쓴다(기존 audioMix의 진폭-선형 `setVolumeRamp`와 램프 중간값이 다르다). §11⑤ 덕킹 E2E가 이 차이를 측정 임계 내에서 흡수하는지 게이트로 확인하며, 회귀 시 진폭-정확 래핑(밀도 포인트 재현)으로 폴백한다.
- **페이드 윈도우 클램핑은 재현하지 않는다**: 기존 경로가 덕킹 램프를 페이드 구간 밖으로 밀어내던 것은 AVFoundation이 한 클립에 중복 볼륨 램프를 받지 못하는 기술 제약의 부산물이다. 그래프는 게인×페이드 곱 구조라 중복이 모호하지 않으므로 클램핑 없이 그대로 곱한다.
- **버스 `ducking` 슬롯·`AudioGraphDucking`**: 1단계 그래프에서는 미사용 — G-26 실시간 사이드체인용 자리로 스키마 변경 없이 유지한다.

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

### 3.1 소스 정규화 — 엔진 어댑터 소유(v1.1 신설)

그래프에 들어오는 소스 오디오는 **항상 그래프 레이트·재생 속도 1로 정규화**된다. 정규화는 엔진 어댑터의 디코드 단계가 소유하며, 오프라인 렌더러는 정규화된 소스만 읽는다:

1. **비디오 컨테이너의 임베디드 오디오**: `AVAudioFile`은 비디오 컨테이너를 읽지 못한다(오디오 전용 포맷 한정). `AVAssetReader`로 오디오 트랙을 추출한다. 오디오 트랙 없는 영상은 무음 소스로 표현한다(무음을 대체 삽입하는 조용한 실패가 아니라 그 실제 기여와 일치).
2. **리샘플**: `nativeSampleRate ≠ 그래프 rate` 소스는 `AVAudioConverter`(고품질)로 그래프 rate로 변환한다. 오프라인 렌더러의 nearest-frame 비율 판독(`AudioGraphStripActivation.playbackRate` ≠ 1)은 **합성 더미(§9.2 null test) 전용 폴백**이며 제품 경로가 사용해서는 안 된다 — 정규화된 제품 소스는 항상 비율 1로 읽힌다.
3. **속도(0.25–4)·리버스**: 속도 ≠ 1 또는 리버스 클립은 어댑터가 현 출력 경로와 동일한 AVFoundation 시간-피치 처리(`scaleTimeRange` 계열)로 사전 렌더해 속도 1 소스로 공급한다. `AudioGraphStripActivation.playbackRate`(리샘플 비율)와 제품 `Clip.playbackRate`(배속)는 **다른 개념**이다 — 필드명 혼동에 주의한다.
4. **정규화 매핑 수식**(제품 클립 로컬 좌표→절대 그래프 샘플, `sourceFrameOffset` 계산, 덕킹 리베이스 포함)은 빌더 단위 테스트로 고정한다(§9.4 정수 수학 원칙의 연장).

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

**과도기 기준(v1.1 — 2-C-3에서 이행 완료)**: Inc 9 게이트는 그래프가 제품 경로가 되기 전이므로 대조 기준을 프리뷰 믹스 렌더로 대체 사용했다(길이 ±0.5s·LUFS/RMS 관대 임계 — AAC 패딩·램프 모양 차이 흡수). **2-C-3(2026-08-19)부터 시행**: 기준 = 출력이 인코딩한 그래프 PCM 그 자체(`renderMix` 동일 정책), 재디코드 측은 상관 측정 코덱 지연(프라이밍/패딩) 트림 후 **±1 샘플 엄격 게이트**가 살아 있다(§8.1의 "트림은 호출자 책임" 조항의 구현).

## 9. 프리뷰↔출력 null test 절차 (설계 규칙 ⑤, Inc 8 게이트)

1. **동일 그래프**로 (a) 프리뷰 엔진 렌더 PCM(`renderCurrentPreviewAudio` 확장), (b) 출력 엔진 렌더 PCM(인코더 입력 단계) 생성.
2. 정렬: latency 보상 후 샘플 오프셋 탐색(±1 샘플 내 최적) → **±1 샘플 정렬** 게이트.
3. 차이: 전 구간에서 최대 절대 편차 ≤ 1 LSB(16비트 기준) → null test PASS.
4. 드리프트: 혼합 sample rate 60분 더미 프로젝트로 종료점 샘플 위치 오차 ≤ 1 비디오 프레임에 해당하는 샘플 수.
5. 자동화: 상시 테스트(정확히는 위 절차를 `swift test`와 E2E 양쪽에 두되, 실측 판정은 E2E만).

## 10. 구현 증분 매핑 (EXECUTION_PLAN §3)

| 증분 | 산출 | 이 문서의 절 |
|---|---|---|
| Inc 7 | `AudioRenderGraphSpec.swift` Core 모델 + Codable + 단위 테스트(렌더링 없음) — 완료 | §2·§3·§5 |
| Inc 8 | AVAudioEngine(프리뷰)·출력 인코더 생성기 + null test 자동화 + latency 보상 Core 함수 — 완료 | §4·§9 |
| Inc 9 | 트랙/마스터 미터·mute/solo·팬 UI + 재구성 비용 측정 + §8 AAC 사후 검사 게이트 — 완료 | §7·§8 |
| 제품 경로 전환(v1.1 승인 전제) | Project→그래프 빌더(§1.1·§3.1 의미론 반영) + 프리뷰/출력 audioMix 경로를 그래프 렌더로 대체 + §8 기준 그래프 PCM 전환(±1 샘플 엄격 게이트) | §0(v1.1)·§1.1·§3.1·§8·§11⑤ |

## 11. 완료 판정(방향 문서 1단계 게이트 직결)

① 프리뷰↔출력 null test 통과(±1 샘플) ② 동일 PCM ③ 60분 drift ≤ 1프레임 ④ LUFS/true-peak 미터 실측값 표시 ⑤ 기존 오디오 E2E(EQ/NR/덕킹 RMS·Goertzel) 무회귀 — **(v1.1) ⑤의 무회귀는 기존 경로와의 비트 동일성이 아니라 현행 측정 임계 내 무회귀를 뜻하며, 판정 대상은 그래프 의미론(§1.1의 dB-선형 덕킹 램프·클램핑 미재현 포함)의 출력이다.**

---

**사용자 승인(v1.1, 2026-08-18)**: 아래 3건이 승인되어 제품 경로 전환 증분(빌더 의미론 수정·엔진 배선·§8 그래프 PCM 전환)이 착수되었다.

1. **§1.1 덕킹 구체화** — 1단계 덕킹은 플래너 산출물의 스트립 게인 자동화 구체화(dB-선형 램프·페이드 클램핑 미재현), 버스 사이드체인 노드는 G-26 이관.
2. **§0 EQ/NR 유효 미디어 규칙** — 그래프 소스 = 클립의 유효 오디오 미디어(EQ/NR 적용 클립은 파생 결과물), 프리뷰 실시간 tap/필터 경로 폐지.
3. **§3.1 소스 정규화** — 비디오 컨테이너 `AVAssetReader` 추출·`AVAudioConverter` 리샘플·속도/리버스 사전 렌더는 엔진 어댑터 소유, 렌더러 비율 판독은 합성 더미 폴백으로 한정.

스키마는 불변(`version: 1`)이므로 마이그레이션은 수반하지 않는다.
