# MovieCut 세부 실행 계획서 — 1단계 잔여 증분 (2026-08-16)

> **문서 지위:** 본 계획서는 [`DEVELOPMENT_DIRECTION_20260815.md`](DEVELOPMENT_DIRECTION_20260815.md) §3의 고정 순서를 **실행 가능한 증분 단위로 전개**한 문서다. 우선순위 해석이 충돌하면 방향 문서가 항상 우선하며, 본 문서는 이를 임의로 변경하지 않는다.
> **작성 근거:** ① `COMPETITIVE_GAP_ANALYSIS_20260816.md`(격차 분석), ② `SESSION_HANDOFF_CURRENT.md`(최신 세션 상태), ③ 코드 실측(EditorViewModel 6,078줄, 보간 피커 존재, W1~W5 스크립트 부재 등 2026-08-16 검증).
> **목적:** 각 증분을 콜드스타트 세션이 맥락 없이 실행해도 **문제가 생기지 않도록** 범위·단계·검증·중단 조건을 세부 고정한다.

---

## 0. 이 계획이 방지하려는 문제 유형

| 문제 유형 | 실제 전례 | 본 문서의 방지 장치 |
|---|---|---|
| 완료 과대 주장(overclaim) | GAP_ANALYSIS_V6 "드래그앤드롭 ✅"이 실제 미동작 | 모든 DoD는 "preview + export 실증"(VERIFICATION_STANDARD §1) |
| 세션 간 맥락 단절 | 콜드스타트 세션이 과거 판정 오독 | 각 증분 자족적 명세 + §7 함정 레지스터 |
| 문서 간 우선순위 충돌 | 백로그 역사 판정 vs 방향 문서 | 권한 서열 고정(방향 문서 > 본 문서 > 백로그/원장) |
| 사전조건 위반 | ViewModel 비대 상태에서 UI 증분 누적 | UI 증분 직전 경계 분해 규칙(§1-6) |
| 병렬 세션 WIP 충돌 | 2026-08-16 22:15 G-23 Inc 2 수학 파일 생성(미커밋) | 프로토콜 0 시작 절차(§2) |
| 같은 버그 재발 | 프리뷰 컴포지터 메타데이터 누띩(G-23 Inc 1 발견) | 신규 시각 속성 4곳 배선 체크리스트(§7-3) |
| 일정 압박 시 임의 생략 | 게이트 조건 미충족 상태로 단계 종료 선언 | 필수/조정 가능 분류 + 에스컬레이션 규칙(§8) |

---

## 1. 공통 실행 프로토콜 (모든 증분에 무조건 적용)

### 1.1 증분 사이클

```
시작 점검 → 구현(범위 내만) → 검증(단계별 게이트) → 커밋(증분 1개 = 커밋 1개) → 문서 갱신 → 핸드오프
```

1. **시작 점검 (프로토콜 0):** `git status --short && git log --oneline -5`로 병렬 세션 WIP 여부 확인. WIP가 있으면 §2의 절차대로 처리한 뒤 신규 증분 착수. `SESSION_HANDOFF_CURRENT.md` 최상단 세션 기록 필독.
2. **구현:** 증분의 "범위 밖(OUT)" 항목은 절대 확장하지 않는다. 진행 중 발견한 범위 외 문제는 핸드오프의 "발견한 함정"에 기록하고 별도 증분/이슈로 분리한다. 사전 존재 드리프트(관련 기존 버그)는 증분에 포함해 수반 수정하되 커밋 메시지에 명시한다(G-23 Inc 1 선례).
3. **검증:** 아래 게이트 명령 표를 증분별 지정 순서대로 실행. 전체 게이트(`verify_gate.sh`)는 커밋 직전 1회 필수.
4. **커밋:** 증분 1개 = 논리적 커밋 1개 원칙(롤백 단위 보장). 커밋 메시지 형식은 기존 관행: `feat(도메인): G-xx Inc n — 요약`. WIP 절반 커밋 금지 — 부득이하면 증분을 더 잘게 쪼갠다.
5. **문서 갱신 (증분 완료 시):** ① `CAPCUT_FEATURE_BACKLOG.md` 해당 항목 상태·근거 갱신 ② `REQUIREMENTS.md` §13 체인지로그 1줄 ③ 스펙/계약이 바뀌면 `VERIFICATION_STANDARD.md`·`PERFORMANCE_SLO.md` ④ 세션 종료 시 `SESSION_HANDOFF_CURRENT.md` 최상단에 완료/함정/인계 기록.
6. **중단:** §8의 중단 조건 해당 시 즉시 멈추고 핸드오프에 상태를 남긴다. 실패를 숨기고 진행하지 않는다.

### 1.2 게이트 명령 표

| 용도 | 명령 | 비고 |
|---|---|---|
| 통합 4단계 (커밋 직전 필수) | `bash scripts/verify_gate.sh` | swift build / swift test 전체 / xcodebuild Mac / xcodebuild iOS |
| Core 국부 | `swift build && swift test --filter '<Suite명>'` | 반복 회귀용 |
| Core·앱 렌더 패리티 | `bash scripts/run_core_editing_parity.sh` | 12 시나리오 → Inc 1에서 #13 추가 |
| 실앱 E2E 출력 | `bash scripts/run_e2e_export.sh` | ffprobe/RMS/Goertzel 실측 포함 |
| 지연 SLO | `bash scripts/run_latency_baseline.sh` | 현재 수집 모드(`--enforce` 전환은 Inc 9) |
| 크래시 복구 | `bash scripts/run_recovery_gate.sh` | 저장소 변경 시 |
| UI 회귀 | `bash scripts/ui_regression.sh` | 인스펙터/타임라인 dHash 골든 |
| 린트 | `bash scripts/lint_gate.sh` | 신규 error 0 정책(병렬 트랙 B) |

### 1.3 불변 원칙 (방향 문서에서 상속)

- 렌더러 CoreImage 유지, 전체 Metal 재작성 금지(§4.3 트리거 table 참조 시에만 선택적 커널).
- 완료 기준은 코드 존재가 아니라 preview + export 실증.
- 자원 배분 macOS 70–80% / iOS 20–30%.
- 부채 예산: 매 증분 공수의 15–20%는 경계 정리에 지출(§1-6 규칙이 이 집행 창구).
- iOS 전체 패리티 비목표 — iOS 증분은 "핵심 숏폼의 검증된 패리티" 범위만.
- 네트워크 entitlement 0 유지. 외부 LLM·클라우드 연동 금지(규칙 기반 어시스턴트 유지).

---

## 2. 출발 상태 확정 (2026-08-16 심야 기준)

- HEAD `34ecb33`, 직전 게이트 PASS(테스트 1,143개 / 파리티 12/12 / Mac·iOS 빌드).
- **진행 중 WIP — G-23 Inc 2의 수학 레이어가 타 세션에 의해 완성된 상태(미커밋):**
  - `Sources/MovieCutCore/Editing/CropRectEditingMath.swift` — 핸들 9종(모서리4/변4/내부1) move·resize, aspect lock, 최소 크기 0.05, 유닛 프레임 클램프
  - `Tests/MovieCutCoreTests/CropRectEditingMathTests.swift` — 이동/리사이즈/앵커/최소크기/aspectlock/interior 테스트
  - `Sources/MovieCutCore/Models/CardDocument.swift` — `NormalizedRect.maxX/maxY` 헬퍼 +6줄
  - `docs/COMPETITIVE_GAP_ANALYSIS_20260816.md` — 본 세션 격차 분석(미커밋)
- **Inc 0(다음 세션 첫 작업) 절차:**
  1. `git status` 재확인 — 타 세션이 이미 Inc 1 UI까지 진행했을 수 있음(수학 파일 타임스탬프 22:15). 진행 상황에 맞춰 아래를 조정한다.
  2. WIP가 위와 동일하면: `swift test --filter CropRectEditingMath` → `bash scripts/verify_gate.sh` → 통과 시 커밋 `feat(crop): G-23 Inc 2 math layer — handle gesture geometry + tests`(격차 분석 문서 포함).
  3. 테스트 실패 시 원인 분석 후 수리 — 수리 불가면 §8 중단 규칙.

---

## 3. 1단계 잔여 증분 상세 (2026-08-16 ~ 2026-10 말)

> 주차 배정은 가이드(순서가 본질). 증분 순서는 방향 문서 §3의 고정 순서를 따른다. 병렬 가능 항목은 §3-11에 별도 표기.

### 스케줄 요약

| 주차 | 증분 | 산출 |
|---|---|---|
| W1 (8/17~) | Inc 0 + Inc 1 | WIP 커밋, G-23 Inc 2 완료(캔버스 핸들·패리티 #13·iOS 진입점) |
| W2 (8/24~) | Inc 2 | EditorViewModel 분해 1호 경계 |
| W3~4 (8/31~) | Inc 3 | G-02 Inc5 HSL 8밴드 편집 UI |
| W4~5 (9/7~) | Inc 4 | G-01 Inc2 카라오케 활성 단어 렌더링 |
| W5 (9/14~) | Inc 5 | G-01 Inc3 자막 스타일 프리셋 |
| W6 (9/21~) | Inc 6 | G-06 베지어 그래프 + **G-25 설계 문서 초안 → 사용자 승인 요청** |
| W7 (9/28~) | Inc 7 | G-25 Inc1 Core 그래프 명세 모델(승인 조건부) |
| W8 (10/5~) | Inc 8 | G-25 Inc2 프리뷰·출력 그래프 생성기 + null test |
| W9 (10/12~) | Inc 9 | G-25 Inc3 미터·팬·mute/solo UI + 측정 증분 완료(T1/T2/T3·장형·W시나리오) |
| W10 (10/19~) | Inc 10 | G-03 조정 레이어 + 1단계 게이트 점검 |

---

### Inc 1 — G-23 Inc 2: 크롭 캔버스 핸들 + 패리티 시나리오 #13 + iOS 진입점

**목표:** 인스펙터 수치 편집에 더해 프리뷰 캔버스에서 직접 크롭 창을 드래그/리사이즈할 수 있게 한다. 수학 레이어는 완료 상태(WIP 참조).

**범위 IN:** Mac 캔버스 크롭 오버레이 UI, 하니스 시나리오 `crop_rect`(패리티 #13), iOS 크롭 UI 진입점(비율 프리셋 노출).
**범위 OUT:** iOS 캔버스 핸들 제스처(후속 증분), 크롭 회전/기울임, 크롭 애니메이션(키프레임화).

**구현 단계:**
1. `App/MovieCutMac/Effects/CropCanvasView.swift` 신규 — `MaskCanvasView` 패턴 차용: 미크롭 원본 프레임 위 오버레이 + 크롭 창 + 핸들 9종 표시. 드래그 delta를 소스 픽셀→정규화 환산 후 `CropRectEditingMath.move/resize` 호출. 비율 프리셋(1:1/4:3/16:9/9:16 등) 선택 시 `aspect` 전달.
2. 제스처 확정 시점에 `SetClipPropertyCommand`(cropRect) 1회 디스패치 — 드래그 중 매 프레임 커맨드 금지(undo 스택 오염 방지). 드래그 중는 로컬 상태로 프리뷰 반영.
3. `PreviewPanel`에 진입점 배선(선택 클립의 크롭 편집 모드 토글). 인스펙터 수치 편집과 동일 커맨드 경로 강제.
4. 하니스: `App/MovieCutMac/UITestHarness.swift`에 `MOVIECUT_UITEST_CROP` 시나리오 — cropRect를 커맨드로 설정 → 프리뷰 프레임 덤프 + export. **함정: `writeHarnessStatus`는 truncate-write — 최종 판정 라인이 반드시 마지막 write.**
5. `scripts/run_core_editing_parity.sh`에 시나리오 #13 `crop_rect` 추가 — 판정 MAD ≤ 2.0, duration ≤ 1프레임(VERIFICATION_STANDARD §2.1). `VERIFICATION_STANDARD.md` 시나리오 표 갱신.
6. iOS: `App/MovieCutiOS/Views/` 기존 캔버스/이펙트 시트에 크롭 비율 프리셋 진입점 추가(G-23 Inc 1에서 Core 배선은 완료됨 — `IOSCustomVideoCompositor.applyClipEffects` 크롭-퍼스트 확인됨).

**검증:** `swift test --filter 'Crop|Golden'` → `run_core_editing_parity.sh`(13/13) → `verify_gate.sh`(iOS 빌드 포함).
**DoD:** ① 캔버스 핸들 드래그 결과와 인스펙터 수치가 동일 커맨드 경로로 저장 ② 패리티 #13 PASS(export에 크롭 반영) ③ undo 1회로 크롭 전 상태 복원 ④ iOS 빌드 + 진입점 표시 ⑤ 골든 픽셀 무회귀.
**리스크/예방:**
- **y-플립 좌표계 혼동** — 크롭 창은 top-left 정규화, CoreImage는 bottom-left. `CropPixelProcessorGoldenTests`의 y-플립 고정 테스트가 기준. 캔버스→정규화 변환은 단일 헬퍼로 양방향 테스트.
- **프리뷰 컴포지터 메타데이터 누락(재발 방지)** — cropRect는 G-23 Inc 1에서 `PlaybackClipInstructionMetadata` 경로 확보 완료. 캔버스 실시간 미리보기가 커스텀 컴포지터를 경유하는지 확인(경유하지 않으면 오버레이 마스킹으로 로컬 표시).
- aspect lock 중 `minimumEdge`와 충돌 시 `CropRectEditingMath` 우선(테스트 고정됨).

---

### Inc 2 — EditorViewModel 분해 1호 경계: timeline editing

**근거:** 방향 문서 §6 — "HSL·키프레임·믹서 UI 추가 **전에** 최소 분해". 현재 `EditorViewModel.swift` 6,078줄. Inc 3·6·9의 직전 조건.

**범위 IN:** 타임라인 편집 책임(클립 선택·이동·트림 관련 메서드/상태)의 extension 파일 이동.
**범위 OUT:** 새 추상화·프로토콜·동작 변경(순수 이동 리팩터링). transport/inspector 등 다른 경계.

**구현 단계:**
1. `MARK`/섹션 조사로 이동 대상 식별 — 선택 상태, 타임라인 커서/스크랩 좌표, 클립 선택·멀티선택 헬퍼.
2. `App/MovieCutMac/EditorViewModel+TimelineEditing.swift` 신규 extension으로 이동(접근 수준 유지).
3. 이동 후 `swift test` 전체 + 파리티 13 + `ui_regression.sh`.

**DoD:** ① EditorViewModel 본체 유의미한 라인 감소(목표 ~5,200 이하) ② 전체 테스트 PASS ③ 파리티 무회귀 ④ diff 검수 시 "이동만" 확인(새 로직 0줄).
**리스크/예방:** 순환 참조·private 접근 — extension 이동만으로 해소 불가한 것은 발견 즉시 기록하고 그 메서드는 이동 보류(강제 추출 금지). 실패해도 Inc 3 진행의 최소 조건은 "본체 축소 시도 기록"이며, 3회 시도 실패 시 §8 에스컬레이션.
**이후 경계 로드맵(각 UI 증분 직전 1개씩, 부채 예산 집행):** selection → transport → inspector → media → effects → audio(Inc 9 직전) → export.

---

### Inc 3 — G-02 Inc5: HSL 8밴드 편집 UI

**상태:** 수학·렌더 완료(`HSLBand` + `HSLCubeBuilder` + `ColorGradePixelProcessor` 체인, 골든 존재). UI 미노출 — 사용자 관점 미구현.

**범위 IN:** Mac 인스펙터 컬러 영역에 8색상 밴드 편집 UI(밴드별 색조 이동/채도/휘도 조정), 커맨드 경로 연결, 골든·패리티 보강, UX 발견성 라벨.
**범위 OUT:** 톤커브 에디터 UI(Inc6 — 별도 증분), iOS 동등 UI(1단계 Mac 우선, iOS는 2단계 파리티 증분), 2차 색 보정 개념 확장.

**구현 단계:**
1. `App/MovieCutMac/Inspector/ColorHSLBandsView.swift` 신규 — 8밴드(적/주/황/녹/청/남/보/마젠타) 각 색조 시프트·채도·휘도 슬라이더. 값은 기존 `ColorGrade`의 HSL 밴드 배열에 기록 — **스키마 필드 추가 여부 확인: 기존 컨테이너 내 변경이면 v4 유지, 신규 필드면 `ProjectSchemaVersioning` v5 + 마이그레이션 테스트 필수.**
2. 적용은 `SetClipPropertyCommand` 계열의 단일 undo 트랜잭션(슬라이더 드래그 종료 시 확정 — Inc 1과 동일 패턴).
3. 골든 픽셀: 밴드 조정 → `HSLCubeBuilder` 큐브 결과 샘플 픽셀 검증(소프트웨어 렌더러 `assertRendererFunctional` 최상단).
4. 컬러 휠·스코프 옆 배치(`InspectorEffectsSection`/`ColorGradeWheel` 인접), VoiceOver 라벨.
5. 패리티 시나리오는 기존 색 경로 재사용 가능하면 재활용, HSL 특화 골든으로 보강.

**검증:** 골든 신규 suite → `run_core_editing_parity.sh` → `ui_regression.sh` → `verify_gate.sh`.
**DoD:** ① preview에서 밴드별 색 변화 가시 ② export 동일 반영(패리티/골든) ③ undo 단일 ④ 프로젝트 저장·재오픈 후 값 유지(라운드트립 테스트) ⑤ 스키마 무변경 또는 v5 마이그레이션 PASS.

---

### Inc 4 — G-01 Inc2: 카라오케 활성 단어 렌더링

**상태:** `WordTiming`·`TextClipContent.wordTimings`·`karaokeEnabled` 저장 완료. 렌더 미구현 — W1(토킹헤드)의 핵심 미완 조각.

**범위 IN:** `TextOverlayPixelProcessor`에서 재생 시각 t 기준 활성 단어 하이라이트 렌더(색/굵기 변화), preview=export 공유 경로 1회 구현, 골든, 타이밍 정확도 테스트.
**범위 OUT:** 스타일 프리셋(Inc 5), iOS 갤러리 UI(2단계), 활성 단어 애니메이션 효과(2단계 "카라오케 스타일 편집").

**구현 단계:**
1. 렌더 시 그리는 자막 텍스트를 워드 단위 세그먼트로 분할 렌더링하는 경로 추가(기존 단일 문자열 렌더와 폴백 호환 — `wordTimings` 없는 클립은 기존 경로 유지, 골든 무회귀 조건).
2. 현재 프레임 시각(클립 상대)으로 활성 워드 판정 — `StyledCaptionWordTimingTests`의 상대시간 변환·clamp 수학 재사용.
3. 골든: 활성 단어만 색 변화(픽셀 검증), 비활성 구간 무변경, 워드 타이밍 경계 ±1프레임.
4. Mac `AutoSubtitlesView`에 카라오케 토글 노출(이미 플래그 존재).

**DoD:** ① 골든 PASS ② 자막 burn-in 패리티(기존 #3 text_overlay) 무회귀 + 활성 단어 export 실증(E2E) ③ `wordTimings` 없는 기존 프로젝트 골든 무회귀(하위호환) ④ undo.
**리스크:** 워드 분할 렌더로 텍스트 레이아웃(줄바꿈/정렬) 재계산 필요 — 기존 단일 렌더와 시각적 동일성 골든 고정 후 착수.

---

### Inc 5 — G-01 Inc3: 자막 스타일 프리셋

**범위 IN:** 자막 전용 스타일 프리셋 5~8종(테두리/배경/폰트/크기/위치/활성 단어 색 조합), `UserTextStylePreset` 저장소 재사용, 프리뷰 즉시 적용.
**범위 OUT:** 애니메이션 프리셋 조합(2단계), 스타일 편집 에디터(적용만).
**DoD:** 프리셋 적용 2클릭 이내, 골든(프리셋별 픽셀), undo 단일, 저장 프리셋 영속화 테스트.

---

### Inc 6 — G-06: 키프레임 기본 베지어 그래프 (+ G-25 설계 문서 병행)

**사실 확인(2026-08-16):** 보간 선택 피커는 Mac `KeyframeListView.swift:59`·iOS `IOSKeyframeEditorView.swift:157,425`에 **이미 존재**. 따라서 G-06의 잔여는 **그래프 뷰**뿐이다(백로그/핸드오프의 "보간 UI 미노출" 기술은 낡음 — 등록 시 정정).

**범위 IN:** 값-시간 캔버스 그래프(속성별 키프레임 표시, 보간 모드 시각화 — hold/ease 형태 구분), 그래프에서 키프레임 추가/이동/삭제, 기존 피커와 동일 커맨드 경로.
**범위 OUT:** 베지어 핸들 직접 편집(2단계 "키프레임 그래프 개선"), 다중 속성 오버레이.
**DoD:** ① 그래프 조작 = 리스트 조작 동일 결과(동일 커맨드) ② 키프레임 렌더 무회귀(기존 골든) ③ iOS에 동등 그래프는 2단계 — 본 증분은 Mac만(자원 배분 원칙) ④ UI 회귀.
**병행(주 내):** Inc 7의 전제인 **G-25 설계 문서 초안** 작성 착수 — 방향 문서 §4.1을 그대로 명세화(노드 그래프 구조, 직렬화 스키마, 샘플 시간 타임베이스, 노드 latency 보상, AAC 사후 검사, 프리셋 알고리즘 버전, null test 절차). **완성 시 사용자 승인 요청 — §8 에스컬레이션 지점.** 승인 대기 중 Inc 7 이외 증분으로 시간 흡수.

---

### Inc 7~9 — G-25: 오디오 믹싱 골격 (설계 승인 후 3증분)

**Inc 7 (Core):** `Sources/MovieCutCore/Audio/AudioRenderGraphSpec.swift` — 직렬화 가능한 그래프 명세 모델(소스/클립 스트립/트랙 버스/마스터 버스), 팬 파라미터, 채널 매핑(mono/stereo/dual-mono). 순수 모델+Codable+단위 테스트(렌더링 없음).
**Inc 8 (엔진):** 그래프 → AVAudioEngine(프리뷰)·출력 인코더(export) 양쪽 생성기. **프리뷰=출력 null test 자동화**(±1 샘플 정렬, 테스트로 상시화). 혼합 sample rate 60분 드리프트 측정(≤1프레임 게이트). 기존 EQ/NR/덕킹의 destructive 파생 미디어 경로는 현행 유지 — 그래프는 게인/팬/매핑/미터 계층부터(컴프레서 등은 2단계 G-26).
**Inc 9 (UI):** 트랙 헤더/인스펙터에 트랙·마스터 미터, mute/solo, 팬 노브. 재생 중 그래프 재구성 비용 측정(signpost `playback.buildComposition` 확장) 후 필요 시 디바운스.

**공통 DoD(방향 문서 1단계 게이트 직결):** ① 프리뷰↔출력 null test 통과 ② 동일 PCM ±1 샘플 ③ 60분 drift ≤1프레임 ④ LUFS/true-peak 미터 실측값 표시(자가보고 아닌 측정 출력) ⑤ 기존 오디오 E2E(EQ/NR/덕킹 RMS·Goertzel) 무회귀.
**리스크:** 재생 그래프 재구성 글리치 — 첫 구현은 "편집 정지 시 재구성" 정책으로 단순화하고 측정 후 개선. CoreAudio 콜백 스레드와 Swift 6 동시성 — 그래프 상태는 값 타입 스냅샷 교환만.

---

### Inc 9-병행 — 측정 증분: T1/T2/T3 + 장형 fixture + W1~W5 시나리오 스크립트 + SLO 전환

**사실 확인(2026-08-16):** `scripts/`·`BETA_GUIDE.md`에 W1~W5 대표 작업 시나리오 스크립트가 **존재하지 않는다** — 1단계 완료 게이트("대표 작업 성공률 90%+")의 측정 도구가 없는 상태다. 이 증분이 도구를 만든다.

**단계:**
1. `PERFORMANCE_SLO.md`의 T1/T2/T3 구성(초안) 확정 → `scripts/make_fixtures.sh`에 타임라인 생성기 추가(멀티레이어·자막 / 광학플로우·AI / 컬러·LUT). fixture는 생성 방식(재현성 해시) — 대형 blob 커밋 금지.
2. 장형(≥10분) fixture로 "10분 프로젝트 열기 ≤3초" 원 의미 실측 → SLO 문서에 p50/p95 기록.
3. `scripts/run_w_scenarios.sh` 신규 — W1~W5 각각을 하니스 시나리오 조합으로 정의(W1: 자동자막+카라오케+덕킹+SNS 출력 등 방향 문서 §1 표 그대로) + 성공/실패·소요시간 기록 포맷. 1단계 게이트의 측정 창구.
4. 측정 안정 판단 시 `run_latency_baseline.sh --enforce` 전환 평가(위반 차단 모드).

**DoD:** SLO 문서에 T1/T2/T3·장형 실측치 기록, W 시나리오 스크립트가 게이트 보고서 출력, fixture 재생성 해시 동일.
**리스크:** VM 러너 수치와 실측 교환 금지(SLO 등급 규칙 §측정 등급). 장형 fixture 생성 시간 — 야간 배치 허용.

---

### Inc 10 — G-03: 조정 레이어 (1단계 말, W4 잠금해제)

**범위 IN:** 상단 "조정 클립"(전체 캔버스 폭, v1은 비디오 트랙 상단 전용)이 자신의 타임라인 범위 아래 가시 클립들에 색보정·필터·변형을 적용. 모델(`Track.kind` 확장 또는 클립 플래그 — 설계 노트 먼저), `FlattenedTimeline`에서 조정 클립 수집→픽셀 프로세서 체인 적용, 골든·패리티 시나리오 추가.
**범위 OUT:** 오디오 조정(2단계 G-26 연계), 부분 범위(클립 일부만) 적용, 조정 레이어 중첩.
**DoD:** ① 골든(조정 레이어 아래 클립들에만 효과, 범위 밖 무변경) ② 패리티 시나리오 신규 PASS ③ iOS export 동등(공유 프로세서 경유 검증) ④ undo·저장 라운드트립 ⑤ 스키마 변경 시 v5+ 마이그레이션.
**리스크:** 렌더 순서 복잡도 — 적용 순서(클립 고유 효과 → 조정 레이어)를 설계 노트에 고정하고 골든으로 잠금. 착수 전 §8 규칙: 1단계 게이트(W10)가 임박하면 본 증분은 2단계 첫 주로 이동(방향 문서가 "1단계 말"로 유연 명시).

---

### 3-11. 병렬 트랙 (기능 증분과 무관하게 상시)

| 트랙 | 내용 | 주의 |
|---|---|---|
| **G-27 iOS 실기기 검증 인프라** | ① XCUITest 타겟 + 시뮬레이터 E2E(현재 전무 — PLATFORM_PARITY §6 경고) ② 3단계 실기기 러너(최소/중간/최신) ③ 필수 시나리오: 프리뷰+출력+오디오 라우팅+발열·메모리+재오픈 | 실기기·Apple 개발자 하드웨어 = **사용자 협력 지점**. 시뮬레이터 E2E 먼저(사용자 불개입) → 실기기는 사용자 일정 확보 시 |
| **lint 신규 error 0 CI** | `lint_gate.sh` 차단 모드 전환, 변경 파일은 이전보다 개선 | 즉시 발효(방향 문서 §6). D-2와 연계 |
| **Track A (사용자 작업)** | A-1 아이콘 → A-2 App Store Connect → A-3 아카이브 | 1단계 완료 후 A-4 TestFlight 권장. 개발 세션과 경쟁 금지 |

---

## 4. 1단계 완료 게이트 점검표 (2026-10 말)

방향 문서 §3의 게이트 조건과 측정 방법 대응:

| 게이트 조건 | 측정 수단 | 담당 증분 |
|---|---|---|
| 대표 작업 성공률 90%+ | `run_w_scenarios.sh`(신규) | 측정 증분(Inc 9-병행) |
| 기존 픽셀 게이트 무회귀 | 골든 전수 + 파리티 13/13 | 매 증분 |
| 동일 PCM 경로 ±1 샘플 | G-25 null test | Inc 8 |
| 60분 프로젝트 A/V drift ≤1프레임 | 혼합 sample rate 측정 | Inc 8 |
| iOS 실기기 3종 통과 | G-27 러너 | 병렬 트랙(사용자 의존) |
| seek·프로젝트 열기 기준선 확정 | `run_latency_baseline.sh`(장형 포함) | 측정 증분 |

**일정 압박 시 조정 우선순위 (에스컬레이션 전 자체 조정 범위):**
- **필수 불가**: G-23 Inc 2 완료, G-02 Inc5, G-25 Inc7+8(골격+null test), 측정 증분(W 시나리오·기준선), G-27 시뮬레이터 단계.
- **2단계 이월 가능(순서 보존)**: G-02 Inc6(커브 에디터 UI), G-03(방향 문서가 "1단계 말"로 유연), G-25 Inc9(UI — 골격·null test가 게이트 조건), G-01 Inc3.
- 그 외 조정은 §8 에스컬레이션(사용자 결정). 게이트 조건 미충족 상태로 1단계 종료 선언 금지.

---

## 5. 2단계 이후 (2026-11 ~, 개요만 — 상세 계획은 1단계 종료 시 본 문서 패턴으로 작성)

- **G-24 손떨림 보정 v1**: 장면 분할(`SceneChangeProvider` 재활용) → Vision 등록 → 경로 평활화 → adaptive crop(중앙값 ≤15%) → CI warp → confidence fallback. DoD 수치는 백로그 §0.5 그대로(잔류 흔들림 중앙값 50%↓·심각 워블 ≤3%·장면 전환 오류 0건). 지표는 §6.4 AI 보완(하위 5%·아티팩트 라벨) 적용.
- **G-28 효과·템플릿 브라우저**: 착수 전 `EffectCostProfile` 스키마 확정(PERFORMANCE_SLO 신설 항목). 검색 성공률·재사용률 KPI(개수 KPI 폐지).
- **N2 원클릭 오토스타일**: 격차 분석 §7-N2 — 등록 결정 후 G-28과 세트로(AutoCutEngine+템플릿+자막+덕킹 조합 제품화).
- **G-26 오디오 프로세서 단계 B**: Apple AU 우선(컴프레서·리미터·리버브)·트랩 스트립·프리셋·디-이서 초기. 게이트 LUFS ±0.2LU·true-peak ±0.2dB.
- **N1 대사 검색·미디어 인덱스**: 격차 분석 §7-N1 — G-01 계열 완료 후 착수 권고.
- 3~4단계(G-29 HDR·팩 v0·HLG 공개·스템 등)는 방향 문서 §3에 위임 — 본 문서에서 순서 재정의 금지.

---

## 6. 신규 격차항목(N1~N10) 등록 프로토콜

격차 분석 `COMPETITIVE_GAP_ANALYSIS_20260816.md` §7의 미등록 후보는 **본 계획서가 임의로 백로그에 등록하지 않는다**(방향 문서 §8이 문서 갱신 권한 보유). 다음 세션의 등록 검토 순서 권고:

1. N1(대사 검색)·N2(오토스타일) — 2단계 착수 전 등록 검토(격차 분석 상위권)
2. N5(커스텀 폰트 임포트) — 1단계 말 여유 슬롯 등록 검토(비용 낮음·W5 직결)
3. N6(뷰티/리터치) — **사용자 포지셔닝 결정 대기** 상태로 백로그에 명시만
4. N3·N4·N7~N10 — 2단계 백로그 정비 시 일괄 검토

---

## 7. 함정 레지스터 (전 증분 공통 — 재발 방지 체크리스트)

1. **하니스 `writeHarnessStatus`는 truncate-write** — 중간 체크포인트는 디버깅용, 최종 판정 라인이 반드시 마지막 write여야 살아남는다.
2. **하니스 시나리오 시작 조건** — `ContentView.task`에서 시작(홈 아님). `MOVIECUT_UITEST=1`이면 에디터 라우팅. 종료 시 `MOVIECUT_UITEST_QUIT=1` 처리를 직접 호출.
3. **신규 시각 속성 4곳 배선 체크리스트** (G-23 Inc 1에서 프리뷰가 transform/opacity/keyframes를 누락하던 클래스 버그): 새 시각 속성은 반드시 ① Core 모델 ② `PlaybackClipInstructionMetadata` ③ Mac·iOS 컴포지터 `applyClipEffects` ④ 양쪽 엔진 트리거 조건 — 4곳 모두 배선 + 패리티 시나리오/골든 추가. 하나라도 빠지면 "출력에만 반영" 드리프트.
4. **iOS 빌드 게이트 생략 금지** — 과거 2주간 iOS 붕괴를 게이트가 못 잡은 사고. `verify_gate.sh` 4단계 항상 실행.
5. **StaticContract은 회귀 잠금일 뿐 완료 증거 아님** — 완료 선언은 preview+export 실증만.
6. **샌드박스 캐시 이슈** — xcodebuild SwiftPM resolution 막힘 시 `swift build --disable-sandbox` 대안(백로그 §5).
7. **병렬 세션 WIP** — 세션 시작 시 `git status`/`git log` 확인. WIP 충돌은 최신 커밋 기준 재조정, 해석 불가 시 중단.
8. **스키마 변경 시** — `ProjectSchemaVersioning` 체인 갱신 + 마이그레이션 테스트 + 기존 프로젝트 로드 E2E.
9. **골든 테스트** — `GoldenPixel.assertRendererFunctional()` 최상단, silent-skip 없음.
10. **측정 등급 혼금 금지** — VM 러너(coarse)와 실하드웨어 수치 교환 비교 금지.
11. **undo 트랜백션** — 드래그성 조작은 종료 시점 단일 커맨드(Inc 1·3 패턴 공통).

---

## 8. 중단/에스컬레이션 규칙

**즉시 중단 후 핸드오프 기록:**
- `verify_gate.sh` 재시도 2회 연속 실패(원인 불명 시)
- 골든/패리티 무회귀 위반이 원인 파악 안 되는 경우
- 스키마 파괴 가능성(기존 프로젝트 로드 실패)이 의심되는 경우
- 병렬 세션 WIP와의 충돌 해석 불가

**사용자 질문 필수(진행 재개 불가 조건):**
- G-25 `AudioRenderGraphSpec` 설계 문서 승인(Inc 7 착수 전제)
- N6 뷰티/리터치 포지셔닝 결정
- 방향 문서와 충돌하는 발견(순서·범위 변경 필요성)
- Track A 계정/자격증명 관련
- 1단계 게이트가 10월 말 임박하게 미달 전망일 때(§4 이월 범위 초과 조정)

**롤백:** 증분=커밋 원칙으로 `git revert <증분 커밋>` 즉시 롤백 가능. 부분 롤백(파일 단위) 금지 — 증분 단위로만.

---

## 9. 문서 갱신 의무 요약

| 시점 | 문서 | 내용 |
|---|---|---|
| 증분 완료 | `CAPCUT_FEATURE_BACKLOG.md` | 해당 G-항목 상태·근거·caveat |
| 증분 완료 | `REQUIREMENTS.md` §13 | 체인지로그 1줄 |
| 증분 완료(렌더/측정 변경) | `VERIFICATION_STANDARD.md`·`PERFORMANCE_SLO.md` | 시나리오 표·실측치 |
| 세션 종료 | `SESSION_HANDOFF_CURRENT.md` | 완료/함정/다음 인계 최상단 기록 |
| 1단계 종료 | `REMAINING_TASKS.md` | Track 구조 4단계 로드맵 재정렬(방향 문서 §8-2) |
| 분기 종료 | `COMPETITIVE_GAP_ANALYSIS_*.md` | 벤치마크 버전 고정 갱신(§6.6) |

---

## 10. 본 계획서의 한계

- 주차 배정은 1증분/주·게이트 1회 가정의 추정이며, 실측 기반 조정한다(순서가 계획의 본질).
- G-25 Inc7 이후는 설계 승인 결과에 따라 세부가 변할 수 있다(문서가 확정 권한).
- 2단계 상세는 1단계 종료 시점 별도 작성(본 문서 패턴 준용).
- 본 문서 작성 시점의 코드 사실(보간 피커 존재, W 스크립트 부재, WIP 상태)은 2026-08-16 실측 — 착수 전 재검증 권장.
