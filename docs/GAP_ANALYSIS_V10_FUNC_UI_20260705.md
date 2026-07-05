# MovieCut vs CapCut 갭 분석 V10 — 기능 + UI 재감사 — 2026-07-05

> 작성일: 2026-07-05 / 브랜치: `feat/core-backend-expansion` (기준 커밋: `738f4ce`)
> 기준선: V9 `docs/GAP_ANALYSIS_V9_FUNC_UI_20260705.md` (`d756ab3`) / 재평가 대상: `d756ab3..738f4ce` + **전체 독립 실사**
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md` v1.4
> 규칙: 코드 존재 ≠ 완료. 완료 = preview/export/iOS 반영 + 증거(골든/E2E/ffprobe/캡처). static contract는 회귀 잠금 전용.
> 이 감사의 실측: `swift build` PASS, `swift test --filter 'StaticContract|Golden|CurveEvaluator|HSLCube|StyledCaption'` **361 tests / 86 suites PASS**, dead-code/dead-value grep 스캔 전수 재실행.

---

## 0. 한 줄 요약

V9 이후 델타는 **G-12 #7 타이틀 템플릿 14종 상환**(`738f4ce`, frame-diff 14종 실측 PASS) 1건으로, G-12는 **9/14**가 됐다. 검증 인프라와 상환 속도는 건강하다. 그러나 이번 독립 실사에서 **"Inc 1~2(순수 로직/저장)에서 멈춘 dead-value가 3계열로 누적"**되고 있음을 확인했다 — `CurveEvaluator`·`HSLCubeBuilder`(App 참조 0), `CurvePoint`/`HSLBand` 타입(ColorGrade 필드 미편입), `wordTimings`(렌더러 소비 0). CapCut 체감 격차(HSL/커브·워드 자막·타임라인 표면·UI 제품 표면)는 V9와 동일하게 열위 유지. **방향 전환 판단 1건을 사용자에게 요청한다: S0 게이트 완화 여부(§5-1).**

---

## 1. V9 이후 델타와 독립 검증

| 커밋 | 내용 | V10 독립 검증 결과 |
|---|---|---|
| `738f4ce` | 타이틀 템플릿 14종 export 검증 (G-12 #7) | ✅ 실사 확인 — `run_e2e_export.sh:240-249`에 14종 no-template baseline 대비 frame-diff 루프 실재, 스펙 검증 기록에 실측 max_overlay_mad 14종 수치(6.46~7.45) 기재. 하니스 훅 `MOVIECUT_UITEST_TEXT_TEMPLATE_NAME` 실재 |

- 이 감사 시점 빌드/테스트: `swift build` PASS, 필터 스위트 361/86 PASS — **회귀 없음**.
- 스펙(§G-12 원장)·백로그는 이미 9/14로 갱신돼 있어 문서-코드 정합 양호. 단 스펙 버전 헤더가 v1.3에 머물러 있던 것은 v1.4로 정리(이번 커밋).

---

## 2. 독립 실사 — dead-code / dead-value 전수 스캔 (2026-07-05)

| 대상 | App 참조 | 판정 | 조치 필요 |
|---|---|---|---|
| `VocalSeparationService` (Core/Audio) | **0** | ❌ dead code 지속 (V7부터 3회 연속 지적) | G-05 Inc 1~3 |
| `StyleTransferProvider` (Core/Analysis) | **0** | ❌ dead code | 폐기 또는 G-07 플러그인으로 흡수 결정 |
| `CurveEvaluator` (Core/Rendering) | **0** | 🟡 dead-value — 순수 로직+테스트만 | **G-02 Inc 3** |
| `HSLCubeBuilder` (Core/Rendering) | **0** | 🟡 dead-value | **G-02 Inc 3** |
| `CurvePoint`/`HSLBand`/`HSLBandCenter` 타입 | 정의만 | 🟡 **`ColorGrade` struct에 저장 필드로 미편입**(실사: struct는 lift/gamma/gain뿐, 타입은 파일 하단에 부유) | **G-02 Inc 3** |
| `TextClipContent.wordTimings` | 저장만 | 🟡 dead-value — Rendering/·App/ 소비 grep 0건 | G-01 Inc 2~4 |
| `AudioEqualizerService` | 1 | ✅ 배선됨 (EQ DSP 상환 완료 상태 유지) | — |

**패턴 경고**: 세션들이 스펙 증분을 따르며 Inc 1~2(모델/순수 로직)에서 커밋을 끊는 것은 규율상 정상이나, **후속 세션이 S0 부채 상환을 우선하면서 Inc 3+(소비처 연결)가 계속 밀리고 있다.** A6(dead-code 금지)는 "서비스 신설"에만 적용되어 순수 로직/타입은 사각지대다. → 스펙 v1.4에 **A6 보강**: 순수 로직·모델 타입도 도입 후 다음 마일스톤 전환 시점까지 소비처 미연결이면 G-12 원장에 자동 등재.

---

## 3. 3분류 현황 (V9 대비 변동분만)

- **2-A 능가/후보**: 변동 없음 + "타이틀 템플릿 14종 export proof"가 텍스트 애니메이션 13종과 함께 검증 완료 축에 합류. 검증 인프라(no-op를 잡는 frame-diff E2E)는 CapCut 대비 명확한 **엔지니어링 우위**로 굳어짐.
- **2-B 검증부채**: G-12 잔여 **5건**(#9 챕터/비트 메타데이터, #11 배경제거 실인물, #12 리프레임 실영상, #13 iCloud 2기기, #14 Photos 드래그). 성격 분화 — #9는 자동 E2E 가능, #11/#12는 **fixture 제작이 선행**(이동 피사체/실인물), #13/#14는 **수동 실기기**(자동화 불가).
- **2-C 열위**: V9 §2-C 그대로 유효 — 캡션(워드 렌더), 색(HSL/커브 체이닝), 타임라인 표면, 오디오(보컬분리/FX), iOS(defer 15건), 제품 표면(홈/설정/토스트/현지화/팔레트) 전부 미착수.

## 4. G-ID / U-ID 현황판 (V10)

| ID | 상태 | 변동 |
|---|---|---|
| G-12 | 🟡 **9/14** | #7 상환 (V9의 8/14 → 9/14) |
| G-01 | 🟡 Inc 1 | 변동 없음 — wordTimings dead-value 지속 |
| G-02 | 🟡 Inc 1~2 | 변동 없음 — 평가기 2종+타입 dead-value 지속, **저장 필드 미편입 재확인** |
| G-09 | 🟡 Inc 1~2 | 변동 없음 — CI job·iOS E2E·defer 15건 잔여 |
| G-03/04/06/07/08/10/11 | ❌ | 변동 없음 |
| G-05 | 🟡 부분 | EQ/NR/덕킹 검증 완료, 보컬분리 dead code 지속 |
| G-13/14 | 합의 대기 | 변동 없음 |
| U-01~U-09 | V9 판정 유지 | **UI 트랙 3회 연속 감사에서 착수 0건** — U-03 부분(lock UI 존재)·U-07 부분 외 전부 ❌ |

---

## 5. 개선 방향성 (V10)

### 5-1. ⚠️ 사용자 결정 요청: S0 게이트 완화 여부

`/surpass` 자동 선택은 "S0 완주 후 본대" 규칙이라, 다음 자동 작업은 G-12 #9다. 그러나:

- 잔여 부채 5건 중 3건(#12 fixture, #13/#14 수동)은 **자동 세션이 완결할 수 없다** → S0가 자동 선택을 무기한 점유.
- 그 사이 dead-value(§2)가 누적되고 CapCut 체감 격차(G-02/G-01/UI)는 정지 상태.

| 옵션 | 내용 | 권고 |
|---|---|---|
| A. 엄격 유지 | #9 상환 후에도 #11~#14를 계속 자동 선택 대상으로 | 비권고 — #13/#14에서 세션이 공회전 |
| **B. 완화 (권고)** | **#9까지 자동 상환 → 이후 자동 선택을 S1(G-02 Inc 3)·S2(G-01 Inc 2)·SU(U-08)로 진행. #11/#12는 fixture 제작 증분으로 재정의해 병행 슬롯, #13/#14는 "수동 검증 대기" 상태로 분리(자동 선택 제외)** | ✅ 스펙 v1.4에 반영(사용자 이의 시 revert) |

### 5-2. 체감 ROI 최우선: G-02 Inc 3 (커브/HSL 체이닝)

절반이 이미 존재한다(평가기 2종 + 타입 + 테스트). 남은 것은 ① `ColorGrade`에 `curves`/`hslBands` optional 필드 편입(A5 디코딩 테스트) ② `ColorGradePixelProcessor` 체이닝(CDL→HSL cube→curves) ③ 골든/E2E ④ 그레이딩 패널 UI(Inc 5~6). **한 세션이 Inc 3만 끝내도 dead-value 3계열이 동시에 상환**되고, 스코프+커브+HSL 통합 패널(CapCut 불가 표면)에 도달한다.

### 5-3. UI 트랙 착수 강제

3회 연속 감사에서 UI 착수 0건. 기능 세션과 UI 세션이 같은 자동 선택 큐를 쓰는 한 UI는 영원히 밀린다. → **개발 프롬프트에 "N번째 세션마다 UI 슬롯" 규칙을 명시**하거나, hermes에서 U-08을 명시 지정해 1회 실행할 것(U-08이 끝나야 이후 모든 UI 작업에 완료 증거 수단이 생긴다).

### 5-4. 방향성 요약 (기능×UI)

1. **부채는 #9까지만 자동으로, 이후 본대 전환** (5-1 옵션 B).
2. **색 그레이딩 완성이 최단 능가 경로** — Inc 3 체이닝 → Inc 5/6 UI → W5 워크플로우 완주.
3. **UI는 U-08부터 강제 착수** — 이후 U-02(+G-04 필름스트립), U-01 홈.
4. **캡션은 색 다음** — wordTimings 소비(Inc 2 렌더러)로 dead-value 상환 겸 숏폼 체감 격차 공략.
5. #11/#12 fixture 제작(이동 피사체·실인물 클립)은 독립 증분으로 아무 세션이나 집어갈 수 있게 G-12 원장에 세분화(스펙 반영).

## 6. 권장 실행 순서 (옵션 B 기준)

| 슬롯 | 작업 | 근거 |
|---|---|---|
| 1 | G-12 #9 챕터/비트 마커 메타데이터 E2E | S0 마지막 자동 상환 가능 항목 |
| 2 | **G-02 Inc 3** 체이닝+골든 | dead-value 3계열 상환 + 최대 체감 ROI |
| 3 | **U-08** UI 회귀 인프라 | UI 트랙 지반, 3회 연속 미착수 해소 |
| 4 | G-02 Inc 5~6 (커브/HSL UI) → W5 완주 | Pro 색 완성 = 첫 "능가" 워크플로우 |
| 5 | G-01 Inc 2~4 (캡션 렌더러+갤러리) | wordTimings 상환 |
| 6 | U-02 + G-04 (타임라인 표면+필름스트립) | 체감 완성도 |
| 병행 | G-12 #11/#12 fixture 제작 증분, #13/#14 수동 검증(사용자 실기기 세션) | 자동 큐와 분리 |

## 7. 실사 증거 요약

- `git log d756ab3..738f4ce` — 델타 1커밋 확인.
- dead-code 스캔: `for f in VocalSeparationService StyleTransferProvider CurveEvaluator HSLCubeBuilder; grep -rl "$f" App/ | wc -l` → 전부 0 (AudioEqualizerService만 1).
- `ColorGrade.swift` 실사: struct 필드 lift/gamma/gain뿐, `CurvePoint`(:61)/`HSLBand`(:93)는 부유 타입.
- `wordTimings` 소비: `grep -rln wordTimings App/ Sources/MovieCutCore/Rendering/` → 0건.
- UI 표면: HomeView/RecentProjects/Settings scene/ToastCenter/CommandPalette/.lproj·xcstrings 전부 grep 0건.
- 빌드·테스트: build PASS, 361 tests/86 suites PASS (2026-07-05).
