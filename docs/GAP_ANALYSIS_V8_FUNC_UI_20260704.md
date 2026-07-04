# MovieCut vs CapCut 갭 분석 V8 — 기능 + UI 재감사 — 2026-07-04

> 작성일: 2026-07-04 / 브랜치: `feat/core-backend-expansion`
> 기준선: V7 `docs/GAP_ANALYSIS_V7_FUNC_UI_20260703.md` (`5cd5155`) / 재감사 대상: `5cd5155..8efa65e`
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md` v1.2
> 규칙: 코드 존재는 완료 증거가 아니다. 완료는 preview + export + iOS 또는 명시 defer + 골든/E2E/ffprobe/GUI 증거로만 판정한다. Static contract는 회귀 잠금 전용이다.

---

## 0. 한 줄 요약

V7 이후 실제 진전은 **S0 검증부채 일부 상환(EQ/NR/덕킹/모션 트래킹/플랫폼 프리셋)**, **G-09 iOS 파리티 매트릭스 재감사**, **G-02 커브/HSL 순수 로직**, **G-01 워드 타이밍 저장**이다. 다만 G-02/G-01은 아직 renderer/UI/export/iOS로 이어지지 않아 완료가 아니며, UI U-ID는 U-03/U-07 일부 기존 구현을 제외하면 V7의 핵심 격차가 대부분 그대로 남아 있다.

---

## 1. 델타 요약: V7 이후 커밋과 판정 변화

| 커밋 | 내용 | V8 판정 |
|---|---|---|
| `2dbd449` | V7 기능+UI 분석, 스펙 v1.1, `/surpass` 갱신 | 기준 문서. 신규 기능 증거 아님 |
| `9ead7e7` | EQ spectrum E2E | G-12 #1 상환. `AudioEqualizerService`는 App 호출 1회(`ExportEngine.swift:836`) + 하니스/Goertzel 증거 보유 |
| `8cbef91` | Noise reduction SNR E2E | G-12 #2 상환. `NoiseReductionService`는 App 호출 2회(`EditorViewModel.swift:2646`, 하니스) + `run_e2e_export.sh` 증거 보유 |
| `0c42535` | Ducking RMS E2E | G-12 #3 상환. `MOVIECUT_UITEST_DUCKING_*` + export RMS 측정 |
| `d43f997` | Platform preset ffprobe E2E | G-12 #8 상환. 5개 플랫폼 프리셋 ffprobe 검증 |
| `b9d5164` | iOS parity matrix audit | G-09 Inc 2 진행. defer 15건 사유 기록 + static contract. iOS W1/E2E/CI job은 완료 증거 없음 |
| `07ab764` | Motion tracking IoU fixture | G-12 #4 상환. 실제 `MotionTrackingProvider.track` 평균 IoU 0.7929 / 최소 0.7095 |
| `07b666b` | Monotone `CurveEvaluator` | G-02 Inc 1 완료(순수 로직). App 호출 0회라 Inc 3 렌더 체이닝 전까지 visible value 없음 |
| `d7c8399` | `HSLCubeBuilder` | G-02 Inc 2 완료(순수 로직). App 호출 0회라 Inc 3 전까지 dead-code risk |
| `84b696c` | Subtitle word timings | G-01 Inc 1 완료. `wordTimings` 저장은 되나 active word renderer/UI/export parity 없음 |
| `cb1f466` | CapCut reassessment docs | 백로그/계획 문서 갱신. 코드 증거 없음 |
| `8efa65e` | `/gap-audit` command | 감사 반복 절차 추가. 코드 증거 없음 |

**중요한 판정 변화**

| 항목 | V7 | V8 |
|---|---|---|
| G-12 | 미착수 | 5/14 상환: #1 EQ, #2 NR, #3 ducking, #4 motion tracking, #8 platform presets |
| G-09 | Inc 1 빌드 복구 | Inc 1+2 진행. 매트릭스 재감사 완료, CI job/iOS W1/iOS E2E는 잔여 |
| G-02 | 미착수 | Inc 1~2 순수 로직 완료. `ColorGrade` 저장 필드, `ColorGradePixelProcessor` 체이닝, Mac/iOS UI는 잔여 |
| G-01 | 미착수 | Inc 1 워드 타이밍 보존 완료. caption style/active word render/UI/iOS는 잔여 |
| U-03 | `Track.isLocked` dead field | dead field 판정 정정: lock 헤더 UI + command guard 존재. 트랙 높이/잠금 시각/완료 증거는 잔여 |
| U-07 | 브라우저 그리드 격차 | 기존 Phase 작업으로 10탭, `LazyVGrid`, hover preview 일부 존재. G-07/G-08용 통합 카드/실콘텐츠는 잔여 |

---

## 2. 3분류 현황: 능가 / 검증부채 / 열위

### 2-A. 능가 또는 능가 후보(유지·확장)

| 축 | 근거 | V8 판정 |
|---|---|---|
| Pro 색 표면 | 3-way grade, scopes, wheel UI는 기존 구현. G-02 Inc 1~2로 커브/HSL 수학 착수 | 능가 후보. Inc 3+ 없으면 아직 CapCut 대비 완성 기능 아님 |
| Mac-native Pro output | ProRes/HDR 관련 완료 기록과 플랫폼 프리셋 ffprobe 증거 | 능가 후보. iOS export parity는 defer |
| Offline/local 검증 구조 | `run_e2e_export.sh`, fixtures, app harness 기반 검증 확대 | CapCut 대비 제품 신뢰성 기회 |
| IA/존 배치 | IA 계약, 타임라인 로컬 command ownership, bottom transport | 지킬 항목. 새 격차로 재보고 금지 |

### 2-B. 검증부채

| 항목 | 상태 | 근거 |
|---|---|---|
| G-12 잔여 | 9개 잔여 | #5 optical flow, #6 text animation, #7 title templates, #9 chapter/beat metadata, #10 audio extraction, #11 background removal real person, #12 auto reframe real tracking, #13 iCloud 2-device, #14 Photos drag |
| G-09 본대 | 진행중 | `PLATFORM_PARITY_MATRIX.md` defer 15건, iOS W1/E2E 없음, `.github/workflows/ci.yml`은 `swift test`만 확인 |
| G-02 Inc 1~2 | 순수 로직 검증만 | `CurveEvaluator` App=0 / `HSLCubeBuilder` App=0. `ColorGradePixelProcessor.swift`는 lift/gamma/gain만 적용 |
| G-01 Inc 1 | 저장 검증만 | `TextClipContent.wordTimings`는 저장/테스트 존재. `TextOverlayPixelProcessor`는 active word/highlight 미사용 |
| U-08 | 미착수 | `scripts/ui_capture.sh`, `scripts/ui_regression.sh`, `Tests/UIEvidence` 0건 |

### 2-C. CapCut 대비 열위

| 축 | 열위 내용 |
|---|---|
| 캡션 | 워드 타이밍 저장만 있고 karaoke/active word style, 스타일 갤러리, preview/export frame proof 없음 |
| 색보정 | 커브/HSL UI·저장·렌더가 없어 CapCut의 HSL/curves 대비 열위 유지 |
| 타임라인 | 전환 pill/FX·grade·speed badge/실제 필름스트립/hover scrub 없음 |
| 오디오 | 보컬 분리/보이스 FX는 dead code 또는 미착수. EQ/NR/덕킹은 검증 상환됐지만 G-05 전체는 미완 |
| iOS | defer 15건. Mac 기능이 iOS에서 동일하게 끝까지 동작한다고 말할 수 없음 |
| 제품 표면 | 홈, 설정, 토스트, 현지화 리소스, UI 회귀 인프라, 커맨드 팔레트 없음 |

---

## 3. 기능 G-ID 현황판

| G-ID | V8 상태 | 완료/진행 증거 | 남은 기준 |
|---|---|---|---|
| G-01 Styled Captions | 🟡 Inc 1 완료 | `WordTiming`, `TranscriptionSegment.words`, `TextClipContent.wordTimings`, `StyledCaptionWordTimingTests` 6개 | `CaptionStyle`, active-word renderer, Mac/iOS compositor, preview/export frame proof, UI 갤러리 |
| G-02 HSL/Curves | 🟡 Inc 1~2 완료 | `CurveEvaluatorTests`, `HSLCubeBuilderTests` | `ColorGrade` 저장 필드, render chain, golden/E2E, curve/HSL UI, iOS sheet |
| G-03 Adjustment Layer | ❌ 미착수 | `Clip.role`/adjustment grep 없음 | 모델+compositor+timeline+inspector |
| G-04 Filmstrip/Hover Scrub | ❌ 미착수 | `TimelineView`는 `thumbnailData(for:)` 단일 이미지 반복 | `FilmstripGenerator`, cache, hover scrub, perf |
| G-05 Audio Suite | 🟡 부분 | EQ/NR/ducking 검증은 G-12에서 상환 | `VocalSeparationService` App=0, voice FX 없음, 보컬분리 E2E 없음 |
| G-06 Easing UI | ❌ 미착수 | interpolation engine은 기존 존재, UI setting path 없음 | 피커 + custom cubic bezier + golden |
| G-07 Effect Pack/Browser/Plugins | ❌ 미착수 | 기존 효과/브라우저는 있으나 20종+plugin dogfood 범위 아님 | 20종 processor/golden, browser, registry |
| G-08 Local Asset Library | 🟡 부분 기반 | bundled SFX 리소스와 picker는 존재 | 음악 10+, 사용자 폴더, `.mcstickers`, license UX |
| G-09 iOS Parity | 🟡 Inc 1~2 | iOS generic build 기록, parity matrix, static contract | CI job, W1 recording, iOS E2E, defer 15건 해소 |
| G-10 FCPXML | ❌ 미착수 | exporter 없음 | FCPXML exporter + real FCP import proof |
| G-11 Preview/Export Policy | ❌ 미착수 | proxy 생성은 있으나 preview consume/export queue 없음 | render scale, proxy preview, export queue |
| G-12 Validation Debt | 🟡 5/14 | #1 EQ, #2 NR, #3 ducking, #4 motion tracking, #8 platform presets | #5~#7, #9~#14 |
| G-13 Retouch | 합의 대기 | 없음 | 범위 합의 필요 |
| G-14 Mac Recording Suite | 합의 대기 | 없음 | 범위 합의 필요 |

---

## 4. UI U-ID 현황판

| U-ID | V8 상태 | 실사 근거 | 판정 |
|---|---|---|---|
| U-01 Home/Project Manager | ❌ | `rg "HomeView|RecentProjects" App` 0건, `MovieCutMacApp.swift:12` `WindowGroup { ContentView(...) }` | 그대로 P0 |
| U-02 Timeline Rich Surface | ❌/부분 | `TimelineView.swift:736` link/sticker 아이콘만. `clipBadges|transitionPill|inspectorFocusSection` 0건. `thumbnailData(for:)` 단일 이미지 반복 | 전환 pill/FX·grade·speed badge/hover scrub 잔여 |
| U-03 Track Header | 🟡 부분 | `TimelineView.swift:680` lock icon, `EditorViewModel.swift:1489` command-backed toggle, `CommandSupport.swift:88` locked guard | `Track.isLocked` dead field 아님. track height/locked visual/GUI proof 잔여 |
| U-04 Toast Feedback | ❌ | `ToastCenter|ToastOverlay` App 0건. `ContentView.swift:361` statusBar 1줄 | 그대로 P1 |
| U-05 Settings | ❌ | `Settings {`, `SettingsView`, `AppPreferences` App 0건 | 그대로 P1 |
| U-06 Localization | ❌ | `find App -name '*.xcstrings' -o -name '*.lproj'` 0건. `NSLocalizedString` 산발 사용만 존재 | 그대로 P1 |
| U-07 Browser Grid Rhythm | 🟡 부분 | `MediaLibraryPanel.swift` 10탭, `LazyVGrid`, `browserGridCard`, hover preview 존재. `BrowserCard` 0건 | 기존 IA/그리드 반복 금지. G-07/G-08 콘텐츠와 공통 컴포넌트화 잔여 |
| U-08 UI Regression/Metrics | ❌ | `scripts/ui_capture.sh`, `scripts/ui_regression.sh`, `Tests/UIEvidence` 0건. `MOVIECUT_BOOTSTRAP_PROJECT`만 존재 | UI 트랙 선행 |
| U-09 Command Palette | ❌ | `CommandPalette|CommandRegistry` App 0건 | 그대로 P2 능가 표면 |

---

## 5. UI 격차표(실사 근거 포함)

| 격차 | 현재 실사 | CapCut 대비 의미 | V8 처리 |
|---|---|---|---|
| 홈/최근 프로젝트 | `WindowGroup`이 바로 `ContentView`를 로드. 최근 프로젝트 저장소 없음 | 앱 첫 표면/프로젝트 재진입 열위 | U-01 유지 |
| 타임라인 적용 상태 가시성 | transition pill/badge grep 0. link/sticker만 표시 | 사용자가 적용된 효과/전환/속도를 타임라인에서 못 봄 | U-02 유지 |
| 필름스트립 | 단일 `thumbnailData`를 타일 반복 | 시간축별 실제 프레임 정보 부족 | G-04와 묶음 |
| 피드백 | `lastStatusMessage`/`lastErrorMessage` 1줄 | 성공/실패/이력 체감 약함 | U-04 유지 |
| 설정 | macOS `Settings` scene 없음 | 제품 설정/기본값/프록시 정책 조절 불가 | U-05 유지 |
| 현지화 | String Catalog 없음 | 한국어 사용자 대상과 불일치 | U-06 유지 |
| 브라우저 | 그리드/hover는 있으나 G-07/G-08용 실제 썸네일·공통 컴포넌트 미완 | 기존 격차 축소. 새 P0 격차로 과장 금지 | U-07 낮춤/병합 |
| UI 증거 | populated capture/golden/click metric 없음 | UI 완료 선언 안전망 없음 | U-08 최우선 UI 슬롯 |

---

## 6. Dead Code / Dead Model Field 후보

### 6-A. Core dead code 후보(App 호출 0회)

| 후보 | grep 근거 | 판정 |
|---|---|---|
| `CenterChannelVocalSeparator` / `VocalSeparationMode` / `StereoFrames` / `AudioStemSeparator` | 자동 카운트: `CenterChannelVocalSeparator App=0 Tests=10`, `VocalSeparationMode App=0`, `StereoFrames App=0 Tests=8` | G-05 보컬분리 dead code. 앱 renderer/UI/E2E 필요 |
| `BackgroundRemovalProvider` | 자동 카운트: `App=0 Tests=9 Sources=1`; Mac/iOS 실제 렌더는 `PersonSegmentationCompositor`/inline path 사용 | legacy/provider dead code 후보. 삭제 금지, 역할 재정의 필요 |
| `StyleTransferProvider` | 자동 카운트: `App=0 Tests=7 Sources=1`; UI/renderer는 `VisualEffectPixelProcessor` 계열 | legacy/provider dead code 후보 |
| `CurveEvaluator` | `App=0 Tests=10 Sources=1` | G-02 Inc 1 산출물. dead code가 아니라 진행중이지만 Inc 3가 지연되면 A6 취지 위반 위험 |
| `HSLCubeBuilder` | `App=0 Tests=11 Sources=1` | G-02 Inc 2 산출물. render chain 연결 필요 |

### 6-B. Dead model/public field 후보

| 후보 | grep 근거 | 판정 |
|---|---|---|
| `TextClipContent.wordTimings` | 저장/테스트는 존재하나 `TextOverlayPixelProcessor`는 `wordTimings`를 읽지 않음. `CaptionStyle`도 아직 없음 | G-01 진행중 필드. active-word renderer/UI 전까지 사용자 가치 없음 |
| `CurvePoint`, `HSLBandCenter`, `HSLBand` | public 타입은 존재하나 `ColorGrade`에 `hslBands`/`curves` 저장 필드가 아직 없음 | G-02 진행중 public model surface. 저장 모델+renderer로 닫아야 함 |
| `Track.isLocked` | V7의 dead field 판정과 달리 `TimelineView.swift:680`, `EditorViewModel.swift:1489`, `CommandSupport.swift:88` 존재 | dead field 아님으로 정정. U-03 잔여는 track height/locked visual/GUI proof |

---

## 7. 개선 방향성

1. **새 순수 로직을 visible feature로 닫기**: G-02 Inc 3에서 `ColorGrade` 저장 모델 + `ColorGradePixelProcessor` HSL/curves 체이닝 + golden/E2E를 한 번에 묶어야 `CurveEvaluator`/`HSLCubeBuilder`가 dead-code risk에서 빠진다.
2. **G-12 잔여를 계속 상환**: 최근 상환 패턴은 좋다. #5 optical flow, #6 text animation, #7 title templates, #9 chapter metadata, #10 audio extraction을 app/E2E 또는 golden으로 먼저 닫는다.
3. **UI는 U-08을 먼저 깔기**: 홈/타임라인/토스트/설정/현지화 작업은 populated capture와 golden 없이는 완료 판정이 흔들린다.
4. **U-03/U-07은 과장하지 말고 축소 재정의**: lock UI와 브라우저 그리드는 이미 일부 존재한다. 남은 것은 track height/visual proof, 공통 카드/실콘텐츠화다.
5. **iOS는 matrix를 실행 계획으로 전환**: Inc 2는 문서/정적 감사다. Inc 3는 freeze/speed/reverse 또는 shared compositor 통일처럼 코드/E2E 증거가 필요하다.

---

## 8. 신규·변경 항목 요약

신규 G-ID/U-ID는 만들지 않는다. 기존 항목 내 상태만 갱신한다.

| 변경 | 내용 |
|---|---|
| G-12 | 5/14 상환으로 갱신. 잔여 목록 명시 |
| G-09 | Inc 2 완료가 아니라 진행중으로 유지. CI/W1/E2E 잔여 명시 |
| G-02 | Inc 1~2 순수 로직 완료, 저장 모델/renderer/UI 미완으로 재표기 |
| G-01 | Inc 1 저장 완료, renderer/UI/iOS 미완으로 재표기 |
| U-03 | `Track.isLocked` dead field 판정 취소. 부분 완료로 이동 |
| U-07 | 기존 browser grid/hover 구현을 반영해 열위 강도 낮춤 |
| Dead code | 보컬분리 외 `BackgroundRemovalProvider`, `StyleTransferProvider`, G-02 pure logic App=0 risk 추가 |

---

## 9. 권장 실행 순서(병행 슬롯)

| 슬롯 | 기능 트랙 | UI 트랙 |
|---|---|---|
| 1 | G-12 잔여 빠른 검증: #5 optical flow 또는 #10 audio extraction | U-08 capture/regression/click metric 인프라 |
| 2 | G-02 Inc 3: `ColorGrade` 저장 필드 + HSL/curve renderer chain + golden | U-02+G-04 timeline surface/filmstrip 묶음 |
| 3 | G-01 Inc 2~4: caption style model + active-word renderer + compositor | U-01 home/project manager |
| 4 | G-09 Inc 3: iOS freeze/speed/reverse 또는 shared compositor 통일 | U-04 toast -> U-05 settings |
| 5 | G-05 vocal separation renderer/E2E + voice FX | U-06 localization |
| 6 | G-07/G-08 effects/assets | U-07 browser common card + U-09 command palette |

---

## 10. 최우선 착수 항목 1개

**G-02 Inc 3: `ColorGrade` 저장 모델 + `ColorGradePixelProcessor` HSL/curve 체이닝 + golden/E2E.**

이유: V8에서 새로 생긴 `CurveEvaluator`와 `HSLCubeBuilder`가 모두 App 호출 0회라, 다음 증분이 없으면 새 코드가 사용자 가치 없이 남는다. Inc 3는 CapCut 대비 핵심 열위(HSL/curves)를 직접 줄이면서 dead-code risk도 동시에 해소한다. UI 슬롯에서는 별도로 U-08을 선행한다.

---

## 11. 실사 명령 요약

- 문서: `.claude/commands/gap-audit.md`, `CAPCUT_SURPASS_SPEC_20260703.md`, 직전 최신 `GAP_ANALYSIS_V7_FUNC_UI_20260703.md`, `CAPCUT_FEATURE_BACKLOG.md` §2.5, UI 원칙/감사 문서.
- Git: `git status --short`, `git branch --show-current`, `git log --oneline -40`, `git diff --name-status 5cd5155..HEAD`, `git show --stat 5cd5155..HEAD`.
- Code grep: `WordTiming|wordTimings`, `CurveEvaluator|HSLCubeBuilder|hslBands|ColorCurves`, audio E2E env, UI U-ID grep, App/Test/Sources symbol count.
- Zero-result checks: `HomeView|RecentProjects`, exact `Settings {`, `SettingsView|AppPreferences`, `CommandPalette|CommandRegistry`, `ToastCenter|ToastOverlay`, `Localizable.xcstrings`, `clipBadges|transitionPill|FilmstripGenerator|onContinuousHover`.
