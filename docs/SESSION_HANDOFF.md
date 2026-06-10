# 세션 핸드오프 — 다음 개발 세션 시작 가이드

> 작성일: 2026-06-10 / 브랜치: `main` / 기준 기능 커밋: `4e982b0` (voiceover recording workflow)
> 이 문서만 읽고 바로 작업을 시작할 수 있도록 작성됨. 기능 백로그 전체는 `docs/CAPCUT_FEATURE_BACKLOG.md`, **개발 명세서(F-ID별 요구사항/구현 방안/수용 기준/마일스톤/DoD)는 `docs/CAPCUT_PARITY_SPEC.md`** 참고. 신규 기능 작업은 명세서의 F-ID 단위로 진행.

---

## 1. 현재 상태 요약

- CapCut 파리티 작업은 Batch 17 이후 P1 transition pass, export/마스크 접근성 및 custom bitrate clamp, 실기기 드래그앤드롭 수정, 썸네일/프록시 생성, speed ramp preview contract, 텍스트 스타일 편집 UI, 보이스오버 실녹음 배치까지 진행됨.
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

- **비파일 드래그 소스 미지원**: Photos 앱/브라우저 이미지는 file promise/image data 형태라 현재 안 받음. `NSFilePromiseReceiver` 또는 `.image`/`.movie` 데이터 수용 필요.
- UI 자동화 테스트 없음 — 이번 검증은 수동 GUI 드래그 기준. XCUITest 기반 자동화는 후속.

### 2-4. 최근 접근성/비트레이트 배치 후속 확인

`45cda56`은 static contract 수준 검증까지 완료. 후속으로 실제 VoiceOver/키보드 접근성 확인 권장:

1. Mac Export toolbar 버튼이 선택된 container/codec/resolution/frame rate/quality를 읽는지 확인.
2. custom bitrate 입력에 0, 75, 250 Mbps를 넣었을 때 `resolvedVideoBitrateMbps`가 nil/75/200으로 동작하는지 테스트는 이미 있음. 실제 Inspector 입력은 Stepper 범위 1...200.
3. Mac/iOS Mask Canvas에서 VoiceOver custom actions로 width/height 1% resize가 가능한지 수동 확인.
4. iOS mask rotation 액션과 brush point rotation 보정은 static contract만 있음. 실제 터치/VoiceOver는 후속 실기기 확인 필요.

## 3. 다음 개발 큐 (P1, 우선순위순)

백로그 §3 기준 미완료 P1 항목. 전환효과 two-source compositor 통합, 썸네일/프록시 생성, speed ramp preview static contract 검증, 텍스트 스타일 편집 UI, 보이스오버 실녹음은 완료됐으므로 다음 우선순위는 페이드 duration 편집 UI:

| # | 작업 | 시작점 |
|---|---|---|
| 1 | **페이드 duration 편집 UI** — `fadeInDuration`/`fadeOutDuration` Inspector 슬라이더 (적용 경로는 이미 동작) | `Inspector/InspectorBasicSection.swift` |
| 2 | **마그네틱 타임라인 / 클립별 zIndex** — 구조 변경 수반, 단독 배치로 진행 권장 | `TimelineView.swift`, Core `Track`/`Clip` 모델 |
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
