# Mac ↔ iOS 플랫폼 파리티 매트릭스 (G-09 Inc 2)

> 작성일: 2026-07-04 재감사 / 결정: Mac + iOS 동시 파리티 유지.
> 목적: G-09 Inc 2 요구사항에 따라 기능 × {Core, Mac UI, iOS UI, Mac compositor/export/preview, iOS compositor/export/preview} 상태를 정직하게 재감사하고, Mac-only 또는 iOS defer 항목마다 사유 1줄을 남긴다.
> 검증 성격: 코드 정적 감사 + 빌드 검증. iOS simulator W1 녹화는 아직 미수행이며, DoD 완료 증거로 과장하지 않는다.

## 1. 재감사 요약

- 빌드 상태: 2026-07-04 콜드 스타트에서 `swift build`, `swift test --filter 'StaticContract|Golden'`, Mac `xcodebuild`, `scripts/run_e2e_export.sh` PASS. Inc 2 종료 검증에는 iOS generic build도 포함한다.
- iOS shared 렌더 경로가 확인된 항목: 색보정, warmth/tint, 3-way color grade, LUT/필터 일부, mask, text burn-in, canvas background.
- 주요 iOS defer 범위: 크로마키 shared processor 위임, two-source transitions, shared background-removal compositor, freeze frame export/preview, speed ramp, reverse playback/export, destructive noise reduction apply, autosave/crash recovery UI/lifecycle, ProRes/GIF/still export, 일부 marker/quick-tools UX.
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
  - iOS preview/export: 🟡 inline `applyChromaKey` path, shared processor 미위임
  - 상태: 🟡 iOS defer — 사유: iOS UI는 있으나 `IOSCustomVideoCompositor`가 `ChromaKeyPixelProcessor`로 통일되지 않아 edgeShrink/softness parity를 보장하지 못함

- 전환 two-source
  - Core: ✅ `TransitionPixelProcessor`
  - Mac UI: ✅ transition controls
  - iOS UI: ❌ 동등 transition editing surface 미확인
  - Mac preview/export: ✅ two-source compositor path
  - iOS preview/export: ❌ `TransitionPixelProcessor.apply` 미배선
  - 상태: 🟡 iOS defer — 사유: iOS compositor/export에 two-source instruction path가 없어 current frame 단일 소스 합성만 수행

- 배경제거 Vision
  - Core: ✅ `BackgroundRemovalProvider`, `PersonSegmentationCompositor`
  - Mac UI: ✅ Remove Background toggle
  - iOS UI: 🟡 flag metadata 소비 가능
  - Mac preview/export: ✅ `PersonSegmentationCompositor`
  - iOS preview/export: 🟡 inline `applyPersonSegmentation`, `PersonSegmentationCompositor` 미사용
  - 상태: 🟡 iOS defer — 사유: shared matte/refine helper 미사용으로 Mac과 edge/refinement parity가 깨질 수 있음

- 정지프레임
  - Core: ✅ `FreezeFrameCommand`
  - Mac UI: ✅ toolbar/inspector action
  - iOS UI: ❌ action surface 미확인
  - Mac preview/export: ✅ E2E duration proof 있음
  - iOS preview/export: ❌ freeze export/preview branch 미확인
  - 상태: 🟡 iOS defer — 사유: `FreezeFrameCommand`를 호출하는 iOS UI와 export/preview special-case가 없음

- speed ramp
  - Core: ✅ `SpeedRampCurve`
  - Mac UI: ✅ speed curve editor
  - iOS UI: ❌ 동등 editor 미확인
  - Mac preview/export: ✅ `insertSpeedRampSegments`
  - iOS preview/export: ❌ `SpeedRampCurve` 미사용
  - 상태: 🟡 iOS defer — 사유: iOS playback/export가 clip speed ramp points를 segment insert로 반영하지 않음

- 역재생
  - Core: ✅ clip `isReversed` 모델/command path
  - Mac UI: ✅ reverse controls
  - iOS UI: ❌ action surface 미확인
  - Mac preview/export: ✅ reverse handling 존재
  - iOS preview/export: ❌ reverse branch 미확인
  - 상태: 🟡 iOS defer — 사유: iOS timeline/export가 `isReversed`를 소비하지 않음

- 오디오 덕킹
  - Core: ✅ `AudioDuckingPlanner`, clip ducking ranges
  - Mac UI: ✅ inspector command path
  - iOS UI: ❌ 동등 duck/clear action 미확인
  - Mac preview/export: ✅ app E2E RMS proof 있음
  - iOS preview/export: 🟡 audio composition 기본 insert만 확인
  - 상태: 🟡 iOS defer — 사유: iOS UI/action 및 ramped volume parameter parity 미검증

- EQ
  - Core: ✅ `AudioEqualizerService` real DSP
  - Mac UI: ✅ preset + five bands
  - iOS UI: ❌ 동등 EQ controls 미확인
  - Mac preview/export: ✅ app E2E spectrum proof 있음
  - iOS preview/export: ❌ real EQ apply/export path 미확인
  - 상태: 🟡 iOS defer — 사유: S0에서 Mac real DSP를 복구했지만 iOS action/export parity는 아직 없음

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

## 3. Mac-only 또는 iOS defer 항목

- Mac-only 또는 iOS defer 항목: 3-way color grade advanced UI — 사유: iOS render는 shared이나 wheel/scope editing surface가 Mac 대비 얕음.
- Mac-only 또는 iOS defer 항목: LUT/필터 full processor-only path — 사유: iOS compositor에 legacy CIFilter switch가 병존.
- Mac-only 또는 iOS defer 항목: 크로마키 shared processor — 사유: iOS compositor가 `ChromaKeyPixelProcessor`를 직접 위임하지 않음.
- Mac-only 또는 iOS defer 항목: 전환 two-source — 사유: iOS compositor/export에 `TransitionPixelProcessor` 및 two-source instruction path 미배선.
- Mac-only 또는 iOS defer 항목: 배경제거 shared compositor — 사유: iOS가 `PersonSegmentationCompositor` 미사용.
- Mac-only 또는 iOS defer 항목: 정지프레임 — 사유: iOS UI/action/export special-case 미배선.
- Mac-only 또는 iOS defer 항목: speed ramp — 사유: iOS preview/export가 `SpeedRampCurve` 미사용.
- Mac-only 또는 iOS defer 항목: 역재생 — 사유: iOS preview/export가 `isReversed` 미소비.
- Mac-only 또는 iOS defer 항목: 오디오 덕킹 — 사유: iOS duck/clear UI와 ramped volume parameter 검증 없음.
- Mac-only 또는 iOS defer 항목: EQ — 사유: iOS real EQ action/export path 없음.
- Mac-only 또는 iOS defer 항목: 노이즈감소 apply — 사유: iOS destructive denoise/source replacement action 없음.
- Mac-only 또는 iOS defer 항목: 자동저장/크래시 복구 — 사유: iOS lifecycle autosave/recovery UX 미배선.
- Mac-only 또는 iOS defer 항목: ProRes/GIF/스틸 export — 사유: iOS export는 `.mov` HighestQuality 중심, Pro 출력은 Mac 우선 범위로 defer.
- Mac-only 또는 iOS defer 항목: platform preset export — 사유: Mac은 ffprobe proof가 있으나 iOS export preset sheet/engine parity 없음.
- Mac-only 또는 iOS defer 항목: marker/quick tools — 사유: iOS touch sheet IA로 재설계 필요.

## 4. 다음 Inc 3 실행 순서

- 1순위: iOS export/preview 구조가 Core 모델을 소비하도록 freeze frame, speed ramp, reverse를 묶어 배선한다.
- 2순위: iOS compositor를 Mac과 같은 shared helpers로 통일한다: `ChromaKeyPixelProcessor`, `TransitionPixelProcessor`, `PersonSegmentationCompositor`.
- 3순위: iOS autosave/crash recovery lifecycle을 `ProjectStore`로 연결한다.
- 4순위: iOS export options sheet에 platform preset/mp4 settings를 반영한다.
- 5순위: iOS inspector sheet에 EQ/ducking/noise reduction actions를 추가하되, 각 항목은 Mac처럼 app/E2E proof를 요구한다.

## 5. 검증 한계

- 이번 G-09 Inc 2는 재감사와 문서/정적 계약 갱신이다. iOS W1 시뮬레이터 녹화는 아직 없음.
- Static contract는 회귀 잠금일 뿐 완료 증거가 아니다. iOS defer 항목은 Inc 3 이후 기능별 E2E 또는 실기기/시뮬레이터 증거가 필요하다.
- CoreSimulator out-of-date 경고는 Mac build/E2E 중 simulator device support 경고로 계속 나타난다. iOS generic device build는 `CODE_SIGNING_ALLOWED=NO`로 검증한다.
