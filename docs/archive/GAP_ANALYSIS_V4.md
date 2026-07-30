# MovieCut vs CapCut 갭 분석 V4

> **[보관 — 대체됨]** 이 문서는 `docs/archive/`에 있다. 현역이 아니며 갱신되지 않는다. 전체 문서 지도는 [docs/README.md](../README.md).
>
> - 상태: 지정 3개 파일만 읽은 제한 범위 감사다.
> - 지금 볼 곳: 최신 격차 분석은 `docs/GAP_ANALYSIS_V13_FUNC_UI_20260729.md`. 판정 기준은 `docs/CAPCUT_BENCHMARK_STANDARD.md`.

분석 범위는 요청된 3개 파일로 제한했다.

- `App/MovieCutMac/Export/ExportEngine.swift`
- `App/MovieCutMac/Playback/PlaybackEngine.swift`
- `App/MovieCutMac/TimelineView.swift`

상태 기준:

- ✅ 완료: 읽은 파일 안에서 기능 흐름이 직접 구현되어 있음
- 🟡 부분: UI 호출, 렌더링 일부, 데이터 연결 등은 보이나 전체 기능 구현은 확인 불가
- ❌ 미구현: 읽은 파일 안에서 관련 구현을 확인할 수 없음

| # | 기능 | 상태 | 비고 |
|---|------|------|------|
| 1 | 클립 자르기/trim | ✅ 완료 | `TimelineView`의 좌/우 trim gesture가 `sourceRange`와 `timelineRange`를 갱신하고 `trimClip`으로 커밋한다. |
| 2 | 클립 분할/split | 🟡 부분 | 컨텍스트 메뉴에서 `viewModel.splitClip()` 호출은 있으나 실제 분할 로직은 읽은 파일에 없다. |
| 3 | 클립 이동/move | ✅ 완료 | drag gesture로 시작 시간을 갱신하고 `moveClip`으로 커밋한다. |
| 4 | 클립 복사/duplicate | 🟡 부분 | 컨텍스트 메뉴에서 `duplicateClip` 호출만 확인된다. |
| 5 | 클립 삭제 | 🟡 부분 | 컨텍스트 메뉴에서 `deleteClip` 호출만 확인된다. |
| 6 | Ripple delete | 🟡 부분 | 컨텍스트 메뉴에서 `rippleDeleteClip` 호출만 확인된다. |
| 7 | 스냅 (clip edge/playhead) | ✅ 완료 | clip 시작/끝, playhead, 0초를 snap point로 사용하는 `snappedTime`이 move/trim에 적용된다. |
| 8 | 줌 | ✅ 완료 | `timelineZoom`을 버튼으로 20~300 범위에서 조절한다. |
| 9 | 드래그앤드롭 | 🟡 부분 | 파일 URL drop으로 미디어 import는 가능하나, drop 위치 배치나 트랙 간 clip drop은 확인되지 않는다. |
| 10 | 다중 선택 | ❌ 미구현 | 단일 `selectedClipId`만 사용한다. |
| 11 | Undo/Redo | ❌ 미구현 | 읽은 파일에서 undo/redo stack 또는 명령 되돌리기 흐름이 없다. |
| 12 | 볼륨 조절 | ✅ 완료 | playback/export 합성에서 `clip.volume`을 `setVolume`으로 반영한다. |
| 13 | 오디오 페이드 | ❌ 미구현 | `setVolumeRamp` 등 fade in/out 처리 흐름이 없다. |
| 14 | 오디오 덕킹 | ❌ 미구현 | 음성/BGM 우선순위 기반 자동 볼륨 감소 로직이 없다. |
| 15 | 이퀄라이저 | ❌ 미구현 | EQ 필터나 오디오 처리 체인이 없다. |
| 16 | 노이즈 감소 | ❌ 미구현 | 노이즈 분석/감쇄 처리 흐름이 없다. |
| 17 | BGM 라이브러리 | ❌ 미구현 | 내장 음악 라이브러리나 탐색 UI가 없다. |
| 18 | 보이스오버 | ❌ 미구현 | 녹음, 입력 장치, voiceover track 생성 로직이 없다. |
| 19 | 오디오 파형 표시 | ❌ 미구현 | timeline clip은 라벨이 있는 사각형이며 waveform 렌더링이 없다. |
| 20 | 텍스트 오버레이 | ✅ 완료 | text track/clip을 `CATextLayer`로 playback/export video composition에 합성한다. |
| 21 | 자동 자막 | ❌ 미구현 | 음성 인식, 자막 생성, transcript 처리 흐름이 없다. |
| 22 | 텍스트 애니메이션 | ❌ 미구현 | 텍스트 레이어는 정적 표시만 하며 animation key/path가 없다. |
| 23 | 색보정 (밝기/대비/채도) | 🟡 부분 | `clip.colorCorrection`을 custom compositor metadata로 전달하지만 조절 UI와 실제 필드 적용은 읽은 파일에서 확인되지 않는다. |
| 24 | 크로마키 | ❌ 미구현 | chroma key 색상 선택, keying, spill 제거 관련 코드가 없다. |
| 25 | 마스킹 | 🟡 부분 | `clip.mask`를 custom compositor metadata로 전달하지만 mask 편집 UI와 실제 합성 구현은 읽은 파일에서 확인되지 않는다. |
| 26 | 배경 제거 | ❌ 미구현 | 세그멘테이션/배경 제거 처리 흐름이 없다. |
| 27 | 전환 효과 | ❌ 미구현 | clip 사이 transition instruction, crossfade, wipe 등의 로직이 없다. |
| 28 | 속도 조절 | ✅ 완료 | `playbackRate` 0.25~4.0, clip별 time scaling, export speed ramp 처리가 있다. |
| 29 | 역재생 | 🟡 부분 | export에서는 `clip.isReversed`와 `ReverseRenderService`를 사용하지만 playback preview에서는 확인되지 않는다. |
| 30 | 정지프레임 | ❌ 미구현 | frame hold/freeze 생성 또는 duration 확장 로직이 없다. |
| 31 | Export (mp4/mov) | ✅ 완료 | `AVAssetExportSession`을 사용하고 확장자/codec에 따라 mp4, mov, m4v를 선택한다. |
| 32 | Export 진행률 | ✅ 완료 | `activeExportSession.progress`를 polling하여 `exportProgress`에 반영한다. |
| 33 | Export 취소 | ❌ 미구현 | `activeExportSession`은 보관하지만 public cancel API나 `cancelExport()` 호출이 없다. |
| 34 | 소셜 공유 | ❌ 미구현 | 공유 sheet, 플랫폼별 export preset, upload 연동이 없다. |
| 35 | 캔버스 비율 (16:9, 9:16 등) | 🟡 부분 | playback/export render size에 `canvas`/`canvasSize`를 반영하지만 preset 선택 UI는 읽은 파일에 없다. |
| 36 | 키프레임 | ❌ 미구현 | transform/opacity는 정적 값이며 시간별 keyframe 배열이나 보간 로직이 없다. |
| 37 | 클라우드 동기화 | ❌ 미구현 | 원격 저장소, 업로드, 동기화 상태 관리가 없다. |
| 38 | 협업 편집 | ❌ 미구현 | 사용자 세션, 충돌 해결, 실시간 presence/operation sync가 없다. |

## Critical

- Undo/Redo를 우선 도입해야 한다. trim, move, split, delete, duplicate, ripple delete는 파괴적 편집이므로 command history 없이는 실사용 안정성이 낮다.
- Export 취소 API를 추가해야 한다. 현재 진행률은 있지만 사용자가 긴 export를 중단할 수 있는 `cancelExport()` 흐름이 없다.
- 읽은 범위 기준으로 split/delete/duplicate/ripple delete는 UI 호출만 확인된다. 실제 mutation command가 원자적으로 동작하고 undo history에 기록되는지 보장해야 한다.

## High

- Timeline 편집 완성도를 높여야 한다. 다중 선택, 트랙 간 이동, drop 위치 기반 배치, ripple edit 옵션, 선택 영역 삭제가 필요하다.
- 오디오 기본기를 보강해야 한다. fade in/out, waveform 표시, clip gain UI가 있어야 컷 편집 품질을 빠르게 판단할 수 있다.
- preview/export 일관성을 맞춰야 한다. 역재생은 export 경로에서만 확인되므로 playback composition에서도 동일하게 보이도록 맞춰야 한다.
- 색보정과 마스킹은 metadata 연결만으로는 부족하다. 실제 compositor 적용 범위, UI 컨트롤, preview/export parity를 검증해야 한다.

## Medium

- 전환 효과와 키프레임을 추가하면 CapCut 대비 체감 격차가 크게 줄어든다. 우선 opacity/position/scale keyframe과 crossfade부터 시작하는 것이 현실적이다.
- 텍스트 기능은 overlay까지는 가능하지만 animation, 스타일 preset, 자막 워크플로가 없다. 자동 자막 전 단계로 수동 subtitle clip UX를 먼저 정리하는 편이 좋다.
- 캔버스 preset 선택 UI와 safe area guide를 추가해야 한다. 현재 render size 반영은 보이지만 16:9, 9:16, 1:1 같은 편집 UX는 확인되지 않는다.

## Low

- BGM 라이브러리, 보이스오버, 노이즈 감소, EQ, 오디오 덕킹은 기본 컷 편집 이후 확장 기능으로 묶는 것이 적절하다.
- 크로마키와 배경 제거는 별도 비디오 처리 파이프라인이 필요하므로 masking/color correction 기반 compositor가 안정화된 뒤 추가하는 것이 좋다.
- 소셜 공유, 클라우드 동기화, 협업 편집은 로컬 편집/출력 품질이 안정된 뒤 제품 레벨 기능으로 설계하는 것이 맞다.

## Core 레이어 검증 보완

검증 범위는 기존 문서와 아래 Core 5개 파일로 제한했다. ExportEngine/PlaybackEngine 연결 여부는 기존 Part 1 문서 기준으로만 판단했으며, EditorViewModel 직접 호출 여부는 이번 읽기 제한상 확인하지 않았다.

- `Sources/MovieCutCore/Analysis/BackgroundRemovalProvider.swift`
- `Sources/MovieCutCore/Analysis/StyleTransferProvider.swift`
- `Sources/MovieCutCore/Audio/AudioEqualizerService.swift`
- `Sources/MovieCutCore/Cloud/CloudSyncService.swift`
- `Sources/MovieCutCore/Templates/TemplateMarketplace.swift`

| 파일 | REAL vs MOCK/STUB | App 레이어 연결 | 남은 갭 |
|---|---|---|---|
| `BackgroundRemovalProvider.swift` | 🟡 Core 처리는 REAL. Vision `VNGeneratePersonSegmentationRequest`로 person mask를 만들고 `CIBlendWithAlphaMask`로 투명 배경 BGRA pixel buffer를 생성한다. 다만 `analyze(asset:in:)`는 빈 `AnalysisResult`를 반환하므로 분석 provider 경로는 STUB에 가깝다. | 확인 안 됨. Part 1의 ExportEngine/PlaybackEngine 경로에서는 배경 제거 provider 호출이 확인되지 않았고, EditorViewModel은 이번 범위에서 직접 확인하지 않았다. | 프레임 단위 처리 API는 있으나 clip/effect 모델, preview/export compositor 연결, UI 토글, 캐싱/성능 제어가 확인되지 않는다. 사람 세그멘테이션 중심이라 일반 객체/배경 제거 범위도 제한적이다. |
| `StyleTransferProvider.swift` | 🟡 Core 처리는 REAL. Core Image 필터 체인으로 `comic`, `noir`, `vintage`, `cyberpunk`, `watercolor` 스타일을 적용한다. 다만 ML 기반 style transfer는 아니고, `analyze(asset:in:)`는 빈 결과를 반환한다. Core Image가 없을 때 generic `apply`가 입력을 그대로 반환하는 fallback은 STUB 성격이다. | 확인 안 됨. Part 1의 ExportEngine/PlaybackEngine 경로에서는 style provider 호출이 확인되지 않았고, EditorViewModel은 이번 범위에서 직접 확인하지 않았다. | clip별 style 선택/파라미터, preview/export 적용 경로, 스타일 UI, render pipeline parity가 확인되지 않는다. Part 1의 색보정 항목(밝기/대비/채도)과는 별도 기능으로 보는 것이 맞다. |
| `AudioEqualizerService.swift` | ✅ REAL. `AVAudioUnitEQ` 5밴드 preset을 구성하고, 오프라인 파일 렌더링 및 realtime `AVAudioEngine` EQ 경로를 제공한다. AVFoundation 미지원 플랫폼에서는 명시적으로 unavailable error를 던진다. | 확인 안 됨. Part 1의 ExportEngine/PlaybackEngine 경로에서는 EQ service 호출이나 clip audio chain 연결이 확인되지 않았고, EditorViewModel은 이번 범위에서 직접 확인하지 않았다. | EQ 처리 서비스는 있으나 timeline clip gain/effect 모델, export 합성 반영, playback preview 반영, preset 선택 UI, 렌더 진행률/취소 처리가 확인되지 않는다. |
| `CloudSyncService.swift` | ✅ REAL. iCloud Drive가 가능하면 ubiquity container의 Documents/MovieCut에 `.moviecut` 프로젝트를 저장/목록/다운로드하고, 불가능하면 Application Support로 fallback한다. `ProjectStore` 기반 save/load와 간단한 conflict strategy도 있다. | 확인 안 됨. Part 1의 ExportEngine/PlaybackEngine/TimelineView 범위에서는 cloud sync 호출이 확인되지 않았고, EditorViewModel은 이번 범위에서 직접 확인하지 않았다. | 실제 앱 워크플로 연결, 자동 동기화 트리거, 원격 변경 감지, conflict 감지/해결 UI, 계정/권한 상태 표시가 확인되지 않는다. 협업 편집이나 실시간 operation sync는 아니다. |
| `TemplateMarketplace.swift` | 🟡 로컬 카탈로그 기능은 REAL, 원격 marketplace는 STUB/시뮬레이션에 가깝다. built-in template에서 JSON catalog를 생성/로드하고 featured/category/search/download를 제공하지만, `refreshCatalog()`도 로컬 catalog reload/generate만 수행한다. | 확인 안 됨. Part 1의 읽은 App 파일들에서는 template marketplace 호출이 확인되지 않았고, EditorViewModel은 이번 범위에서 직접 확인하지 않았다. | 원격 API, 결제/라이선스, 평점/작성자 검증, template asset 다운로드/cache/versioning, marketplace UI 연결이 확인되지 않는다. |

### Part 1 요약 보정

Core 파일 검증으로 기존 Part 1 상태를 아래처럼 보정한다. 다만 App 레이어 연결이 확인되지 않았으므로 모두 제품 기능 완료가 아니라 부분 구현으로 분류한다.

| 기능 | Part 1 상태 | 보정 상태 | 보정 근거 |
|---|---:|---:|---|
| #15 이퀄라이저 | ❌ 미구현 | 🟡 부분 | `AudioEqualizerService`에 실제 AVAudioUnitEQ 기반 오프라인/realtime 처리 코드가 있다. App 연결은 확인되지 않는다. |
| #26 배경 제거 | ❌ 미구현 | 🟡 부분 | `BackgroundRemovalProvider`에 Vision person segmentation 기반 frame-level 배경 제거 코드가 있다. preview/export/UI 연결은 확인되지 않는다. |
| #37 클라우드 동기화 | ❌ 미구현 | 🟡 부분 | `CloudSyncService`에 iCloud Drive/local fallback 기반 프로젝트 저장, 목록, 다운로드, conflict merge 코드가 있다. 앱 workflow 연결은 확인되지 않는다. |

변경하지 않는 항목:

- #23 색보정은 기존 🟡 부분 유지. `StyleTransferProvider`는 Core Image 스타일 필터이며 Part 1의 밝기/대비/채도 색보정 완료 근거로 보기는 어렵다.
- #38 협업 편집은 기존 ❌ 미구현 유지. `CloudSyncService`의 conflict strategy는 파일 동기화 보조 기능이지 실시간 협업 편집 구현은 아니다.
- Template marketplace는 Part 1 표에 별도 기능 항목이 없으므로 상태 보정 대상이 아니다.

## v4.1 수정 사항 (Critical+High 해결)

1. Export 취소: `cancelExport()` 메서드를 추가하고 `ContentView` Cancel 버튼에서 호출하도록 연결했다.
2. 다중 선택: `selectedClipIds: Set<UUID>`를 추가하고 Cmd+click 토글 선택, 배치 delete/duplicate를 지원한다.
3. 오디오 fade: `PlaybackEngine`과 `ExportEngine`에 `setVolumeRamp`를 적용해 `fadeInDuration`/`fadeOutDuration`을 반영한다.
4. 오디오 파형: `TimelineView`에 Canvas 기반 waveform 오버레이를 추가했다.
5. 역재생 preview: `PlaybackEngine`에서 `ReverseRenderService`로 임시 역재생 에셋을 생성한 뒤 composition에 삽입한다.
6. Undo/Redo: 이미 `EditorSession`에 구현되어 있었다. GAP_V4가 파일 3개만 읽어서 누락한 항목이다.
7. split/delete/duplicate/ripple: 이미 `session.dispatch`로 동작하고 있었다. GAP_V4가 파일 3개만 읽어서 누락한 항목이다.

### v4.1 요약표 보정

기존 표는 보존한다. 아래 표는 v4.1 기준으로 Critical/High 해결 항목만 append-only 방식으로 보정한 요약이다.

| # | 기능 | v4.1 상태 | 비고 |
|---|------|---:|------|
| 2 | 클립 분할/split | ✅ 완료 | `session.dispatch` 경로로 실제 분할 mutation이 동작하는 것으로 확인되어 기존 🟡 부분 판정을 보정한다. |
| 4 | 클립 복사/duplicate | ✅ 완료 | `session.dispatch` 경로로 duplicate가 동작하며, v4.1에서 다중 선택 배치 duplicate도 지원한다. |
| 5 | 클립 삭제 | ✅ 완료 | `session.dispatch` 경로로 delete가 동작하며, v4.1에서 다중 선택 배치 delete도 지원한다. |
| 6 | Ripple delete | ✅ 완료 | `session.dispatch` 경로로 ripple delete가 동작하는 것으로 확인되어 기존 🟡 부분 판정을 보정한다. |
| 10 | 다중 선택 | ✅ 완료 | `selectedClipIds: Set<UUID>`와 Cmd+click 토글 선택을 추가했고 배치 delete/duplicate에 연결했다. |
| 11 | Undo/Redo | ✅ 완료 | `EditorSession`에 이미 구현되어 있었으며, 기존 GAP_V4의 제한된 파일 검토로 누락된 항목이다. |
| 13 | 오디오 페이드 | ✅ 완료 | `PlaybackEngine`/`ExportEngine` 모두 `setVolumeRamp`로 `fadeInDuration`/`fadeOutDuration`을 반영한다. |
| 19 | 오디오 파형 표시 | ✅ 완료 | `TimelineView`에 Canvas 기반 waveform 오버레이를 추가했다. |
| 29 | 역재생 | ✅ 완료 | export 경로뿐 아니라 preview에서도 `ReverseRenderService`로 임시 역재생 에셋을 만들어 composition에 삽입한다. |
| 33 | Export 취소 | ✅ 완료 | `ExportEngine.cancelExport()` API와 `ContentView` Cancel 버튼 연결을 추가했다. |
