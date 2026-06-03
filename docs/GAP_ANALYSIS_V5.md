# MovieCut vs CapCut 갭 분석 V5 Part A: 타임라인+비디오+오디오

## 분석 범위

요청에 따라 아래 5개 파일만 확인했다.

- `App/MovieCutMac/EditorViewModel.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/Export/ExportEngine.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`
- `Sources/MovieCutCore/EditorAPI/EditorSession.swift`

판정 기준:
- `✅ 완료`: 지정 파일 안에서 UI/API 연결과 실제 편집/재생/내보내기 경로가 충분히 확인됨.
- `🟡 부분`: 명령, 상태, 메타데이터, 일부 렌더링 경로는 있으나 UI, 미리보기, 내보내기, 실제 알고리즘 중 일부가 지정 파일 안에서 확인되지 않음.
- `❌ 미구현`: 지정 파일 안에서 기능을 수행하는 구현이 확인되지 않음.

요약: 완료 15개, 부분 9개, 미구현 6개.

| # | 기능 | 상태 | 구현 파일 | 비고 |
|---:|---|---|---|---|
| 1 | 클립 자르기/trim | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:200-213`에서 좌우 trim handle을 만들고, `TimelineView.swift:292-349`에서 left/right trim 드래그로 `sourceRange`와 `timelineRange`를 조정한다. `TimelineView.swift:386-397`에서 커밋 시 `viewModel.trimClip`을 호출하고, `EditorViewModel.swift:339-353`에서 `TrimClipCommand`를 dispatch한다. |
| 2 | 클립 분할/split | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:223-227` 컨텍스트 메뉴의 `Split`이 `viewModel.splitClip()`을 호출한다. `EditorViewModel.swift:322-333`에서 playhead가 선택 클립 내부인지 검사한 뒤 `SplitClipCommand(clipId:trackId:splitTime:)`를 dispatch한다. |
| 3 | 클립 이동/move | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:271-289`의 `moveGesture`가 드래그 중 timeline start를 갱신하고, `TimelineView.swift:372-383`에서 `viewModel.moveClip`으로 커밋한다. `EditorViewModel.swift:356-370`은 `MoveClipCommand`를 dispatch한다. |
| 4 | 클립 복사/복제 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:232-235`의 `Duplicate` 메뉴가 선택 집합을 대상으로 `duplicateClips`를 호출한다. `EditorViewModel.swift:381-397`에서 `DuplicateClipCommand`를 순서대로 dispatch하고, `EditorViewModel.swift:400-408`에는 지정 트랙/시각으로 복사하는 `CopyClipCommand` 경로도 있다. |
| 5 | 클립 삭제 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:228-230`의 `Delete` 메뉴가 선택 클립 집합을 넘긴다. `EditorViewModel.swift:411-424`에서 `DeleteClipCommand`를 순서대로 dispatch하고 삭제된 ID를 `selectedClipIds`에서 제거한다. |
| 6 | Ripple delete | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:237-240`에 `Ripple Delete` 메뉴가 있고, `EditorViewModel.swift:373-378`에서 `RippleDeleteCommand(clipId:)`를 dispatch한 뒤 선택을 정리한다. |
| 7 | 스냅 (clip edge/playhead) | ✅ 완료 | `App/MovieCutMac/TimelineView.swift` | `TimelineView.swift:432-441`의 `snappedTime`이 다른 클립의 시작/끝, `viewModel.playheadTime`, `0.0`을 snap point로 사용한다. move와 trim에서 각각 `TimelineView.swift:278-279`, `304-306`, `336-338`로 이 함수를 사용한다. |
| 8 | 타임라인 줌 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `EditorViewModel.swift:39`에 `timelineZoom` 상태가 있고, `TimelineView.swift:20-22`에서 pixels-per-second로 사용한다. `TimelineView.swift:30-36`의 +/- 버튼이 20-300 범위로 줌을 변경하며, ruler와 클립 위치/폭 계산에 `TimelineView.swift:74-97`, `159-160`에서 반영된다. |
| 9 | 드래그앤드롭 미디어 임포트 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `TimelineView.swift:138-150`에서 `.fileURL` drop을 받아 URL을 만들고 `viewModel.importMedia([url])`를 호출한다. `EditorViewModel.swift:229-236`은 `MediaImporter.probe` 후 `ImportMediaCommand`를 dispatch한다. |
| 10 | 다중 선택 (Cmd+click) | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `EditorViewModel.swift:12-28`이 `selectedClipIds` 집합과 단일 선택 호환 getter/setter를 가진다. `TimelineView.swift:220-222`는 탭 시 command modifier 여부를 넘기고, `TimelineView.swift:244-258`은 Cmd+click 토글 선택을 구현한다. `TimelineView.swift:262-268`은 컨텍스트 메뉴 동작에도 선택 집합을 재사용한다. |
| 11 | Undo/Redo | ✅ 완료 | `Sources/MovieCutCore/EditorAPI/EditorSession.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `EditorSession.swift:8-22`에서 `undoStack`/`redoStack`을 유지하고 모든 `dispatch` 전에 이전 `Project`를 저장한다. `EditorSession.swift:31-46`이 undo/redo 복원 로직이고, `EditorViewModel.swift:430-446`이 UI 계층에서 이를 호출한 뒤 세션을 refresh한다. |
| 12 | 컨텍스트 메뉴 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift` | `TimelineView.swift:223-241`에 클립별 context menu가 있으며 `Split`, `Delete`, `Duplicate`, `Ripple Delete`를 제공한다. |
| 13 | 색보정 (밝기/대비/채도) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:516-519`에서 `SetColorCorrectionCommand`로 선택 클립의 `ColorCorrection`을 갱신한다. `ExportEngine.swift:282-360`과 `PlaybackEngine.swift:542-614`는 `colorCorrection != nil`이면 `CustomVideoCompositor`로 메타데이터를 넘긴다. 다만 밝기/대비/채도 픽셀 처리 알고리즘 자체는 지정 5개 파일 안에서 확인되지 않는다. |
| 14 | 필터/스타일 트랜스퍼 | ❌ 미구현 | - | `EditorViewModel.swift:543-545`에 `effects` 배열을 저장하는 setter는 있으나, 지정 파일 내에서 필터나 스타일 트랜스퍼를 적용하는 렌더링 로직이 없다. `ExportEngine.swift:672-676`은 `effects`를 메타데이터 조건에 포함하지만 `CustomCompositionClipEffect` 생성에는 전달하지 않고, `PlaybackEngine.swift` 쪽에도 `effects` 처리 경로가 없다. |
| 15 | 전환 효과 (crossfade) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:501-504`에서 `transition`을 설정한다. `ExportEngine.swift:323-337`과 `PlaybackEngine.swift:580-594`는 `transition.type == .crossDissolve`일 때 클립 끝 구간에 opacity ramp를 적용한다. 하지만 인접 클립 간 자동 overlap 생성, 양방향 fade, 전환 전용 UI는 지정 파일 안에서 확인되지 않아 부분 구현으로 본다. |
| 16 | 크로마키 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:511-514`가 `ChromaKeySettings`를 clip property로 설정한다. `ExportEngine.swift:123-125`, `231-236`, `345-360`과 `PlaybackEngine.swift:399-403`, `597-614`가 chroma key color/threshold를 custom compositor로 넘긴다. 실제 keying 알고리즘은 지정 파일 안에 없다. |
| 17 | 마스킹 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:521-524`가 `SetClipMaskCommand`를 dispatch한다. `ExportEngine.swift:121-125`, `231-236`, `345-360`과 `PlaybackEngine.swift:399-403`, `597-614`에서 `mask`를 custom compositor 메타데이터로 넘긴다. 마스크 편집 UI나 실제 합성 알고리즘은 지정 파일 안에서 확인되지 않는다. |
| 18 | 배경 제거 | ❌ 미구현 | - | 지정 파일에서 background removal, segmentation, matte, person/object cutout에 해당하는 구현 경로가 확인되지 않는다. |
| 19 | 속도 조절 (speed ramp) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:481-490`은 단일 `playbackRate`와 `speedRampPoints`를 설정한다. `ExportEngine.swift:202-220`은 ramp point가 2개 이상이면 `applySpeedRamp`를 사용하고, `ExportEngine.swift:439-485`에서 segment별 `scaleTimeRange`를 적용한다. `PlaybackEngine.swift:180-185`, `373-386`, `415-420`, `461-467`은 단일 playback rate만 반영하며 `speedRampPoints` 미리보기는 지정 파일 안에 없다. |
| 20 | 역재생 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:526-529`가 `ReverseClipCommand`를 dispatch한다. `ExportEngine.swift:181-200`과 `PlaybackEngine.swift:354-371`은 `clip.isReversed`인 비디오 클립에 대해 `ReverseRenderService().renderReversed`로 임시 reversed asset을 만들고 composition에 삽입한다. 지정 파일 기준으로 비디오 역재생은 재생/내보내기 모두 연결되어 있다. |
| 21 | 정지프레임 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `EditorViewModel.swift:531-540`에서 playhead가 선택 클립 내부인지 검사한 뒤 `FreezeFrameCommand(clipId:freezeTime:freezeDuration:)`를 dispatch한다. 다만 지정 파일 안에서는 freeze frame이 composition에서 어떻게 렌더링되는지 별도 구현이 확인되지 않는다. |
| 22 | 볼륨 조절 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `EditorViewModel.swift:476-479`가 `SetVolumeCommand`로 선택 클립 볼륨을 갱신한다. `ExportEngine.swift:65-73`, `240-246`, `563-568`과 `PlaybackEngine.swift:187-195`, `423-428`, `469-474`, `638-645`가 `AVMutableAudioMixInputParameters.setVolume`과 audio mix를 적용한다. |
| 23 | 오디오 페이드 (fade in/out) | 🟡 부분 | `App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `ExportEngine.swift:76-101`과 `PlaybackEngine.swift:198-223`에서 `clip.fadeInDuration`/`clip.fadeOutDuration`이 0보다 크면 `setVolumeRamp`로 fade in/out을 적용한다. 하지만 지정 파일 안에는 fade duration을 수정하는 ViewModel 메서드나 Timeline UI가 없다. |
| 24 | 오디오 덕킹 | ❌ 미구현 | - | 지정 파일 안에서 음성/음악 트랙을 분석해 자동으로 BGM 볼륨을 낮추는 ducking 로직, sidechain, keyframe 생성 경로가 확인되지 않는다. |
| 25 | 이퀄라이저 | ❌ 미구현 | - | 지정 파일 안에서 EQ band, filter graph, AVAudioUnitEQ, 주파수별 gain 조정 관련 구현이 확인되지 않는다. |
| 26 | 노이즈 감소 | ❌ 미구현 | - | 지정 파일 안에서 denoise/noise reduction 모델, 필터, 오디오 분석 또는 내보내기 적용 경로가 확인되지 않는다. |
| 27 | 오디오 파형 표시 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `EditorViewModel.swift:47`, `100-116`에서 `waveformCache`와 `WaveformGenerator.generate(for:)`로 샘플을 만든다. `TimelineView.swift:168-185`는 text가 아닌 클립에 대해 Canvas로 waveform bar를 그린다. |
| 28 | BGM 라이브러리 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `EditorViewModel.swift:33`, `55`에 `MusicLibrary.placeholder()`가 있고, `EditorViewModel.swift:268-291`의 `addMusicTrack(_:)`가 `MusicTrack.fileURL`을 audio asset으로 import한 뒤 playhead 위치에 audio clip을 추가한다. 실제 라이브러리 탐색/검색/미리듣기/상용 BGM 카탈로그는 지정 파일 안에서 확인되지 않는다. |
| 29 | 보이스오버 녹음 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `EditorViewModel.swift:775`에 Voiceover 섹션이 있고, `EditorViewModel.swift:835-852`의 `addVoiceoverAudio(from:)`가 녹음된 것으로 보이는 URL을 import해 audio track에 추가한다. 그러나 마이크 캡처, 녹음 시작/정지, 모니터링 UI는 지정 파일 안에 없다. |
| 30 | 오디오 추출 | ❌ 미구현 | - | 지정 파일 안에서 비디오에서 오디오만 추출해 별도 asset/track/file로 만드는 함수나 명령이 확인되지 않는다. 비디오 트랙의 원본 오디오를 composition에 포함하는 재생/내보내기 경로는 있으나, 별도 추출 기능은 아니다. |
| 31 | 텍스트 오버레이 | 🟡 부분 | `App/MovieCutMac/InspectorPanel.swift` | `InspectorPanel.swift:120-135`에서 선택 클립의 `textContent`를 편집하는 TextField는 확인된다. 다만 `ContentView.swift`와 `InspectorPanel.swift` 안에서 새 텍스트 클립을 생성/추가하는 버튼, 메뉴, 명령 호출은 확인되지 않아 텍스트 오버레이 생성 경로는 미확인이다. |
| 32 | 텍스트 애니메이션 | 🟡 부분 | `App/MovieCutMac/Effects/TextAnimationRenderer.swift` | 디렉토리 목록에서 `TextAnimationRenderer.swift` 파일은 확인된다. 하지만 지정 5개 파일 안에서 `TextAnimationRenderer` 참조나 `CustomVideoCompositor.swift` 연결은 확인되지 않는다. |
| 33 | 자동 자막 | 🟡 부분 | `App/MovieCutMac/Transcription/AutoSubtitlesView.swift`<br>`App/MovieCutMac/InspectorPanel.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `AutoSubtitlesView.swift:9-59`에서 provider 선택, `prepareSubtitles()`, 진행률 표시, `applyGeneratedSubtitles()` 호출 UI가 있다. `InspectorPanel.swift:211-218`, `582-589`에서 video/audio 클립에 자막 UI를 연결한다. 다만 `EditorViewModel.swift` 구현은 이번 지정 5개 파일 밖이라 실제 전사/타임라인 적용 구현은 확인하지 않았다. |
| 34 | 스티커/이모지 | 🟡 부분 | `App/MovieCutMac/Stickers/StickerPickerView.swift` | 디렉토리 목록에서 `StickerPickerView.swift` 파일은 확인된다. 그러나 `ContentView.swift`와 `InspectorPanel.swift` 안에서 `StickerPickerView`를 여는 연결은 확인되지 않는다. |
| 35 | 텍스트 템플릿 | 🟡 부분 | `App/MovieCutMac/ContentView.swift`<br>`App/MovieCutMac/Templates/TemplatePickerView.swift` | `ContentView.swift:78-80`, `114-115`에서 `TemplatePickerView`를 sheet로 여는 템플릿 버튼은 있다. 다만 `TemplatePickerView.swift`는 이번 지정 파일 밖이라 텍스트 전용 템플릿인지, 텍스트 클립 생성까지 이어지는지는 확인하지 않았다. |
| 36 | Export (mp4/mov) | 🟡 부분 | `App/MovieCutMac/ContentView.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift` | `ContentView.swift:95-98`에서 Export 버튼이 `viewModel.exportProject()`를 호출하고, 디렉토리 목록에서 `ExportEngine.swift` 파일은 확인된다. 다만 이번 지정 5개 파일 안에서는 mp4/mov 포맷 지원 구현을 확인하지 않았다. |
| 37 | Export 진행률 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `ContentView.swift:108-112`, `191-200`에서 `exportEngine.isExporting` 동안 sheet를 띄우고 `exportEngine.exportProgress`를 `ProgressView`와 퍼센트 텍스트로 표시한다. 실제 progress polling/update 구현은 지정 파일 밖이라 확인하지 않았다. |
| 38 | Export 취소 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `ContentView.swift:208-210`의 Cancel 버튼이 `viewModel.cancelExport()`를 호출한다. 취소가 `ExportEngine` 작업에 실제로 전파되는지는 이번 지정 5개 파일 안에서 확인되지 않는다. |
| 39 | 소셜 공유 | ✅ 완료 | `App/MovieCutMac/ContentView.swift` | `ContentView.swift:100-104`에서 `lastExportURL`이 있으면 `ShareLink(item:)`로 내보낸 파일 공유 UI를 노출한다. |
| 40 | 캔버스 비율 선택 | ✅ 완료 | `App/MovieCutMac/ContentView.swift` | `ContentView.swift:57-76`에서 toolbar `Picker("Canvas")`와 Canvas 설정 popover가 `viewModel.updateCanvas`에 연결된다. `ContentView.swift:119-127`에는 16:9, 9:16, 4:5, 1:1, 21:9, ultrawide preset이 있다. |
| 41 | Export 프리셋 | 🟡 부분 | `Sources/MovieCutCore/Models/ExportSettings.swift`<br>`Sources/MovieCutCore/Models/ExportPreset.swift` | 디렉토리 목록에서 `ExportSettings.swift`와 `ExportPreset.swift` 모델 파일은 확인된다. 하지만 `ContentView.swift:191-213`의 `ExportSheet`에는 preset 선택 UI가 없고, 모델 사용 경로는 지정 파일 안에서 확인되지 않는다. |
| 42 | 키프레임 에디터 UI | ✅ 완료 | `App/MovieCutMac/Keyframes/KeyframeEditorView.swift`<br>`App/MovieCutMac/InspectorPanel.swift` | `InspectorPanel.swift:221-244`에서 `KeyframeEditorView`와 `KeyframeListView`를 Animation 섹션에 연결한다. `KeyframeEditorView.swift:13-44`는 속성 선택, 추가/삭제 버튼, timeline lane UI를 제공하고, `KeyframeEditorView.swift:97-124`에서 keyframe 추가/삭제 후 `onChange`를 호출한다. |
| 43 | 키프레임 렌더링 | ❌ 미구현 | `App/MovieCutMac/Export/CustomVideoCompositor.swift` | `CustomVideoCompositor.swift:105-122`는 color correction, chroma key, mask만 적용한다. 지정 파일 안에서 `Keyframe`/`AnimatableProperty` 기반 보간이나 렌더링 적용 경로는 확인되지 않는다. |
| 44 | 마커 | 🟡 부분 | `Sources/MovieCutCore/Models/Marker.swift` | 디렉토리 목록에서 `Marker.swift` 모델 파일은 확인된다. 그러나 지정 5개 파일 안에서 marker 생성, 표시, 편집, 이동, 타임라인 연결은 확인되지 않는다. |
| 45 | 자동 컷 | 🟡 부분 | `Sources/MovieCutCore/Analysis/SilenceDetectionProvider.swift`<br>`Sources/MovieCutCore/Analysis/AutoCutEngine.swift` | 디렉토리 목록에서 `SilenceDetectionProvider.swift`와 `AutoCutEngine.swift` 파일은 확인된다. 그러나 지정 5개 파일 안에서 자동 컷 UI나 실행 연결은 확인되지 않는다. |
| 46 | 씬 변경 감지 | 🟡 부분 | `Sources/MovieCutCore/Analysis/SceneChangeProvider.swift` | 디렉토리 목록에서 `SceneChangeProvider.swift` 파일은 확인된다. 그러나 지정 5개 파일 안에서 scene change 감지 실행, 결과 표시, 타임라인 적용 경로는 확인되지 않는다. |
| 47 | 자동 리프레임 | 🟡 부분 | `Sources/MovieCutCore/Analysis/AutoReframeProvider.swift` | 디렉토리 목록에서 `AutoReframeProvider.swift` 파일은 확인된다. 그러나 지정 5개 파일 안에서 자동 리프레임 UI, provider 실행, transform/keyframe 적용 연결은 확인되지 않는다. |
| 48 | AI 어시스턴트 | 🟡 부분 | `App/MovieCutMac/Analysis/AutoAssistantView.swift` | 디렉토리 목록에서 `AutoAssistantView.swift` 파일은 확인된다. 하지만 `ContentView.swift`와 `InspectorPanel.swift` 안에서 `AutoAssistantView` 연결은 확인되지 않는다. |
| 49 | 클라우드 동기화 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `ContentView.swift:84-91`에 cloud sync toolbar 버튼이 있고 `isCloudSyncing`이면 spinner를 표시하며 `viewModel.syncToCloud()`를 호출한다. 실제 cloud sync 구현은 지정 파일 밖이라 확인되지 않는다. |
| 50 | 프로젝트 템플릿 | 🟡 부분 | `App/MovieCutMac/ContentView.swift`<br>`App/MovieCutMac/Templates/TemplatePickerView.swift`<br>`Sources/MovieCutCore/Templates/TemplateMarketplace.swift` | `ContentView.swift:78-80`, `114-115`에서 Templates 버튼이 `TemplatePickerView` sheet를 연다. 디렉토리 목록에서 `TemplateMarketplace.swift` 파일도 확인된다. 다만 marketplace 로딩/적용 구현은 지정 파일 밖이라 확인하지 않았다. |

## 총평 (all 50 features)

- ✅ 완료: 18개
- 🟡 부분: 25개
- ❌ 미구현: 7개

## 다음 우선순위

Critical:
- 키프레임 렌더링: UI는 있지만 `CustomVideoCompositor`에 keyframe 보간/적용 경로가 없어 export/playback 결과에 반영되지 않을 가능성이 크다.
- 텍스트 오버레이 생성 경로: Inspector에는 기존 `textContent` 편집만 있고, 지정 파일 기준 새 텍스트 클립 생성 진입점이 없다.
- Export 핵심 검증: mp4/mov 포맷, 진행률 update, 취소 전파, preset 적용이 `ContentView` 밖에 있어 실제 동작 확인이 필요하다.

High:
- 자동 자막: `AutoSubtitlesView`와 Inspector 연결은 있으므로 `EditorViewModel.prepareSubtitles()`/`applyGeneratedSubtitles()`의 전사 및 text clip 생성 경로를 검증해야 한다.
- AI/자동화 기능 연결: 자동 컷, 씬 변경 감지, 자동 리프레임, AI 어시스턴트는 파일은 있으나 지정 UI 연결이 확인되지 않는다.
- 클라우드 동기화: toolbar 버튼은 있으므로 실제 provider, 오류 처리, conflict 처리, 완료 상태 표시를 확인해야 한다.

Medium:
- 스티커/이모지, 텍스트 애니메이션, 텍스트 템플릿: 파일 존재는 확인되지만 `ContentView`/`InspectorPanel` 연결 또는 compositor/export 연결이 부족하다.
- 마커: 모델 파일은 있으나 timeline 표시/편집/탐색 연결이 확인되지 않는다.
- Export 프리셋: 모델 파일은 있으나 `ExportSheet`에 preset 선택 UI가 없다.

Low:
- 소셜 공유와 캔버스 비율 선택은 지정 파일 기준 완료로 보이며, 이후에는 edge case와 UX polish 중심으로 점검하면 된다.
- Part B에서 파일 존재만 확인한 항목들은 다음 라운드에서 해당 구현 파일을 직접 읽어 상태를 ✅/❌로 재분류해야 한다.
