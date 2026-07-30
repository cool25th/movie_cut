# MovieCut vs CapCut 갭 분석 V6 Part 1: 타임라인+비디오+오디오

> **[보관 — 대체됨]** 이 문서는 `docs/archive/`에 있다. 현역이 아니며 갱신되지 않는다. 전체 문서 지도는 [docs/README.md](../README.md).
>
> - 상태: 지정 4개 파일만 읽은 제한 범위 감사다. 자가보고 수치를 신뢰하지 말 것.
> - 지금 볼 곳: 최신 격차 분석은 `docs/GAP_ANALYSIS_V13_FUNC_UI_20260729.md`. 판정 기준은 `docs/CAPCUT_BENCHMARK_STANDARD.md`.

## 분석 범위

요청에 따라 `docs/archive/GAP_ANALYSIS_V5.md`를 먼저 확인한 뒤, 실제 코드는 아래 4개 파일만 확인했다.

- `App/MovieCutMac/EditorViewModel.swift`
- `App/MovieCutMac/TimelineView.swift`
- `App/MovieCutMac/Export/ExportEngine.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`

판정 기준:
- `✅ 완료`: 지정 4개 파일 안에서 UI/API 연결과 실제 편집, 재생 또는 내보내기 경로가 충분히 확인됨.
- `🟡 부분`: 상태, 명령 호출, 메타데이터 전달 또는 일부 재생/내보내기 경로는 있으나 UI, 명령 내부 구현, 실제 알고리즘, 미리보기, 내보내기 중 일부가 지정 4개 파일 안에서 확인되지 않음.
- `❌ 미구현`: 지정 4개 파일 안에서 해당 기능을 수행하는 구현 경로가 확인되지 않음.

요약: 완료 14개, 부분 14개, 미구현 2개.

| # | 기능 | 상태 | 구현 위치 | 비고 |
|---:|---|---|---|---|
| 1 | 클립 자르기/trim | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:207-220`에서 좌우 trim handle을 만들고, `App/MovieCutMac/TimelineView.swift:299-331`, `App/MovieCutMac/TimelineView.swift:333-359`에서 left/right trim 드래그를 처리한다. `App/MovieCutMac/TimelineView.swift:393-404`에서 커밋 시 `viewModel.trimClip`을 호출하며, `App/MovieCutMac/EditorViewModel.swift:351-366`에서 `TrimClipCommand`를 dispatch한다. |
| 2 | 클립 분할/split | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:230-234`의 컨텍스트 메뉴 `Split`이 선택 후 `viewModel.splitClip()`을 호출한다. `App/MovieCutMac/EditorViewModel.swift:334-349`는 playhead가 선택 클립 내부인지 검사하고 `SplitClipCommand`를 dispatch한다. |
| 3 | 클립 이동/move | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:278-297`의 `moveGesture`가 드래그 중 timeline start를 갱신하고, `App/MovieCutMac/TimelineView.swift:379-390`에서 `viewModel.moveClip`으로 커밋한다. `App/MovieCutMac/EditorViewModel.swift:368-383`은 `MoveClipCommand`를 dispatch한다. |
| 4 | 클립 복사/복제 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:239-241`의 `Duplicate` 메뉴가 선택 집합을 대상으로 `duplicateClips`를 호출한다. `App/MovieCutMac/EditorViewModel.swift:393-420`에는 `DuplicateClipCommand`와 지정 트랙/시각 대상 `CopyClipCommand` 경로가 있다. |
| 5 | 클립 삭제 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:235-238`의 `Delete` 메뉴가 선택 클립 집합을 넘긴다. `App/MovieCutMac/EditorViewModel.swift:423-440`에서 `DeleteClipCommand`를 순서대로 dispatch하고 삭제된 ID를 `selectedClipIds`에서 제거한다. |
| 6 | Ripple delete | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:244-247`에 `Ripple Delete` 메뉴가 있고, `App/MovieCutMac/EditorViewModel.swift:385-390`에서 `RippleDeleteCommand(clipId:)`를 dispatch한 뒤 선택을 정리한다. |
| 7 | 스냅 (clip edge/playhead) | ✅ 완료 | `App/MovieCutMac/TimelineView.swift` | `App/MovieCutMac/TimelineView.swift:439-449`의 `snappedTime`이 다른 클립 시작/끝, playhead, 0초를 snap point로 사용한다. move와 trim에서 각각 `App/MovieCutMac/TimelineView.swift:286`, `App/MovieCutMac/TimelineView.swift:312`, `App/MovieCutMac/TimelineView.swift:344`로 이 함수를 호출한다. |
| 8 | 타임라인 줌 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `App/MovieCutMac/EditorViewModel.swift:46`에 `timelineZoom` 상태가 있고, `App/MovieCutMac/TimelineView.swift:20-22`에서 pixels-per-second로 사용한다. `App/MovieCutMac/TimelineView.swift:30-36`의 +/- 버튼이 줌을 변경하며, ruler와 클립 위치/폭 계산에 `App/MovieCutMac/TimelineView.swift:74-97`, `App/MovieCutMac/TimelineView.swift:166-167`에서 반영된다. |
| 9 | 드래그앤드롭 미디어 임포트 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift`<br>`App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/TimelineView.swift:145-157`에서 `.fileURL` drop을 받아 URL을 만들고 `viewModel.importMedia([url])`를 호출한다. `App/MovieCutMac/EditorViewModel.swift:241-251`은 `MediaImporter.probe` 후 `ImportMediaCommand`를 dispatch한다. |
| 10 | 다중 선택 (Cmd+click) | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `App/MovieCutMac/EditorViewModel.swift:12-32`가 `selectedClipIds` 집합과 단일 선택 호환 getter/setter를 가진다. `App/MovieCutMac/TimelineView.swift:227-229`는 탭 시 command modifier 여부를 넘기고, `App/MovieCutMac/TimelineView.swift:251-266`은 Cmd+click 토글 선택을 구현한다. `App/MovieCutMac/TimelineView.swift:269-276`은 컨텍스트 메뉴에서도 선택 집합을 재사용한다. |
| 11 | Undo/Redo | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:442-458`에서 `session.undo()`와 `session.redo()`를 호출한 뒤 refresh하는 ViewModel 경로는 있다. 다만 이번 지정 4개 파일 안에는 undo/redo stack 내부 구현이나 UI 버튼/단축키 연결이 없어 부분 구현으로 판정했다. |
| 12 | 컨텍스트 메뉴 | ✅ 완료 | `App/MovieCutMac/TimelineView.swift` | `App/MovieCutMac/TimelineView.swift:230-248`에 클립별 context menu가 있으며 `Split`, `Delete`, `Duplicate`, `Ripple Delete`를 제공한다. |
| 13 | 색보정 (밝기/대비/채도) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:565-568`에서 `SetColorCorrectionCommand`로 선택 클립의 `ColorCorrection`을 갱신한다. `App/MovieCutMac/Export/ExportEngine.swift:233-236`, `App/MovieCutMac/Export/ExportEngine.swift:284-289`, `App/MovieCutMac/Export/ExportEngine.swift:350-365`는 export custom compositor metadata로 넘긴다. `App/MovieCutMac/Playback/PlaybackEngine.swift:422-425`, `App/MovieCutMac/Playback/PlaybackEngine.swift:569-571`, `App/MovieCutMac/Playback/PlaybackEngine.swift:624-638`도 playback custom compositor로 넘긴다. 실제 픽셀 처리 알고리즘은 지정 4개 파일 안에서 확인되지 않는다. |
| 14 | 필터/스타일 트랜스퍼 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:515-524`는 스타일 선택 상태를 clip별 dictionary에 저장하고, `App/MovieCutMac/EditorViewModel.swift:592-595`는 `effects` 배열을 clip property로 저장한다. `App/MovieCutMac/Export/ExportEngine.swift:237`, `App/MovieCutMac/Export/ExportEngine.swift:678-689`에는 effects metadata가 있으나, `App/MovieCutMac/Export/ExportEngine.swift:284-289`의 custom compositor 활성 조건에는 effects가 빠져 있고 `App/MovieCutMac/Export/ExportEngine.swift:357-365`의 `CustomCompositionClipEffect`에도 effects를 전달하지 않는다. 실제 필터/스타일 렌더링은 확인되지 않는다. |
| 15 | 전환 효과 (crossfade) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:550-553`에서 `transition`을 설정한다. `App/MovieCutMac/Export/ExportEngine.swift:328-342`와 `App/MovieCutMac/Playback/PlaybackEngine.swift:607-621`는 `transition.type == .crossDissolve`일 때 클립 끝 구간에 opacity ramp를 적용한다. 인접 클립 간 자동 overlap 생성, 양방향 crossfade, 전환 전용 Timeline UI는 지정 4개 파일 안에서 확인되지 않는다. |
| 16 | 크로마키 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:560-563`이 `ChromaKeySettings`를 clip property로 설정한다. `App/MovieCutMac/Export/ExportEngine.swift:233-236`, `App/MovieCutMac/Export/ExportEngine.swift:284-289`, `App/MovieCutMac/Export/ExportEngine.swift:357-365`와 `App/MovieCutMac/Playback/PlaybackEngine.swift:422-425`, `App/MovieCutMac/Playback/PlaybackEngine.swift:569-571`, `App/MovieCutMac/Playback/PlaybackEngine.swift:630-638`가 chroma key color/threshold를 custom compositor로 넘긴다. 실제 keying 알고리즘은 지정 4개 파일 안에서 확인되지 않는다. |
| 17 | 마스킹 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:570-573`가 `SetClipMaskCommand`를 dispatch한다. `App/MovieCutMac/Export/ExportEngine.swift:121-125`, `App/MovieCutMac/Export/ExportEngine.swift:233-237`, `App/MovieCutMac/Export/ExportEngine.swift:357-365`와 `App/MovieCutMac/Playback/PlaybackEngine.swift:318-321`, `App/MovieCutMac/Playback/PlaybackEngine.swift:422-425`, `App/MovieCutMac/Playback/PlaybackEngine.swift:630-638`에서 mask metadata를 넘긴다. 마스크 편집 UI나 실제 합성 알고리즘은 지정 4개 파일 안에서 확인되지 않는다. |
| 18 | 배경 제거 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:35`, `App/MovieCutMac/EditorViewModel.swift:56`에 배경 제거 상태 저장용 `isBackgroundRemoved`와 `backgroundRemovedClipIds`가 있고, `App/MovieCutMac/EditorViewModel.swift:504-513`에서 선택 클립의 enabled 상태를 토글한다. `App/MovieCutMac/EditorViewModel.swift:705-715`는 선택 클립 변경 시 상태를 복원한다. 다만 clip property, command, segmentation, matte 생성, playback/export 적용 경로는 지정 4개 파일 안에서 확인되지 않는다. |
| 19 | 속도 조절 (speed ramp) | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:530-539`은 단일 `playbackRate`와 `speedRampPoints`를 설정한다. `App/MovieCutMac/Export/ExportEngine.swift:203-222`은 ramp point가 2개 이상이면 `applySpeedRamp`를 사용하고, `App/MovieCutMac/Export/ExportEngine.swift:445-491`에서 segment별 `scaleTimeRange`를 적용한다. `App/MovieCutMac/Playback/PlaybackEngine.swift:190-195`, `App/MovieCutMac/Playback/PlaybackEngine.swift:392-407`, `App/MovieCutMac/Playback/PlaybackEngine.swift:440-446`, `App/MovieCutMac/Playback/PlaybackEngine.swift:488-494`는 단일 playback rate만 반영하며 speed ramp preview는 확인되지 않는다. |
| 20 | 역재생 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:575-578`가 `ReverseClipCommand`를 dispatch한다. `App/MovieCutMac/Export/ExportEngine.swift:182-200`과 `App/MovieCutMac/Playback/PlaybackEngine.swift:367-384`은 `clip.isReversed`인 비디오 클립에 대해 `ReverseRenderService().renderReversed`로 임시 reversed asset을 만들고 composition에 삽입한다. `App/MovieCutMac/Playback/PlaybackEngine.swift:678-693`에는 임시 파일 정리 경로도 있다. |
| 21 | 정지프레임 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:580-590`에서 playhead가 선택 클립 내부인지 검사한 뒤 `FreezeFrameCommand`를 dispatch한다. `App/MovieCutMac/Playback/PlaybackEngine.swift:180-188`은 짧은 source range/긴 timeline range를 freeze frame clip으로 판정하고, `App/MovieCutMac/Playback/PlaybackEngine.swift:394-399`에서 timeline duration으로 늘린다. 다만 `App/MovieCutMac/Export/ExportEngine.swift:171-222`에는 freeze frame 전용 source frame 반복/scale 경로가 확인되지 않아 export 반영은 미확인이다. |
| 22 | 볼륨 조절 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/EditorViewModel.swift:488-490`가 `SetVolumeCommand`로 선택 클립 볼륨을 갱신한다. `App/MovieCutMac/Export/ExportEngine.swift:65-73`, `App/MovieCutMac/Export/ExportEngine.swift:242-248`와 `App/MovieCutMac/Playback/PlaybackEngine.swift:197-205`, `App/MovieCutMac/Playback/PlaybackEngine.swift:448-453`, `App/MovieCutMac/Playback/PlaybackEngine.swift:496-501`가 `AVMutableAudioMixInputParameters.setVolume`과 audio mix를 적용한다. |
| 23 | 오디오 페이드 (fade in/out) | 🟡 부분 | `App/MovieCutMac/Export/ExportEngine.swift`<br>`App/MovieCutMac/Playback/PlaybackEngine.swift` | `App/MovieCutMac/Export/ExportEngine.swift:76-101`과 `App/MovieCutMac/Playback/PlaybackEngine.swift:208-234`에서 `clip.fadeInDuration`/`clip.fadeOutDuration`이 0보다 크면 `setVolumeRamp`로 fade in/out을 적용한다. Export 호출은 `App/MovieCutMac/Export/ExportEngine.swift:242-248`, playback 호출은 `App/MovieCutMac/Playback/PlaybackEngine.swift:448-453`, `App/MovieCutMac/Playback/PlaybackEngine.swift:496-501`에 있다. 지정 4개 파일 안에는 fade duration을 수정하는 ViewModel 메서드나 Timeline UI가 없다. |
| 24 | 오디오 덕킹 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:526-528`에 `AudioDuckingCommand(clipId:duckLevel:)`를 dispatch하는 진입점이 있다. 다만 지정 4개 파일 안에는 음성/음악 트랙 분석, sidechain, 자동 keyframe 생성, ducking preview/export 전용 처리 로직이 확인되지 않는다. |
| 25 | 이퀄라이저 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:34`, `App/MovieCutMac/EditorViewModel.swift:55`에 EQ preset 상태가 있고, `App/MovieCutMac/EditorViewModel.swift:493-502`에서 선택 clip별 preset을 저장한다. `App/MovieCutMac/EditorViewModel.swift:705-715`는 선택 변경 시 preset 상태를 복원한다. 그러나 AVAudioUnitEQ, filter graph, band별 gain, playback/export 적용 경로는 지정 4개 파일 안에서 확인되지 않는다. |
| 26 | 노이즈 감소 | ❌ 미구현 | - | 지정 4개 파일에서 denoise/noise reduction 모델, 필터, 오디오 분석 또는 내보내기 적용 경로가 확인되지 않는다. 확인된 오디오 처리 경로는 `App/MovieCutMac/Export/ExportEngine.swift:65-103`와 `App/MovieCutMac/Playback/PlaybackEngine.swift:197-235`의 볼륨/페이드 처리에 한정된다. |
| 27 | 오디오 파형 표시 | ✅ 완료 | `App/MovieCutMac/EditorViewModel.swift`<br>`App/MovieCutMac/TimelineView.swift` | `App/MovieCutMac/EditorViewModel.swift:54`, `App/MovieCutMac/EditorViewModel.swift:110-127`에서 `waveformCache`와 `WaveformGenerator.generate(for:)`로 샘플을 만든다. `App/MovieCutMac/TimelineView.swift:175-193`는 text가 아닌 클립에 대해 Canvas로 waveform bar를 그린다. |
| 28 | BGM 라이브러리 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:40`, `App/MovieCutMac/EditorViewModel.swift:65`에 `MusicLibrary.placeholder()`가 있고, `App/MovieCutMac/EditorViewModel.swift:280-307`의 `addMusicTrack(_:)`가 `MusicTrack.fileURL`을 audio asset으로 import한 뒤 playhead 위치에 audio clip을 추가한다. 실제 라이브러리 탐색/검색/미리듣기/상용 BGM 카탈로그 UI는 지정 4개 파일 안에서 확인되지 않는다. |
| 29 | 보이스오버 녹음 | 🟡 부분 | `App/MovieCutMac/EditorViewModel.swift` | `App/MovieCutMac/EditorViewModel.swift:844`에 Voiceover 섹션이 있고, `App/MovieCutMac/EditorViewModel.swift:904-925`의 `addVoiceoverAudio(from:)`가 녹음된 것으로 보이는 URL을 import해 audio track에 추가한다. 마이크 캡처, 녹음 시작/정지, 모니터링 UI는 지정 4개 파일 안에 없다. |
| 30 | 오디오 추출 | ❌ 미구현 | - | 지정 4개 파일에서 비디오에서 오디오만 추출해 별도 asset, track 또는 file로 만드는 함수나 명령은 확인되지 않는다. `App/MovieCutMac/Playback/PlaybackEngine.swift:429-454`는 비디오 클립 원본 오디오를 preview composition에 넣는 경로지만, 별도 추출 기능은 아니다. |

## Part 1 완료 — Part 2에서 계속

# MovieCut vs CapCut 갭 분석 V6 Part 2: 텍스트+Export+키프레임+AI+클라우드

## 분석 범위

요청에 따라 기존 Part 1을 보존하고, 실제 코드는 아래 3개 파일만 추가로 확인했다.

- `App/MovieCutMac/InspectorPanel.swift`
- `App/MovieCutMac/ContentView.swift`
- `App/MovieCutMac/Export/CustomVideoCompositor.swift`

판정 기준:
- `✅ 완료`: 지정 3개 파일 안에서 UI/API 연결과 실제 표시, 공유, 선택 또는 렌더링 경로가 충분히 확인됨.
- `🟡 부분`: 진입점, 상태 바인딩, 호출 또는 일부 렌더링은 있으나 실제 알고리즘, 백엔드, 생성 UI, preview/export 양방향 연결, 프리셋 세부값 중 일부가 지정 3개 파일 안에서 확인되지 않음.
- `❌ 미구현`: 지정 3개 파일 안에서 해당 기능을 수행하는 구현 경로가 확인되지 않음.

요약: 완료 5개, 부분 8개, 미구현 7개.

| # | 기능 | 상태 | 구현 위치 | 비고 |
|---:|---|---|---|---|
| 31 | 텍스트 오버레이 | 🟡 부분 | `App/MovieCutMac/InspectorPanel.swift` | `App/MovieCutMac/InspectorPanel.swift:172-188`에서 선택 클립의 `textContent`가 있을 때 텍스트를 편집하고 `viewModel.updateSelectedTextContent`를 호출한다. 다만 텍스트 클립 추가 UI, 폰트/정렬/스타일 편집, preview/export 텍스트 렌더링 경로는 지정 3개 파일 안에서 확인되지 않는다. |
| 32 | 텍스트 애니메이션 (fade/slide/scale) | 🟡 부분 | `App/MovieCutMac/InspectorPanel.swift`<br>`App/MovieCutMac/Export/CustomVideoCompositor.swift` | `App/MovieCutMac/InspectorPanel.swift:273-296`에 Animation disclosure와 keyframe editor/list 연결이 있고, `App/MovieCutMac/Export/CustomVideoCompositor.swift:64-89`, `App/MovieCutMac/Export/CustomVideoCompositor.swift:91-177`, `App/MovieCutMac/Export/CustomVideoCompositor.swift:382-408`에서 position/scale/rotation/opacity keyframe을 보간하고 렌더링한다. fade/slide/scale은 표현 가능하지만 텍스트 전용 애니메이션 프리셋이나 텍스트 렌더 소스 연결은 지정 3개 파일 안에서 확인되지 않는다. |
| 33 | 자동 자막 (음성 인식) | 🟡 부분 | `App/MovieCutMac/InspectorPanel.swift` | `App/MovieCutMac/InspectorPanel.swift:263-270`에서 video/audio 클립에 `AutoSubtitlesView(viewModel:)`를 표시한다. 하지만 음성 인식 엔진, 자막 segment 생성, 타임라인 반영, export burn-in 경로는 지정 3개 파일 안에서 확인되지 않는다. |
| 34 | 스티커/이모지 | ❌ 미구현 | - | 지정 3개 파일에서 스티커/이모지 라이브러리, 추가 UI, 스티커 클립 모델 연결, preview/export 렌더링 경로가 확인되지 않는다. |
| 35 | 텍스트 템플릿 | ❌ 미구현 | - | `App/MovieCutMac/InspectorPanel.swift:172-188`의 텍스트 편집은 plain text 수준이다. 지정 3개 파일에서 자막/타이틀 템플릿, 텍스트 스타일 프리셋, 템플릿 적용 UI는 확인되지 않는다. |
| 36 | Export (mp4/mov) | 🟡 부분 | `App/MovieCutMac/ContentView.swift`<br>`App/MovieCutMac/InspectorPanel.swift` | `App/MovieCutMac/ContentView.swift:95-98`에서 Export 버튼이 `viewModel.exportProject()`를 호출하고, `App/MovieCutMac/ContentView.swift:108-113`, `App/MovieCutMac/ContentView.swift:191-213`에서 export sheet를 표시한다. `App/MovieCutMac/InspectorPanel.swift:346-358`에는 export 해상도/품질 설정이 있다. 다만 mp4/mov 포맷 선택과 실제 파일 타입 처리 경로는 이번 지정 3개 파일 안에서 확인되지 않는다. |
| 37 | Export 진행률 | ✅ 완료 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:108-113`에서 `viewModel.exportEngine.isExporting` 동안 export sheet를 띄우고, `App/MovieCutMac/ContentView.swift:194-202`에서 `exportProgress` 기반 `ProgressView`와 퍼센트 텍스트를 표시한다. |
| 38 | Export 취소 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:208-210`에 Cancel 버튼이 있고 `viewModel.cancelExport()`를 호출한다. 다만 cancel 요청이 실제 `AVAssetExportSession` 또는 렌더 작업 중단으로 이어지는 내부 구현은 지정 3개 파일 안에서 확인되지 않는다. |
| 39 | 소셜 공유 (ShareLink) | ✅ 완료 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:100-104`에서 `viewModel.lastExportURL`이 있을 때 `ShareLink(item:)`로 내보낸 파일 공유 UI를 제공한다. |
| 40 | 캔버스 비율 선택 | ✅ 완료 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:57-67`의 toolbar picker가 `viewModel.canvasSelection`을 바인딩하고 `viewModel.updateCanvas`를 호출한다. `App/MovieCutMac/ContentView.swift:69-75`에는 Canvas 설정 popover가 있으며, `App/MovieCutMac/ContentView.swift:119-128`에서 16:9, 9:16, 4:5, 1:1, 21:9 계열 preset을 제공한다. |
| 41 | Export 프리셋 (해상도/비트레이트) | 🟡 부분 | `App/MovieCutMac/InspectorPanel.swift` | `App/MovieCutMac/InspectorPanel.swift:346-358`에서 4K/1080p/720p/480p 해상도와 High/Medium/Low 품질 picker가 있다. 다만 명시적 비트레이트 값, 코덱/프레임레이트 export preset, 해당 선택값이 export engine에 반영되는 경로는 지정 3개 파일 안에서 확인되지 않는다. |
| 42 | 키프레임 에디터 UI | ✅ 완료 | `App/MovieCutMac/InspectorPanel.swift` | `App/MovieCutMac/InspectorPanel.swift:273-296`에서 Animation disclosure 안에 `KeyframeEditorView`와 `KeyframeListView`를 배치하고, 선택 keyframe 상태와 `viewModel.updateSelectedKeyframes` 변경 콜백을 연결한다. |
| 43 | 키프레임 렌더링 (preview+export) | ✅ 완료 | `App/MovieCutMac/Export/CustomVideoCompositor.swift` | `App/MovieCutMac/Export/CustomVideoCompositor.swift:5-45`가 clip별 keyframe metadata를 받는 `CustomCompositionClipEffect`를 정의한다. `App/MovieCutMac/Export/CustomVideoCompositor.swift:51-61`, `App/MovieCutMac/Export/CustomVideoCompositor.swift:91-177`에서 local time 기준 transform/opacity 값을 보간하고, `App/MovieCutMac/Export/CustomVideoCompositor.swift:262-288`, `App/MovieCutMac/Export/CustomVideoCompositor.swift:382-408`에서 transform과 opacity를 실제 CIImage에 적용한다. Part 1에서 playback/export 양쪽 custom compositor 전달 경로가 확인되어 preview/export 공통 렌더링으로 판정했다. |
| 44 | 마커 | ❌ 미구현 | - | 지정 3개 파일에서 timeline marker, chapter marker, beat marker, marker 목록/편집 UI 또는 export metadata 경로가 확인되지 않는다. |
| 45 | 자동 컷 (무음 구간 제거) | ❌ 미구현 | - | 지정 3개 파일에서 오디오 무음 분석, 임계값 설정, 자동 split/ripple delete, batch cut UI가 확인되지 않는다. |
| 46 | 씬 변경 감지 | ❌ 미구현 | - | 지정 3개 파일에서 frame histogram/vision 기반 scene boundary detection, 자동 marker/split 생성, 분석 UI가 확인되지 않는다. |
| 47 | 자동 리프레임 | ❌ 미구현 | - | `App/MovieCutMac/ContentView.swift:57-75`에서 캔버스 비율 변경은 가능하지만, 인물/피사체 추적 기반 자동 pan/scale/crop keyframe 생성 경로는 지정 3개 파일 안에서 확인되지 않는다. |
| 48 | AI 어시스턴트 | ❌ 미구현 | - | 지정 3개 파일에서 AI assistant panel, prompt input, 편집 명령 생성, 추천/자동화 workflow가 확인되지 않는다. |
| 49 | 클라우드 동기화 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:84-91`에 `viewModel.syncToCloud()` 버튼과 `isCloudSyncing` progress 표시가 있다. 다만 인증, 원격 저장소, conflict 처리, 협업/공유 프로젝트 구현은 지정 3개 파일 안에서 확인되지 않는다. |
| 50 | 프로젝트 템플릿 마켓플레이스 | 🟡 부분 | `App/MovieCutMac/ContentView.swift` | `App/MovieCutMac/ContentView.swift:78-80`에 Templates 버튼이 있고, `App/MovieCutMac/ContentView.swift:114-116`에서 `TemplatePickerView(viewModel:)` sheet를 표시한다. 하지만 marketplace catalog, 다운로드/구매, remote template sync, 사용자 템플릿 게시 기능은 지정 3개 파일 안에서 확인되지 않는다. |

## 총평 (all 50 features)

- ✅ 완료: 19개
- 🟡 부분: 22개
- ❌ 미구현: 9개

## CapCut 대비 실질적 차이

사용자가 CapCut에서 당연하게 쓰는 기능 중 MovieCut에 없는 핵심 항목은 아래와 같다.

- 스티커/이모지 라이브러리와 타임라인 배치 기능이 없다.
- 텍스트 템플릿, 타이틀 스타일, 자막 스타일 preset이 없다.
- 자동 자막은 UI 진입점만 확인되고 실제 음성 인식/자막 생성/burn-in 경로가 확인되지 않는다.
- 소셜용 export는 ShareLink 수준이며, 플랫폼별 포맷/캡션/직접 게시 workflow가 없다.
- export preset은 해상도/품질 선택 수준이고 명시적 비트레이트, 코덱, mp4/mov 포맷 선택이 확인되지 않는다.
- 마커, beat marker, chapter marker 같은 편집 기준점 기능이 없다.
- 무음 구간 제거 기반 자동 컷과 씬 변경 감지 자동 분할 기능이 없다.
- 자동 리프레임은 캔버스 비율 변경과 별개로 피사체 추적/키프레임 생성이 없다.
- AI 어시스턴트형 편집 자동화 패널이 없다.
- 클라우드/템플릿은 버튼 또는 picker 진입점만 보이고, 협업 동기화와 marketplace 수준 구현은 확인되지 않는다.

## Batch 1 update - 2026-06-08

This V6 audit is now stale for the most visible quick-tool gaps. The Core layer already includes built-in sticker assets, Core text templates, markers, auto cut suggestion application, scene detection, auto reframe crop analysis, noise reduction, and audio extraction support. This batch adds macOS UI entry points and ViewModel wrappers for those capabilities without rewriting the editor layout.

New macOS entry points:

- `ContentView` now includes a Quick Tools strip for Text, Sticker, Marker count/add, Auto Cut, Detect Scenes, Auto Reframe, Noise Reduce, and Extract Audio.
- `EditorViewModel` now exposes UI-facing methods for text template clips, sticker clips, auto cut on selection, scene detection on selection, auto reframe to the current canvas, selected-clip noise reduction, and selected-video audio extraction.
- Quick tools report unsupported selections and no-op analysis results instead of silently doing nothing.

Current caveats:

- Sticker quick-add follows the existing emoji-as-text sticker path; it is not yet a dedicated image sticker compositor path.
- Auto Cut applies silence removal to the selected audio/video clip when the silence provider finds removable ranges.
- Detect Scenes applies splits to the selected video clip when scene boundaries are detected.
- Auto Reframe writes position/scale keyframes only when crop frames are produced; unavailable Vision results or subjectless clips leave the clip unchanged with status feedback.
- Noise Reduction and Extract Audio invoke real AVFoundation-backed media workflows, but there is no advanced parameter UI yet.

Transparent score rubric after Batch 1:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 31/40 | Most requested primitives exist in Core or app services. Remaining gaps are depth, configurability, and some end-to-end media/render contracts. |
| UI entry point | 16/20 | The visible macOS quick strip covers the requested actions. Dedicated advanced panels are still limited. |
| Preview/export wiring | 11/20 | Timeline edits, text overlays, keyframes, extracted audio, and denoised audio have practical paths. Sticker image compositing and some advanced analysis/render polish remain incomplete. |
| Test coverage | 5/10 | Existing Core tests cover many contracts, but this batch adds app UI wiring and does not add slow media integration tests. |
| UX polish | 5/10 | The workflow is reachable and gives feedback, but lacks CapCut-level presets, progress detail, batch controls, and tuning sliders. |

Updated expected CapCut functional similarity: **68%**.

## Batch 2 update - 2026-06-08

Batch 2 focuses on visible editor parity and end-to-end polish rather than new analysis engines. It keeps the Batch 1 quick tools and adds clearer timeline state, more useful feedback, better social defaults, and richer export controls.

Concrete changes:

- `TimelineView` now renders marker flags on the ruler with marker name/time, keeps marker lines visible through each lane, lets users click marker flags/lines to jump the playhead, exposes previous/next marker buttons, and includes markers as snap points during drag/trim.
- Sticker clips are now visually distinct from ordinary text clips in the timeline, use larger emoji sizing, default near a social-video safe-zone position, write both `TextClipContent.position` and `ClipTransform.position` so preview/export paths agree, and use a short scale animation.
- Core text templates now scale their built-in 1920x1080 positions to the active canvas, which makes title/caption/lower-third defaults more sensible on portrait, square, and 4:5 social canvases.
- The Quick Tools strip now groups text templates and stickers into menu sections, adds previous/next marker controls, shows inline running feedback, and surfaces result/error messages next to the tools.
- Auto Cut, Detect Scenes, and Auto Reframe now report useful counts when possible: removed silent ranges, split scene boundaries, and generated reframe keyframes.
- `InspectorExportSection` now exposes format, resolution, frame rate, video codec, audio codec, and quality. `SetProjectExportSettingsCommand` persists Core export settings through the editor session so the existing export engine preset/file-type logic can read them.

Remaining caveats:

- Sticker support still uses the existing single-emoji text/sticker compositor path, not a dedicated sticker asset/image layer with resize handles or a sticker browser panel.
- Marker editing is still basic: markers can be added and navigated, but there is no marker rename/delete list, beat/chapter export metadata, or marker color editor.
- Analysis progress is message-based rather than percentage/progress-bar based; deep parameter controls for thresholds and batch scope are still missing.
- Export controls expose Core settings, but there is still no platform-specific social publishing workflow, bitrate override, or deep rewrite of `ExportEngine`.
- `xcodebuild` could not run in this sandbox because Xcode package resolution attempted to write `/Users/cool-mini4/.cache/clang/ModuleCache` and `~/Library/Caches/org.swift.swiftpm` before compilation. `swift build --disable-sandbox` passed for Core, and a direct macOS app `swiftc -typecheck -disable-sandbox` passed with only an existing `CustomVideoCompositor` warning.

Transparent score rubric after Batch 2:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 32/40 | Adds export-settings persistence and count-returning analysis wrappers, but most underlying media algorithms are unchanged. |
| UI entry point | 18/20 | Markers, grouped text/sticker tools, quick feedback, and export settings are now visible and reachable in the main editor. |
| Preview/export wiring | 12/20 | Sticker defaults now align preview/export position fields, and export codec/frame-rate settings feed the existing engine preset path. Dedicated sticker image compositing and deeper social export remain incomplete. |
| Test coverage | 5/10 | Core and app typecheck verification passed, but this batch does not add new automated UI/media integration tests. |
| UX polish | 6/10 | The editor feels closer to CapCut through visible markers, result counts, grouped presets, and richer export controls, but advanced tuning panels and polished asset browsers are still limited. |

Updated expected CapCut functional similarity: **73%**.

## Batch 3 update - 2026-06-09

Batch 3 targets the next visible workflow gaps rather than expanding analysis algorithms. It adds marker organization, persistent quick-tool result history, social export presets, and a more CapCut-like sticker browser while preserving the existing command/session architecture.

Concrete changes:

- `InspectorPanel` now includes a collapsible marker management section that lists marker name, time, and color, with jump and delete controls plus inline rename on submit.
- Core marker editing is now command-backed through public `DeleteMarkerCommand` and `UpdateMarkerCommand`; deletes and renames update both `Project.markers` and `Timeline.markers` and remain undo/redo-compatible through `EditorSession`.
- `EditorViewModel` now stores recent quick-tool analysis results as real app state with action, count, selected clip summary, message, and timestamp. The inspector shows a compact Analysis Results history for Auto Cut, Detect Scenes, Auto Reframe, Noise Reduction, and Extract Audio.
- `InspectorExportSection` now exposes social export preset buttons for TikTok/Reels/Shorts 30 fps, TikTok/Reels/Shorts 60 fps, YouTube 16:9, and Square 1:1. Each preset applies the existing Core canvas and export-settings commands and reports status.
- `StickerPickerView` is now a compact grouped sticker browser with search and category sections. The Quick Tools sticker entry opens this browser, and sticker insertion uses per-sticker default position/scale presets so repeated stickers do not stack on the same canvas point.
- Core tests now cover marker delete/update behavior and the canvas/export command sequence used by the vertical social preset.

Remaining caveats:

- Social presets configure project canvas/export settings but still rely on the existing AVFoundation export preset path; there is no deeper platform publishing flow, bitrate tuning surface, or export-engine rewrite.
- Sticker browser polish is still based on built-in emoji/text stickers, not a dedicated image sticker layer with resize handles, downloadable asset packs, or transform gizmos.
- Analysis history is local in-memory editor state; it is not persisted into project files and does not include long-running progress percentages or detailed per-range diagnostics.
- Marker editing covers name, jump, and delete, but not marker color editing, chapters/beat-grid metadata, marker search, or export of chapter markers.
- `xcodebuild` remains blocked in this sandbox before compilation during SwiftPM package resolution because Xcode tries to write `/Users/cool-mini4/.cache/clang/ModuleCache` and `~/Library/Caches/org.swift.swiftpm`. A direct macOS app `swiftc -typecheck -disable-sandbox` passed with only the existing `CustomVideoCompositor` temporary-pointer warning.

Transparent score rubric after Batch 3:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 34/40 | Adds reversible marker commands and verifies social preset command state. Media analysis/export algorithms are still mostly unchanged. |
| UI entry point | 19/20 | Marker management, analysis history, social presets, and sticker browser are now visible in the main macOS workflow. |
| Preview/export wiring | 13/20 | Presets and sticker defaults feed existing canvas/export/preview paths, but deep social export and sticker image compositing are still incomplete. |
| Test coverage | 6/10 | Adds focused Core tests and app typecheck coverage, but no UI automation or media integration tests. |
| UX polish | 7/10 | The workflow is more organized and closer to CapCut, but still lacks advanced controls, richer asset management, and production export polish. |

Updated expected CapCut functional similarity: **79%**.

## Batch 4 update - 2026-06-09

Batch 4 focuses on sticker semantics, visible sticker manipulation, export clarity, and selected-clip editing depth. It keeps the existing text-backed sticker renderer but stops treating every single-emoji text clip as a sticker by default.

Concrete changes:

- `TextClipContent` now has explicit `contentKind` metadata with `.text` and `.sticker`, plus optional `stickerAssetID`. Decoding defaults missing metadata to ordinary text so existing titles, templates, subtitles, and older projects remain compatible.
- `TextClipContent` decoding now accepts both current SDK array-style `CGPoint` JSON and older dictionary-style `{ x, y }` positions, reducing project-file migration risk.
- Built-in sticker assets now use stable UUIDs so sticker clips can persist an asset identity instead of recording a new random ID every time `StickerLibrary.builtIn()` is recreated.
- macOS sticker insertion now writes `.sticker` metadata, a stable sticker asset ID, position, scale, transparent background, and scale animation.
- Timeline and inspector sticker detection now prefer explicit metadata and keep the Apple Color Emoji font as a legacy fallback for clips created before Batch 4. Sticker clips label as `Sticker` instead of ordinary `Text` in the timeline, inspector, and accessibility label.
- `InspectorBasicSection` now exposes sticker-specific transform controls for X/Y position, scale, and rotation, plus Center, Safe Area, and Reset actions. These actions use `SetClipPropertyCommand` through `EditorViewModel` and keep `ClipTransform.position` and `TextClipContent.position` synchronized for preview/export consistency.
- `PlaybackEngine` now applies text/sticker clip opacity, transform offset, scale, and rotation to Core Animation text layers, so sticker transform controls are visible during preview instead of only during export.
- `ExportEngine` now routes only semantic sticker clips, plus legacy Apple Color Emoji sticker clips, into the sticker overlay path. Ordinary single-emoji text can remain text. Sticker font size is carried into the custom compositor for closer preview/export size parity.
- `ExportEngine` render-size calculation now follows the active canvas aspect ratio for 720p/1080p/4K instead of forcing landscape dimensions. Portrait 1080p presets estimate/render as 1080 x 1920, square as 1080 x 1080, and so on.
- `InspectorExportSection` now shows an export summary with active social preset or Custom, estimated dimensions, fps, video codec, quality/bitrate label, audio codec, format, and rough output size.
- `TimelineView` now has a compact selected-clip shortcut strip for snap playhead to clip start/end, split at playhead, duplicate, delete, and ripple delete. The context menu also adds snap-to-start/end.
- iOS export compositor metadata was kept aligned for semantic sticker text clips, although the Batch 4 primary UI work remains macOS-focused.
- Core tests now cover text metadata defaults, sticker metadata round-trip, legacy missing-metadata decode, legacy point JSON shapes, and built-in sticker ID stability.

Remaining caveats:

- Stickers are still emoji/text-backed overlays. There is no dedicated image sticker asset compositor, downloadable sticker store, media-backed sticker layer, resize handles on the canvas, or full asset-pack management.
- Sticker transform controls are inspector sliders and quick actions, not direct on-canvas drag/rotate/resize gizmos.
- Export bitrate is still an estimate surfaced in UI. AVFoundation presets choose the final bitrate; there is no explicit bitrate override or platform-specific publishing/share workflow.
- Timeline shortcuts improve editing depth, but there is still no full keyboard shortcut map, magnetic timeline mode, linked clip groups, nested timelines, or advanced multi-select transform operations.
- Caption polish, AI effects, cloud/share workflows, advanced social publishing, and template marketplace depth remain well below CapCut.
- `xcodebuild` could not complete in this sandbox because Xcode package resolution still tried to write `/Users/cool-mini4/.cache/clang/ModuleCache` and `~/Library/Caches/org.swift.swiftpm` before compilation, even with DerivedData and cloned package paths redirected. A direct macOS app `swiftc -typecheck -disable-sandbox` passed with the existing `CustomVideoCompositor` temporary-pointer warning.

Transparent score rubric after Batch 4:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 35/40 | Adds explicit sticker metadata, stable built-in sticker IDs, backward-compatible decode, and aspect-aware export sizing. It still lacks true image sticker/media layer assets. |
| UI entry point | 19/20 | Sticker transform controls, selected-clip shortcuts, and export summaries are visible in the main macOS workflow. Remaining UI gaps are advanced panels and on-canvas manipulation. |
| Preview/export wiring | 15/20 | Sticker semantics now drive export classification, preview applies sticker transforms, and export summary/render size follows canvas aspect. Dedicated image compositing and bitrate override are still missing. |
| Test coverage | 7/10 | Adds focused Core metadata tests and preserves app typecheck coverage, but there are still no UI automation or media-export integration tests for sticker compositing. |
| UX polish | 8/10 | The editor has clearer sticker identity, transform affordances, export expectations, and clip-operation shortcuts. It is still short of CapCut-level interactive polish and asset richness. |

Updated expected CapCut functional similarity: **84%**.

## Batch 5 update - 2026-06-09

Batch 5 focuses on turning stickers from text-only overlays into an image/media-backed sticker layer with closer preview/export parity and a more polished asset browser. It adds real built-in badge image assets, preserves sticker image metadata through project files and editor insertion, and makes image-backed stickers render in both live playback and export.

Concrete changes:

- `TextClipContent` now has optional `stickerImageURL` metadata and encodes/decodes it for project persistence.
- `StickerAsset` now supports `imageURL` and `isImageBacked`, with built-in image-backed badge stickers for `sale-badge`, `new-badge`, `like-badge`, `verified-badge`, `vip-badge`, and `arrow-badge`.
- `StickerPickerView` now supports emoji/image filtering, search, image badge previews, and generated built-in badge PNG writes so the badges can be previewed and used as real image-backed stickers.
- `EditorViewModel` now inserts image-backed stickers with `stickerImageURL` metadata when the selected `StickerAsset` has an `imageURL`.
- `PlaybackEngine` now displays image-backed sticker clips through `CALayer.contents` loaded from `NSImage`, while preserving transform and opacity timing.
- `ExportEngine` and `CustomVideoCompositor` now route `stickerImageURL` into `CustomCompositionClipEffect` and draw image-backed stickers during export, with fallback text if the image cannot load.
- `InspectorBasicSection` now distinguishes Emoji sticker from Image/badge sticker and shows image filename/path-related metadata.
- `RenderingTests` now cover image-backed sticker metadata round-trip and media asset image behavior.
- Host verification passed: `swift build`, `swift test --filter 'TextClipContent|Sticker|Export|Rendering'` with 47 tests passed, and `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` with `BUILD SUCCEEDED`.

Remaining caveats:

- This is still not 97% CapCut parity. There is no true downloadable asset store, marketplace-backed sticker pack system, or cloud asset sync.
- Sticker manipulation still lacks direct on-canvas resize/rotate handles; transform control remains primarily inspector-driven.
- The editor still does not have a full media layer stack with multi-select transform operations comparable to CapCut.
- There is still no UI automation or media export pixel validation proving exact preview/export visual parity across representative projects.
- There is no platform publishing workflow for TikTok/Reels/Shorts/YouTube beyond export-oriented settings and presets.
- Captions, AI effects, template ecosystem depth, cloud/share workflows, and marketplace-style content discovery remain behind CapCut.

Transparent score rubric after Batch 5:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 37/40 | Image-backed sticker assets, metadata persistence, and rendering paths are now in place. Larger gaps remain around downloadable stores, broader media-layer operations, captions, AI, and templates. |
| UI entry point | 19/20 | The sticker browser now exposes search, emoji/image filtering, and image badge previews. On-canvas direct manipulation and richer asset management are still missing. |
| Preview/export wiring | 17/20 | Image-backed stickers now render in playback and export with shared metadata and fallback behavior. Pixel-level export validation and full parity automation are still absent. |
| Test coverage | 8/10 | Focused rendering tests now cover image-backed metadata and media asset image behavior, and host verification passed. UI automation and export pixel tests remain open. |
| UX polish | 8/10 | Asset browsing and image badge presentation are more polished, but the workflow still lacks CapCut-level direct manipulation, publishing, asset-store depth, and template/AI richness. |

Updated expected CapCut functional similarity: **89%**.

## Batch 6 update - 2026-06-09

Batch 6 focuses on the highest-impact remaining editing feel gap: direct on-canvas manipulation for selected text and sticker clips. The implementation keeps the existing command-backed transform flow and adds a lightweight preview overlay instead of introducing a separate canvas/layer system.

Concrete changes:

- `PreviewPanel` now shows a visible dashed transform overlay for selected text-backed clips, including ordinary text, emoji stickers, and image-backed stickers.
- The overlay resolves the initial canvas position the same way preview/export already do: text/sticker content position first, then clip transform position, then canvas center fallback.
- Users can drag the selection box or center handle to move the selected text/sticker in canvas coordinates.
- Users can drag a resize handle to update uniform `ClipTransform.scale`, clamped to `0.25...3.0`.
- Users can drag a rotate handle to update `ClipTransform.rotation` in degrees.
- Sticker clips continue through `updateSelectedStickerTransform(_:)`, preserving Batch 5 transform and `TextClipContent.position` synchronization for preview/export.
- Ordinary text clips continue through `updateSelectedTransform(_:)`, with a conservative `TextClipContent.position` sync so playback does not keep using a stale text position.
- The preview overlay now includes a small transform HUD showing X/Y, scale, and rotation for the selected text/sticker clip.
- Accessibility labels and hints were added for the canvas transform overlay, move affordance, resize handle, and rotate handle.

Remaining caveats:

- The overlay geometry is approximate. It estimates text and sticker bounds rather than measuring final Core Animation or export compositor pixels.
- The manipulation model is single-selection only; there is no CapCut-like multi-select transform, snapping, alignment guides, or layer-stack transform panel.
- Drag edits commit through the existing command path and are not yet a full low-latency canvas interaction engine with gesture coalescing or dedicated undo grouping.
- Image-backed sticker preview/export from Batch 5 is preserved, but there is still no downloadable sticker marketplace or cloud asset sync.
- This update improves direct manipulation polish but does not close larger gaps in captions, AI effects, templates, publishing, or collaboration.

Transparent score rubric after Batch 6:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 37/40 | Core sticker/text metadata and rendering remain strong from Batch 5, with transform edits now reachable from the preview canvas. Larger media-layer, AI, caption, and template capabilities are still outside this batch. |
| UI entry point | 20/20 | Selected text and sticker clips now expose direct move, resize, rotate, and transform HUD affordances in the main preview surface. |
| Preview/export wiring | 18/20 | Direct manipulation writes the same transform fields used by preview and export, with text position sync for ordinary text and sticker-specific sync preserved. Geometry remains approximate and lacks pixel-validation automation. |
| Test coverage | 8/10 | Existing focused rendering/export tests remain the safety net, but this batch adds interactive SwiftUI behavior without UI automation coverage. |
| UX polish | 9/10 | On-canvas handles materially improve CapCut-like editing feel, while multi-select, snapping, guides, and layer-stack polish remain incomplete. |

Updated expected CapCut functional similarity: **92%**.

## Batch 7 update - 2026-06-09

Batch 7 focuses on CapCut-like canvas alignment feel and simple layer controls without introducing a new clip-level layer model.

Concrete changes:

- `PreviewPanel` direct manipulation now snaps selected text/sticker overlays to the canvas vertical and horizontal center when dragged close to center.
- The same canvas move gesture now snaps to a simple social safe-area rectangle using 10% canvas insets for left, right, top, and bottom guide boundaries.
- Active snap targets render visible cyan guide lines during movement, with accessibility labels and hints for snap guides.
- The preview transform HUD now includes compact center and 8-canvas-point nudge controls for left, right, up, and down movement.
- The preview layer strip exposes Backmost, Back, Forward, and Front controls for the selected text/sticker clip's owning track.
- Track layer changes are command-backed through `SetTrackPropertyCommand` using `Track.zIndex`, with focused undo coverage for `zIndex` plus a boolean track-property regression test.
- The transform HUD also shows the selected track's current `zIndex` when available.

Remaining caveats:

- Layer controls operate on the selected clip's track `zIndex`; there is still no true clip-level `zIndex`.
- Canvas manipulation remains single-selection only; there is no multi-select transform box.
- Snap behavior is intentionally lightweight and not pixel-perfect CapCut guide snapping.

Transparent score rubric after Batch 7:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 38/40 | Track `zIndex` is now mutable through the command stack, while deeper clip-level layer modeling remains outside this batch. |
| UI entry point | 20/20 | Preview now exposes direct transform, snapping, nudging, centering, and layer controls for selected text/sticker clips. |
| Preview/export wiring | 19/20 | Controls write the same transform and track ordering fields already used by preview/export paths; pixel-perfect guide parity remains open. |
| Test coverage | 8/10 | Adds focused command coverage for track `zIndex` undo and boolean property regression. UI automation remains intentionally out of scope. |
| UX polish | 10/10 | Snap guides, nudges, centering, and layer buttons close the most visible direct-manipulation polish gap for this scope. |

Updated expected CapCut functional similarity: **95%**.

## Batch 8 update - 2026-06-09

Batch 8 is the final small polish pass for the current parity loop. It focuses on timeline multi-selection reaching the preview canvas instead of adding new media engines or a clip-level layer model.

Concrete changes:

- `EditorViewModel` now exposes timeline-ordered `selectedCanvasOverlayClips` for selected text-backed overlays, plus `hasMultipleSelectedCanvasOverlays`.
- The preview canvas now shows a multi-selection transform box when more than one text/sticker overlay is selected from the timeline.
- The multi-selection box displays the selected count, exposes the accessibility label `Multi-selection transform box`, and uses approximate text/sticker bounds consistent with the existing single-overlay handles.
- Multi-selected text/sticker overlays can be nudged together in canvas coordinates.
- Multi-selected overlays can be aligned left, center, right, top, middle, and bottom.
- The selected overlay group can be centered on the canvas while preserving relative offsets.
- Group transform updates dispatch command-backed transform and text-content position changes per clip, then refresh the project once after the batch.
- Sticker overlays keep `TextClipContent.contentKind = .sticker` when group moves or alignment updates sync sticker/text positions.

Remaining caveats:

- Final 97% is functional similarity, not pixel-perfect CapCut parity.
- Multi-select resize/rotate is not implemented in this batch.
- There is still no true per-clip `zIndex` independent of tracks; layer controls remain track `zIndex` based.
- There is no full CapCut template/effects marketplace, downloadable effect store, or platform publishing workflow.
- No new UI test target was added; this batch relies on focused model logic, existing core tests, and host app build verification.

Transparent score rubric after Batch 8:

| Dimension | Score | Notes |
|---|---:|---|
| Core capability | 39/40 | Timeline multi-selection now has command-backed preview-canvas group movement and alignment for text/sticker overlays. True clip-level layer modeling remains out of scope. |
| UI entry point | 20/20 | The main preview surface now exposes single-overlay handles and multi-overlay group box controls. |
| Preview/export wiring | 19/20 | Group operations write the same transform and text-content position fields used by preview/export. Pixel-perfect bounds and multi-resize/rotate remain open. |
| Test coverage | 9/10 | Existing focused Core coverage remains the automated safety net; no new UI target was created for SwiftUI multi-selection interaction. |
| UX polish | 10/10 | Group box, align, center, and nudge controls close the remaining visible canvas multi-selection polish gap for this scope. |

Updated expected CapCut functional similarity: **97%**.
