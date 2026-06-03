# MovieCut vs CapCut 갭 분석 V3 Part 1

## 분석 범위

요청에 따라 아래 10개 파일만 읽고 코드 레벨로 확인했다.

- `App/MovieCutMac/Export/ExportEngine.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`
- `App/MovieCutMac/EditorViewModel.swift`
- `App/MovieCutMac/InspectorPanel.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/ContentView.swift`
- `App/MovieCutMac/Effects/MaskCompositor.swift`
- `App/MovieCutMac/Effects/TextAnimationRenderer.swift`
- `App/MovieCutMac/Export/ReverseRenderService.swift`
- `App/MovieCutMac/Export/ChromaKeyCompositor.swift`

판정 기준:

- ✅ 완료: 지정 파일 범위 안에서 UI/상태/실행 또는 렌더/내보내기 경로까지 확인됨
- 🟡 부분: UI, 상태 저장, 명령 호출, 렌더러 조각 중 일부만 확인되거나 최종 preview/export 연결이 불완전함
- ❌ 미구현: 지정 파일 범위에서 관련 UI/상태/처리 경로를 확인할 수 없음

핵심 요약:

- MovieCut은 기본 프로젝트/미디어 추가, 클립 선택, 줌, split/delete/undo/redo 진입점, 볼륨, 기본 속도, 캔버스 기반 export, export 진행률은 갖추고 있다.
- CapCut 대비 가장 큰 격차는 타임라인 직접 조작과 합성 파이프라인이다. TimelineView는 표시/선택/줌 중심이고 trim/move/ripple/snap/drag/drop/multi-select는 보이지 않는다.
- Inspector에는 전환, 효과, 색보정, 마스크, 크로마키, 키프레임, 텍스트, 자동자막 UI 또는 상태 연결이 많지만 PlaybackEngine/ExportEngine에서 상당수가 실제 렌더링되지 않는다.
- 텍스트 트랙은 PlaybackEngine에서 `case .text: continue`, ExportEngine에서 `.text -> nil`로 제외된다. 따라서 텍스트 오버레이/자막/자동자막은 생성되어도 preview/export 결과물에 반영되는 경로가 지정 파일 안에서는 없다.
- ExportEngine의 `makeCustomVideoCompositorInstruction`는 placeholder 후 `nil`을 반환한다. MaskCompositor, TextAnimationRenderer, ChromaKeyCompositor가 있어도 실제 export 합성에 연결된 코드는 지정 파일 범위에서 확인되지 않는다.

## 1. 타임라인

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 1 | 타임라인 표시 | ✅ 완료 | `TimelineView.swift:35-43`, `TimelineView.swift:94-130` | 트랙/클립 lane과 playhead를 SwiftUI로 렌더링한다. |
| 2 | 클립 선택 | ✅ 완료 | `TimelineView.swift:151-153`, `EditorViewModel.swift:53-58` | 탭으로 단일 `selectedClipId`를 갱신한다. |
| 3 | 미디어를 타임라인에 추가 | 🟡 부분 | `EditorViewModel.swift:176-196` | 선택 asset을 트랙에 추가하는 경로는 있다. 실제 미디어 브라우저 UI는 `ContentView.swift:12`의 외부 뷰라 범위 밖이다. |
| 4 | 텍스트 클립 추가 | 🟡 부분 | `EditorViewModel.swift:231-250` | 텍스트 클립 생성은 가능하지만 preview/export 렌더는 별도 항목처럼 미연결이다. |
| 5 | 자르기/trim | ❌ 미구현 | 지정 파일 내 없음 | clip edge 조절, sourceRange 변경 UI, trim command 호출이 확인되지 않는다. |
| 6 | 분할/split | 🟡 부분 | `EditorViewModel.swift:256-270`, `ContentView.swift:45-48` | `SplitClipCommand` dispatch와 Cmd+B UI는 있다. command 구현은 지정 파일 밖이라 실제 분할 mutation은 여기서 검증 불가다. |
| 7 | 이동/move | ❌ 미구현 | 지정 파일 내 없음 | 클립 위치 이동 함수, drag gesture, move command 호출이 없다. |
| 8 | 복사/duplicate | ❌ 미구현 | 지정 파일 내 없음 | copy/paste/duplicate 명령 또는 UI가 없다. |
| 9 | 삭제/delete | 🟡 부분 | `EditorViewModel.swift:273-283`, `ContentView.swift:50-53`, `ContentView.swift:125-133` | delete command dispatch와 단축키는 있다. command 구현은 지정 파일 밖이다. |
| 10 | ripple edit | ❌ 미구현 | 지정 파일 내 없음 | 삭제/trim 이후 뒤 클립을 당기는 ripple 로직이나 옵션이 없다. |
| 11 | 스냅/snap | ❌ 미구현 | 지정 파일 내 없음 | playhead/clip edge/인접 clip 기준 snapping 로직이 없다. |
| 12 | 줌 | ✅ 완료 | `EditorViewModel.swift:21`, `TimelineView.swift:10-12`, `TimelineView.swift:20-26` | `timelineZoom`을 20...300 범위에서 증감한다. |
| 13 | 드래그앤드롭 | ❌ 미구현 | 지정 파일 내 없음 | TimelineView에 `.onDrop`, `.dropDestination`, `.draggable`, drag gesture가 없다. |
| 14 | 다중 선택 | ❌ 미구현 | `EditorViewModel.swift:11`, `TimelineView.swift:151-153` | 선택 상태가 단일 UUID라 multi-select 구조가 없다. |
| 15 | Undo | 🟡 부분 | `EditorViewModel.swift:285-292`, `ContentView.swift:33-36` | `session.undo()`와 Cmd+Z UI는 있다. undo stack 구현은 지정 파일 밖이다. |
| 16 | Redo | 🟡 부분 | `EditorViewModel.swift:294-301`, `ContentView.swift:38-41` | `session.redo()`와 Cmd+Shift+Z UI는 있다. |
| 17 | 프레임 단위 이동 | ✅ 완료 | `EditorViewModel.swift:307-319`, `ContentView.swift:135-143` | 좌/우 화살표로 1/30초 기준 seek한다. 프로젝트 frameRate가 아닌 고정 30fps다. |
| 18 | 트랙 mute/lock 표시 | 🟡 부분 | `TimelineView.swift:101-106` | 아이콘 표시만 있고 토글 UI/command는 없다. |

## 2. 비디오 효과

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 19 | Transform 적용 | 🟡 부분 | `PlaybackEngine.swift:169-193`, `PlaybackEngine.swift:274-285`, `PlaybackEngine.swift:383-387`, `ExportEngine.swift:215-220` | playback/export layer transform 적용 경로는 있다. Inspector는 값 표시만 있고 편집 컨트롤은 보이지 않는다. |
| 20 | Opacity 적용 | ✅ 완료 | `InspectorPanel.swift:43-60`, `PlaybackEngine.swift:389-399`, `ExportEngine.swift:223-231` | Inspector slider, preview, export layer opacity ramp가 연결되어 있다. |
| 21 | 기본 속도 조절 | ✅ 완료 | `InspectorPanel.swift:83-111`, `EditorViewModel.swift:336-340`, `PlaybackEngine.swift:162-167`, `PlaybackEngine.swift:266-272`, `ExportEngine.swift:141-147` | 0.25x...4x slider/preset, playback/export `scaleTimeRange` 경로가 있다. |
| 22 | Speed ramp | 🟡 부분 | `EditorViewModel.swift:342-345`, `ExportEngine.swift:128-139` | speedRampPoints 저장/ExportEngine 호출은 있으나 지정 파일 내 UI와 `applySpeedRamp` 구현은 확인되지 않는다. PlaybackEngine은 speed ramp를 반영하지 않는다. |
| 23 | 역재생 | 🟡 부분 | `InspectorPanel.swift:407-424`, `EditorViewModel.swift:381-384`, `ExportEngine.swift:107-126`, `ReverseRenderService.swift:3-150` | export용 비디오 역렌더는 실제 구현되어 있다. PlaybackEngine은 `isReversed`를 사용하지 않고, 오디오 역재생도 없다. |
| 24 | 정지프레임 | 🟡 부분 | `InspectorPanel.swift:420-424`, `EditorViewModel.swift:386-396` | `FreezeFrameCommand` 호출만 있다. 실제 frame freeze 생성/렌더 구현은 지정 파일 밖이다. |
| 25 | 필터/효과 추가 | 🟡 부분 | `InspectorPanel.swift:145-209`, `InspectorPanel.swift:491-550`, `EditorViewModel.swift:398-400`, `ExportEngine.swift:158-159`, `ExportEngine.swift:233-258` | UI와 effect parameters는 있으나 custom compositor가 `nil`이라 export 적용이 확인되지 않는다. PlaybackEngine도 effects를 적용하지 않는다. |
| 26 | 색보정 | 🟡 부분 | `InspectorPanel.swift:306-357`, `EditorViewModel.swift:371-374`, `ExportEngine.swift:158`, `ExportEngine.swift:233-258` | brightness/contrast/saturation/warmth/tint UI와 metadata는 있다. 실제 CI filter 연결은 placeholder다. |
| 27 | 전환 | 🟡 부분 | `InspectorPanel.swift:246-276`, `InspectorPanel.swift:512-529`, `EditorViewModel.swift:356-359` | transition type/duration 저장 UI는 있다. PlaybackEngine/ExportEngine에서 transition을 사용하는 경로는 보이지 않는다. |
| 28 | 크로마키 | 🟡 부분 | `InspectorPanel.swift:138-142`, `EditorViewModel.swift:366-369`, `ChromaKeyCompositor.swift:5-60` | CIColorCube 기반 compositor는 있다. ExportEngine/PlaybackEngine에서 `ChromaKeyCompositor` 또는 `customVideoCompositorClass` 연결은 확인되지 않는다. |
| 29 | 마스킹 | 🟡 부분 | `InspectorPanel.swift:359-405`, `EditorViewModel.swift:376-379`, `MaskCompositor.swift:6-237`, `ExportEngine.swift:157`, `ExportEngine.swift:233-258` | rectangle/ellipse/triangle/diamond/linear/brush mask renderer는 있다. export custom compositor가 `nil`이라 최종 적용은 미연결이다. |
| 30 | 배경제거 | ❌ 미구현 | 지정 파일 내 없음 | 사람/객체 segmentation, matte 생성, background removal UI/API가 없다. |
| 31 | Blur/Sepia/Grayscale 등 스타일 효과 | 🟡 부분 | `InspectorPanel.swift:532-550`, `EditorViewModel.swift:398-400` | effect 목록은 있지만 preview/export 적용 경로가 없다. |
| 32 | 이미지/스티커 오버레이 | 🟡 부분 | `EditorViewModel.swift:443-470` | sticker를 이미지 asset으로 만들어 video track에 추가한다. 레이어 합성은 AVComposition track 기반이나 세부 transform UI는 제한적이다. |

## 3. 오디오

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 33 | 볼륨 조절 | ✅ 완료 | `InspectorPanel.swift:62-81`, `EditorViewModel.swift:331-334`, `PlaybackEngine.swift:304-305`, `PlaybackEngine.swift:345-346`, `ExportEngine.swift:163-165` | clip volume slider와 AVAudioMix `setVolume` 경로가 preview/export에 있다. |
| 34 | 오디오 track export/playback | ✅ 완료 | `PlaybackEngine.swift:288-310`, `PlaybackEngine.swift:311-348`, `ExportEngine.swift:58-70`, `ExportEngine.swift:168-179` | video 내장 오디오와 audio track을 composition/audioMix에 넣는다. |
| 35 | 오디오 페이드 | ❌ 미구현 | 지정 파일 내 없음 | `setVolumeRamp` 또는 fade-in/out audio property가 없다. |
| 36 | 오디오 덕킹 | ❌ 미구현 | 지정 파일 내 없음 | voice/BGM ducking 분석 또는 volume automation이 없다. |
| 37 | EQ | ❌ 미구현 | 지정 파일 내 없음 | EQ filter/AVAudioUnit/UI가 없다. |
| 38 | 노이즈 감소 | ❌ 미구현 | 지정 파일 내 없음 | noise reduction filter/API/UI가 없다. |
| 39 | BGM 추가 | 🟡 부분 | `EditorViewModel.swift:15`, `EditorViewModel.swift:32`, `EditorViewModel.swift:202-229` | placeholder music library와 audio clip 추가 경로는 있다. 실제 라이브러리 UI/검색/라이선스/비트 매칭은 범위 밖 또는 없음. |
| 40 | 보이스오버 추가 | 🟡 부분 | `EditorViewModel.swift:677-698` | 외부 URL을 audio clip으로 추가한다. 녹음 UI, waveform, countdown, retake 기능은 보이지 않는다. |
| 41 | 오디오 추출 | ❌ 미구현 | 지정 파일 내 없음 | video에서 audio asset을 별도 추출하는 기능이 없다. |
| 42 | 오디오 파형 | ❌ 미구현 | `TimelineView.swift:139-149` | Timeline clip은 단색 block과 label만 표시한다. waveform rendering이 없다. |

## 4. 텍스트/자막

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 43 | 텍스트 오버레이 생성 | 🟡 부분 | `EditorViewModel.swift:231-250`, `InspectorPanel.swift:120-136`, `TimelineView.swift:164-168` | text clip 생성/수정/타임라인 label은 있다. PlaybackEngine과 ExportEngine은 text track을 제외한다. |
| 44 | 텍스트 preview | ❌ 미구현 | `PlaybackEngine.swift:349-350` | text track은 composition build에서 `continue` 처리된다. |
| 45 | 텍스트 export | ❌ 미구현 | `ExportEngine.swift:269-277` | `.text` track은 export media type이 `nil`이라 composition에 들어가지 않는다. |
| 46 | 텍스트 애니메이션 렌더러 | 🟡 부분 | `TextAnimationRenderer.swift:7-150`, `ExportEngine.swift:249-258` | fade/typewriter/bounce/slide/scale 렌더 함수는 있다. 호출부가 지정 파일 안에서 확인되지 않고 export placeholder가 nil이다. |
| 47 | 자막 자동 생성 | 🟡 부분 | `EditorViewModel.swift:403-441`, `InspectorPanel.swift:211-218` | TranscriptionService로 subtitle clip을 만들고 text track에 추가하는 흐름은 있다. 생성된 text clip이 preview/export되지 않는 것이 치명적이다. |
| 48 | 자막 템플릿/스타일 | 🟡 부분 | `EditorViewModel.swift:17`, `EditorViewModel.swift:37-39`, `EditorViewModel.swift:700-717`, `ContentView.swift:66-87` | built-in template store와 template picker 진입점은 있다. 템플릿 상세/마켓/텍스트 스타일 렌더는 범위 밖 또는 미연결이다. |
| 49 | 캡션 편집 UX | 🟡 부분 | `InspectorPanel.swift:126-134`, `EditorViewModel.swift:421-441` | 단일 text field 수정과 generated subtitle apply는 있다. CapCut 수준의 batch caption editor, timing adjust, style preset은 보이지 않는다. |

## 5. 내보내기

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 50 | Export 실행 | ✅ 완료 | `EditorViewModel.swift:144-160`, `ExportEngine.swift:16-50`, `ContentView.swift:72-75` | Save panel 후 AVAssetExportSession으로 mp4/mov 출력한다. |
| 51 | Export preset/codec/resolution | ✅ 완료 | `ExportEngine.swift:27-33`, `ExportEngine.swift:280-295` | h264/hevc와 720/1080/4K preset mapping이 있다. |
| 52 | Output file type | ✅ 완료 | `ExportEngine.swift:41-42`, `ExportEngine.swift:297-321` | 확장자와 codec 기반으로 mp4/mov/m4v를 선택한다. |
| 53 | Export 진행률 | ✅ 완료 | `ExportEngine.swift:323-341`, `ContentView.swift:151-170` | export session progress polling과 progress sheet가 있다. |
| 54 | Canvas size/frameRate 적용 | ✅ 완료 | `ContentView.swift:57-64`, `EditorViewModel.swift:352-354`, `ExportEngine.swift:196-198` | project canvas를 videoComposition renderSize/frameDuration에 반영한다. |
| 55 | 캔버스 비율 프리셋 UI | 🟡 부분 | `ContentView.swift:57-64` | CanvasSettingsView popover는 호출된다. 실제 비율 프리셋 UI 정의는 지정 파일 밖이라 검증 불가다. |
| 56 | Export cancel | ❌ 미구현 | `ContentView.swift:151-170`, `ExportEngine.swift:323-341` | progress sheet에 취소 버튼이 없고 active session cancel API 호출도 없다. |
| 57 | 공유/share | ❌ 미구현 | 지정 파일 내 없음 | SNS/share sheet/upload workflow가 없다. |
| 58 | Export에서 효과 합성 | 🟡 부분 | `ExportEngine.swift:149-160`, `ExportEngine.swift:233-258` | metadata는 모으지만 animationTool/custom compositor가 nil이라 CapCut식 최종 합성이 빠져 있다. |
| 59 | Export에서 텍스트/자막 포함 | ❌ 미구현 | `ExportEngine.swift:269-277` | text track 자체가 export 대상에서 제외된다. |

## 6. AI

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 60 | 자동컷/분석 | 🟡 부분 | `EditorViewModel.swift:617-675` | SilenceDetectionProvider, SceneChangeProvider, AutoCutEngine 적용 경로는 있다. CapCut식 종합 AI 편집, beat sync, highlight 생성까지는 확인되지 않는다. |
| 61 | 자동자막 | 🟡 부분 | `EditorViewModel.swift:403-441` | transcription 기반 subtitle 생성은 있다. 최종 텍스트 렌더/export 미연결 때문에 사용자 결과물 기준으로는 부분 구현이다. |
| 62 | AI 리프레임 | ❌ 미구현 | 지정 파일 내 없음 | 피사체 추적, aspect ratio별 auto reframe, crop keyframe 생성 기능이 없다. |
| 63 | AI 어시스턴트 | ❌ 미구현 | 지정 파일 내 없음 | 자연어 편집 assistant, prompt command, chat UI가 없다. |
| 64 | AI 배경제거 | ❌ 미구현 | 지정 파일 내 없음 | segmentation 기반 background removal이 없다. |

## 7. 클라우드/협업

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 65 | 프로젝트 저장/열기 | ✅ 완료 | `EditorViewModel.swift:104-142`, `ContentView.swift:120-123` | local `.moviecut` 저장/열기 경로가 있다. |
| 66 | 클라우드 동기화 | ❌ 미구현 | 지정 파일 내 없음 | 계정, remote project store, sync conflict 처리 없음. |
| 67 | 협업 편집 | ❌ 미구현 | 지정 파일 내 없음 | presence, comments, realtime merge, shared timeline 없음. |
| 68 | 버전 히스토리 | ❌ 미구현 | 지정 파일 내 없음 | local undo 외 프로젝트 version history/snapshot browser 없음. |
| 69 | 마켓플레이스 | ❌ 미구현 | 지정 파일 내 없음 | template/effect/music marketplace, download/install flow 없음. |

## 8. UI/UX

| # | 기능 | 상태 | 위치 | 비고 |
|---|------|------|------|------|
| 70 | 편집 화면 레이아웃 | ✅ 완료 | `ContentView.swift:10-30` | Media library, preview, inspector, timeline의 3-pane+timeline 구조가 있다. |
| 71 | Inspector | 🟡 부분 | `InspectorPanel.swift:20-279` | 많은 속성 UI가 있으나 transform은 표시만 하고, 효과/전환/키프레임은 최종 렌더 연결이 약하다. |
| 72 | 단축키 | ✅ 완료 | `ContentView.swift:33-75`, `ContentView.swift:113-148` | undo/redo/split/delete/export/play/save/frame step 단축키가 있다. |
| 73 | Preview | 🟡 부분 | `PlaybackEngine.swift:43-66`, `PlaybackEngine.swift:149-415`, `ContentView.swift:15-16` | AVPlayerItem composition preview는 있다. text/effects/mask/chroma/reverse/speed ramp/keyframes는 preview에 반영되지 않는다. |
| 74 | 미디어 브라우저 | 🟡 부분 | `ContentView.swift:12`, `EditorViewModel.swift:42-50`, `EditorViewModel.swift:163-174` | MediaLibraryPanel 호출과 importMedia는 있다. 브라우저 상세 UI는 지정 파일 밖이다. |
| 75 | 키프레임 UI | 🟡 부분 | `InspectorPanel.swift:221-244`, `EditorViewModel.swift:347-350` | editor/list view와 keyframe 저장 호출은 있다. PlaybackEngine/ExportEngine에서 keyframes 적용이 보이지 않는다. |
| 76 | macOS 앱 | ✅ 완료 | `ContentView.swift:30`, `EditorViewModel.swift:1`, `EditorViewModel.swift:132-149` | AppKit `NSSavePanel`, macOS min window size 기준의 SwiftUI 앱이다. |
| 77 | iOS 대응 | ❌ 미구현 | 지정 파일 내 없음 | iOS view/navigation/import/export 분기 없음. |
| 78 | 오류 표시 | ✅ 완료 | `EditorViewModel.swift:22`, `ContentView.swift:95-99`, `ContentView.swift:163-166` | status bar와 export sheet에서 error message를 보여준다. |

## 파일별 코드 레벨 관찰

- `ExportEngine.swift`: AVAssetExportSession 기반 export는 존재한다. 비디오/오디오 track composition, volume mix, speed, reverse export 일부는 구현되어 있다. 그러나 `.text`는 `mediaType(for:)`에서 nil이고, custom compositor instruction은 placeholder 후 nil이다.
- `PlaybackEngine.swift`: AVMutableComposition preview, transform/opacity/basic speed/audio volume은 있다. text track은 `continue`이고 effects/mask/chroma/reverse/keyframes는 사용하지 않는다.
- `EditorViewModel.swift`: 기능 진입점은 많다. split/delete/undo/redo, text, subtitle, BGM, voiceover, AI analysis, template, chroma/mask/effects/keyframes property update가 있다. 다만 많은 기능은 command 구현 또는 renderer 연결이 지정 파일 밖이다.
- `InspectorPanel.swift`: CapCut과 유사한 속성 패널 방향성은 있다. 하지만 UI에서 저장한 transition/effect/color/mask/keyframe이 playback/export에 반영되는 경로가 부족하다.
- `TimelineView.swift`: timeline의 시각화와 선택/줌까지만 구현되어 있다. CapCut의 핵심 조작인 trim/move/ripple/snap/DnD/multi-select가 없다.
- `ContentView.swift`: 기본 편집 레이아웃, toolbar, 단축키, export progress sheet가 있다. 공유, export cancel, 고급 workspace UX는 없다.
- `MaskCompositor.swift`: CI 기반 mask renderer 자체는 비교적 구체적이다. 문제는 호출 연결이다.
- `TextAnimationRenderer.swift`: 텍스트 애니메이션 bitmap/CIImage 렌더 조각은 있다. 문제는 text track preview/export 연결이다.
- `ReverseRenderService.swift`: video sample을 읽어서 역순으로 retime/write하는 실제 구현이 있다. 메모리에 sample buffer를 모두 쌓는 구조라 긴 영상에서 위험이 있다.
- `ChromaKeyCompositor.swift`: CIColorCube 기반 chroma key 구현은 있다. ExportEngine/PlaybackEngine에 custom compositor로 등록되는 코드는 지정 파일 안에서 보이지 않는다.

## 우선순위 분류

### Critical

| 항목 | 이유 | 근거 |
|---|---|---|
| 텍스트/자막이 preview/export에서 제외됨 | 자동자막과 텍스트 오버레이가 있어도 결과 영상에 안 나오면 CapCut 대비 핵심 워크플로가 깨진다. | `PlaybackEngine.swift:349-350`, `ExportEngine.swift:269-277` |
| 효과/색보정/마스크/크로마키/텍스트 애니메이션 합성 미연결 | Inspector와 renderer 조각은 있으나 최종 합성이 nil이라 사용자가 적용 결과를 얻기 어렵다. | `ExportEngine.swift:233-258`, `ChromaKeyCompositor.swift:5-60`, `MaskCompositor.swift:6-237`, `TextAnimationRenderer.swift:7-150` |
| 타임라인 직접 편집 부재 | CapCut의 기본 사용성인 trim/move/ripple/snap/DnD/multi-select가 없다. | `TimelineView.swift:118-153`, `EditorViewModel.swift:11` |

### High

| 항목 | 이유 | 근거 |
|---|---|---|
| 전환은 저장 UI만 있고 playback/export 적용이 없음 | CapCut 대비 기본 영상 편집 결과 품질에 직접 영향. | `InspectorPanel.swift:246-276`, `EditorViewModel.swift:356-359` |
| 키프레임은 UI/상태만 있고 렌더 적용이 없음 | 애니메이션 편집의 핵심 기능이 결과물에 반영되지 않는다. | `InspectorPanel.swift:221-244`, `EditorViewModel.swift:347-350`, `PlaybackEngine.swift:149-415` |
| 역재생 preview/audio 미지원 | export video reverse만 있고 편집 중 확인과 오디오 처리가 없다. | `ExportEngine.swift:107-126`, `ReverseRenderService.swift:56-126`, `PlaybackEngine.swift:244-305` |
| 오디오 고급 기능 부재 | fade/ducking/EQ/noise reduction/waveform이 없어 CapCut식 오디오 편집과 차이가 크다. | `InspectorPanel.swift:62-81`, `PlaybackEngine.swift:304-345` |

### Medium

| 항목 | 이유 | 근거 |
|---|---|---|
| Speed ramp가 export 중심이고 preview/UI 검증이 부족 | 고급 속도 편집 체감이 낮다. | `EditorViewModel.swift:342-345`, `ExportEngine.swift:128-139`, `PlaybackEngine.swift:162-167` |
| BGM/voiceover가 파일 추가 수준 | 녹음, retake, beat sync, ducking 같은 제작 UX가 없다. | `EditorViewModel.swift:202-229`, `EditorViewModel.swift:677-698` |
| Export cancel/share 부재 | 긴 렌더링 작업과 배포 흐름에서 UX 부족. | `ContentView.swift:151-170`, `ExportEngine.swift:323-341` |
| 자동컷이 silence/scene 기반으로 제한적 | CapCut식 AI highlight, beat, semantic edit와 차이가 크다. | `EditorViewModel.swift:617-675` |

### Low

| 항목 | 이유 | 근거 |
|---|---|---|
| iOS 대응 없음 | 현재 파일은 macOS 앱 구조로 보이며 제품 범위 문제다. | `EditorViewModel.swift:1`, `ContentView.swift:30` |
| 클라우드/협업/마켓플레이스 없음 | 로컬 편집 MVP라면 후순위이나 CapCut 대비 플랫폼 기능 갭이다. | 지정 파일 내 없음 |
| Transform 편집 UI 부족 | transform 적용 경로는 있으나 Inspector에서 값 표시 중심이다. | `InspectorPanel.swift:32-41`, `EditorViewModel.swift:321-324` |

## Core 레이어 검증 결과

요청된 Core 파일 10개를 추가로 확인했다. Part 1의 앱/렌더 파일 범위에서는 미구현으로 보였던 일부 항목이 Core 유틸리티 또는 서비스 형태로 존재한다. 다만 대부분은 앱 UI, playback/export, timeline mutation까지 연결된 완성 워크플로가 아니라 독립 API 또는 로컬 facade 수준이다.

검증 중 `TODO`/`FIXME` 문자열은 발견되지 않았다. 명시적인 `placeholder`는 `WaveformGenerator.swift:21` 1건이고, `simulate` 성격의 주석은 `StyleTransferProvider.swift:7`, `CollaborationService.swift:135`, `CollaborationService.swift:149`, `TemplateMarketplace.swift:145`에서 확인된다.

| 파일 | REAL / MOCK 판정 | 프로덕션 동작 판정 | TODO/FIXME/placeholder |
|---|---|---|---|
| `BackgroundRemovalProvider.swift` | REAL. `VNGeneratePersonSegmentationRequest`와 `CIBlendWithAlphaMask`, `CIContext.render`를 사용한다. | 프레임 단위 배경제거 함수는 Vision 가능 플랫폼에서 실제 동작 가능한 구현이다. 그러나 `analyze(...)`는 빈 `AnalysisResult`만 반환하고, 앱/preview/export에서 `removeBackground(from:)` 호출 경로를 확인하지 못했다. 기능 워크플로 기준으로는 부분 구현이다. | TODO/FIXME 없음. placeholder 없음. 근거: `BackgroundRemovalProvider.swift:27-50`, `BackgroundRemovalProvider.swift:57-108` |
| `StyleTransferProvider.swift` | REAL Core Image 필터 체인. `CIPhotoEffectNoir`, `CIVignette`, `CIColorControls`, `CIEdgeWork` 등을 조합한다. 다만 ML style transfer가 아니라 필터 기반 스타일 시뮬레이션이다. | `CIImage` 입력에 스타일을 적용하는 유틸리티로는 동작 가능하다. 그러나 `analyze(...)`는 빈 결과이고 앱/렌더 파이프라인에서 호출되지 않아 제품 기능으로는 컴파일된 유틸 조각에 가깝다. | TODO/FIXME 없음. `simulate common visual styles` 주석 있음. 근거: `StyleTransferProvider.swift:7`, `StyleTransferProvider.swift:27-60`, `StyleTransferProvider.swift:62-151` |
| `AutoReframeProvider.swift` | REAL. `AVAssetImageGenerator`로 1fps 샘플링하고 Vision face/human rectangle로 crop rect를 계산한다. | crop frame 계산은 실제 구현이다. 하지만 `analyze(...)`는 빈 결과이고, `calculateCropFrames(...)` 호출 경로가 앱에서 확인되지 않는다. `AutoReframeCommand`는 존재하지만 Vision crop frame을 적용하지 않고 클립 transform을 aspect fill로만 조정한다. 따라서 CapCut식 subject-aware auto reframe은 부분 구현이다. | TODO/FIXME 없음. placeholder 없음. 근거: `AutoReframeProvider.swift:41-89`, `AutoReframeProvider.swift:93-147`, `AutoReframeCommand.swift:18-44` |
| `AudioEqualizerService.swift` | REAL. `AVAudioEngine`, `AVAudioUnitEQ`, offline manual rendering을 사용한다. | 직접 호출하면 오디오 파일 EQ 렌더링은 가능한 구조다. realtime 함수도 EQ가 연결된 engine을 반환한다. 그러나 앱 UI, clip 속성, playback/export audio mix로 연결된 참조가 확인되지 않아 제품 기능 기준으로는 부분 구현이다. | TODO/FIXME 없음. placeholder 없음. 근거: `AudioEqualizerService.swift:15-34`, `AudioEqualizerService.swift:36-115`, `AudioEqualizerService.swift:123-149` |
| `CloudSyncService.swift` | REAL file/iCloud facade. `FileManager.url(forUbiquityContainerIdentifier:)`와 `ProjectStore.save/load`를 사용한다. | iCloud Drive가 있으면 `.moviecut` 파일 저장/목록/로드가 가능하고, 없으면 Application Support로 fallback한다. 계정, 원격 API, 실시간 sync, 자동 conflict detection은 없어서 CapCut식 cloud sync로는 부분 구현이다. | TODO/FIXME 없음. placeholder 없음. `local fallback storage` 주석 있음. 근거: `CloudSyncService.swift:40`, `CloudSyncService.swift:65-83`, `CloudSyncService.swift:85-153`, `CloudSyncService.swift:172-194` |
| `CollaborationService.swift` | MOCK/STUB 성격이 강함. 네트워크/서버 없이 로컬 배열에 collaborator, invite, change event를 저장한다. | 로컬 상태 기록과 fetch는 동작하지만 multi-user presence, realtime edit merge, remote invite, 권한 enforcement가 없다. 주석도 join/leave를 simulation으로 명시한다. 실제 협업 편집 기능으로는 프로덕션 동작한다고 보기 어렵다. | TODO/FIXME 없음. simulation 주석 있음. 근거: `CollaborationService.swift:96-107`, `CollaborationService.swift:120-153`, `CollaborationService.swift:156-175` |
| `TemplateMarketplace.swift` | MOCK/STUB 성격의 local marketplace facade. built-in template에서 JSON catalog를 생성하고 로컬 검색/다운로드를 제공한다. | 로컬 catalog search/download는 동작한다. 하지만 remote marketplace API, asset download, 결제/라이선스, 업데이트 채널이 없고 `refreshCatalog()`도 로컬 catalog reload/generate만 수행한다. 제품 marketplace로는 부분 구현이다. | TODO/FIXME 없음. `Simulates refreshing the remote marketplace` 주석 있음. 근거: `TemplateMarketplace.swift:87-123`, `TemplateMarketplace.swift:125-152`, `TemplateMarketplace.swift:173-259` |
| `SpeechTranscriptionProvider.swift` | REAL. Apple `Speech` framework와 `AVAssetExportSession`을 사용한다. | 앱의 `TranscriptionService`에서 기본 provider로 연결되어 있어 자동자막 입력 경로는 실제다. 오디오 파일은 권한과 on-device recognizer가 충족되면 동작 가능하다. 다만 비디오 입력은 `AVAssetExportPresetPassthrough` + `.wav` export가 실제 지원되지 않을 수 있어 안정성이 낮고, 생성된 text clip은 Part 1처럼 preview/export에서 제외된다. | TODO/FIXME 없음. placeholder 없음. 근거: `SpeechTranscriptionProvider.swift:16-23`, `SpeechTranscriptionProvider.swift:31-111`, `SpeechTranscriptionProvider.swift:124-155`, `TranscriptionService.swift:13-18` |
| `ThumbnailGenerator.swift` | REAL. 이미지 파일은 `CIImage(contentsOf:)`, 비디오는 `AVAssetImageGenerator.copyCGImage`로 PNG data를 만든다. | thumbnail 생성 유틸리티 자체는 실제 동작 가능한 구현이다. 다만 지정 검색 범위에서 앱 UI가 `ThumbnailGenerator.generate(...)`를 호출하는 경로는 확인되지 않았다. | TODO/FIXME 없음. placeholder 없음. 근거: `ThumbnailGenerator.swift:8-39`, `ThumbnailGenerator.swift:45-79` |
| `WaveformGenerator.swift` | REAL 구현이 들어 있으나 파일 주석은 placeholder라고 되어 있다. `AVAssetReaderTrackOutput`으로 16-bit PCM mono를 읽어 200-bin waveform을 계산한다. | 파형 sample 계산은 실제 구현이다. 그러나 timeline UI와 연결된 호출이 없고, 동기 API/고정 bin count라 긴 파일 처리 UX와 progressive rendering은 부족하다. 제품 파형 표시 기준으로는 부분 구현이다. | TODO/FIXME 없음. placeholder 주석 있음. 근거: `WaveformGenerator.swift:21-24`, `WaveformGenerator.swift:31-103` |

## Core 반영 우선순위 재분류

### Critical

| 항목 | 조정 | 이유 | 근거 |
|---|---|---|---|
| 텍스트/자막 preview/export 제외 | 유지 | Speech provider는 실제지만, 생성된 subtitle/text clip이 결과물에 나오지 않는 문제는 그대로다. 자동자막의 최종 사용자 가치가 여기서 막힌다. | `SpeechTranscriptionProvider.swift:31-111`, `TranscriptionService.swift:13-18`, `PlaybackEngine.swift:349-350`, `ExportEngine.swift:269-277` |
| Core AI/effect processor의 렌더 파이프라인 미연결 | 확대 | 배경제거, style filter, auto reframe provider가 실제 API 기반으로 존재하지만 앱/preview/export 적용 경로가 없다. Part 1의 효과 합성 미연결 문제에 AI Core 유틸도 포함된다. | `BackgroundRemovalProvider.swift:32-50`, `StyleTransferProvider.swift:33-60`, `AutoReframeProvider.swift:46-89`, `ExportEngine.swift:233-258` |
| 타임라인 직접 편집 부재 | 유지 | Core 보완 파일에서 trim/move/ripple/snap/DnD/multi-select를 보완하는 구현은 확인되지 않았다. | `TimelineView.swift:118-153`, `EditorViewModel.swift:11` |

### High

| 항목 | 조정 | 이유 | 근거 |
|---|---|---|---|
| 오디오 고급 기능의 앱/렌더 연결 부재 | 보정 | EQ와 waveform은 Core에 실제 구현이 있으므로 "완전 미구현"은 아니다. 하지만 fade/ducking/noise reduction은 여전히 없고, EQ/waveform도 앱 UI와 playback/export 연결이 확인되지 않는다. | `AudioEqualizerService.swift:15-115`, `WaveformGenerator.swift:24-103`, `InspectorPanel.swift:62-81`, `TimelineView.swift:139-149` |
| Auto reframe workflow 미완성 | 신규/상향 | Vision 기반 crop frame 계산은 있으나 앱 호출, keyframe/crop 적용, preview/export 연결이 없다. `AutoReframeCommand`도 subject crop frame을 쓰지 않고 aspect fill transform만 적용한다. | `AutoReframeProvider.swift:46-89`, `AutoReframeCommand.swift:18-44` |
| 비디오 자동자막 입력 안정성 | 신규 | Apple Speech 자체는 REAL이지만 비디오에서 WAV 추출 경로가 불안정하고 temp cleanup이 없다. 최종 subtitle render 문제와 함께 자동자막 품질 리스크가 남는다. | `SpeechTranscriptionProvider.swift:57-70`, `SpeechTranscriptionProvider.swift:124-155` |

### Medium

| 항목 | 조정 | 이유 | 근거 |
|---|---|---|---|
| Cloud sync는 local/iCloud file sync 수준 | 보정 | 기존 "없음"에서 부분 구현으로 조정한다. 다만 계정, 서버 sync, conflict detection, UI가 없어 CapCut식 cloud workflow는 아니다. | `CloudSyncService.swift:65-83`, `CloudSyncService.swift:85-153`, `CloudSyncService.swift:172-194` |
| Template marketplace는 local catalog 수준 | 보정 | 검색/download facade는 있지만 remote catalog나 실제 asset delivery가 없다. | `TemplateMarketplace.swift:87-152`, `TemplateMarketplace.swift:173-259` |

### Low

| 항목 | 조정 | 이유 | 근거 |
|---|---|---|---|
| Collaboration service는 local simulation | 보정 | collaborator/invite/change event 모델은 있으나 multi-user production 협업은 아니다. 플랫폼 기능으로는 후순위이나 상태는 "없음"보다 "mock성 부분"으로 정정한다. | `CollaborationService.swift:96-153`, `CollaborationService.swift:156-175` |
| Thumbnail generator 앱 연결 미확인 | 신규 | Core 유틸은 실제지만 CapCut 갭의 핵심 기능은 아니다. 미디어 브라우저 품질 개선 항목으로 낮은 우선순위다. | `ThumbnailGenerator.swift:8-39` |

## Core 반영 최종 요약 테이블

아래 표는 Part 2 Core 검증으로 보정된 항목만 정리한다. 표에 없는 Part 1 항목은 기존 상태를 유지한다.

| Part 1 # | 기능 | Part 1 상태 | Core 확인 후 상태 | 우선순위 | 정정 근거 |
|---|---|---|---|---|---|
| 30 / 64 | 배경제거 / AI 배경제거 | ❌ 미구현 | 🟡 부분 | Critical | Vision person segmentation과 Core Image alpha mask는 실제 구현이다. 그러나 `analyze(...)`는 빈 결과이고 preview/export 적용 경로가 없다. |
| 31 | Blur/Sepia/Grayscale 등 스타일 효과 | 🟡 부분 | 🟡 부분 | Critical | Core Image style chain이 존재하지만 앱/렌더 연결이 없어 Part 1의 합성 미연결 판단은 유지된다. |
| 37 | EQ | ❌ 미구현 | 🟡 부분 | High | `AudioEqualizerService`가 AVAudioEngine/AVAudioUnitEQ로 offline/realtime 처리를 구현한다. UI/export 연결은 확인되지 않는다. |
| 42 | 오디오 파형 | ❌ 미구현 | 🟡 부분 | High | `WaveformGenerator`가 AVAssetReader로 200-bin waveform을 계산한다. Timeline 표시와 호출 경로는 확인되지 않고 placeholder 주석이 남아 있다. |
| 47 / 61 | 자막 자동 생성 / 자동자막 | 🟡 부분 | 🟡 부분 | Critical | `SpeechTranscriptionProvider`는 Apple Speech 기반으로 실제 연결되어 있다. 하지만 비디오 추출 안정성과 text preview/export 제외 문제가 남는다. |
| 62 | AI 리프레임 | ❌ 미구현 | 🟡 부분 | High | `AutoReframeProvider`는 Vision crop frame을 계산하고 `AutoReframeCommand`도 존재한다. 앱 호출, subject-aware 적용, preview/export 연결은 확인되지 않는다. |
| 66 | 클라우드 동기화 | ❌ 미구현 | 🟡 부분 | Medium | `CloudSyncService`가 iCloud Drive 또는 local fallback에 `.moviecut` 저장/목록/로드를 수행한다. 계정/서버/자동 conflict workflow는 없다. |
| 67 | 협업 편집 | ❌ 미구현 | 🟡 부분 | Low | `CollaborationService`는 local collaborator/invite/change event만 관리하며 join/leave도 simulation으로 명시된다. 실제 realtime 협업은 아니다. |
| 69 | 마켓플레이스 | ❌ 미구현 | 🟡 부분 | Medium | `TemplateMarketplace`가 built-in template 기반 local catalog search/download를 제공한다. remote marketplace는 simulation/local reload 수준이다. |
| 74 | 미디어 브라우저 | 🟡 부분 | 🟡 부분 | Low | `ThumbnailGenerator`는 실제 thumbnail 생성 유틸이지만 앱 호출 경로는 확인되지 않아 브라우저 품질 보완 근거로만 반영한다. |
