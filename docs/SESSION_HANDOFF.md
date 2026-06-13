# 세션 핸드오프 — 다음 개발 세션 시작 가이드

> 작성일: 2026-06-11 / 브랜치: `main` / 기준 커밋: `08db5a0` (magnetic timeline + clip z-index)
> 이 문서만 읽고 바로 작업을 시작할 수 있도록 작성됨. 기능 백로그 전체는 `docs/CAPCUT_FEATURE_BACKLOG.md`, **개발 명세서(F-ID별 요구사항/구현 방안/수용 기준/마일스톤/DoD)는 `docs/CAPCUT_PARITY_SPEC.md`** 참고. 신규 기능 작업은 명세서의 F-ID 단위로 진행.

---

## 1. 현재 상태 요약

- CapCut 파리티 작업은 Batch 17 이후 P1 transition pass, export/마스크 접근성 및 custom bitrate clamp, 실기기 드래그앤드롭 수정, 썸네일/프록시 생성, speed ramp preview contract, 텍스트 스타일 편집 UI, 보이스오버 실녹음, F-06 임포트 메타데이터 배치까지 진행됨.
- 이전 핸드오프의 **미커밋 71개 파일 유실 위험은 해결됨**. 기능 단위 커밋 6개(`d5db68f`~`ef74997`), 접근성/비트레이트 커밋 `45cda56`, 실기기 드래그앤드롭 수정 `91e7cb4`, 썸네일/프록시 생성 `3933d94`, speed ramp preview contract `71893cb`, 텍스트 스타일 UI `4a2bad8`, 보이스오버 실녹음 `4e982b0`까지 저장됨.
- `45cda56` 포함 작업:
  - `ExportSettings` custom bitrate를 1~200 Mbps 범위로 문서화/클램프.
  - Mac Export 버튼/진행률/Share, Inspector export picker/summary/preset/custom bitrate에 VoiceOver label/value/hint 추가.
  - iOS export progress/result sheet 접근성 문구 추가.
  - Mac/iOS Mask Canvas resize VoiceOver 액션 추가: width/height를 1% 단위로 증감. macOS는 brush point scale 유지, iOS는 resize 액션 및 rotation brush point 보정 포함.
  - 대응 static contract 테스트 3종 갱신.
- 검증 완료:
  - `swift test --filter 'ExportFormatStaticContract|IOSMaskCanvasStaticContract|MacMaskCanvasStaticContract'` — 23 tests passed.
  - `git diff --check` — 통과.
  - `swift test --filter 'Transition|Rendering|StaticContract'` — 108 tests passed (2026-06-10 재실행, 접근성 배치의 contract 테스트 추가로 P1 transition pass 시점의 98개에서 증가). `swift build` 및 `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.
- `3933d94` 썸네일/프록시 배치는 `swift build`, `swift test --filter 'Thumbnail|Proxy|Rendering|StaticContract'`(107 tests passed), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED로 검증됨.
- speed ramp preview 배치는 Mac `PlaybackEngine`의 video, embedded-audio, standalone audio-track preview 경로가 `SpeedRampCurve` segment 삽입과 `scaleTimeRange`를 사용한다는 static contract로 검증됨. 호스트 검증: `git diff --check`, `swift build`, `swift test --filter 'SpeedRamp|speed ramp|StaticContract'` 69 tests passed, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.
- 텍스트 스타일 편집 UI 배치는 Mac `InspectorBasicSection`의 일반 텍스트 클립 편집 그룹이 본문, 폰트, 크기, 정렬, foreground/background 색상, background none toggle/path, Title/Caption/Lower Third/BG Safe quick presets를 `TextClipContent` + `updateSelectedTextContent` command path로 갱신하도록 닫는 범위다. Sticker clip은 기존 sticker metadata/transform 중심 UI를 유지한다. 호스트 검증: `git diff --check` 통과, `swift build` 통과, `swift test --filter 'Text|StaticContract|Rendering'` 119 tests passed, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.
- 보이스오버 실녹음 배치는 Mac `Info.plist`에 `NSMicrophoneUsageDescription`을 추가하고, Mac `VoiceoverRecordingView`가 macOS `AVCaptureDevice` microphone 권한 확인/요청 후 shared `VoiceoverRecorder`(`AVAudioEngine` input tap)로 temp CAF를 녹음하도록 닫는 범위다. stop 시 recorder elapsed time을 `fallbackDuration`으로 넘기고, `EditorViewModel.addVoiceoverAudio(from:fallbackDuration:)`가 `audioDuration(for:)` → fallback duration → 0.1s minimum 순서로 clip duration을 확정하며, `MediaImporter`는 CAF를 audio asset으로 분류한다. 호스트 검증: `git diff --check`, `swift build`, `swift test --filter 'Voiceover|StaticContract|Audio'` 74 tests passed, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED. Caveat: 실제 마이크 캡처는 macOS Microphone 권한과 실제 입력 하드웨어 상태에 의존하므로 GUI 녹음 검증은 별도 실제 입력 환경에서 확인해야 한다.
- 페이드 duration 편집 UI 배치는 Mac `InspectorBasicSection`의 볼륨 섹션에서 fade controls를 분리해 `Fade Duration` Inspector 그룹으로 노출한다. Fade In/Fade Out은 현재값을 초 단위로 표시하고 Slider, Seconds `TextField`, 0.05s Stepper로 0...min(10s, clip duration) 범위 정밀 편집을 제공하며 Reset Fades/None/Soft/Long preset도 포함한다. 모든 변경은 `updateSelectedAudioFade` → `AudioFadeCommand` command path만 사용한다. 호스트 검증: `git diff --check`, `swift build`, `swift test --filter 'AudioFade|Fade|StaticContract|Audio'` 79 tests passed, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.
- 마그네틱 타임라인 / 클립별 zIndex 배치는 Core Add/Move/Duplicate/Delete command path의 track snapshot undo, same-track magnetic packing, persisted `Clip.zIndex`, Mac `TimelineView` display ordering 및 Bring to Front / Send to Back layer actions를 닫는 범위다. Caveat: 클립 그룹/링크는 P2 별도 항목으로 남긴다.
  - 검증: `git diff --check`, `swift build`, `swift test --filter 'Delete|Magnetic|ZIndex|CoreModule|StaticContract'`, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`를 호스트에서 재실행해 통과 확인.
- F-05 키보드 단축키 맵 배치는 `MovieCutMacApp.commands`에 Playback/Timeline/Edit 메뉴를 추가해 Space, Cmd+B, Q/W, Delete, Shift+Delete, Cmd+D, Arrow/Shift+Arrow, Up/Down, +/-, M, Cmd+Z/Shift+Cmd+Z를 단일 등록하고, `EditorViewModel`에 trim-to-playhead/1초 seek/clip-boundary jump/zoom actions를 노출한다. `ContentView`의 toolbar/background duplicate shortcut 등록은 제거됐다. Caveat: text-entry-sensitive unmodified shortcuts는 AppKit first-responder guard 기반 best-effort이며, 실제 GUI 텍스트 필드 회귀 검증은 호스트에서 별도 확인해야 한다.
  - 검증: `git diff --check`, `swift build`, `swift test --filter 'Keyboard|Shortcut|StaticContract'` 통과. macOS app compile은 가능하면 `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`로 추가 확인.
- F-06 임포트 메타데이터 배치는 Core `MediaImporter.probe`를 Foundation-only 경량 path로 유지하고, Mac `EditorViewModel.mediaAssetWithAppProbe`에서 AVFoundation/ImageIO best-effort metadata probing을 수행한다. Video/audio duration, video resolution/fps/codec, audio sample rate/channel count/codec, image dimensions를 `MediaMetadata`에 채우고, `MediaLibraryPanel` 행/접근성 value에 compact summary로 노출한다. Caveat: exact codec labels depend on AVFoundation format descriptions/subtype mapping. GUI visual verification not included.
  - 검증: static contract 기준. 호스트 검증은 `git diff --check`, `swift build`, `swift test --filter 'ImportMetadata|MediaMetadata|StaticContract'`, 가능하면 `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build`.
- **드래그앤드롭 P0는 실기기 GUI 검증까지 완료(2026-06-10)**. 라이브 검증 중 실제 버그를 발견·수정함: 기존 `DropDelegate` 기반 타임라인 `.onDrop` 등록이 실제 Finder 드래그를 조용히 거부했음(드래그 고스트는 레인 위에 표시되지만 drop 미발생, 로그/피드백 없음). 라이브러리 패널에서 검증된 closure 기반 `onDrop(of:isTargeted:perform:)` (location 오버로드)로 교체하고, 커스텀 UTType `com.moviecut.media-asset-id`를 Info.plist `UTExportedTypeDeclarations`에 정식 선언해 해결. Finder→타임라인 파일 드롭(드롭 위치 클립 생성 + 실제 3.0s duration + 상태 메시지)과 라이브러리→타임라인 내부 에셋 드래그 모두 실제 마우스 드래그로 확인됨.

## 2. 가장 먼저 할 일 (순서대로)

### 2-1. 상태 재확인 (커밋 유실 방지 확인)

이전 71개 파일 미커밋 이슈는 해결됐지만, 새 세션 시작 시 먼저 실제 작업트리를 확인:

1. `git status --short`가 비어 있는지 확인.
2. `git log --oneline -8`에서 최소 아래 커밋들이 보이는지 확인:
   - `f4a0255 feat: complete voiceover recording workflow`
   - `4a2bad8 feat: complete text style inspector controls`
   - `71893cb test: lock speed ramp preview parity`
   - `3933d94 feat: add thumbnail and proxy workflow`
   - `91e7cb4 fix: timeline drop rejected live Finder drags`
   - `45cda56 feat: custom bitrate clamp and export mask accessibility`
   - `ef74997 feat: wire two source transition compositor`
   - `541e805 feat: inspector stickers plugins and parity docs`
   - `a9bc5ea feat: persist export container quality bitrate`
   - `fb1c96a feat: speech subtitles and analysis contracts`
   - `81ec8e0 feat: shared pixel processors and compositor wiring`
   - `d5db68f feat: timeline drag drop import feedback`
3. 작업트리가 더러우면 먼저 diff/stat을 읽고 의도 있는 변경인지 확인한 뒤 기능 단위로 커밋.

### 2-2. 드래그앤드롭 실동작 — ✅ 검증 완료 (2026-06-10)

사용자가 반복 보고한 "드래그앤드롭이 안 된다"는 **실제 버그였음** (static contract 테스트는 통과했지만 런타임은 깨져 있었음).

- **근본 원인**: `TimelineTrackDropDelegate`(DropDelegate 기반) `.onDrop` 등록이 실제 Finder 드래그에서 조용히 거부됨. 같은 앱의 라이브러리 패널(closure 기반 `.onDrop`)은 정상 동작 → delegate 방식 + Info.plist 미선언 커스텀 UTType 조합이 원인.
- **수정**: ① 타임라인 드롭을 closure 기반 `onDrop(of:isTargeted:perform:)` location 오버로드로 교체(`handleTrackDrop`), ② `com.moviecut.media-asset-id`를 Info.plist `UTExportedTypeDeclarations`에 선언, ③ contract 테스트를 새 구현에 맞게 갱신.
- **라이브 검증**(실제 마우스 드래그, GUI 자동화): Finder→타임라인 드롭 시 드롭 위치에 클립 생성 + 실제 3.0s duration + "Added 1 media file to the timeline" 상태 메시지 확인. 라이브러리 행→타임라인 내부 드래그도 클립 생성 확인. 테스트 파일: `~/Desktop/MovieCutDropTest/` (재검증용으로 유지).
- **교훈**: 문자열 존재만 검사하는 static contract 테스트는 런타임 회귀를 못 잡는다. drop 등록 방식 같은 플랫폼 동작은 실기기 검증 필수.

### 2-3. 알려진 드래그앤드롭 잔여 갭

- **F-01 비파일 드래그 소스**: `.image`/`.movie` provider 수용, file representation/data representation materialization, 라이브러리/타임라인 기존 import 경로 재사용, NSItemProvider behavioral tests는 구현됨. 검증: `swift build`, `swift test --filter 'ExternalMediaDrop|MediaDragDrop|DragDropFeedback|Drop'` 13 tests passed, `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.
- **F-01 실기기 추가 확인(2026-06-11 22:44~22:56)**: Safari embedded data URL PNG → MovieCut 라이브러리 실제 드래그 성공(`Imported Media.png`, 320×180, thumbnail ready, `Imported 1 media file.`), Safari embedded data URL PNG → Video 1 타임라인 실제 드래그 성공(`image-…` 클립 생성). 증거: `/tmp/moviecut_f01_safari_data_to_library_after.png`, `/tmp/moviecut_f01_timeline_direct_after.png`. **남은 필수 확인**: Photos 앱 또는 대체 네이티브 앱 비파일 소스에서 실제 GUI 드래그로 클립 생성 확인. 이번 세션에서는 Photos window 0/AppleScript import timeout, Preview/Telegram 검증 시 screencapture black-frame으로 증거 확보 실패. F-01 명세는 contract 테스트만으로 완료 처리하지 말라고 못박혀 있으므로 전체 완료 처리는 아직 보류.
- UI 자동화 테스트 없음 — 이번 검증은 수동 GUI 드래그 기준. XCUITest 기반 자동화는 후속.

### 2-4. 최근 접근성/비트레이트 배치 후속 확인

`45cda56`은 static contract 수준 검증까지 완료. 후속으로 실제 VoiceOver/키보드 접근성 확인 권장:

1. Mac Export toolbar 버튼이 선택된 container/codec/resolution/frame rate/quality를 읽는지 확인.
2. custom bitrate 입력에 0, 75, 250 Mbps를 넣었을 때 `resolvedVideoBitrateMbps`가 nil/75/200으로 동작하는지 테스트는 이미 있음. 실제 Inspector 입력은 Stepper 범위 1...200.
3. Mac/iOS Mask Canvas에서 VoiceOver custom actions로 width/height 1% resize가 가능한지 수동 확인.
4. iOS mask rotation 액션과 brush point rotation 보정은 static contract만 있음. 실제 터치/VoiceOver는 후속 실기기 확인 필요.

## 3. 다음 개발 큐 (P1, 우선순위순)

**`docs/CAPCUT_PARITY_SPEC.md`의 F-ID가 작업 단위의 기준이다** (요구사항/구현 방안/AC 포함). 남은 M1 항목부터 순서대로:

| # | 작업 (명세서 F-ID) | 시작점 |
|---|---|---|
| 1 | **F-01 실기기 검증** — Safari/브라우저 data URL 이미지의 라이브러리 import와 Video 1 타임라인 클립 생성은 2026-06-11 실제 GUI 드래그로 확인됨. 남은 범위는 Photos 앱 또는 대체 네이티브 앱 비파일 소스 드래그 1회 검증. 구현/behavioral tests/xcodebuild는 통과, 완료 처리는 이 검증 후. | `TimelineView.handleTrackDrop`, `MediaLibraryPanel.handleDrop`, `DragDropHandler.loadExternalMediaURLs` |
| 완료 | ✅ **F-04 클립 그룹/링크** — GUI 실기기 검증까지 완료(2026-06-11): 연결 선택을 단일클릭+Delete 그룹 전체 삭제로 입증, link 아이콘/메뉴 가드 확인. 부수 수리: File>Open·New·Import 메뉴 스텁 배선, 탭 제스처 이벤트 기반 전환. 스펙 F-04 검증 기록 참조 | `GroupClipsCommand.swift`, `MovieCutMacApp.swift`, `TimelineView` |
| 3 | **텍스트 템플릿/타이틀 프리셋 적용 경로** — Core template의 Inspector/Canvas 적용 확인(스펙 F-12R과 연계) | `Inspector/InspectorBasicSection.swift`, Core text/template 모델 |

M1 종료 시 §1.1의 W1 워크플로우(숏폼 제작) 수동 완주로 마일스톤 판정.

M2 진행 현황: F-07은 2026-06-11 targeted pass로 fade-through-black boundary pixel fixture와 Inspector verification guard가 추가됐다. 이는 targeted transition confidence only이며 export golden/device playback/full-suite/release-ready claim은 금지한다. 다음 F-07 산출물은 deterministic golden export sample(output path + hash). **F-11 캔버스 배경은 구현+테스트+배선 완료(🟡, 실기기/픽스처 잔여 — 스펙 F-11 검증 기록 참조)**. **M3 F-13 자막 편집+SRT import/export도 구현+테스트 완료(🟡, `ad9630e`)** — 세그먼트 수정/분할/병합/삭제 + pending clip 재정렬 재사용 + SRT 라운드트립, W3 실기기 완주 잔여. **F-14 오디오 덕킹(범위 기반)도 구현+테스트 완료(🟡, `3946305`)** — planner/명령/양 엔진 ramp/Inspector UI, 청감 확인 잔여. **F-15 비트 감지도 구현+합성 트랙 검증 완료(🟡)** — provider/마커 kind/배치 명령/틱 렌더/Quick Tools, 실음원 확인 잔여. **F-17 TTS(M3 마감), F-18 자동컷 preview/파라미터/단일undo 모두 구현+테스트 완료(🟡)**. 다음 후보: F-19 씬감지/리프레임 E2E, F-20 자동 하이라이트, F-09 외부 LUT, F-10 크로마키 스포이드, F-08 배경제거 E2E.

참고: `swift test` 전체 실행은 이 호스트에서 미디어/Speech 통합 테스트로 10분+ 걸리거나 권한 프롬프트에 막힐 수 있음 — 필터 스위트 사용이 관례.
| 완료 | ✅ **F-06 임포트 메타데이터** — Mac import path가 `MediaImporter.probe`의 `fileSize`를 유지한 뒤 AVFoundation/ImageIO best-effort probe로 video/audio duration, video resolution/fps/codec, audio sample rate/channel count/codec, image dimensions를 채운다. Media Library row/accessibility value가 compact metadata summary를 표시한다. Caveat: exact codec labels depend on AVFoundation format descriptions; GUI visual verification not included. | `App/MovieCutMac/EditorViewModel.swift`, `App/MovieCutMac/MediaLibraryPanel.swift`, `Tests/MovieCutCoreTests/F06ImportMetadataStaticContractTests.swift` |
| 완료 | ✅ **F-05 키보드 단축키 맵** — `MovieCutMacApp.commands`가 F-05 menu/shortcut registration을 단일 소유하고, `EditorViewModel`이 Q/W trim-to-playhead, Shift+Delete ripple, Cmd+D duplicate, one-second seek, clip-boundary jump, zoom actions를 제공한다. Help 목록 포함. Caveat: GUI 실동작 및 text-field regression은 static contract 밖의 host verification. | `App/MovieCutMac/MovieCutMacApp.swift`, `App/MovieCutMac/EditorViewModel.swift`, `App/MovieCutMac/ContentView.swift`, `Tests/MovieCutCoreTests/KeyboardShortcutStaticContractTests.swift` |
| 완료 | ✅ **마그네틱 타임라인 / 클립별 zIndex** — Add/Move/Duplicate/Delete command path가 track snapshot undo와 same-track magnetic packing을 제공하고, persisted `Clip.zIndex`가 TimelineView display ordering/layer actions 및 Bring to Front / Send to Back에 연결된다. Caveat: 클립 그룹/링크는 P2 별도 항목. | `Sources/MovieCutCore/Commands/CommandSupport.swift`, `Sources/MovieCutCore/Models/Clip.swift`, `App/MovieCutMac/TimelineView.swift`, `Tests/MovieCutCoreTests/MagneticTimelineZIndexStaticContractTests.swift` |
| 완료 | ✅ **페이드 duration 편집 UI** — Mac Inspector `Fade Duration` 그룹이 Fade In/Fade Out 현재값, Slider, Seconds `TextField`, 0.05s Stepper, Reset Fades/None/Soft/Long preset을 제공한다. 모든 변경은 `updateSelectedAudioFade` → `AudioFadeCommand` path로 적용된다. | `App/MovieCutMac/Inspector/InspectorBasicSection.swift`, `Tests/MovieCutCoreTests/AudioFadeInspectorStaticContractTests.swift` |
| 완료 | ✅ **보이스오버 실녹음** — Mac 앱 microphone usage string, macOS 권한 요청, real `VoiceoverRecorder` CAF capture, saving/progress/accessibility state, on-disappear cancel, duration fallback handoff, and timeline insertion duration resolution are wired. Caveat: actual capture requires macOS Microphone permission and real input hardware host verification. | `App/MovieCutMac/Recording/VoiceoverRecordingView.swift`, `App/MovieCutMac/EditorViewModel.swift`, `App/MovieCutMac/Info.plist` |
| 완료 | ✅ **텍스트 스타일 편집 UI** — 일반 텍스트 클립 Inspector가 본문/font/size/alignment/foreground/background/none/presets를 `updateSelectedTextContent` command path로 갱신한다. Sticker clip metadata path는 그대로 유지한다. Caveat: 고급 title template library는 별도 후속. | `App/MovieCutMac/Inspector/InspectorBasicSection.swift`, `Tests/MovieCutCoreTests/TextStyleInspectorStaticContractTests.swift` |
| 완료 | ✅ **speed ramp preview 반영** — Mac preview가 video, video-embedded audio, standalone audio track 모두에서 `SpeedRampCurve` segment 삽입과 `scaleTimeRange`를 사용한다. ExportEngine의 기존 speed ramp export 경로와 backlog 완료 문구도 static contract로 잠근다. Caveat: 실제 GUI/manual playback 검증은 이번 범위가 아니며, optical-flow slow motion은 별도 P3 항목이다. | `App/MovieCutMac/Playback/PlaybackEngine.swift`, `App/MovieCutMac/Export/ExportEngine.swift`, `Tests/MovieCutCoreTests/SpeedRampPreviewStaticContractTests.swift` |
| 완료 | ✅ **썸네일/프록시 생성** — Mac import path가 video/image asset에 `ThumbnailGenerator` PNG 썸네일을 non-fatal로 채우고, Media Library/Timeline이 `thumbnailData`를 실제 이미지로 렌더한다. video asset은 `ProxyGenerator.makeProxyPlan` + AVFoundation best-effort export로 실제 proxy file이 존재할 때만 `ProxyInfo(proxyURL:)`를 저장한다. Media Library row/context action에서 Generate Proxy를 실행하고 Proxy ready/No proxy 및 thumbnail 상태를 접근성 value에 노출한다. Caveat: source가 AVAssetExportSession mp4 proxy export를 지원하지 않으면 asset.proxy는 nil로 유지된다. | `Sources/MovieCutCore/Media/ThumbnailGenerator.swift`, `App/MovieCutMac/EditorViewModel.swift`, `App/MovieCutMac/MediaLibraryPanel.swift`, `App/MovieCutMac/TimelineView.swift` |
| 완료 | ✅ **전환효과 two-source compositor 통합** — Mac preview/export가 `requiresTwoSourcePixelProcessing` 전환(wipeLeft/Up/Down, slide, zoom, glitch)에 대해 outgoing/incoming track metadata를 `CustomVideoCompositor`로 넘기고 `TransitionPixelProcessor.apply(type:from:to:progress:)`로 합성한다. 인접 비디오 클립은 전환 overlap에서 별도 composition track을 쓰도록 배선했다. Caveat: SwiftPM/static contract 검증 기준이며, 실제 exported visual fixture 검증은 아직 필요하다. | `Sources/MovieCutCore/Rendering/TransitionPixelProcessor.swift`, `App/MovieCutMac/Export/CustomVideoCompositor.swift`, `App/MovieCutMac/Export/ExportEngine.swift`, `App/MovieCutMac/Playback/PlaybackEngine.swift` |

P2 이후(배경제거 실DSP, EQ/덕킹, 비트감지, AI 어시스턴트, 클라우드 등)는 백로그 §3 H~J 참고.

## 4. 작업 규칙 (이 프로젝트에서 합의된 것)

- **DoD(완료 기준)**: "코드 존재"가 아니라 **"preview에서 보이고 export 결과물에도 반영됨"**. 갭 분석 V6의 자가보고 수치는 신뢰하지 말 것.
- **공유 픽셀 프로세서 패턴**: 시각 효과는 `Sources/MovieCutCore/Rendering/`의 shared processor로 구현하고, Mac/iOS `CustomVideoCompositor`가 위임. 신규 효과도 같은 패턴 유지.
- **명령 기반 편집**: 모든 편집은 `EditorSession.dispatch(Command)` 경유 (undo/redo 호환). ViewModel에서 직접 모델 변형 금지.
- **iOS 동기화**: Mac에서 compositor/모델 변경 시 `App/MovieCutiOS/`의 대응 파일도 함께 갱신 (IOSCustomVideoCompositor 등).
- **테스트**: 픽셀 테스트는 sandbox에서 `CIContext`가 transparent black을 반환하는 환경이 있어 guarded 패턴 사용 (기존 `*PixelProcessorTests.swift` 참고). 배선 검증은 static-contract 테스트 패턴.
- 백로그 문서(`CAPCUT_FEATURE_BACKLOG.md`)는 배치 완료 시마다 해당 항목에 ✅/caveat을 갱신하는 관례.

## 5. 빌드/테스트 명령

```bash
# Core 빌드/테스트
swift build
swift test --filter 'Rendering|PixelProcessor|StaticContract'
swift test --filter 'ExportFormatStaticContract|IOSMaskCanvasStaticContract|MacMaskCanvasStaticContract'

# macOS 앱
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build

# sandbox 환경에서 xcodebuild가 막히면
swift build --disable-sandbox
```

## 6. 핵심 파일 맵

| 영역 | 파일 |
|---|---|
| 타임라인/드롭 | `App/MovieCutMac/TimelineView.swift` (DropDelegate :679) |
| 라이브러리/드래그 | `App/MovieCutMac/MediaLibraryPanel.swift` (drag provider :217) |
| 임포트/클립 생성 | `App/MovieCutMac/EditorViewModel.swift` (`importMediaAndAddToTimeline` :591, `insertMediaAssetOnTimeline` :2615) |
| 공유 렌더 프로세서 | `Sources/MovieCutCore/Rendering/` (Color/VisualEffect/ChromaKey/Mask/TextOverlay/Transition) |
| Mac compositor | `App/MovieCutMac/Export/CustomVideoCompositor.swift`, `ExportEngine.swift` |
| Mac preview | `App/MovieCutMac/Playback/PlaybackEngine.swift`, `PreviewPanel.swift` |
| Mac export/accessibility | `App/MovieCutMac/ContentView.swift`, `App/MovieCutMac/Inspector/InspectorExportSection.swift` |
| Mask Canvas | `App/MovieCutMac/Effects/MaskCanvasView.swift`, `App/MovieCutiOS/Views/IOSMaskCanvasView.swift` |
| iOS compositor/export | `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`, `IOSExportEngine.swift`, `App/MovieCutiOS/iOSContentView.swift` |
| STT | `App/MovieCutMac/Transcription/TranscriptionService.swift`, `Sources/MovieCutCore/Transcription/` |
| 테스트 | `Tests/MovieCutCoreTests/` (`*PixelProcessorTests`, `*StaticContractTests`) |
