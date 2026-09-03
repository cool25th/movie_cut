# Mac ↔ iOS 플랫폼 파리티 매트릭스 (G-09 Inc 2)

> 작성일: 2026-07-04 재감사 · **2026-09-03 capcut-surpass 통합 반영(§8)** / 결정: Mac + iOS 동시 파리티 유지.
> 목적: G-09 Inc 2 요구사항에 따라 기능 × {Core, Mac UI, iOS UI, Mac compositor/export/preview, iOS compositor/export/preview} 상태를 정직하게 재감사하고, Mac-only 또는 iOS defer 항목마다 사유 1줄을 남긴다.
> 검증 성격: 코드 정적 감사 + 빌드 검증. iOS simulator W1 녹화는 아직 미수행이며, DoD 완료 증거로 과장하지 않는다.

## 1. 재감사 요약

- 빌드 상태: 2026-07-04 콜드 스타트에서 `swift build`, `swift test --filter 'StaticContract|Golden'`, Mac `xcodebuild`, `scripts/run_e2e_export.sh` PASS. Inc 2 종료 검증에는 iOS generic build도 포함한다.
- iOS 빌드 게이트: 2026-08-14부터 CI iOS 빌드가 **차단**(continue-on-error 제거) + `verify_gate.sh` 4단계(iOS generic) 추가 — iOS 스킴이 2주간(cd1458f 수리 전) 못 빌드되는 동안 아무 게이트가 이를 못 잡았던 사고의 재발 방지 (W4/kiro 9.3).
- iOS shared 렌더 경로가 확인된 항목: 색보정, warmth/tint, 3-way color grade, LUT/필터 일부, mask, text burn-in, canvas background, 크로마키 export(full settings, build-verified), 배경제거 export(shared compositor, build-verified).
- 주요 iOS defer 범위: two-source transitions, iOS preview의 크로마/전환 렌더링, iOS 행동 검증 인프라 전반(kiro 9.2 — 이것이 크로마/배경제거 행동 검증의 선행 조건), freeze frame export/preview, speed ramp, reverse playback/export, destructive noise reduction apply, autosave/crash recovery UI/lifecycle, ProRes/GIF/still export, 일부 marker/quick-tools UX.
- G-09 AC2 판정: Mac-only 셀은 0건이 아니므로 각 항목을 명시적 defer로 유지한다. 해소는 G-09 Inc 3 이후 순서대로 진행한다.

## 2. 기능별 파리티 매트릭스

- 색보정(밝기/대비/채도)
  - Core: ✅ `ColorCorrectionPixelProcessor`
  - Mac UI: ✅ Inspector controls
  - iOS UI: ✅ effects inspector/basic controls
  - Mac preview/export: ✅ custom compositor shared processor
  - iOS preview/export: ✅ `PreviewView` + `IOSCustomVideoCompositor` shared processor
  - 상태: ✅ parity 유지

- warmth/tint
  - Core: ✅ `ColorCorrectionPixelProcessor`의 `6500 - warmth * 2000` 방향
  - Mac UI: ✅
  - iOS UI: ✅
  - Mac preview/export: ✅
  - iOS preview/export: ✅ shared processor 위임
  - 상태: ✅ 2026-06-24 P0 divergence fix 유지

- 3-way color grade
  - Core: ✅ `ColorGradePixelProcessor`
  - Mac UI: ✅ wheel/scope controls
  - iOS UI: 🟡 basic effects inspector 노출, Mac wheel/scope 동등 UI는 defer
  - Mac preview/export: ✅
  - iOS preview/export: ✅ `ColorGradePixelProcessor.apply`
  - 상태: 🟡 iOS UI depth defer — 사유: 렌더 parity는 있으나 Mac의 wheel/scope editing affordance가 iOS 시트에 동등하게 없음

- LUT/필터(VisualEffect)
  - Core: ✅ `VisualEffectPixelProcessor`
  - Mac UI: ✅ effects/filter picker
  - iOS UI: ✅ `IOSFilterPickerView`
  - Mac preview/export: ✅ shared processor
  - iOS preview/export: ✅ LUT 계열은 `VisualEffectPixelProcessor.apply`; 일부 legacy CIFilter switch도 병존
  - 상태: 🟡 partial parity — 사유: iOS compositor에 legacy per-effect switch가 남아 있어 Mac과 완전한 processor-only 구조는 아님

- 마스킹
  - Core: ✅ `MaskPixelProcessor`
  - Mac UI: ✅ mask canvas/inspector
  - iOS UI: ✅ `IOSMaskCanvasView`
  - Mac preview/export: ✅
  - iOS preview/export: ✅ `MaskPixelProcessor.apply`
  - 상태: ✅ static parity 유지

- 텍스트 burn-in
  - Core: ✅ `TextOverlayPixelProcessor`
  - Mac UI: ✅ text/subtitle controls
  - iOS UI: ✅ `IOSTextClipSheet`, auto subtitle sheet
  - Mac preview/export: ✅
  - iOS preview/export: ✅ `TextOverlayPixelProcessor.apply`
  - 상태: ✅ static parity 유지

- 캔버스 배경
  - Core: ✅ `CanvasBackgroundPixelProcessor`
  - Mac UI: ✅ canvas controls
  - iOS UI: ✅ `IOSCanvasSettingsView`
  - Mac preview/export: ✅
  - iOS preview/export: ✅ `CanvasBackgroundPixelProcessor.compose`
  - 상태: ✅ static parity 유지

- 크로마키
  - Core: ✅ `ChromaKeyPixelProcessor`
  - Mac UI: ✅ `ChromaKeyView` + eyedropper
  - iOS UI: 🟡 `IOSChromaKeyView` exists
  - Mac preview/export: ✅ `ChromaKeyPixelProcessor.apply`
  - iOS preview/export: 🟡 **wired, build-verified** (ed449f8): export가 full `ChromaKeySettings`(softness/spill/edgeShrink)를 `ChromaKeyPixelProcessor`로 위임 — Mac과 동일 분기. **행동 검증은 iOS 테스트 인프라(kiro 9.2) 대기중.** iOS preview(`PreviewView`)는 여전히 크로마 미표시 — 별도 항목.
  - 상태: 🟡 iOS export만 shared processor 위임 완료. iOS preview 크로마 렌더링과 행동 검증은 9.2 이후.

- 전환 two-source
  - Core: ✅ `TransitionPixelProcessor`
  - Mac UI: ✅ transition controls
  - iOS UI: ❌ 동등 transition editing surface 미확인
  - Mac preview/export: ✅ two-source compositor path
  - iOS preview/export: ❌ `TransitionPixelProcessor.apply` 미배선
  - 상태: 🟡 iOS defer — 사유: iOS compositor/export에 two-source instruction path가 없어 current frame 단일 소스 합성만 수행. **의도적 보류**: iOS 행동 검증 인프라(9.2) 없이 배선하면 빌드만 통과하는 미검증 코드가 됨(판정 규율 §6 rule 1).

- 배경제거 Vision
  - Core: ✅ `BackgroundRemovalProvider`, `PersonSegmentationCompositor`
  - Mac UI: ✅ Remove Background toggle
  - iOS UI: 🟡 flag metadata 소비 가능
  - Mac preview/export: ✅ `PersonSegmentationCompositor`
  - iOS preview/export: 🟡 **wired, build-verified** (ed449f8): export 컴포지터가 `PersonSegmentationCompositor.align`/`removeBackground` 사용, `needsCustomCompositor`가 `isBackgroundRemoved` 포함(이전엔 조용한 no-op), Vision 실패 시 프레임 유지(Mac F-08 AC④와 정렬). **행동 검증은 9.2 대기중.**
  - 상태: 🟡 iOS export 경로 shared compositor 위임 + no-op 버그 수정 완료. 행동 검증은 9.2 이후.

- 정지프레임
  - Core: ✅ `FreezeFrameCommand`
  - Mac UI: ✅ toolbar/inspector action
  - iOS UI: ❌ action surface 미확인
  - Mac preview/export: ✅ E2E duration proof 있음
  - iOS preview/export: 🟡 Step 7 — `IOSExportEngine` freeze branch 구현됨(tiny source → scaleTimeRange), 시뮬레이터 E2E 미수행
  - 상태: 🟡 구현/검증대기 — 사유: export 경로는 구현됐으나 iOS actual-app E2E 인프라가 없어 런타임 검증 대기

- speed ramp
  - Core: ✅ `SpeedRampCurve` + `ClipTimeMapping` (Step 3)
  - Mac UI: ✅ speed curve editor
  - iOS UI: ❌ 동등 editor 미확인
  - Mac preview/export: ✅ `insertSpeedRampSegments`
  - iOS preview/export: 🟡 Step 7 — `IOSExportEngine.applySpeedRamp` segment walker 구현됨, 시뮬레이터 E2E 미수행
  - 상태: 🟡 구현/검증대기 — 사유: export ramp 경로는 구현됐으나 iOS actual-app E2E 인프라가 없어 런타임 검증 대기

- 역재생
  - Core: ✅ clip `isReversed` 모델/command path
  - Mac UI: ✅ reverse controls
  - iOS UI: ❌ action surface 미확인
  - Mac preview/export: ✅ reverse handling 존재
  - iOS preview/export: 🟡 Step 7 — `IOSExportEngine.renderReversedAsset` + `ReverseRenderService` 구현됨, 시뮬레이터 E2E 미수행
  - 상태: 🟡 구현/검증대기 — 사유: export reverse 경로는 구현됐으나 iOS actual-app E2E 인프라가 없어 런타임 검증 대기

- 오디오 덕킹
  - Core: ✅ `AudioDuckingPlanner`, clip ducking ranges
  - Mac UI: ✅ inspector command path
  - iOS UI: ❌ duck/clear action 표면 없음(2026-09-03 확인 — 엔진·프리뷰는 모델 필드 `duckingRanges`/`duckingLevel` 소비)
  - Mac preview/export: ✅ app E2E RMS proof 있음
  - iOS preview/export: ✅(렌더 경로) stage-4(2026-09-02) placed-span 덕킹 — Mac `applyDuckingRamps` 계약과 동일 램프(attack 0.12s·release 0.25s)를 공유 오디오 믹스 플랜에 적용, 프리뷰·export가 같은 플랜 소비. `IOSAudioDuckingEQTests` 5종(감쇠 ≥6dB·2x placed-span 판별기)
  - 상태: 🟡 렌더 parity 확보·iOS UI action 표면 없음 — 사유: 덕 창/레벨은 Core 모델 필드로 존재하나 iOS 시트에 발동 액션이 없어 사용자가 iOS에서 설정 불가

- EQ
  - Core: ✅ `AudioEqualizerService` real DSP
  - Mac UI: ✅ preset + five bands
  - iOS UI: ❌ EQ controls 표면 없음(2026-09-03 확인)
  - Mac preview/export: ✅ app E2E spectrum proof 있음
  - iOS preview/export: ✅(렌더 경로) stage-4(2026-09-02) EQ'd 클립 오디오를 공유 Core `AudioEqualizerService.apply`로 오프라인 파생해 삽입(원본 시간 배치 보존 — sourceRange 1:1)·`eqDerivations` 캐시는 Mac `equalizedPreviewAudio` 패리티. bassBoost 저/고 비 ≥2배 스펙트럼 행동 테스트
  - 상태: 🟡 렌더 parity 확보·iOS UI 표면 없음 — 사유: iOS에 EQ 프리셋/밴드 편집 시트가 없음(렌더는 프로젝트 메타데이터 기반으로만 동작)

- 노이즈감소 apply
  - Core: ✅ `NoiseReductionService` real DSP
  - Mac UI: ✅ destructive apply action
  - iOS UI: ❌ action surface 미확인
  - Mac preview/export: ✅ app E2E SNR proof 있음
  - iOS preview/export: ❌ destructive denoise apply path 미확인
  - 상태: 🟡 iOS defer — 사유: iOS에 `applyNoiseReduction` action 및 source replacement flow가 없음

- 자동저장/크래시 복구
  - Core: ✅ `ProjectStore` autosave primitives
  - Mac UI/lifecycle: ✅ autosave status + recovery harness
  - iOS UI/lifecycle: ❌ autosave/recovery UX 미확인
  - Mac proof: ✅ E2E autosave file proof 있음
  - iOS proof: ❌
  - 상태: 🟡 iOS defer — 사유: iOS app lifecycle에서 ProjectStore autosave/recovery를 호출하는 경로가 없음

- export formats/platform presets
  - Core: ✅ `ExportSettings`, `PlatformExportPreset`
  - Mac UI/export: ✅ format controls + platform preset ffprobe proof
  - iOS UI/export: 🟡 basic export sheet/progress, `.mov` HighestQuality 중심
  - 상태: 🟡 iOS defer — 사유: iOS `IOSExportEngine`은 `.mov` output 중심이며 mp4/platform preset/ProRes/GIF/still parity가 없음

- markers / quick tools
  - Core: ✅ markers and several command surfaces
  - Mac UI: ✅ marker/quick tools surfaces broad
  - iOS UI: 🟡 auto assistant/subtitles/music/SFX 일부만 존재
  - preview/export: 기능별 편차
  - 상태: 🟡 iOS defer — 사유: Mac Quick Tools 상당수와 marker management가 iOS touch sheet pattern으로 정리되지 않음

- 프록시 재생 + 타임라인 배지 (B-I7)
  - Core: ✅ `ProxyGenerator`, `ProxyInfo`, `ProxyResolution`(480p/540p/720p/1080p), `PlaybackSettings.useProxyPlayback`+`.proxyResolution`, `ProxyBadgeState.resolve`
  - Mac UI: ✅ 라이브러리 생성 버튼/상태 + Inspector 재생 토글 + **해상도 선택 4단**(720p 권장 표시) + **타임라인 클립 배지**(idle/active 2상태)
  - iOS UI: ❌ 없음
  - Mac preview/export: ✅ preview가 프록시 소비, export는 원본 유지(B-I7 요구사항)
  - iOS preview/export: 🟡 stage-4-1(2026-09-02) `IOSSourcePolicy` — 프리뷰는 `.proxyWhenAvailable` 정책으로 프록시 소비 가능(프록시 존재 시 원본 판독 행동 증명·`IOSSourcePolicyTests`), export는 `.originalOnly` 명시 고정(마스터 다운스케일 방지)
  - 상태: 🟡 iOS defer — 사유: 프리뷰 소비 정책은 배선됐으나 **프록시 생성 경로와 iOS 타임라인 배지 표면이 없음**. 실앱 증거: `proxy_generated=1 proxy_playback=0 proxy_badge=idle` / `proxy_playback=1 proxy_badge=active` (2026-07-30, `MOVIECUT_UITEST_PROXY_BADGE`)

## 3. Mac-only 또는 iOS defer 항목

- Mac-only 또는 iOS defer 항목: 3-way color grade advanced UI — 사유: iOS render는 shared이나 wheel/scope editing surface가 Mac 대비 얕음.
- Mac-only 또는 iOS defer 항목: LUT/필터 full processor-only path — 사유: iOS compositor에 legacy CIFilter switch가 병존.
- Mac-only 또는 iOS defer 항목: 크로마키 preview/행동검증 — 사유: iOS **export는 full settings로 `ChromaKeyPixelProcessor` 위임 완료**(ed449f8, build-verified)·iOS preview 크로마 렌더링과 행동 검증(9.2) 잔여.
- Mac-only 또는 iOS defer 항목: 전환 two-source — 사유: iOS compositor/export에 `TransitionPixelProcessor` 및 two-source instruction path 미배선(2026-09-03 확인 — 여전).
- Mac-only 또는 iOS defer 항목: 배경제거 행동검증 — 사유: iOS **export가 `PersonSegmentationCompositor` 사용 완료**(ed449f8, build-verified)·행동 검증(9.2) 잔여.
- Mac-only 또는 iOS defer 항목: 정지프레임 — 사유: iOS export freeze branch는 구현(§6 Step 7)·UI action 표면과 시뮬레이터 E2E 미수행.
- Mac-only 또는 iOS defer 항목: speed ramp — 사유: iOS export `applySpeedRamp`는 구현(§6 Step 7)·동등 에디터 UI와 시뮬레이터 E2E 미수행.
- Mac-only 또는 iOS defer 항목: 역재생 — 사유: iOS export `renderReversedAsset`은 구현(§6 Step 7)·action 표면과 시뮬레이터 E2E 미수행.
- Mac-only 또는 iOS defer 항목: 오디오 덕킹 — 사유: iOS duck/clear UI 표면 없음(렌더 placed-span parity는 2026-09-02 stage-4 완료 — 위 행 참조).
- Mac-only 또는 iOS defer 항목: 프록시 재생 + 타임라인 배지 — 사유: 프리뷰 소비 정책은 stage-4-1 배선(`IOSSourcePolicy`)·프록시 **생성 경로와 배지 표면** 없음. Core `ProxyBadgeState.resolve`는 플랫폼 중립이라 iOS 배선 시 재사용 가능.
- Mac-only 또는 iOS defer 항목: EQ — 사유: iOS EQ UI 표면 없음(렌더 파생·캐시는 2026-09-02 stage-4 완료 — 위 행 참조).
- Mac-only 또는 iOS defer 항목: 노이즈감소 apply — 사유: iOS destructive denoise/source replacement action 없음.
- Mac-only 또는 iOS defer 항목: 자동저장/크래시 복구 — 사유: iOS lifecycle autosave/recovery UX 미배선.
- Mac-only 또는 iOS defer 항목: ProRes/GIF/스틸 export — 사유: iOS export는 `.mov` HighestQuality 중심, Pro 출력은 Mac 우선 범위로 defer.
- Mac-only 또는 iOS defer 항목: platform preset export — 사유: Mac은 ffprobe proof가 있으나 iOS export preset sheet/engine parity 없음.
- Mac-only 또는 iOS defer 항목: marker/quick tools — 사유: iOS touch sheet IA로 재설계 필요.

## 4. 다음 Inc 3 실행 순서

- 1순위: iOS export/preview 구조가 Core 모델을 소비하도록 freeze frame, speed ramp, reverse를 묶어 배선한다. **(2026-08-23 명문화 승인)** Inc3 각 항목의 DoD에는 preview에서 사용자가 발동 가능한 액션 표면(iOS UI)과 실기기 증거(D)를 포함한다. UI 제외 시 해당 항목은 '배선 완료·U 미노출'로 표기한다.
- 2순위: iOS compositor를 Mac과 같은 shared helpers로 통일한다: `ChromaKeyPixelProcessor`, `TransitionPixelProcessor`, `PersonSegmentationCompositor`.
- 3순위: iOS autosave/crash recovery lifecycle을 `ProjectStore`로 연결한다.
- 4순위: iOS export options sheet에 platform preset/mp4 settings를 반영한다.
- 5순위: iOS inspector sheet에 EQ/ducking/noise reduction actions를 추가하되, 각 항목은 Mac처럼 app/E2E proof를 요구한다.

## 5. 검증 한계

- 이번 G-09 Inc 2는 재감사와 문서/정적 계약 갱신이다. iOS W1 시뮬레이터 녹화는 아직 없음.
- Static contract는 회귀 잠금일 뿐 완료 증거가 아니다. iOS defer 항목은 Inc 3 이후 기능별 E2E 또는 실기기/시뮬레이터 증거가 필요하다.

## 6. Step 7 업데이트 (core-editing repair handoff, 2026-07-28)

> 핵심 경고: **iOS actual-app 테스트 인프라(XCUITest 타겟, 시뮬레이터 E2E)가 전혀 없다.** 아래 Step 7 항목은 코드 구현은 완료됐으나 런타임 검증이 불가능하므로, 모두 "구현 완료 / 검증 대기" 상태다. 완료로 처리하지 않는다.

### 구현 완료 (검증 대기)
- **속도(배속)**: `IOSExportEngine.insertClip`에 constant-rate `scaleTimeRange` 추가 + `IOSExportEngine.applySpeedRamp` segment walker 구현. iOS `PreviewView.insertClip`도 constant-rate scale 적용. — 시뮬레이터 E2E 미수행.
- **역재생**: `IOSExportEngine.renderReversedAsset` + `ReverseRenderService` 연동 구현. — 시뮬레이터 E2E 미수행.
- **정지프레임**: `IOSExportEngine` freeze branch(tiny source → scaleTimeRange) 구현. — 시뮬레이터 E2E 미수행.
- **iOS 시간 매핑**: `IOSAutoAssistantView`, `IOSAutoSubtitlesView`, `IOSKeyframeEditorView`가 `Clip.makeTimeMapping()` 사용 (마일스톤 A의 macOS 경로와 동일). — 시뮬레이터 E2E 미수행.
- **iOS Preview composition 수학**: `PreviewView.sourceTimeRange`가 `ClipTimeMapping` 기반으로 교정 (더 이상 `min(source, timeline)` 1:1 아님). — 시뮬레이터 E2E 미수행.

### overclaim 강등 (정적 계약만으로 ✅ 표시된 항목)
다음 6개 항목은 Core shared processor 위임은 사실이나, iOS actual-app E2E 없이 source-string StaticContract만으로 ✅ "parity 유지"를 표시한 것은 과대 표현이다. iOS 시뮬레이터 E2E가 확보되기 전까지 🟡(검증 미비)로 간주한다:
- 색보정 (ColorCorrectionPixelProcessor) — 렌더 경로 shared, iOS 런타임 미검증
- warmth/tint — 동일
- 3-way color grade — 동일
- 마스킹 (MaskPixelProcessor) — 동일
- 텍스트 burn-in (TextOverlayPixelProcessor) — 동일
- 캔버스 배경 (CanvasBackgroundPixelProcessor) — 동일

### 여전히 defer (이번 Step 7 범위 외)
- 크로마키 shared processor 위임 (iOS inline `applyChromaKey` → `ChromaKeyPixelProcessor` 전환)
- two-source transitions (`TransitionPixelProcessor` iOS 배선)
- 배경제거 shared compositor (`PersonSegmentationCompositor` iOS 사용)
- 오디오 덕킹/EQ/노이즈감소 iOS UI action + export wiring
- ProRes/GIF/스틸 export, platform preset export
- iOS autosave/crash recovery lifecycle
- `IOSPlaybackEngine` (dead code — ✅ 제거됨, `7b5b2ad`)
- CoreSimulator out-of-date 경고는 Mac build/E2E 중 simulator device support 경고로 계속 나타난다. iOS generic device build는 `CODE_SIGNING_ALLOWED=NO`로 검증한다.

## 8. capcut-surpass 통합 재감사 (2026-09-03, 문서 갱신)

> `codex/integrate-capcut-surpass` stage-4 완료(2026-09-02) 이후 문서 재감사 — 덕킹·EQ·프록시 행과 §3 사유를 현재 코드 상태로 갱신했다. 근거: `IOSExportEngine` placed-span 덕킹/EQ 파생 + `eqDerivations` 캐시 · `IOSSourcePolicy` · 테스트 `IOSAudioDuckingEQTests`/`IOSSourcePolicyTests`(iOS 시뮬 전체 83/20 PASS — 2026-09-03 BUG-ACC-09 종료 시점).
> 유의: 이번에 렌더 경로로 표시된 iOS 항목은 시뮬레이터 유닛/구조 테스트 기반이다. 실기기 행동 검증은 G-27 잔여(1/3 완료 — iPhone 13 Pro 2026-08-22), two-source transition은 여전 미배선. 상세 경위: `CAPCUT_SURPASS_INTEGRATION_PROGRESS.md` 4단계.
