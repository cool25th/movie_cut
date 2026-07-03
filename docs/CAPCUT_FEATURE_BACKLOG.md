# CapCut 기능 백로그 & 작업 핸드오프

> 목적: 다른 세션(콜드 스타트)에서 이 문서만 읽고 바로 작업을 이어갈 수 있도록 정리한 핸드오프 문서.
> 작성일: 2026-06-09 / 기준 브랜치: `main`
> 관련 문서: `docs/GAP_ANALYSIS_V6.md` (단, 아래 "현실 점검" 참고 — 자가보고 수치는 신뢰하지 말 것)

---

## 0. 한 줄 요약

기본 명령/배선(command, metadata)은 대부분 존재하지만, **사용자가 실제 결과를 보는 경로(드래그앤드롭, 픽셀/샘플 처리, 렌더링 UX 등)가 비어 있거나 부분 구현인 항목이 많다.** 자동자막 STT P0는 Apple Speech 기반 실생성 + 선택 타임라인 클립 정렬까지 닫혔지만, 자가보고 97% 파리티는 여전히 과장이다. **실동작 기준 체감 55~65%**로 보는 것이 안전하다. 완료 기준을 "코드 존재"가 아니라 "preview + export에서 결과 확인"으로 잡고 진행할 것.

---

## 1. P0 버그: 이미지/영상 드래그앤드롭이 실제로 안 됨

`GAP_ANALYSIS_V6.md`에는 "드래그앤드롭 미디어 임포트 ✅ 완료"로 적혀 있으나 **실제로는 타임라인에 드롭해도 클립이 생기지 않는다.**

### 근본 원인

1. **타임라인 드롭이 클립을 안 만든다.**
   - `App/MovieCutMac/TimelineView.swift:265` 의 `.onDrop` 핸들러가 `viewModel.importMedia([url])`만 호출.
   - `EditorViewModel.importMedia` (`App/MovieCutMac/EditorViewModel.swift:512`)는 `ImportMediaCommand`로 **미디어 라이브러리(mediaAssets)에만** 추가하고, 트랙에 `Clip`을 만들지 않음.
   - 클립 생성은 별도 메서드 `addClipToTimeline` (`App/MovieCutMac/EditorViewModel.swift:530`)이며, 현재는 라이브러리 패널의 "Add to Timeline" 버튼(`App/MovieCutMac/MediaLibraryPanel.swift:49`)으로만 호출됨.
   - 결과: 타임라인에 드롭 → 라이브러리에만 조용히 추가 → 타임라인엔 아무것도 안 나타남 → "안 된다"로 체감.

2. **라이브러리 → 타임라인 드래그가 불가능.**
   - `MediaLibraryPanel.swift`의 에셋 행(row)에 `.draggable` / `.onDrag`가 **없음**. 따라서 라이브러리에서 타임라인으로 끌어다 놓는 경로 자체가 존재하지 않음.

3. **실제 미디어 길이를 안 읽음.**
   - `Sources/MovieCutCore/Media/MediaImporter.swift:16` 의 `probe`가 확장자만 보고 `duration: nil` 반환 (AVFoundation 미사용).
   - 영상/오디오를 넣어도 실제 길이가 아니라 `defaultDuration` 기본값으로 클립이 생성됨. 해상도/fps도 모름.

### 현재 유일하게 동작하는 경로
라이브러리 영역에 드롭 → 에셋 선택 → "Add to Timeline" 버튼 클릭. (`MediaLibraryPanel.swift:71` 드롭 → `:49` 버튼)

### 수정 작업 (P0)

- [x] **타임라인 드롭 → 클립 생성**: `TimelineView`의 `DropDelegate`가 드롭 X좌표를 시간으로 환산(`x / pixelsPerSecond`)하고, `EditorViewModel.importMediaAndAddToTimeline`으로 import + clip 생성을 한 번에 수행한다. 검증은 build/static-contract 기준이며 UI 자동화는 아직 생성하지 않았다.
- [x] **라이브러리 아이템 `.draggable` 추가**: `MediaLibraryPanel` 에셋 row에 내부 asset UUID payload drag를 추가하고, 타임라인 drop이 내부 asset ID를 받아 기존 에셋으로 clip을 생성한다. 검증은 build/static-contract 기준이며 UI 자동화는 아직 생성하지 않았다.
- [x] **실제 import metadata probe**: Core `MediaImporter.probe`는 경량으로 유지하고, 앱 레이어(`EditorViewModel`)에서 `AVURLAsset`/ImageIO 기반 best-effort probe로 video/audio duration, 해상도/fps/codec, audio sample rate/channel count, image dimensions를 `MediaMetadata`에 채운다. 라이브러리 행/접근성 value가 compact metadata summary를 표시한다. 검증은 build/static-contract 기준이며 GUI visual verification은 아직 생성하지 않았다.
- [x] **드롭 성공/실패 사용자 피드백**: 타임라인 파일 드롭, 라이브러리 에셋→타임라인 드롭, 미디어 라이브러리 파일 드롭이 성공 시 `lastStatusMessage`, 실패/빈 payload 시 `lastErrorMessage`를 설정한다. `ContentView.statusBar`가 두 메시지를 표시하며, `DragDropFeedbackStaticContractTests`가 decoded-empty callback과 invalid payload feedback wiring을 검증한다.

### 검증 방법
실제 mp4/png 파일을 ① 타임라인에 직접 드롭 ② 라이브러리에서 타임라인으로 드래그 — 두 경로 모두 올바른 위치에 올바른 길이의 클립이 생기는지 확인. `swift build` + `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`.

> 참고: 현재 sandbox 엔타이틀먼트 파일 없음(`.entitlements` 부재) → 파일 접근 권한 문제는 아님. 순수하게 클립 생성 로직 누락이 원인.

---

## 2. 갭 분석 V6 현실 점검 (중요)

V6 문서의 판정은 "지정된 N개 파일 안에서 코드 경로가 보이는가"였고, **실제 동작/렌더 결과를 검증한 것이 아님.** 패턴:

- **메타데이터/명령 배선만 있고 실제 처리 없음** (🟡로 표기됨): 배경제거, EQ, 덕킹, 노이즈감소 → custom compositor로 값은 넘기지만 실제 픽셀/샘플 처리 알고리즘 미확인. 색보정 중 밝기/대비/채도는 shared `CIColorControls` pixel processor와 preview/export custom compositor static contract로 검증됨. Batch 13에서 procedural LUT/필터는 `VisualEffectPixelProcessor`로 preview/export 공통 경로에 연결됨(외부 `.cube` LUT import는 후속). Batch 14에서 크로마키는 shared `ChromaKeyPixelProcessor`와 Mac preview/export `CustomVideoCompositor` 경로에 연결되고 픽셀 알파/softness/spill suppression 테스트로 검증됨. Batch 15에서 마스크 합성은 shared `MaskPixelProcessor`로 rectangle/ellipse/triangle/diamond/linear/brush, feather/invert/rotation 경로를 Core renderer에 모으고 Mac/iOS custom compositor가 이를 호출하도록 정리됨. Batch 16에서 텍스트/자막 burn-in export는 shared `TextOverlayPixelProcessor`로 Mac/iOS custom compositor가 호출하는 공통 픽셀 경로에 연결됨.
- **UI 진입점만**: 자동자막, AI 어시스턴트, 클라우드 동기화, 템플릿 마켓 → 버튼/시트만.
- **실제 끝까지 동작**: trim/split/move/delete/ripple, 볼륨, 파형, 키프레임 렌더, 역재생, export 진행률/공유, 마커, 스티커 변형.

→ **완료 기준 재정의**: 새 작업은 "preview에서 보이고 export 결과물에도 반영됨"을 DoD(Definition of Done)로 삼는다.

---

## 2.5 증거 기반 검증 현황 리셋 (2026-06-23/24)

> Phase 0(기반 경화)에서 "🟡 자가보고"를 **실측 증거**로 교체했다. 상세·로드맵은 `docs/MOVIECUT_PRO_ROADMAP_20260622.md`, 성능은 `docs/PERF_BASELINE_20260622.md`.

**검증 인프라(신규)** — 이제 완료 증거는 static contract가 아니라 아래로 판정한다:
- **골든 픽셀 하니스** `Tests/.../Support/GoldenPixelHarness.swift` — `CIContext(useSoftwareRenderer:true)` 결정적·sandbox-safe, **silent-skip 제거**(망가진 렌더러는 소리내어 실패). 색보정·배경제거 골든이 이를 사용.
- **결정적 fixture** `Tests/Fixtures/` + `scripts/make_fixtures.sh` (실 AVFoundation 로드 검증).
- **앱 레벨 E2E** `scripts/run_e2e_export.sh` + DEBUG 하니스(`App/MovieCutMac/UITestHarness.swift`, env 게이트) — import→export·freeze·NR·autosave를 **실제 앱 런타임**으로 검증.

**티어1 스윕 판정(실측)**:

| 기능 | 기존 | 실측 판정 | 증거 |
|---|---|---|---|
| 색보정 밝기/대비/채도 | ✅ | ✅ | `ColorCorrectionGoldenTests` 골든 |
| 색보정 warmth/tint | ❌(no-op) | **✅ 구현 완료** | 골든(warm/magenta shift), 죽은 슬라이더 실수정 |
| 배경제거 F-08 | 🟡 | **✅**(실인물 E2E만 🟡) | `BackgroundRemovalGoldenTests`(alpha 255/0) |
| 정지프레임 | 🟡 미확인 | **✅ export 반영** | E2E duration 2.0→4.0s |
| 노이즈감소 | 🟡~❌ | **✅ 앱 런타임** | 헤드리스 크래시 없음·소스 swap |
| EQ | 🟡~❌ | **✅ 앱 export 실측** | `run_e2e_export.sh` EQ spectrum: bass_ratio 2.315524 vs treble_ratio 0.488654 |

**안정성(0.6)**: undo/redo 무결성(스냅샷 기반, `UndoIntegrityTests`)·크래시 복구 자동저장(`AutosaveRecoveryTests` + 앱 배선) ✅.

**성능(0.3)**: export +9%(0.49× realtime)·preview 5.5ms/frame(182fps) → CoreImage 합성 병목 아님 → **Metal 전면 재작성 보류**.

**미검증/주의**: 위 표 외 🟡 항목(덕킹·비트감지·자동컷·리프레임·자막워크플로우·TTS·캔버스배경·클라우드)은 **아직 실측 미검증** — 자가보고 "구현됨"을 완료로 보지 말 것. 전체 `swift test`는 네트워크/Speech/마이크 통합 테스트로 헤드리스 완주 곤란(633/0 부분 통과).

**S0 iOS 빌드 복구(2026-07-03)**: G-09 Inc 1로 `MovieCutiOS` generic iOS 빌드를 `CODE_SIGNING_ALLOWED=NO` 조건에서 복구했다. 같은 세션에서 `swift build`, `swift test --filter 'StaticContract|Golden'`(341 tests), Mac `xcodebuild`, iOS generic `xcodebuild`, `scripts/run_e2e_export.sh`가 모두 PASS. CoreSimulator out-of-date는 simulator 지원 경고로 남아 있으나 generic device build에는 영향 없음.

**S0 iOS 파리티 매트릭스 재감사(2026-07-04)**: G-09 Inc 2로 `PLATFORM_PARITY_MATRIX.md`를 기능 × Core/Mac UI/iOS UI/Mac preview-export/iOS preview-export 기준으로 갱신했다. Mac-only/iOS defer 15건(3-way advanced UI, LUT legacy path, chroma shared processor, two-source transition, background-removal shared compositor, freeze, speed ramp, reverse, ducking, EQ, NR apply, autosave/recovery, ProRes/GIF/still, platform presets, marker/quick tools)에 사유를 기록하고 `IOSParityMatrixStaticContractTests`로 문서/코드 신호를 잠갔다. Inc 3 시작점은 iOS freeze/speed/reverse 또는 shared compositor 통일.

**S0 G-12 #1 EQ 청감 상환(2026-07-03)**: `AudioEqualizerService`의 앱 export 크래시 경로를 AVAudioFile 버퍼 DSP로 교체하고, `eq_low_high_2s_mono.wav` fixture + `MOVIECUT_UITEST_EQ_PRESET` 하니스 + `run_e2e_export.sh` Goertzel 측정으로 bassBoost/trebleBoost 차이를 codify했다. 실측: bass_ratio 2.315524, treble_ratio 0.488654, bass_low 2.281896e+02, bass_high 9.854772e+01, treble_low 9.240646e+01, treble_high 1.891041e+02. 남은 G-12 오디오 부채는 NR 실잡음 효과와 덕킹 청감.

**S0 G-12 #2 NR 실잡음 효과 상환(2026-07-04)**: `NoiseReductionService`의 앱 export 경로를 deterministic AVAudioFile 버퍼 DSP로 고정하고, `noisy_voice_1k_hiss_8k_2s_mono.wav` fixture + `MOVIECUT_UITEST_DENOISE` 하니스 + `run_e2e_export.sh` Goertzel 측정으로 8kHz hiss/1kHz voice 비율 개선을 codify했다. 실측: base_ratio 0.248784 → denoised_ratio 0.075641, improvement_db 5.17dB, voice_retention 0.913, base_hiss 4.195051e+01 → denoised_hiss 1.164459e+01. 남은 G-12 오디오 부채는 덕킹 청감.

**S0 G-12 #3 덕킹 청감 상환(2026-07-04)**: `duck_bgm_220hz_4s_mono.wav` + `duck_voice_1000hz_1s_mono.wav` fixtures, DEBUG 앱 하니스 `MOVIECUT_UITEST_DUCKING_*`, `SetAudioDuckingCommand`, export ramp를 `run_e2e_export.sh` Goertzel 측정으로 codify했다. 실측: base_voice 3.098866e+01 → ducked_voice 1.935795e+00, reduction_db 12.04dB, quiet_delta_db 0.00dB, ducked_voice_quiet_ratio 0.062.

**S0 G-12 #8 플랫폼 프리셋 5종 상환(2026-07-04)**: `bars_320x240_3s_30fps.mp4` fixture, DEBUG 앱 하니스 `MOVIECUT_UITEST_PLATFORM_PRESET=<rawValue>`, 실제 `applyPlatformExportPreset` → `exportProject(to:)` 경로를 `run_e2e_export.sh` ffprobe 검증으로 codify했다. 실측: TikTok/Reels/Shorts 1080x1920 30/1 h264 `.mp4`, YouTube Standard 1920x1080 30/1 h264 `.mp4`, Instagram Post 1080x1080 30/1 h264 `.mp4` (`format_name=mov,mp4,m4a,3gp,3g2,mj2`).

---

## 3. CapCut 기능 백로그 (도메인별)

상태: ✅ 실제 동작 / 🟡 배선·UI만 존재(실처리 없음) / ❌ 없음
우선순위: P0(기본기 필수) > P1 > P2 > P3(차별화·후순위)

### A. 미디어 입출력
- [x] ✅ 타임라인 직접 드롭 → 클립 생성 **(P0, §1 참조; 2026-06-10 실기기 GUI 드래그 검증 완료 — DropDelegate가 실제 드래그를 거부하던 런타임 버그를 closure 기반 onDrop + Info.plist UTType 선언으로 수정)**
- [x] ✅ 라이브러리 → 타임라인 드래그 **(P0; 2026-06-10 실기기 GUI 드래그 검증 완료)**
- [x] ✅ 실제 import metadata probe (AVAsset/ImageIO, F-06) **(P0; video/audio duration, 해상도/fps/codec, audio sample rate/channel count, image dimensions를 앱 레이어에서 best-effort로 구현. GUI visual verification은 별도)**
- [x] ✅ 드롭 성공/실패 피드백 **(P0; status bar의 `lastStatusMessage`/`lastErrorMessage`, static-contract 검증)**
- [x] ✅ 썸네일/프록시 생성 (P1) — import path가 video/image `MediaAsset`에 `ThumbnailGenerator` PNG 썸네일을 opportunistic/non-fatal로 채우고, Media Library와 Timeline clip background가 `thumbnailData`를 실제 이미지로 렌더한다. video asset은 `ProxyGenerator.makeProxyPlan`의 deterministic target/resolution과 AVFoundation best-effort proxy export를 통해 실제 파일이 존재할 때만 `ProxyInfo(proxyURL:)`를 저장한다. Media Library row/context action에서 Generate Proxy를 실행하고 Proxy ready/No proxy 및 thumbnail 상태를 접근성 value에 노출한다. Caveat: proxy export는 `AVAssetExportSession`이 해당 source와 mp4 output을 지원하는 경우에만 성공하며, 실패 시 asset.proxy는 nil로 유지된다.
- [x] ✅ 포맷별 export(mp4/mov, 코덱/비트레이트 실제 반영) (P1) — format/codec/quality/container/estimated bitrate are persisted in `ExportSettings` and wired to macOS export. Custom bitrate now resolves only inside the documented 1~200 Mbps range (`nil` below minimum, clamp to 200 above maximum), and Inspector/toolbar export controls expose selected settings to VoiceOver. `AVAssetExportSession` still exposes preset selection plus `fileLengthLimit` rather than a direct `averageVideoBitRate` knob, so exact encoder bitrate control remains approximate.
- [ ] 🟡 비파일 드래그 소스(사진/브라우저, F-01) (P1) — Core `DragDropHandler.loadExternalMediaURLs`가 fileURL/movie/image 페이로드를 처리(`loadFileRepresentation`→data fallback→`MovieCutImports` 임시 디렉토리), 타임라인/라이브러리 onDrop에 `.movie`/`.image` 추가. `ExternalMediaDropTests` 6개가 실제 NSItemProvider 페이로드로 행동 검증. **2026-06-11 실기기 GUI 추가 검증: Safari data URL 이미지 드래그 → 라이브러리 import 성공(`Imported Media.png`, 320×180, thumbnail ready, `Imported 1 media file.`), Safari data URL 이미지 드래그 → Video 1 타임라인 클립 생성 성공.** Caveat: Photos 앱 또는 대체 네이티브 앱 비파일 소스는 Photos window 0/AppleScript import timeout 및 이후 screencapture black-frame 상태로 미검증 — DoD §1.3에 따라 F-01 전체 완료는 계속 ✅ 보류.
- [x] ✅ 플랫폼 프리셋(TikTok/Reels/Shorts/YouTube/Instagram Post) 실제 인코딩 (P2) — **2026-07-04 G-12 #8 상환**: `MOVIECUT_UITEST_PLATFORM_PRESET` 하니스가 실제 `applyPlatformExportPreset` 앱 호출부로 canvas/export settings를 바꾼 뒤 `exportProject(to:)`로 export한다. `run_e2e_export.sh` ffprobe 실측: TikTok/Reels/Shorts 1080x1920 30/1 h264 `.mp4`, YouTube Standard 1920x1080 30/1 h264 `.mp4`, Instagram Post 1080x1080 30/1 h264 `.mp4` (`format_name=mov,mp4,m4a,3gp,3g2,mj2`). Caveat: 현재 5종 프리셋 정의는 모두 30fps/H.264/AAC/MP4이며 직접 게시 API가 아니라 파일 export 검증이다.

### B. 타임라인 편집
- ✅ Trim / Split / Move / Delete / Ripple
- ✅ 스냅 / 줌 / 다중선택 / 컨텍스트 메뉴
- [x] ✅ 마그네틱 타임라인(자동 밀착) (P1) — Add/Move/Duplicate/Delete command path가 `RestoreTrackClipsCommand` track snapshot을 남기고, Add/Move/Duplicate/Delete 후 same-track magnetic packing으로 클립을 0초부터 end-to-start로 밀착한다. Undo는 이전 track snapshot/range를 복원한다.
- [x] ✅ 멀티트랙 레이어링 + 클립별 zIndex (P1) — persisted `Clip.zIndex`가 legacy JSON에서 기본값 0으로 decode되고 round-trip encode된다. `TimelineView`는 `clipsForDisplay(track)`와 `.zIndex(Double(clip.zIndex))` 기반 TimelineView display ordering/layer actions를 사용하며 Bring to Front / Send to Back context action으로 선택 클립 layer를 조정한다. Caveat: 클립 그룹/링크는 P2 별도 항목으로 남긴다.
- [x] ✅ 클립 그룹/링크(영상+오디오 묶음, F-04) (P2) — GUI 실기기 검증 완료(2026-06-11): 단일 클릭+Delete로 그룹 전체 삭제(연결 선택 입증), link 아이콘, Group/Ungroup 메뉴 가드. 상세는 스펙 F-04 검증 기록. 구현: `Clip.groupId` 영속화(legacy decode nil), `GroupClipsCommand`/undo, 연결 선택(그룹 클립 탭 → 그룹 전체 선택/해제), 컨텍스트 메뉴 Group/Ungroup, 타임라인 link 아이콘. `ClipGroupingTests` 7개 행동 검증. Caveat: 마그네틱 패킹 하에서 시간 오프셋 유지 이동은 미적용(연결 선택 방식 채택), GUI 실조작 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 키보드 단축키 맵 전체 (P2) — `MovieCutMacApp.commands` now owns the F-05 Playback/Timeline/Edit shortcut map: Space, Cmd+B, Q/W, Delete, Shift+Delete, Cmd+D, frame/1s arrows, clip-boundary Up/Down, +/- zoom, M, and Cmd+Z/Shift+Cmd+Z. Toolbar/background duplicate shortcut registrations were removed from `ContentView`, and Help exposes "MovieCut Keyboard Shortcuts." Caveat: text-entry-sensitive unmodified shortcuts use a centralized AppKit first-responder guard rather than a full SwiftUI FocusState router; GUI text-field regression remains host verification.

### C. 비디오 효과 (Visual)
- [x] ✅ 색보정(밝기/대비/채도) **실제 픽셀 처리** (P0) — `ColorCorrectionPixelProcessor`가 `CIColorControls`로 밝기/대비/채도를 적용하고, Mac `CustomVideoCompositor`가 preview/export 공통 경로에서 이를 사용한다. SwiftPM static contract가 `PlaybackEngine`/`ExportEngine`의 custom compositor 라우팅을 확인한다. 현재 sandbox에서는 `CIContext`가 non-black fixture도 transparent black으로 렌더해 pixel assertion은 guarded; 정상 CoreImage runner에서는 identity/brightness/saturation pixel sampling 테스트가 실행된다. **warmth/tint는 2026-06-23 구현 완료** — `CITemperatureAndTint` 단계를 shared processor에 추가(warmth+ = 따뜻함/red↑, tint+ = 마젠타). Mac/iOS Inspector 슬라이더가 이미 존재했으나 프로세서가 무시하던 **작동 안 하는 컨트롤**이었고 이제 preview/export 실반영. non-skippable 골든(`ColorCorrectionGoldenTests`: warmth+1→[166,148,121], tint+1→[191,124,185]).
- [x] ✅ 필터/LUT 실제 렌더 (P1) — `VisualEffectPixelProcessor`가 grayscale/sepia/blur/exposure/temperature/styleTransfer 및 cinematic/vintage/noir/vivid/cool procedural LUT preset을 Core Image로 적용한다. Mac `CustomVideoCompositor`가 clip `effects`를 preview/export 공통 custom compositor 경로에서 이 shared processor로 위임하고, `VisualEffectPixelProcessorTests`가 renderable contract, extent preservation, guarded pixel sampling, `PlaybackEngine`/`ExportEngine` 라우팅, Inspector preset 노출을 검증한다. 외부 `.cube` LUT import는 F-09에서 완료(`CubeLUTParser`+`.externalLUT`+Import LUT… UI, `CubeLUTTests` 10개, guarded 픽셀 검증). Caveat: 실기기 import GUI 확인 잔여.
- [x] ✅ 크로마키 keying 알고리즘 (P1) — `ChromaKeyPixelProcessor`가 `ChromaKeySettings`의 keyColor/tolerance/softness/spillSuppression을 Core Image `CIColorKernel`로 적용하고, keyed green 픽셀 alpha 제거, near-key partial alpha, foreground opacity 유지, invalid hex fallback, extent preservation을 SwiftPM 테스트로 검증한다. Mac `CustomVideoCompositor`와 `ChromaKeyCompositor`는 shared processor로 위임하며 `ExportEngine`/`PlaybackEngine` static contract가 chroma-key clip의 custom compositor 라우팅을 확인한다. eyedropper/매트 erode는 F-10에서 완료(`PixelSampler` 스포이드 + `edgeShrink`, `ChromaKeyEyedropperTests` 9개). Caveat: 실기기 스포이드 GUI 확인 잔여.
- [x] ✅ 마스킹(도형/그리기) 합성 (P1) — Batch 15에서 `MaskPixelProcessor`가 Core Image/CGContext 기반으로 rectangle/ellipse/triangle/diamond/linear/brush 마스크를 실제 알파 합성하고, Mac/iOS `CustomVideoCompositor`가 shared processor를 호출한다. SwiftPM 테스트가 rectangle/inverted/ellipse/brush 알파 샘플과 extent preservation, Mac export/playback 라우팅 static contract를 검증한다. Caveat: AI segmentation/refine edge 같은 고급 매트 보정은 이 배치 범위가 아니며 별도 후속 항목이다.
- [ ] 🟡 배경 제거(인물 세그멘테이션, F-08) (P2→preview 배선/품질분리/AC④ 완료) — `isBackgroundRemoved` Clip 속성 + `PersonSegmentationCompositor`(shared, guarded 픽셀 테스트) + preview `.fast`/export `.accurate` + 인물 미검출 시 무변경. `BackgroundRemovalTests` 9개. Caveat: 실인물 영상 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 전환효과 다양화 + Inspector 선택/Duration 노출 + two-source preview/export 배선 (P1) — Batch 17에서 `TransitionType`을 12개 built-in(none/crossDissolve/fadeThroughBlack/wipeRight/Left/Up/Down/slideLeft/Right/zoomIn/Out/glitch)으로 확장하고, Core 전용 `TransitionPixelProcessor`가 cross dissolve, fade-through-black, directional wipe, slide, zoom, deterministic glitch를 두 소스 `CIImage` 합성으로 처리한다. P1 transition pass에서 Mac export/playback이 `requiresTwoSourcePixelProcessing` 전환(wipeLeft/Up/Down, slide, zoom, glitch)에 대해 outgoing/incoming track metadata를 `CustomVideoCompositor`에 전달하고, transition overlap에서 별도 composition track source frame을 가져와 `TransitionPixelProcessor.apply(type:from:to:progress:)`로 합성하도록 배선했다. 2026-06-11 F-07 targeted pass에서 fade-through-black midpoint/boundary pixel fixture와 Inspector verification note/accessibility guard를 추가해 "targeted confidence only; export/device golden pending" 상태를 UI와 static contract로 잠갔다. Caveat: crossDissolve/fadeThroughBlack/wipeRight의 기존 layer-instruction ramp는 유지한다. 실제 exported visual fixture/e2e 검증은 후속으로 필요하며, release-ready/exported/device-verified라고 보고하면 안 된다.
- [ ] ❌ 모션 트래킹 (P3)

### D. 텍스트/자막
- [x] ✅ 텍스트 오버레이 + 폰트/정렬/스타일 편집 UI (P1) — burn-in export는 Batch 16에서 완료됐고, Mac Inspector controls now cover font/size/color/background/alignment/presets for ordinary text clips. 편집은 `TextClipContent`를 `updateSelectedTextContent` → `SetClipPropertyCommand.textContent` 경로로 갱신하며, sticker clip은 기존 sticker metadata/transform 중심 UI를 유지한다. Caveat: advanced title template library remains separate P1/P2 work.
- [ ] 🟡 텍스트 템플릿/타이틀 프리셋 (Core만 존재) (P1)
- [x] ✅ 자동 자막(STT) 실제 생성 **(P0)** — Mac `AutoSubtitlesView` 경로가 `TranscriptionService.currentProvider`의 Apple Speech provider로 실제 STT를 실행하고, 선택된 audio/video 타임라인 클립이 있으면 `subtitleClips(from:alignedTo:)`로 `sourceRange`/`timelineRange`에 맞춰 pending subtitle clips를 만든 뒤 Apply에서 삽입한다. 타임라인 클립 없이 라이브러리 asset만 선택한 경우에는 00:00 기준 pending clips를 만들며 status text에 이를 명시한다. Caveat: macOS Speech Recognition 권한과 recognizer availability가 필요하고, SwiftPM static-contract/build 검증은 추가됐지만 실제 오디오 fixture 기반 UI e2e 자동화는 아직 없다.
- [x] ✅ 자막/text burn-in export (P1) — Batch 16에서 `TextOverlayPixelProcessor`가 CoreGraphics/CoreText 기반으로 텍스트/자막 클립을 투명 RGBA overlay에 렌더하고 Mac/iOS `CustomVideoCompositor`가 shared processor로 위임한다. 픽셀 테스트는 배경 박스/알파 변화, fadeIn, typewriter, extent preservation을 guarded `CIContext`로 검증하고 static contract가 Mac/iOS compositor delegation과 Mac export/playback 경로를 확인한다. Caveat: 이 완료 범위는 text/subtitle clip burn-in이며, 자막 스타일 프리셋과 고급 caption template 렌더링은 이미 별도 구현된 경우를 제외하면 후속 항목이다.
- [ ] 🟡 자막 편집 워크플로우 + SRT import/export (F-13) (P1→구현됨) — Core `SubtitleDocument` SRT 파서/시리얼라이저 + ViewModel 세그먼트 편집(수정/분할/병합/삭제, pending clip 재정렬 재사용) + `AutoSubtitlesView` 인라인 편집·SRT Import/Export. `SubtitleDocumentTests` 9개 검증. Caveat: W3 실기기 완주와 외부 플레이어 SRT 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 텍스트 외곽선/그림자/굵기+사용자 프리셋 (F-12R) (P1→구현됨) — `TextClipContent` 데코 필드(A5) + shared 렌더러 stroke 2-pass/`setShadow`/폰트 트레이트 + `UserTextStylePreset` 저장소 + Inspector 컨트롤. `TextDecorationTests` 9개(RGBA 스캔 픽셀 검증 포함). Caveat: 실기기 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 텍스트 애니메이션 프리셋 (P2)

### E. 스티커/오버레이
- ✅ 이모지/이미지 스티커 + 캔버스 변형
- ✅ 온캔버스 드래그/리사이즈/회전 핸들(단일 선택)
- [ ] ❌ 다운로드형 스티커 스토어/팩 (P3)

### F. 오디오
- ✅ 볼륨 / 페이드 / 파형 표시
- [x] ✅ 페이드 duration 편집 UI (P1) — Mac Inspector `Fade Duration` 그룹에서 Fade In/Fade Out 현재값을 초 단위로 표시하고 Slider + Seconds `TextField` + 0.05s Stepper로 0...min(10s, clip duration) 범위 정밀 편집을 제공한다. Reset Fades/None/Soft/Long preset은 모두 `updateSelectedAudioFade` → `AudioFadeCommand` 경로로 적용되어 undo/redo path를 유지한다.
- [x] ✅ 자동 덕킹 **실제 preview/export ramp + 앱 export RMS 검증** (P2) — **2026-07-04 G-12 #3 상환**: `AudioDuckingPlanner` + `Clip.duckingRanges/duckingLevel` + `SetAudioDuckingCommand`(단일 undo) + Mac preview/export 동일 ramp(attack 0.12s/release 0.25s, fade 회피) + Inspector Duck/Clear. `AudioDuckingTests` 14개에 더해 `run_e2e_export.sh`가 `duck_bgm_220hz_4s_mono.wav`/`duck_voice_1000hz_1s_mono.wav`를 앱 하니스로 두 트랙 export 후 220Hz BGM 성분을 Goertzel 측정한다. 실측: voice-window BGM 3.098866e+01→1.935795e+00, reduction 12.04dB, quiet_delta 0.00dB, voice/quiet 0.062. Caveat: 실제 상용 BGM+사람 음성 GUI 녹화는 후속 품질 작업.
- [x] ✅ EQ **실제 DSP + 앱 export 스펙트럼 검증** (P2) — **2026-07-03 G-12 #1 상환**: 과거 판정(`AudioEqualizerService` dead/crash + 평균게인 볼륨근사)은 현재 해소. `AudioEqualizerService`는 AVAudioFile 버퍼 DSP로 bass/mid/treble 대역을 분리 적용하고, Mac 하니스 `MOVIECUT_UITEST_EQ_PRESET`이 command-backed `applyEQPreset` 경로로 선택 클립에 적용한다. `run_e2e_export.sh`가 `eq_low_high_2s_mono.wav`를 bassBoost/trebleBoost로 각각 앱 export 후 Goertzel 측정: bass_ratio 2.315524 vs treble_ratio 0.488654, treble_high 1.891041e+02 > bass_high 9.854772e+01. Caveat: UI 슬라이더 실조작 녹화와 세밀한 5밴드 청감 튜닝은 후속 품질 작업으로 남는다.
- [x] ✅ 노이즈감소 **실제 DSP + 앱 export SNR 검증** (P2) — **2026-07-04 G-12 #2 상환**: `NoiseReductionService`가 deterministic AVAudioFile 버퍼 DSP로 sub-voice rumble 제거 + high-frequency residual attenuation을 적용하고 `applyNoiseReduction(for:)` destructive apply로 클립 소스를 denoise 파일로 교체한다. 앱 컨텍스트 `MOVIECUT_UITEST_DENOISE` + `noisy_voice_1k_hiss_8k_2s_mono.wav` E2E에서 8kHz hiss/1kHz voice 비율이 0.248784→0.075641로 감소(improvement 5.17dB, voice_retention 0.913). Caveat: 실제 사람 음성/생활소음 청감 GUI 녹화는 후속 품질 작업으로 남는다.
- [ ] 🟡 비트 감지(음악 동기 편집, F-15) (P2→구현됨) — `BeatDetectionProvider`(에너지 플럭스 onset, 합성 클릭 트랙으로 <50ms 간격 검증) + `Marker.kind(.beat)` + 배치 마커 명령(단일 undo) + 룰러 틱 렌더/스냅 포함 + Quick Tools Detect/Clear Beats. `BeatDetectionTests` 13개. Caveat: 실음원 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [x] ✅ 보이스오버 실제 마이크 녹음 (P1) — Mac `VoiceoverRecordingView`가 macOS `AVCaptureDevice` microphone 권한을 확인/요청하고, shared `VoiceoverRecorder`의 `AVAudioEngine` input tap 경로로 temp CAF에 실제 녹음한다. 녹음 UI는 timer/input level/saving progress/accessibility label·hint를 제공하고, stop 시 recorder elapsed time을 `fallbackDuration`으로 `EditorViewModel.addVoiceoverAudio(from:fallbackDuration:)`에 넘긴다. EditorViewModel은 `audioDuration(for:)`로 readable audio duration을 먼저 쓰고, recorder fallback duration, 0.1s minimum 순서로 duration을 확정해 playhead 위치에 audio clip을 추가/선택한다. `MediaImporter`는 voiceover CAF를 audio asset으로 분류한다. Caveat: 실제 마이크 접근은 `NSMicrophoneUsageDescription`, macOS Microphone 권한, 선택된 입력 하드웨어에 의존하므로 호스트에서 실제 녹음 검증이 필요하다.
- [ ] 🟡 오디오 추출 (P2)
- [ ] 🟡 TTS(텍스트→음성, F-17) (P3→구현됨) — shared `TextToSpeechSynthesizer`(AVSpeechSynthesizer.write→CAF) + value-type voice 목록 + ViewModel 텍스트클립 정렬 오디오 클립 생성 + Inspector Voice 피커/Generate Voice. `TextToSpeechTests` 7개(실합성 통합 테스트가 실제 오디오 생성). Caveat: 실기기 GUI 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

### G. 속도/시간
- [x] ✅ 속도 조절 / speed ramp preview+export (P1) — Mac `PlaybackEngine` preview와 `ExportEngine` export가 `SpeedRampCurve(points: clip.speedRampPoints)`로 source segment를 나누고 `scaleTimeRange`로 composition time range를 조정한다. 비디오 클립의 audio preview path와 `.audio` track preview path도 같은 segment/scale 경로를 사용한다. Caveat: 고급 옵티컬 플로우 기반 부드러운 슬로우모션은 별도 P3 항목이며 아직 완료되지 않았다.
- ✅ 역재생
- [x] ✅ 정지프레임 (P2) — **2026-06-23 export 반영 확정**: `ExportEngine`(`isFreezeFrame` 감지 → 1프레임 source range → `scaleTimeRange`)·`PlaybackEngine` 양쪽 표준 기법. **헤드리스 E2E 측정**: 2s 클립에 2s freeze → export 2.0s→**4.0s**(delta 정확히 freeze duration). `run_e2e_export.sh`.
- [ ] ❌ 옵티컬 플로우 보간(부드러운 슬로우모션) (P3)

### H. AI 기능 (CapCut 차별화)
- [ ] 🟡 자동 컷(무음 제거, F-18) (P1→preview/파라미터/단일undo 구현됨) — `AutoCutPlanner`(패딩으로 발화 보존) + `AutoCutCommand`(단일 undo) + ViewModel preview/apply/cancel + threshold/min/padding 슬라이더 + 타임라인 빨간 하이라이트. `AutoCutPlannerTests` 13개. Caveat: 실인터뷰 fixture 청취 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 씬 변경 감지 자동 분할 — Core 존재 (P2)
- [ ] 🟡 자동 리프레임(피사체 추적 crop, F-19) (P2→스무딩/미리보기 구현됨) — `ReframeSmoothing`(moving average + clamp, AC③ 떨림 감소 테스트) + ViewModel preview/apply/cancel + PreviewPanel crop-path 오버레이 + Inspector 섹션. `ReframeSmoothingTests` 8개. Caveat: 실영상 추적 정확도(AC②) 확인 잔여 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 AI 어시스턴트(자연어 편집 명령, F-21) (P3→규칙기반 1단계 구현됨) — `AssistantCommandParser`(동의어 target×action + 숫자 파싱) + ViewModel 실행기(기존 명령 매핑) + Inspector AssistantSection. `AssistantCommandParserTests` 8개(20 intent 시나리오 포함). Caveat: 외부 LLM 연동 별도 합의 — DoD §1.3에 따라 ✅ 보류.
- [ ] 🟡 자동 하이라이트(롱폼→숏폼, F-20) (P3→구현됨) — `HighlightScorer`(silence/scene/beat 출력 조합, 비중첩 top-N) + ViewModel detect/createSequence(새 프로젝트 스왑) + Inspector HighlightsSection. `HighlightScorerTests` 8개. Caveat: 실영상 후보 적합성 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

### I. 캔버스/프로젝트
- ✅ 비율 프리셋(16:9 / 9:16 / 1:1 / 4:5 / 21:9)
- [ ] 🟡 캔버스 배경(블러/컬러/이미지, F-11) (P2→구현됨) — shared `CanvasBackgroundPixelProcessor` + Mac/iOS compositor 합성 + Canvas 팝오버 UI + `CanvasBackgroundTests` 14개. Caveat: 실기기 preview 확인과 export visual fixture 잔여 — DoD §1.3에 따라 ✅ 보류. 상세는 스펙 F-11 검증 기록.
- ✅ 마커(추가/이름/삭제/점프)
- [ ] ❌ 챕터/비트 마커 export 메타데이터 (P3)

### J. 협업/배포
- [ ] 🟡 클라우드 동기화(F-22) (P3→충돌 해소+테스트 완료) — `CloudSyncService` latestWins+백업(`resolveConflictKeepingBackup`/`writeConflictBackup`), `CloudConflictTests` 7개(2기기 시나리오). Caveat: 실 iCloud 2기기 GUI 검증 잔여.
- [ ] 🟡 템플릿 마켓플레이스 — picker만 (P3)
- [ ] 🟡 템플릿 패키지(F-23) (P3→구현됨) — `ProjectPackage` .mctemplate export/import + Package 메뉴, `ProjectPackageTests` 7개. Caveat: 실기기 GUI 잔여.
- [x] ✅ 플랫폼 게시(F-24) — OS 공유 시트(ShareLink)로 충족. 직접 API 게시는 스펙 권고대로 범위 외.

---

## 4. 권장 작업 순서

1. **P0 묶음 완료 확인** — 라이브러리→타임라인 드래그앤드롭은 2026-06-10 실기기 GUI 검증까지 완료됐고, 드롭 성공/실패 피드백(A), 색보정 밝기/대비/채도 실픽셀 처리(C), 자동자막 STT(D)도 닫혔다. 단, 이것이 CapCut 95% 도달을 뜻하지는 않는다.
2. **P1 high-ROI 실제 렌더링/UX 항목 계속 진행** — 썸네일/프록시(A), speed ramp preview+export(G), 텍스트 스타일 편집 UI(D), 보이스오버 실녹음(F), 페이드 duration 편집 UI(F), 마그네틱 타임라인 / 클립별 zIndex(B), 키보드 단축키 맵(F-05), 임포트 메타데이터(F-06)는 닫혔다. F-01 비파일 드래그 소스(Photos/브라우저 이미지 드래그)는 `.image`/`.movie` payload materialization과 NSItemProvider behavioral test까지 통과했고, 2026-06-11 Safari data URL 이미지의 라이브러리 import 및 Video 1 타임라인 클립 생성은 실제 GUI 드래그로 확인했다. 단 Photos 앱 또는 대체 네이티브 앱 비파일 소스는 Photos window 0/AppleScript import timeout 및 screencapture black-frame 상태로 미검증이라 전체 완료 처리는 보류한다. 다음 1순위는 F-01 실기기 검증(Photos/Safari/브라우저 실제 GUI 드래그)이다. export format/codec controls(A)는 custom bitrate 1~200 Mbps clamp와 export/mask accessibility 배치까지 닫혔고, 자막/text burn-in export(D)는 Batch 16 범위에서 닫혔고, 전환효과 Inspector picker/duration 노출은 Batch 17 범위에서, two-source custom compositor preview/export 배선은 P1 transition pass에서 닫혔으므로 남은 P1 UI 목록에서 제외한다.
3. **"🟡 배선만" → 실제 알고리즘 채우기** — 명령/메타데이터 경로가 이미 있으므로, compositor에 CIFilter/Vision/AVAudioUnit 처리만 붙이면 됨. 신규 배선보다 ROI 높음.
4. **갭 문서 재작성** — "코드 존재"가 아니라 "preview+export 결과 확인"을 완료 기준으로.

---

## 5. 빌드/검증 메모

- `swift build` 는 Core에서 통과.
- `swift test --filter '...'` 으로 부분 테스트 가능.
- macOS 앱 빌드: `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`.
- 과거 일부 환경에서 `xcodebuild`가 SwiftPM 패키지 resolution 단계에서 `~/.cache/clang/ModuleCache`, `~/Library/Caches/org.swift.swiftpm` 쓰기 때문에 막힌 기록 있음(샌드박스 한정). 대안: `swift build --disable-sandbox`, `swiftc -typecheck -disable-sandbox`.

## 6. 핵심 파일 위치
- 타임라인/드롭: `App/MovieCutMac/TimelineView.swift`
- 라이브러리/드롭/Add to Timeline: `App/MovieCutMac/MediaLibraryPanel.swift`
- 임포트/클립 생성 로직: `App/MovieCutMac/EditorViewModel.swift` (`importMedia` :512, `addClipToTimeline` :530)
- probe: `Sources/MovieCutCore/Media/MediaImporter.swift`
- export compositor: `App/MovieCutMac/Export/CustomVideoCompositor.swift`, `Export/ExportEngine.swift`
- preview 렌더: `App/MovieCutMac/Playback/PlaybackEngine.swift`, `PreviewPanel.swift`
- iOS 대응: `App/MovieCutiOS/` (Mac과 구조 유사, 변경 시 동기화 필요)
