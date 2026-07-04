# MovieCut vs CapCut 갭 분석 V9 — 기능 + UI 재평가 — 2026-07-05

> 작성일: 2026-07-05 / 브랜치: `feat/core-backend-expansion`
> 기준선: V8 `docs/GAP_ANALYSIS_V8_FUNC_UI_20260704.md` (`c3788ed`) / 재평가 대상: `c3788ed..fe9b062`
> 원천 스펙: `docs/CAPCUT_SURPASS_SPEC_20260703.md` v1.2+
> 규칙: 코드 존재는 완료 증거가 아니다. 완료는 preview/export/iOS 또는 명시 defer + 골든/E2E/ffprobe/GUI 증거로만 판정한다. Static contract는 회귀 잠금 전용이다.

---

## 0. 한 줄 요약

V8 이후 실제 진전은 **G-12 검증부채 3건 추가 상환(#10 오디오 추출, #5 옵티컬 플로우, #6 텍스트 애니메이션 13종)**이다. 특히 텍스트 애니메이션은 none-baseline 대비 export frame-diff로 no-op 회귀를 잡고 실제 burn-in 변화를 검증했으므로 기존 `🟡 텍스트 애니메이션 프리셋`은 검증 완료로 승격한다. 다만 G-02 HSL/Curves와 G-01 Styled Captions의 사용자-visible renderer/UI/iOS 격차, UI U-ID 미착수 축, iOS defer 축은 여전히 커서 **CapCut 능가 선언은 금지**다.

---

## 1. V8 이후 델타 커밋과 판정 변화

| 커밋 | 내용 | V9 판정 |
|---|---|---|
| `2756f96` | 오디오 추출 E2E 검증 | G-12 #10 상환. 실제 `extractAudio(from:)` 앱 경로 + audio-only export ffprobe/RMS 증거 보유 |
| `6ab1e03` | motion-aware optical flow slow motion | G-12 #5 상환. 기존 duplicate-frame 반복을 frame-diff로 잡고 motion-aware 보간 asset 경로로 보강 |
| `fe9b062` | text animation export verification | G-12 #6 상환. 13종 text animation preset을 none-baseline frame-diff E2E로 검증 |

**중요한 판정 변화**

| 항목 | V8 | V9 |
|---|---|---|
| G-12 | 5/14 상환 | 8/14 상환: #1 EQ, #2 NR, #3 ducking, #4 motion tracking, #5 optical flow, #6 text animation, #8 platform presets, #10 audio extraction |
| 텍스트 애니메이션 | 검증부채 | 13종 export proof 완료. 단 synthetic 320×240 fixture 기준이라 상용 템플릿 motion quality는 후속 품질 |
| 체감 완성도 | 65~72% | 68~74%로 소폭 상향 가능. 검증 인프라와 S0 debt 상환은 개선됐지만 G-02/G-01/UI/iOS 핵심 열위는 유지 |
| 자동 선택 다음 항목 | G-12 #6 | 엄격한 S0 순서 기준 G-12 #7 타이틀 템플릿 14종 |

---

## 2. 3분류 현황: 능가 / 검증부채 / 열위

### 2-A. 능가 또는 능가 후보

| 축 | 근거 | V9 판정 |
|---|---|---|
| Offline/local 검증 구조 | `run_e2e_export.sh`, fixtures, DEBUG app harness, ffprobe/Goertzel/RMS/frame-diff 측정이 계속 확대됨 | CapCut 대비 제품 신뢰성 기회. 아직 제품 기능 능가 선언은 아님 |
| Mac-native Pro output | ProRes/HDR 완료 기록 + 플랫폼 프리셋 5종 ffprobe | 능가 후보. iOS export parity는 defer |
| Pro 색 표면 | 3-way grade/scopes/wheel UI + G-02 Inc 1~2 순수 로직 | 능가 후보이나 HSL/curves renderer/UI 저장이 없어 아직 완성 기능 아님 |
| 텍스트 animation export proof | 13종 preset none-baseline 대비 frame-diff PASS | 검증 관점에서 진전. CapCut 타이틀/템플릿 library 품질까지 능가한 것은 아님 |

### 2-B. 검증부채

| 항목 | 상태 | 근거 |
|---|---|---|
| G-12 잔여 | 6개 잔여 | #7 title templates, #9 chapter/beat metadata, #11 background removal real person, #12 auto reframe real tracking, #13 iCloud 2-device, #14 Photos drag |
| G-09 본대 | 진행중 | `PLATFORM_PARITY_MATRIX.md` defer 15건, iOS W1/E2E 없음, CI job은 여전히 Mac/SwiftPM 중심 |
| G-02 Inc 1~2 | 순수 로직 검증만 | `CurveEvaluator` / `HSLCubeBuilder`는 아직 App-visible render chain 연결 전 |
| G-01 Inc 1 | 저장 검증만 | `wordTimings` 저장은 있으나 active-word/karaoke renderer와 style gallery/export proof 없음 |
| U-08 | 미착수 | populated UI capture/regression/click metric 인프라 없음 |

### 2-C. CapCut 대비 열위

| 축 | 열위 내용 |
|---|---|
| 캡션 | 워드 타이밍 저장만 완료. karaoke/active-word style, 스타일 갤러리, preview/export proof, iOS parity 없음 |
| 색보정 | HSL/curves 저장 모델·렌더 체이닝·UI·iOS가 없어 CapCut의 HSL/curves 대비 열위 유지 |
| 타임라인 | 전환 pill/FX·grade·speed badge/실제 필름스트립/hover scrub 없음 |
| 오디오 | EQ/NR/ducking은 강해졌지만 G-05 전체 기준 보컬 분리 renderer/E2E/voice FX가 남음 |
| iOS | defer 15건. Mac parity를 제품 수준으로 주장할 수 없음 |
| 제품 표면 | 홈, 설정, 토스트, 현지화, UI 회귀 인프라, 커맨드 팔레트 없음 |
| 타이틀/템플릿 | 텍스트 animation은 검증됐지만 타이틀 템플릿 14종 export proof는 아직 G-12 #7 잔여 |

---

## 3. 기능 G-ID 현황판

| G-ID | V9 상태 | 완료/진행 증거 | 남은 기준 |
|---|---|---|---|
| G-01 Styled Captions | 🟡 Inc 1 완료 | `WordTiming`, `TextClipContent.wordTimings`, `StyledCaptionWordTimingTests` | `CaptionStyle`, active-word renderer, Mac/iOS compositor, preview/export frame proof, UI gallery |
| G-02 HSL/Curves | 🟡 Inc 1~2 완료 | `CurveEvaluatorTests`, `HSLCubeBuilderTests` | `ColorGrade` 저장 필드, render chain, golden/E2E, curve/HSL UI, iOS sheet |
| G-03 Adjustment Layer | ❌ 미착수 | adjustment clip role grep 없음 | 모델+compositor+timeline+inspector |
| G-04 Filmstrip/Hover Scrub | ❌ 미착수 | `thumbnailData(for:)` 단일 이미지 반복 | `FilmstripGenerator`, cache, hover scrub, perf |
| G-05 Audio Suite | 🟡 부분 | EQ/NR/ducking G-12 상환 | vocal separation App path, voice FX, E2E |
| G-06 Easing UI | ❌ 미착수 | interpolation engine은 있으나 UI path 없음 | picker + custom cubic bezier + golden |
| G-07 Effect Pack/Browser/Plugins | ❌ 미착수 | 기존 효과/브라우저와 별개 | 20종 processor/golden, browser, registry |
| G-08 Local Asset Library | 🟡 부분 기반 | bundled SFX 리소스와 picker | 음악 10+, 사용자 폴더, sticker pack/license UX |
| G-09 iOS Parity | 🟡 Inc 1~2 | generic iOS build, parity matrix | CI job, W1 recording, iOS E2E, defer 15건 해소 |
| G-10 FCPXML | ❌ 미착수 | exporter 없음 | FCPXML exporter + real FCP import proof |
| G-11 Preview/Export Policy | ❌ 미착수 | proxy 생성은 있으나 preview consume/export queue 없음 | render scale, proxy preview, export queue |
| G-12 Validation Debt | 🟡 8/14 | #1/#2/#3/#4/#5/#6/#8/#10 상환 | #7/#9/#11/#12/#13/#14 |
| G-13 Retouch | 합의 대기 | 없음 | 범위 합의 필요 |
| G-14 Mac Recording Suite | 합의 대기 | 없음 | 범위 합의 필요 |

---

## 4. UI U-ID 현황판

V9에서 UI U-ID 자체의 신규 구현은 없다. 따라서 V8 판정을 유지한다.

| U-ID | V9 상태 | 판정 |
|---|---|---|
| U-01 Home/Project Manager | ❌ | 그대로 P0. 최근 프로젝트/홈 없음 |
| U-02 Timeline Rich Surface | ❌/부분 | 전환 pill/FX·grade·speed badge/hover scrub 잔여 |
| U-03 Track Header | 🟡 부분 | lock UI는 존재. track height/locked visual/GUI proof 잔여 |
| U-04 Toast Feedback | ❌ | status bar 1줄 중심. ToastCenter/Overlay 없음 |
| U-05 Settings | ❌ | Settings scene/AppPreferences 없음 |
| U-06 Localization | ❌ | String Catalog/lproj 없음 |
| U-07 Browser Grid Rhythm | 🟡 부분 | 기존 grid/hover 존재. 공통 카드/실콘텐츠화 잔여 |
| U-08 UI Regression/Metrics | ❌ | UI 트랙 선행 필요 |
| U-09 Command Palette | ❌ | CommandPalette/Registry 없음 |

---

## 5. Dead-code / dead-value risk

| 후보 | V9 판정 |
|---|---|
| `CurveEvaluator`, `HSLCubeBuilder` | G-02 진행중 순수 로직. Inc 3 지연 시 계속 dead-value risk |
| `TextClipContent.wordTimings` | 저장은 되지만 renderer/UI 미사용. G-01 Inc 2+ 필요 |
| `VocalSeparationService` 계열 | G-05 보컬분리 dead-code 후보. App path/E2E 필요 |
| `BackgroundRemovalProvider` | legacy/provider 역할 재정의 필요. 실인물 E2E는 G-12 #11 잔여 |
| `StyleTransferProvider` | legacy/provider dead-code 후보 |
| `TextAnimationPreset` | V9에서 export proof를 얻어 dead-value risk는 낮아짐. 단 title template library와 상용 motion quality는 별개 |

---

## 6. 완성도 재평가

- V8/loop-9 기준 체감 완성도: 65~72%.
- V9 기준 체감 완성도: **68~74%**.

상향 근거:
- G-12가 5/14에서 8/14로 증가했다.
- #5 optical flow는 기존 duplicate-frame 반복을 실제 frame-diff로 잡고 수리했다.
- #6 text animation은 none-baseline 대비 no-op export를 잡고 13종 전체 proof를 추가했다.
- #10 audio extraction은 실제 app command path + audio-only export를 검증했다.

상향 제한 근거:
- CapCut 체감 핵심인 HSL/curves, styled captions, title template library, filmstrip/hover scrub, adjustment layer, UI surface, iOS parity가 여전히 미완이다.
- G-12 잔여 6개 중 #13/#14는 실기기/수동 녹화 성격이라 자동 E2E만으로 끝나지 않는다.
- synthetic fixture 검증은 회귀 방지에 강하지만 상용 실사 품질을 보장하지 않는다.

따라서 V9 결론은 “검증 신뢰도와 일부 실기능은 개선됐으나, CapCut 능가 선언 금지”다.

---

## 7. 권장 실행 순서

엄격한 `/surpass` S0 자동 선택 순서:
1. **G-12 #7 타이틀 템플릿 14종** — 템플릿 적용→export 프레임 텍스트 존재 proof.
2. G-12 #9 챕터/비트 마커 metadata export.
3. G-12 #11 배경제거 실인물.
4. G-12 #12 자동 리프레임 실영상 추적.
5. G-12 #13 iCloud 2기기 충돌.
6. G-12 #14 Photos 앱 드래그.

CapCut 체감 가치 기준 병행 후보:
1. **G-02 Inc 3** — `ColorGrade` 저장 필드 + HSL/curve renderer chain + golden/E2E.
2. G-01 Inc 2~4 — caption style model + active-word renderer + compositor/UI/iOS.
3. U-08 — UI capture/regression/click metric 인프라.
4. U-02 + G-04 — timeline rich surface + filmstrip/hover scrub.
5. G-09 Inc 3 — iOS freeze/speed/reverse 또는 shared compositor 통일.

자동 선택 규칙은 S0 우선이므로 다음 개발 착수는 **G-12 #7 타이틀 템플릿 14종**이 맞다. 단, S0 게이트를 잠시 완화한다면 제품 체감 ROI는 G-02 Inc 3가 더 크다.

---

## 8. 실사 명령 요약

- `git status --short`
- `git log --oneline c3788ed..HEAD`
- `swift build`
- `swift test --filter 'TextAnimation|TextOverlayPixelProcessor|StaticContract|Golden'`
- `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`
- `scripts/run_e2e_export.sh`

---

## 9. 결론

V9에서는 S0 검증부채 상환 속도가 좋아졌고, `run_e2e_export.sh`가 실제 no-op export를 잡는 수준으로 강화됐다. 그러나 “능가”는 아직 기능/UX 전면 기준이 아니라 **검증 인프라와 일부 기능 트랙의 진전**에 가깝다. 다음 자동 작업은 G-12 #7로 타이틀 템플릿 검증부채를 상환하고, 이후 G-02/G-01/UI/iOS 본대 작업으로 넘어가야 한다.
