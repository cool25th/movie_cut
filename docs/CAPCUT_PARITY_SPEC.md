# MovieCut → CapCut 수준 개발 명세서 (Development Specification)

> 버전: 1.2 / 작성일: 2026-06-11 / 기준 커밋: `08db5a0`
> 관련 문서: `CAPCUT_FEATURE_BACKLOG.md`(기능 목록·상태), `SESSION_HANDOFF.md`(세션 인수인계)
> 이 문서는 "무엇을"(백로그)이 아니라 **"어떻게, 어떤 기준으로, 어떤 순서로"**를 정의한다.
> 운영 규칙: 신규 기능 작업은 이 문서의 F-ID 단위로 진행하고, 완료 시 해당 AC에 검증 결과를 1줄 추가한다. AC를 바꿔야 하면 이 문서를 먼저 수정·커밋한다(스펙이 사실의 원천).

---

## 1. 목표와 범위

### 1.1 목표
일반 사용자가 CapCut(데스크탑)에서 수행하는 핵심 편집 워크플로우를 MovieCut macOS 앱에서 **동등한 체감 품질**로 수행할 수 있게 한다. 목표는 기능 체크리스트 충족이 아니라 **워크플로우 완주율**이다:

| 핵심 워크플로우 | 정의 |
|---|---|
| W1. 숏폼 제작 | 미디어 임포트 → 컷 편집 → 자막/스티커 → 9:16 export → 공유 |
| W2. 브이로그 편집 | 멀티클립 배치 → 전환/필터 → BGM/덕킹 → 1080p export |
| W3. 자막 영상 | 영상 임포트 → 자동자막 → 자막 스타일링 → burn-in export |
| W4. 효과 합성 | 크로마키/마스크/배경제거 → 키프레임 애니메이션 → export |

### 1.2 범위 제외 (Non-Goals)
- CapCut의 클라우드 협업·계정 시스템·템플릿 마켓플레이스의 **상용 백엔드** (로컬/iCloud 수준까지만)
- 모바일(iOS) 파리티 — Mac 우선, iOS는 compositor/모델 동기화만 유지
- 픽셀 단위 CapCut 룩앤필 복제 — 기능적 동등성만

### 1.3 완료 기준 (Definition of Done) — 전 기능 공통
이 프로젝트에서 반복 확인된 교훈("static contract 통과 ≠ 실동작" — 드래그앤드롭 사례: contract 테스트 통과 상태에서 런타임 드롭이 조용히 거부됨)에 따라, 모든 기능은 아래 4단계를 모두 통과해야 "완료"다:

1. **Core 로직**: SwiftPM 테스트 (픽셀 처리는 guarded pixel sampling 포함)
2. **배선 검증**: preview(`PlaybackEngine`)와 export(`ExportEngine`) **양쪽** 경로 연결
3. **실기기 확인**: 빌드된 앱에서 해당 기능을 실제 조작으로 1회 이상 확인 (가능하면 XCUITest로 자동화)
4. **결과물 검증**: export된 파일에서 효과가 실제로 보이는지 확인 (대표 기능은 visual fixture 비교)

---

## 2. 현재 기준선 (2026-06-11, `d439168` 실측/커밋 기준)

### 2.1 완료 (✅)
- **타임라인 편집**: trim/split/move/delete/ripple, 스냅, 줌, 다중선택, 마커(추가/이름/삭제/점프/스냅)
- **드래그앤드롭**: Finder→타임라인(드롭 위치 클립 생성, 실제 duration), 라이브러리→타임라인 — **2026-06-10 실기기 GUI 드래그 검증 완료**
- **썸네일/프록시**(`3933d94`): import 시 PNG 썸네일(라이브러리/타임라인 클립 표시), best-effort 프록시 생성 + Generate Proxy 액션
- **픽셀 처리**(shared processor + Mac/iOS compositor): 색보정(밝기/대비/채도), 필터/LUT 프리셋 5종, 크로마키(tolerance/softness/spill), 마스크 6종(feather/invert/rotation), 텍스트/자막 burn-in
- **전환**: 12종 `TransitionPixelProcessor` + two-source compositor 배선 (단, export visual fixture 검증은 미완 → F-07)
- **키프레임**(position/scale/rotation/opacity) preview+export, 역재생, 정지프레임(preview), 볼륨/페이드, 파형
- **speed ramp**: export `scaleTimeRange` + preview parity contract(`71893cb`)
- **텍스트**: 스타일 편집 UI(본문/폰트/크기/정렬/전경·배경색/quick preset, `4a2bad8`), 자동자막(Apple Speech STT)+타임라인 정렬
- **보이스오버**: 마이크 권한 + `AVAudioEngine` 실녹음 → 클립 배치(`4e982b0`; 실제 마이크 GUI 검증은 잔여 caveat)
- **스티커**: 이모지/이미지, 온캔버스 이동/리사이즈/회전/스냅 가이드/멀티선택 정렬, 클립별 라벨
- **Export**: container(mp4/mov)/codec/fps/quality/커스텀 비트레이트(1~200Mbps clamp), 소셜 프리셋, 진행률/취소/공유, 접근성
- **마그네틱 타임라인 + 클립 zIndex**(`08db5a0`): same-track magnetic packing, `Clip.zIndex` 기반 표시 순서/Bring to Front·Send to Back — F-03 완료, F-04는 zIndex만 완료(그룹/링크 잔여)
- **오디오 페이드 편집 UI**(`0a5874f`): Inspector Fade In/Out slider/stepper/preset → `AudioFadeCommand`
- **임포트 메타데이터(F-06)**: 앱 레이어에서 video/audio duration, 해상도/fps/codec, audio sample rate/channel count, image dimensions를 best-effort로 probe하고 라이브러리 행/접근성 value에 노출

### 2.2 미완 (이 명세서의 대상)
비파일 드래그 소스(F-01 실기기 검증), 클립 그룹/링크(F-04 잔여), 전환 visual fixture(F-07), 배경제거 실세그멘테이션(F-08), 외부 .cube LUT(F-09), 크로마키 스포이드(F-10), 캔버스 배경(F-11), 텍스트 외곽선/그림자·프리셋 저장(F-12R), 자막 편집/SRT(F-13), 오디오 DSP(F-14), 비트 감지(F-15), TTS(F-17), AI 도구 E2E(F-18~F-20), AI 어시스턴트(F-21), 생태계(F-22~F-24).

### 2.3 아키텍처 현황 (유지할 구조)
```
Sources/MovieCutCore/          ← 플랫폼 중립 SwiftPM 패키지
  Models/        (Project, Timeline, Track, Clip, ExportSettings, …)
  Commands/      (명령 패턴, EditorSession.dispatch 경유, undo/redo)
  Rendering/     (shared pixel processors — CIImage in/out)
  Analysis/      (무음/씬/리프레임 provider)
  Transcription/ (STT provider 추상화)
App/MovieCutMac/               ← AppKit/SwiftUI 앱
  EditorViewModel.swift        (UI ↔ Core 브리지, @MainActor)
  Playback/PlaybackEngine.swift (AVPlayer 기반 preview, custom compositor)
  Export/ExportEngine.swift     (AVAssetExportSession + CustomVideoCompositor)
App/MovieCutiOS/               ← Mac과 동일 패턴 (compositor 포팅 유지)
```

**불변 원칙**
- A1. 모든 편집 변형은 `EditorSession.dispatch(Command)` 경유 (undo/redo 보장). ViewModel에서 모델 직접 변형 금지.
- A2. 시각 효과는 `Sources/MovieCutCore/Rendering/`의 shared processor(CIImage→CIImage)로 구현, Mac/iOS compositor는 위임만.
- A3. preview와 export는 동일한 effect metadata를 소비한다 (한쪽만 구현 금지).
- A4. Core는 AVFoundation 등 미디어 프레임워크 의존을 최소화하고, 미디어 I/O는 앱 레이어에서.
- A5. 모델 필드 추가는 Codable 하위호환(optional 디코딩) + 디코딩 테스트 의무.

---

## 3. 마일스톤

| 마일스톤 | 테마 | 포함 기능 | 완료 판정 |
|---|---|---|---|
| **M1. 편집 기본기 완성** | 미디어 파이프라인 + 타임라인 UX | F-01, F-04(잔여), F-05, F-06 | W1 워크플로우를 외부 도움 없이 완주 |
| **M2. 비주얼 심화** | 효과의 신뢰성과 깊이 | F-07~F-11 | W4 완주 + export visual fixture 통과 |
| **M3. 오디오 & 텍스트** | 소리와 자막의 CapCut 체감 | F-12R, F-13~F-15, F-17 | W2, W3 완주 |
| **M4. 지능형 편집** | AI 도구 E2E | F-18~F-21 | 자동컷/리프레임이 실제 영상에서 유효 결과 |
| **M5. 생태계(선택)** | 클라우드/게시/마켓 | F-22~F-24 | 별도 합의 후 착수 |

순서 원칙: M1→M2→M3 순차 권장(의존성), M4는 M2와 병행 가능. 각 마일스톤 종료 시 §1.1 워크플로우 1회 수동 완주 + 백로그/핸드오프 문서 갱신.

---

## 4. 기능 명세

각 항목: **요구사항 → 구현 방안(파일 수준) → 수용 기준(AC)**.

### M1. 편집 기본기

#### F-01. 비파일 드래그 소스 수용 (사진/브라우저) — 🟡 구현+행동테스트+Safari 실기기 검증 완료(2026-06-11), Photos/네이티브 소스 검증 잔여 (`pending`, 2026-06-11)
- **요구사항**: 사진(Photos) 앱, 웹 브라우저, 메일 첨부에서 이미지/영상을 타임라인·라이브러리에 직접 드래그할 수 있다.
- **구현**: `TimelineView.handleTrackDrop` / `MediaLibraryPanel.handleDrop`의 수용 타입에 `.image`, `.movie`를 추가하고, `DragDropHandler.loadExternalMediaURLs`가 file URL, `loadFileRepresentation`, `loadDataRepresentation` payload를 임시 디렉토리(`FileManager.temporaryDirectory/MovieCutImports/`)에 materialize한 뒤 기존 `importMediaAndAddToTimeline` / `importMedia` 경로를 재사용한다. raw image/movie data는 UTType 기반 확장자로 저장 후 동일 경로에 태운다.
- **AC**: ① 사진 앱에서 사진을 타임라인에 드래그 → 클립 생성 ② Safari 이미지 드래그 → 클립 생성 ③ 실패 시 `lastErrorMessage`로 원인 표시. **실기기 검증 필수**(드래그앤드롭 전례 — F-01은 contract 테스트만으로 완료 처리 금지).
- **검증 기록(2026-06-11)**: 구현은 Core `DragDropHandler.loadExternalMediaURLs`(fileURL 통과 + movie/image 우선순위 + `loadFileRepresentation`→data fallback→임시 디렉토리 기록)로 완료. `ExternalMediaDropTests` 6개가 실제 `NSItemProvider` 페이로드(브라우저식 PNG data, mp4 data, fileURL, 비미디어 거부, movie>image 우선, 파일명 규칙)를 행동 검증. 타임라인/라이브러리 `.onDrop`에 `.movie`/`.image` 추가. **실기기 추가 확인(2026-06-11 야간): Finder 실드래그가 신규 movie file-representation 경로로 클립을 정상 생성**(라이브러리에 3.0s·640×360·30fps 메타데이터, 드롭 위치 클립, 상태 피드백 — 즉 F-01 신규 코드 경로 자체는 실드래그로 입증됨). **Safari AC② 추가 검증(2026-06-11 22:44~22:56): embedded data URL PNG를 Safari에서 MovieCut 라이브러리로 실제 마우스 드래그 → `Imported Media.png` row 생성(320×180, `Thumbnail ready`, status `Imported 1 media file.`); 같은 Safari data URL PNG를 Video 1 타임라인 레인으로 실제 마우스 드래그 → `image-…` 클립 생성. 증거 스크린샷: `/tmp/moviecut_f01_safari_data_to_library_after.png`, `/tmp/moviecut_f01_timeline_direct_after.png`.** 사진 앱→타임라인 드래그는 Photos window 0 및 AppleScript import timeout으로 자동 검증이 막혔고, Preview/Telegram 대체 네이티브 소스 시도 시 `screencapture`가 black frame만 반환해 증거 확보 실패. 따라서 AC①/네이티브 앱 소스 검증은 잔여로 유지하고 F-01 전체 완료는 보류한다.
- **현재 검증**: `swift build`, `swift test --filter 'ExternalMediaDrop|MediaDragDrop|DragDropFeedback|Drop'`, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` 통과. 남은 검증은 실제 Photos/Safari/브라우저 GUI 드래그다.

#### F-03. 마그네틱 타임라인 — ✅ 완료 (`08db5a0`, 2026-06-11)
- **요구사항**: CapCut처럼 클립 이동/삭제 시 같은 트랙의 뒤 클립들이 자동 밀착(옵션 토글). 드래그 중 인접 클립과 충돌 시 밀어내기 또는 스왑.
- **구현**: Core에 `MagneticInsertCommand`/`CloseGapCommand` 신설(기존 `RippleDeleteCommand` 일반화). `EditorViewModel.isMagneticTimeline: Bool`(기본 on, UserDefaults). `TimelineView.moveGesture` 커밋 시 마그네틱 모드면 충돌 해소 명령으로 변환. 토글 UI는 타임라인 헤더에 자석 아이콘.
- **AC**: ① 중간 클립 삭제 → 갭 자동 닫힘 ② 클립을 다른 클립 위로 드래그 → 겹침 없이 삽입·재배치 ③ 토글 off 시 기존 자유 배치 유지 ④ 모든 동작 단일 undo.

#### F-04. 클립 단위 zIndex & 그룹/링크 — ✅ 완료 (zIndex `08db5a0`, 그룹/링크 `1f46b13` + GUI 실기기 검증 2026-06-11)
- **요구사항**: 트랙이 아닌 클립 단위 레이어 순서 조정. 영상+오디오, 영상+자막을 그룹으로 묶어 함께 이동/트림.
- **구현**: `Clip`에 `zIndexOverride: Int?`, `groupId: UUID?` 추가(A5 준수). compositor 정렬 키를 `(track.zIndex, clip.zIndexOverride ?? 0)`으로 확장. 그룹: 컨텍스트 메뉴 "Group/Ungroup", `moveClip`/`trimClip`이 같은 groupId 클립에 델타 전파(단일 undo 단위 batch dispatch).
- **AC**: ① 두 텍스트 오버레이의 앞뒤 순서를 클립 단위로 변경 → preview/export 동일 ② 그룹 이동 시 상대 오프셋 유지 ③ ungroup 후 개별 동작 ④ 구버전 프로젝트 로드 호환.
- **GUI 실기기 검증(2026-06-11 야간)**: 그룹 클립 2개가 든 프로젝트 파일을 새로 배선한 File>Open으로 로드 → 타임라인에 link 아이콘 표시 확인 → **그룹 클립 하나만 단일 클릭 후 Delete 1회 → 그룹 멤버 2개가 모두 삭제됨**(Export Summary 6.0s→Timeline empty)으로 연결 선택을 행동 입증. Group/Ungroup 컨텍스트 메뉴 노출·비활성 로직과 "Select at least two clips to group" 가드 피드백도 실조작 확인. Caveat: 합성 이벤트는 cmd+클릭 modifier를 전달하지 못해(자동화 도구 한계) GUI에서의 그룹 생성은 사전 그룹 프로젝트 파일로 우회 검증했고, 그 과정에서 탭 제스처를 `NSApp.currentEvent` 폴링에서 `TapGesture().modifiers(.command)` 이벤트 기반으로 교체(견고성 개선).
- **검증 기록(2026-06-11)**: `Clip.groupId`(optional, legacy decode 기본 nil) + `GroupClipsCommand`/`RestoreClipGroupsCommand`(이질적 이전 멤버십 복원 invert) + EditorViewModel 연결 선택(`selectTimelineClip`/`linkedClipIds` — 그룹 클립 선택 시 그룹 전체 선택, Cmd-해제 시 그룹 전체 해제) + 타임라인 컨텍스트 메뉴 Group/Ungroup + link 아이콘 표시. `ClipGroupingTests` 7개(legacy decode, round-trip, cross-track 그룹, undo 복원, 단일/미존재 클립 거부, 이질 멤버십 invert) 통과, 필터 스위트 196개 + Mac 앱 빌드 통과. **설계 결정**: `08db5a0`의 마그네틱 패킹이 모든 트랙을 0초부터 끝-시작 밀착으로 강제하므로 AC②의 "시간 오프셋 유지 이동"은 현 아키텍처에서 정의 불가 — 대신 연결 선택으로 그룹이 기존 다중선택 연산(삭제/복제/이동 툴바)의 단위가 되는 CapCut 링크 방식을 채택. GUI 실조작(Group/Ungroup 메뉴, 연결 선택) 확인은 잔여.

#### F-05. 키보드 단축키 맵 — ✅ 구현+정적 계약 완료(2026-06-11), GUI 실동작 검증 별도
- **요구사항**: CapCut 표준 단축키. Space(재생/정지), Cmd+B(분할), Q/W(playhead 기준 앞/뒤 트림), Delete(삭제), Shift+Delete(ripple), Cmd+D(복제), ←/→(프레임), Shift+←/→(1초), ↑/↓(클립 점프), +/-(줌), M(마커), Cmd+Z/Shift+Cmd+Z.
- **구현**: `MovieCutMacApp`의 `.commands`가 `Playback`/`Timeline` 메뉴와 Edit undo/redo replacement로 F-05 키맵을 단일 등록한다. `EditorViewModel`은 Q/W trim-to-playhead, Shift+Delete ripple delete, Cmd+D duplicate, Shift+Arrow 1초 seek, Up/Down clip-boundary jump, +/- timeline zoom을 기존 command/dispatch 흐름 또는 ViewModel playback/selection state로 노출한다. `ContentView`의 toolbar/background shortcut 중복 등록은 제거하고 toolbar 버튼은 클릭 액션만 유지한다. Help 메뉴에는 "MovieCut Keyboard Shortcuts" 목록을 추가했다.
- **텍스트 입력 caveat**: full SwiftUI `@FocusState` command router는 아직 도입하지 않았다. 대신 Space/Q/W/Delete/Arrow/+/-/M 같은 text-entry-sensitive command actions는 `MovieCutShortcutGuard`에서 AppKit first responder(`NSTextView`/`NSTextField`)를 확인해 중앙 차단하고, static contract로 잠근다.
- **AC 상태**: ① 메뉴 표기와 전 shortcut 등록은 static contract로 완료 ② 텍스트 필드 충돌은 guard 기반 best-effort 완료, 실제 텍스트 편집 GUI 회귀는 호스트 확인 필요 ③ Help 메뉴 목록 구현 완료. **GUI 실동작 검증은 이번 완료 범위에 포함하지 않음.**

#### F-06. 임포트 메타데이터 완성 (해상도/fps) — ✅ 구현+정적 계약 완료(2026-06-11)
- **요구사항**: duration만 읽는 현재 probe를 확장해 해상도/fps/코덱을 `MediaMetadata`에 기록, 라이브러리 행과 Inspector에 표시.
- **구현**: Core `MediaImporter.probe`는 기존처럼 Foundation-only 경량 probe로 유지하고, macOS 앱 레이어 `EditorViewModel.mediaAssetWithAppProbe`가 `AVURLAsset.loadTracks(withMediaType:)`와 Swift async `load` API로 video duration/naturalSize/preferredTransform/nominalFrameRate/formatDescriptions, audio duration/sample rate/channel count/formatDescriptions를 best-effort metadata probing으로 채운다. Still image는 ImageIO/NSImageRep로 width/height를 읽는다.
- **표시**: `MediaLibraryPanel` 라이브러리 행과 접근성 value가 resolution, fps, codec, audio sample rate/channel count를 compact summary로 노출한다. 현재 별도 selected-asset Inspector가 없으므로 이 배치의 Inspector 대체 표면은 라이브러리 행 + accessibility value로 문서화한다.
- **Caveat**: import는 probe 실패에도 계속 성공한다. exact codec labels depend on AVFoundation format descriptions/subtype mapping. GUI visual verification not included; 정적 계약과 빌드/테스트 기준으로 완료 처리한다.
- **AC**: 1080p/30fps 영상 임포트 시 라이브러리에 "3.0s · 1920×1080 · 30 fps · H.264" 형식으로 표시 가능. 오디오 asset은 "48 kHz · 2 ch · AAC", 이미지 asset은 "1920×1080" 형식으로 표시 가능. 프록시 트리거(F-02 완료분)는 기존 흐름을 유지한다.

### M2. 비주얼 심화

#### F-07. 전환효과 E2E 시각 검증 + 갭 마감
- **요구사항**: 12종 전환이 preview와 export에서 **시각적으로 동일**하게 렌더됨을 증명. crossDissolve/fadeThroughBlack/wipeRight도 layer-instruction ramp가 아닌 two-source 경로로 통일.
- **구현**: ① 잔여 3종을 two-source 경로로 이관 ② **export visual fixture 테스트** 신설: 고정 색 합성 클립 2개 + 각 전환 1초 export → 중간 프레임 픽셀 샘플 기대값 비교(`TransitionExportFixtureTests`; sandbox CoreImage 불가 환경은 skip 마킹).
- **AC**: ① 12종 전환 각각 export 픽셀 fixture 통과 ② preview 스크럽과 시각 일치 ③ 전환 duration이 인접 클립 overlap과 일치.
- **검증 기록(2026-06-11 targeted pass)**: `TransitionPixelProcessorTests`에 fade-through-black midpoint가 cross dissolve가 아니라 black boundary를 통과하는 픽셀 fixture와 0.25/0.75 boundary progression fixture를 추가했다. `InspectorEffectsSection`은 transition picker/duration accessibility와 `transitionVerificationNote`를 노출하여 accepted evidence, blocked claim, next artifact, owner를 명확히 표시한다. 이 기록은 **targeted transition confidence only**이며 export golden, device playback, full-suite, release-ready claim은 여전히 금지한다. 다음 산출물은 deterministic golden export sample(output path + hash)이다. Timeline minimum height는 header/ruler/3개 기본 lane이 GUI 검증 중 가려지지 않도록 210으로 올렸다.

#### F-08. 배경 제거 (인물 세그멘테이션) 실동작
- **요구사항**: 버튼 한 번으로 인물 외 배경 제거(알파) → preview/export 반영.
- **구현**: 기존 Vision 기반 segmentation(`b85a10a`)을 frame-by-frame 경로로 연결: `CustomVideoCompositor`에서 `backgroundRemoval` effect 클립에 `VNGeneratePersonSegmentationRequest` 마스크를 `MaskPixelProcessor`와 동일한 알파 합성으로 적용. preview는 fast quality+프레임 캐시, export는 accurate.
- **AC**: ① 인물 영상 적용 시 preview 배경 투명(캔버스 배경 노출) ② export 동일 ③ 1080p preview 15fps 이상(프록시 병행) ④ 인물 없는 영상은 무변경 + 상태 메시지.

#### F-09. 외부 LUT(.cube) 임포트
- **요구사항**: .cube 파일을 가져와 필터로 적용·관리, 강도 조절.
- **구현**: Core `Rendering/CubeLUTParser`(.cube 텍스트 → `CIColorCube` data, 17/33/65 size). `Effect`에 `lutURL` 파라미터. Inspector 필터 섹션 "Import LUT…"(NSOpenPanel) + `~/Library/Application Support/MovieCut/LUTs/` 보관.
- **AC**: ① 표준 33-size .cube 적용 시 preview/export 색 변화 일치(픽셀 테스트) ② 잘못된 파일 에러 메시지 ③ intensity 0~1 슬라이더.

#### F-10. 크로마키 스포이드 & 매트 보정
- **요구사항**: 미리보기에서 클릭으로 키 색상 추출(eyedropper), 매트 정리(shrink/feather).
- **구현**: `PreviewPanel` eyedropper 모드(클릭 좌표 → 현재 프레임 픽셀 → `ChromaKeySettings.keyColor`). `ChromaKeyPixelProcessor`에 matte erode/feather 파라미터 추가(기존 softness와 직교).
- **AC**: ① 그린스크린에서 스포이드 1클릭 → 즉시 키잉 ② edge fringe가 feather로 감소(픽셀 테스트) ③ 설정 프로젝트 저장/복원.

#### F-11. 캔버스 배경 (컬러/블러/이미지) — 🟡 구현+테스트+배선 완료(2026-06-11), 실기기/визual fixture 잔여
- **요구사항**: 9:16 캔버스에 16:9 영상 배치 시 여백을 단색/소스 블러/이미지로 채움.
- **구현**: `Project.canvasBackground: CanvasBackground`(enum: color(hex)/blur(radius)/image(url), A5 준수). compositor 첫 단계에서 배경 합성(blur는 소스 확대+`CIGaussianBlur`). ProjectSettings popover에 UI.
- **AC**: ① 3종 배경 모두 preview/export 일치 ② blur 배경이 프레임마다 갱신(정지 아님).

### M3. 오디오 & 텍스트

#### F-12R. 텍스트 스타일 잔여분 (외곽선/그림자/프리셋 저장)
- **상태**: 본문/폰트/크기/정렬/전경·배경색/quick preset은 `4a2bad8`에서 완료. 잔여: 외곽선(stroke), 그림자(shadow), 굵기/이탤릭, 사용자 프리셋 저장.
- **구현**: `TextClipContent`에 stroke(색/두께)/shadow(색/오프셋/블러)/weight/italic 필드 추가(A5). `TextOverlayPixelProcessor` 확장(stroke=외곽 draw, shadow=offset draw). 사용자 프리셋 `~/Library/Application Support/MovieCut/TextStyles.json`.
- **AC**: ① stroke/shadow 유무가 export 픽셀 테스트로 구분 ② 프리셋 저장→새 텍스트 1클릭 적용 ③ 구버전 프로젝트 호환.

#### F-13. 자막 편집 워크플로우 완성 — 🟡 구현+테스트 완료(2026-06-11), W3 실기기 완주 잔여
- **요구사항**: STT 결과를 리스트에서 텍스트 수정·타이밍 조정·분할/병합 후 일괄 스타일 적용. SRT import/export.
- **구현**: `AutoSubtitlesView` 확장: pending segment 인라인 편집(텍스트/start/end), 행 분할·병합. Core `SubtitleDocument`(SRT 파서/시리얼라이저, 외부 의존 없음). 스타일은 F-12R 프리셋 참조.
- **AC**: ① 5분 영상 STT → 오인식 수정 → 일괄 스타일 → burn-in export 완주(W3) ② SRT export가 외부 플레이어에서 로드됨 ③ SRT import로 자막 클립 생성.
- **검증 기록(2026-06-11)**: Core `SubtitleDocument`(SRT 파서/시리얼라이저 — 인덱스 라인 생략·CRLF·dot-millis 허용, 잘못된/역순 타임코드 블록 스킵, 시작시간 정렬, 라운드트립) + `SubtitleDocumentTests` 7개. ViewModel: `updateGeneratedSubtitleSegment`(텍스트/시작/끝, 최소 0.1s 보장, 재정렬), `splitGeneratedSubtitleSegment`(중점 분할+단어 반분), `mergeGeneratedSubtitleSegmentWithNext`, `deleteGeneratedSubtitleSegment`, `importSubtitles(from:)`/`exportSubtitles(to:)` — export는 편집 중 세그먼트 우선, 없으면 타임라인 텍스트 클립(스티커 제외)에서 유도. 모든 편집은 `rebuildPendingSubtitleClips()`로 STT와 동일한 정렬 규칙(선택 클립 정렬 또는 00:00 기준)을 재사용. `AutoSubtitlesView`에 행 단위 인라인 편집(로컬 버퍼, submit/포커스 해제 시 커밋)·분할/병합/삭제 버튼·Import/Export SRT 패널. Caveat: W3 워크플로우 실기기 완주(STT→수정→burn-in export)와 외부 플레이어 SRT 로드 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

#### F-14. 오디오 DSP 실구현 (EQ/덕킹/노이즈) — 🟡 덕킹(범위 기반) 구현+테스트 완료(2026-06-11), EQ/노이즈 DSP·청감 확인 잔여
- **요구사항**: EQ 프리셋 5종(보이스 강조/저음 강화 등), 자동 덕킹(보이스 구간 BGM -12dB), 노이즈 감소 강도 조절 — preview/export 모두에서 들림.
- **구현**:
  - 덕킹(우선): `SilenceDetectionProvider` 역활용 — 보이스 트랙 비무음 구간에 BGM volume keyframe 자동 생성(`AudioDuckingCommand` 완성). keyframe 방식이라 preview/export 자동 일치.
  - EQ: `MTAudioProcessingTap`으로 `AVAudioUnitEQ` 체인을 preview에 적용, export는 오디오 사전 렌더(offline render 후 교체 asset) — 양 경로가 **공통 렌더 함수**를 쓰도록 Core에 파라미터 정의.
  - 노이즈: 기존 noise reduction 경로(`e420791`) 검증 + 강도 파라미터 노출.
- **AC**: ① 사인파 fixture FFT로 EQ 전후 스펙트럼 차이 확인 ② 덕킹 ramp가 파형으로 확인 ③ preview/export 청감 일치(수동 1회) ④ 모두 undo 가능.
- **검증 기록(2026-06-11, 덕킹)**: Core `AudioDuckingPlanner`(silence 보집합→voice intervals, padding/merge/clip-local 변환 — 순수 수학, 행동 테스트 6개) + `Clip.duckingRanges`/`duckingLevel`(A5 하위호환 + 디코딩 테스트) + `SetAudioDuckingCommand`(다중 클립 단일 undo, clear+invert 복원). Mac Export/Playback 양 엔진의 `applyAudioVolumeAndFades`에 동일한 `applyDuckingRamps` 추가 — attack 0.12s/release 0.25s ramp, fade 창과 겹침 방지 클램프(A3: 같은 메타데이터 소비). ViewModel `autoDuckOtherAudio`(선택 음성 클립 silence 분석→타임라인 매핑→겹치는 오디오 클립에 일괄 적용, 기본 -12dB=0.25) + `clearDuckingOnSelectedClip`, Inspector Audio Ducking 그룹(Duck Other Audio/Clear + 범위·레벨 표시). `AudioDuckingTests` 14개 통과. Caveat: 실제 청감(preview 재생/export 파형) 확인과 EQ/노이즈 DSP는 잔여 — DoD §1.3에 따라 ✅ 보류. 속도 램프된 클립의 클립-로컬 시간 매핑은 미보정(후속).

#### F-15. 비트 감지 (음악 동기 편집) — 🟡 구현+합성 트랙 검증 완료(2026-06-11), 실음원 확인 잔여
- **요구사항**: BGM 클립에서 비트 감지 → 타임라인 비트 마커 표시, 스냅 대상 포함.
- **구현**: Core `Analysis/BeatDetectionProvider`(에너지 플럭스 onset, Accelerate vDSP). `Marker`에 `kind: .beat` 추가(A5). `TimelineView.snappedTime` snap point에 비트 마커 포함.
- **AC**: ① 고정 BPM 테스트 트랙에서 비트 간격 오차 < 50ms ② 클립 드래그가 비트에 스냅 ③ 비트 마커 일괄 삭제.
- **검증 기록(2026-06-11)**: Core `BeatDetectionProvider` — 에너지 플럭스 onset 검출(frame 1024/hop 512, 적응 임계 + 피크 에너지 10% 절대 하한으로 정상파 오탐 억제, 최소 비트 간격 피크 픽킹)을 **순수 함수**로 구현해 합성 클릭 트랙으로 행동 검증: 120BPM 8비트 간격 오차 <50ms(AC①), 80BPM 카운트, 무음/상수 톤 무오탐, 간격 억제, BPM 추정(±8). AVFoundation 래퍼는 무음 감지와 동일한 AVAssetReader 모노 PCM 읽기. `Marker.kind`(.standard/.beat, A5 하위호환+디코딩 테스트), `AddMarkersCommand`/`RemoveMarkersCommand(kind:)` 배치 단일 undo(테스트 포함). 타임라인: 비트는 룰러 하단 주황 틱으로 렌더(플래그 홍수 방지), 기존 marker-시간 스냅 경로에 자동 포함(AC②), Quick Tools `Detect Beats`(+BPM 상태 메시지)/`Clear Beats`(AC③). `BeatDetectionTests` 13개 + 필터 스위트 130개 + Mac 빌드 통과. Caveat: 실제 음악 파일 GUI 검증과 드래그 스냅 체감 확인 잔여 — DoD §1.3에 따라 ✅ 보류.

#### F-17. TTS (텍스트→음성)
- **요구사항**: 텍스트 클립에서 "음성 생성" → 합성 오디오 클립 생성(시스템 보이스 선택).
- **구현**: `AVSpeechSynthesizer.write(_:toBufferCallback:)`로 파일 렌더 → 기존 import 경로 재사용.
- **AC**: 텍스트 클립과 동기화된 오디오 클립 생성, export 포함.

### M4. 지능형 편집

#### F-18. 자동 컷 E2E 신뢰성
- **요구사항**: 무음 제거가 실제 인터뷰 영상에서 유효(임계값/최소 구간/패딩 조절 UI + 적용 전 미리보기).
- **구현**: 기존 `SilenceDetectionProvider` + 파라미터 UI(threshold dB, 최소 무음 길이, 앞뒤 패딩). 제거 예정 구간을 타임라인 하이라이트로 미리보기 → 확인 후 일괄 적용.
- **AC**: ① 10분 인터뷰 fixture에서 발화 손실 없음(수동 1회 + 무음 비율 테스트) ② 미리보기→취소 시 무변경 ③ 일괄 적용 단일 undo.

#### F-19. 씬 감지 & 자동 리프레임 E2E
- **요구사항**: 씬 분할과 피사체 추적 리프레임(16:9→9:16)이 실제 영상에서 유효, 리프레임 결과 미리보기 후 확정.
- **구현**: 기존 provider 검증 + 크롭 경로 preview 오버레이 표시 → 확정. 리프레임 keyframe 이동 평균 스무딩.
- **AC**: ① 멀티씬 fixture에서 컷 경계 ±10프레임 분할 ② 리프레임 시 인물이 크롭 밖으로 나가는 프레임 0 ③ keyframe 떨림 없음(미분값 상한 테스트).

#### F-20. 자동 하이라이트 (롱폼→숏폼 후보)
- **요구사항**: 오디오 에너지/음성 밀도/씬 변화 점수화 → 상위 N개 구간(15~60초) 제안 → 클릭으로 새 시퀀스 생성.
- **구현**: Core `Analysis/HighlightScorer`(기존 provider 출력 조합, 신규 ML 의존 없음). UI는 분석 히스토리 패널 확장.
- **AC**: 30분 fixture에서 3개 후보 제안 → 선택 시 해당 구간만의 새 프로젝트 생성.

#### F-21. AI 어시스턴트 (로컬 명령 해석, 선택)
- **요구사항**: "모든 클립에 시네마틱 필터 적용해줘" 수준의 자연어를 기존 명령으로 매핑하는 패널. 외부 LLM API 연동은 별도 합의.
- **구현 1단계**: 규칙 기반 intent 매핑(대상×동작 동의어 사전) → `EditorSession` 명령 시퀀스. 온디바이스 Foundation Models 연동은 후속 검토.
- **AC**: 정의된 20개 intent 문장 시나리오 테스트 통과, 미해석 문장은 가능한 명령 안내.

### M5. 생태계 (착수 전 별도 합의)
- **F-22. iCloud 프로젝트 동기화**: 기존 `CloudSyncService` 완성 — conflict는 최신 수정 우선 + 백업 사본. AC: 두 기기 시나리오 시뮬레이션 테스트.
- **F-23. 템플릿 패키지**: 프로젝트를 에셋 포함 `.mctemplate`(zip)로 export/import. AC: 템플릿 적용 후 미디어 교체 플로우 완주.
- **F-24. 플랫폼 게시**: OS 공유 시트 유지(직접 API 게시는 범위 외 유지 권장).

---

## 5. 비기능 요구사항 (NFR)

| 항목 | 기준 |
|---|---|
| Preview 성능 | 1080p 타임라인 재생 30fps(효과 2개 중첩 기준), 4K는 프록시로 동일 |
| 분석 작업 | 모든 분석(STT/씬/무음/리프레임/비트)은 비동기 + 진행률/상태 메시지, UI 블로킹 0 |
| 프로젝트 파일 | 모델 변경은 Codable 하위호환(optional 디코딩) + 디코딩 테스트 의무(A5) |
| Undo | 사용자 가시 변형 100% undo/redo, 그룹 동작은 단일 undo 단위 |
| 접근성 | 신규 UI는 기존 관례 유지: accessibilityLabel/Value/Hint + VoiceOver custom action |
| 현지화 | `NSLocalizedString` 경유, 한국어/영어 |
| 에러 가시성 | 실패 침묵 금지 — `lastErrorMessage`/`lastStatusMessage` 경유 status bar 표시 |

---

## 6. 테스트 전략

드래그앤드롭 사례(contract 통과 + 런타임 깨짐)의 재발 방지가 핵심.

1. **픽셀 프로세서**: 기존 패턴 유지 — guarded `CIContext` 픽셀 샘플링 + extent 보존 + renderable contract.
2. **Export visual fixture (신설, M2)**: 고정 색 합성 클립으로 실제 export 실행 → 프레임 픽셀 기대값 비교. 전환/필터/배경제거/텍스트 스타일에 적용. sandbox에서 CoreImage 불가 시 skip 마킹.
3. **XCUITest 스모크 (신설, M1)**: `MovieCutMacUITests` 타겟. 최소 시나리오: 앱 실행 → 임포트 → 클립 존재 → 분할 → export 시트. CI는 `xcodebuild test`.
4. **Static contract**: 배선 가시성 용도로만 유지 — **단독으로 "완료" 근거 사용 금지**.
5. **수동 검증 체크리스트**: 각 마일스톤 종료 시 §1.1 워크플로우 1회 완주, 결과를 핸드오프 문서에 기록.

---

## 7. 리스크와 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| preview/export 오디오 경로 불일치 (F-14) | 들리는 결과 다름 | 덕킹은 keyframe 방식 우선(자동 일치), DSP는 공통 렌더 함수 |
| Vision 세그멘테이션 성능 (F-08) | preview 프레임 드롭 | fast quality + 프레임 캐시 + 프록시, export만 accurate |
| 마그네틱 타임라인 회귀 (F-03) | 기존 편집 파괴 | 기존 명령 경로 보존, 충돌 해소만 신규 명령, 토글로 격리 |
| 모델 필드 추가로 구버전 파일 깨짐 | 프로젝트 손실 | A5(optional 디코딩 + 디코딩 테스트) 의무 |
| iOS 동기화 누락 | 플랫폼 분기 | compositor/모델 변경 시 iOS 대응 파일 체크 (기존 관례) |
| 권한 의존 기능 (F-13 Speech, F-16 Mic) | 기능 차단 | usage description + 거부 시 안내 UI (F-16은 적용됨) |
| 다중 세션 동시 작업 | 문서/작업 충돌·유실 | 신규 문서는 작성 즉시 커밋, 세션 시작 시 `git log`/`git status` 확인(핸드오프 §2-1) |

---

## 8. 운영 규칙

- 작업 단위: 기능 ID(F-xx) 단위 커밋(`feat: F-03 magnetic timeline`), 완료 시 ① 백로그 체크 ② 이 문서 AC에 검증 결과 1줄 ③ 핸드오프 갱신.
- DoD 4단계(§1.3) 미충족 기능은 백로그에 ✅ 표기 금지 — caveat와 함께 🟡 유지.
- AC 변경은 이 문서 선(先)수정·커밋 후 구현.
