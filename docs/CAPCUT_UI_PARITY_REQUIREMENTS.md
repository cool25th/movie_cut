# CapCut UI 유사도 — 요구사항 & 작업 가이드

> **[상태: 대체됨 — 역사 기록]** 현역 문서가 아니다. 전체 문서 지도는 [docs/README.md](README.md).
>
> - 판정 근거: "CapCut 유사도(similarity ≥ 0.75)" 지표가 폐기됐다 — 능가가 목표인데 유사도를 재는 것은 모순이라는 2026-06-24 결정.
> - 지금 볼 곳: 현행 UI 기준은 `docs/UI_DESIGN_PRINCIPLES.md`, UI 작업 단위는 `docs/CAPCUT_SURPASS_SPEC_20260703.md` §5 (U-ID).
> - `docs/archive/`로 옮기지 않은 이유: StaticContract 테스트가 이 경로를 직접 읽는다(경로를 바꾸면 테스트가 깨진다).

> 작성일: 2026-06-16 / 기준 브랜치: `feat/core-backend-expansion` / 관련 커밋: `a4d6116`(CapCut-style UI layout overhaul), `1f42054`(UI polish/accessibility guard), `77daf7d`(R1-01), `79cbba3`(R4-01), `f24a45d`(R4-03/UX-02)
> **이 문서만 읽고 다른 세션에서 바로 작업을 시작할 수 있도록 작성됨.** UX 백로그 원본은 `docs/UIUX_HANDOFF.md`, 기능 명세는 `docs/CAPCUT_PARITY_SPEC.md` 참고.
> **전제: 기능(F-01~F-24)과 백엔드는 구현 완료 상태다. 이 작업은 "기능 추가"가 아니라 CapCut 데스크탑 UI에 맞춘 "구조·인터랙션·시각" 프레젠테이션 정렬이다.** 명령/세션/렌더 아키텍처와 기존 테스트를 깨지 말 것.

---

## 0. 목표 — "유사도"를 3계층으로 정의

| 계층 | 의미 | 판정 |
|---|---|---|
| **구조(IA)** | 화면 영역 배치·패널 구성 | 영역 인벤토리 일치 |
| **인터랙션** | 드래그/더블클릭/hover/스냅/단축키 | 표준 워크플로 완주 |
| **시각(폴리시)** | 다크 팔레트·간격·타이포·아이콘·밀도 | 디자인 토큰 체크 |

**원칙**: 픽셀 카피가 아니라 **패턴 재현**.

**가드레일**
- **IP**: CapCut 독점 아이콘/로고/정확한 색/에셋/문구 복제 금지 → 자체·라이선스 자산, SF Symbols 매핑.
- **네이티브 우선**: SwiftUI 네이티브 컨트롤로 CapCut 패턴 재현(웹/Electron 모방 X). macOS 타이틀바/스플릿뷰는 유지.
- **아키텍처 불변**: 프레젠테이션만 변경. `EditorSession.dispatch(Command)`·렌더 파이프라인·ViewModel 메서드는 호출만.

---

## 1. 현재 상태 스냅샷 (이미 된 것 / 남은 것)

**최근 UI 커밋까지 이미 반영됨 — 중복 작업 금지:**
- ✅ 좌측 **탭형 브라우저 7종**: Media/Audio/Text/Stickers/Effects/Transitions/Filters (`MediaLibraryPanel.swift` `LibraryTab`), 라이브러리→타임라인 `onDrag` 존재.
- ✅ **창 기본 크기/리사이즈**: `MovieCutMacApp.swift` `.defaultSize(1440×900)` + `.windowResizability`.
- ✅ **상단 단일 Export**(R1-01): `ContentView.swift` toolbar의 단일 `ControlGroup`(Export + 포맷 ▾), Share는 export 결과 후 드롭다운 내부 노출.
- ✅ **프리뷰 빈 상태 CTA + 트랜스포트 기본 정돈**(R3-04/UX-06): `PreviewPanel.swift` empty state의 `Import Media` CTA가 `NSOpenPanel`→`viewModel.importMedia(_:)` 경로로 연결됨.
- ✅ **타임라인 단일 도구 바 집약**(R5-01/UX-05): `TimelineView.swift` 상단 한 줄에 Timeline/Edit/Quick Tools/Zoom이 모였고 split/delete/ripple/duplicate/snap/marker/freeze/reverse/quick tools가 노출됨.
- ✅ **타임라인 줌 슬라이더 + Fit**(R5-02): `TimelineView.swift` `zoomControls`가 +/- 버튼, 연속 `Slider`, 현재 px/s 표시, Fit Timeline 버튼을 한 줄에 노출.
- ✅ **인스펙터 clip-first + 선택종류별 패널 스왑**(R4-01): 선택 시 `clip.kind`에 따라 audio/text/visual 인스펙터 컨텍스트 분기, 전역도구 `DisclosureGroup` 접힘(`InspectorPanel.swift`).
- ✅ **인스펙터 서브탭**(R4-02): 비디오/이미지 선택 시 `InspectorSubtab` Basic/Speed/Animation/Adjustment/Mask 세그먼트로 Basic/Speed/Adjustment/Mask/Animation 섹션 전환. Speed 서브탭은 constant speed와 Speed Curve editor를 함께 노출.
- ✅ **디자인 토큰·접근성 정적 계약**(UX-07/UX-08): `MovieCutSpacing`/`MovieCutRadius`/`MovieCutTheme`/카드·헤더 헬퍼와 `UIUXAccessibilityRegressionStaticContractTests.swift` 반영.

**핵심 상태:**
- ✅ **export 거버넌스 텍스트 제거**(R4-03/UX-02, 2026-06-16): `InspectorExportSection.swift` export summary는 포맷/해상도/코덱/품질/예상 크기/비트레이트 정보만 노출.
- ✅ 상단 바 **프로젝트명·저장상태**(R1-02, 2026-06-16): principal toolbar가 프로젝트명과 save/autosave 상태를 표시한다.
- ✅ 라이브러리 **탭별 검색·썸네일 그리드**(R2-02/R2-03, 2026-06-16): `MediaLibraryPanel.swift`에 탭명 기반 검색 placeholder, Media/Text/Effects/Transitions/Filters 필터, 2열 card/grid 브라우저가 반영됨.
- ✅ 라이브러리 **hover 미리듣기/미리보기**(R2-04, 2026-06-17): Music/SFX hover-to-listen과 Effects/Filters/Transitions visual hover preview surface가 구현됨.
- ✅ 인스펙터 **서브탭**(Basic/Speed/Animation/Adjustment/Mask) + **Speed 곡선 에디터**(presets/add/reset/point edit).
- ✅ 타임라인 **단일 도구 바 완성**(R5-01) + **줌 slider/fit**(R5-02) + **트랙 헤더 토글**(R5-03) + **메인 비디오 트랙 시각 구분**(R5-04): freeze/reverse가 타임라인 바에 승격됐고, zoomControls에 연속 slider와 Fit Timeline이 추가됐으며, 트랙 헤더에 잠금·숨김·음소거 토글과 첫 `.video` 트랙의 Main 배지/액센트가 연결됨.
- ✅ **구조 IA/menu-position fixed**(2026-06-19): top toolbar는 project/status/view/export chrome에 집중하고 Split/Delete/Add Marker는 timeline-local이다. preview transport는 bottom-docked, timeline header는 Edit/Markers/Quick Tools/Zoom command center다.
- ✅ **P0/P1/P2 polish implemented**: browser/timeline polish(P0), preview/inspector hierarchy polish(P1), top chrome micro-density polish(P2)가 반영됨. 관련 커밋: `060b0e5`, `05ca9a5`, `a2b86a0`.
- ✅ **Visual metric latest pass**: Loop 6 populated/text-selected metrics passed at `/tmp/moviecut-ui-evidence/current-loop/resume-20260619-004321/metrics_capcut_vs_moviecut_loop6_text_selected.json` with mean subregion similarity **0.7528 >= 0.75** and worst `dark_fill` delta **0.0850 <= 0.15**.
- 🟡 **검증 backlog**: IA/P0/P1/P2 이후의 matching populated side-by-side recapture/metrics, 표준 워크플로 walkthrough(미디어 추가→컷→텍스트→BGM→Export, 자동 자막→스타일), optional iOS sync decision은 아직 별도 검증 항목이다. Loop 6 metric은 최신 passing evidence지만, P2 이후 fresh populated recapture를 주장하지 않는다.

**IA/menu-position pass (2026-06-19):** top toolbar no longer owns clip editing; Split/Delete/Add Marker are timeline-local. preview transport is bottom-docked near the timeline boundary. timeline is the edit command center with Edit, Markers, Quick Tools, and Zoom clusters.

---

## 2. 요구사항 도출 방법론 (반복 가능한 7단계)

1. **레퍼런스 캡처 + UI 표면 인벤토리** — CapCut 데스크탑을 상태별(선택없음/비디오/오디오/텍스트/재생중)로 스크린샷, 보이는 컨트롤 전수 라벨링 → `영역 × 상태` 매트릭스.
2. **정보구조(IA) 분해** — 5영역 고정(R1 상단 바 / R2 좌측 브라우저 / R3 중앙 프리뷰 / R4 우측 인스펙터 / R5 하단 타임라인+도구바).
3. **인터랙션 명세** — 드래그드롭·더블클릭/＋추가·hover 미리보기·컨텍스트 메뉴·선택 모델·스냅·단축키.
4. **갭 매핑** — 컴포넌트별 ✅/🟡/❌ + 근거(파일:라인).
5. **시각 토큰화** — 다크 팔레트·spacing(4/8/12/16)·타이포·아이콘셋·패널 비율·구분선·밀도.
6. **수용기준(AC)** — 각 항목에 측정 가능한 AC.
7. **우선순위·검증** — P0 구조 → P1 인터랙션 → P2 시각 → P3 심층. side-by-side + 워크플로 완주.

**요구사항 항목 형식**
```
[R<영역>-NN] 목표 | 현재(✅/🟡/❌) | 구현 힌트(파일) | AC | 우선순위
```

---

## 3. 요구사항 (R1~R6)

### R1. 상단 바 — `App/MovieCutMac/ContentView.swift`(toolbar)
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R1-01 | 우상단 **단일 Export**(주 버튼 + ▾ 포맷) | ✅ 구현(2026-06-16): 단일 `ControlGroup`(Export + 포맷 ▾), Share는 export 결과 후 드롭다운 내부 노출. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(141 tests / 37 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. 스크린샷: `/tmp/moviecut-ui-evidence/r1-01_single_export.png`, crop `/tmp/moviecut-ui-evidence/r1-01_single_export_toolbar_crop.png` | 주 Export 1개 + 드롭다운에 포맷, Share는 결과 후 노출 | P0 |
| R1-02 | 프로젝트명 + **저장상태** 인디케이터 | ✅ 구현(2026-06-16, Codex R1-02): `ContentView.swift` principal toolbar가 프로젝트명과 저장 상태(`projectDisplayName`, `projectSaveStatusLabel`, `projectSaveStatusSystemImage`)를 표시하고 accessibility label/value/hint를 제공. `EditorViewModel.swift` read-only presentation properties만 추가했으며 save/autosave persistence semantics는 변경 없음. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(168 tests / 43 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 타이틀 영역에 프로젝트명, "저장됨/저장 중" 표시 | P1 |
| R1-03 | 비율/해상도 배지 | ✅ 구현(2026-06-16, Codex R1-03/R3-03): `EditorViewModel.swift` read-only badge helpers가 현재 캔버스 비율과 `ExportPlanner().renderSize(for:canvas:)` 기반 export render size를 `16:9 · 1920×1080` 형태로 제공. `ContentView.swift` toolbar Canvas controls 옆 compact capsule badge가 ratio/resolution과 accessibility label/value/hint를 표시하며 export/render semantics 변경 없음. 검증: `git diff --check`, `swift test --filter StaticContract`(181 tests / 46 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 현재 캔버스 비율 + export 해상도 한눈에 | P2 |
| R1-04 | undo/redo 좌측 클러스터 | ✅ | 유지 | — |

### R2. 좌측 탭 브라우저 — `App/MovieCutMac/MediaLibraryPanel.swift`
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R2-01 | 탭 7종 + Captions/Adjustment 보강 | ✅ 7탭(`LibraryTab`) | 9탭, 활성탭 강조 | P2 |
| R2-02 | 탭별 검색바 | ✅ 구현(2026-06-16, Codex R2-02/R2-03): `MediaLibraryPanel.swift`에 `librarySearchText`와 selected tab 기반 `Search Media`/`Search Audio` placeholder 검색장을 추가. Media는 파일명·종류·duration/metadata/proxy/thumbnail 상태, Text는 custom action·template name/subtitle, Effects/Filters는 displayName/subtitle, Transitions는 displayName/subtitle/category로 필터한다. Audio/Stickers는 기존 `MusicLibraryView`/`SFXPickerView`/`StickerPickerView` 내부 검색 API를 깨지 않도록 유지하고 top-level 검색 입력 시 embedded search 안내만 표시. 검증: `git diff --check`, `swift test --filter StaticContract`(173 tests / 44 suites), `swift build`, `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 각 탭 상단 검색 → 그리드 필터 | P1 |
| R2-03 | 썸네일 그리드 | ✅ 구현(2026-06-16, Codex R2-02/R2-03): Media/Text/Effects/Filters/Transitions가 `LazyVGrid(columns: libraryGridColumns)` 기반 compact 2열 card surface를 사용한다. Media card는 큰 16:9 thumbnail/icon, metadata, thumbnail/proxy state, select/onDrag/context proxy action을 유지하고, browser action cards는 기존 add/apply actions를 그대로 호출한다. 검증: `git diff --check`, `swift test --filter StaticContract`(173 tests / 44 suites), `swift build`, `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 2~3열 그리드 썸네일/아이콘 | P1 |
| R2-04 | hover 미리듣기/미리보기 | ✅ 구현(2026-06-17, Codex R2-04): Music/SFX rows/cards reuse existing `AVAudioPlayer` preview infrastructure for hover-to-listen while preserving manual preview toggle and Add actions. Effects/Filters/Transitions cards show a compact hover preview affordance (`Preview effect/filter/transition`) only; click apply behavior remains unchanged and render/export/core semantics 변경 없음. 검증: `git diff --check`, `swift test --filter StaticContract`. | 오디오 hover 재생, 효과/전환 hover 미리보기 | P1 |
| R2-05 | 드래그 **또는** ＋/더블클릭 추가 | ✅ 구현(2026-06-16, Codex R2-05): Media card는 기존 single-select/onDrag/`assetDragProvider(for:)`/proxy context를 유지하면서 더블클릭과 per-card ＋ 버튼이 `selectedAssetId` 설정 후 `addClipToTimeline()`을 호출한다. Text/Effects/Filters/Transitions card는 기존 click add/apply 동작과 ＋ affordance/accessibility hint를 유지한다. 검증: `git diff --check`, `swift test --filter StaticContract`(177 tests / 45 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 드래그 드롭 + 더블클릭/＋ 둘 다 동작 | P1 |

### R3. 중앙 프리뷰 — `App/MovieCutMac/PreviewPanel.swift`
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R3-01 | 트랜스포트 정렬 + 타임코드(현재/전체) | ✅ 구현(2026-06-16, Codex R3-01/R3-02): `PreviewPanel.swift` transport가 Current/Duration `mm:ss:ff` badge와 frame back/play/frame forward capsule을 유지하고, preview canvas/export badge·zoom·volume controls를 같은 adaptive transport bar에 정렬. 기존 Current/Duration/Playback/frame/play-pause accessibility label/hint 유지. 검증: `git diff --check`, `swift test --filter StaticContract`(185 tests / 47 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | `mm:ss:ff` 현재/전체, 재생/프레임 이동 정렬 | P1 |
| R3-02 | zoom-to-fit + 줌 | ✅ 구현(2026-06-16, Codex R3-01/R3-02): `PreviewPanel.swift`에 `previewZoom`/`isPreviewZoomFit` presentation state, `Fit Preview` reset, `Text(previewZoomDisplay)` percentage readout, +/- buttons, `Slider(value:)` zoom control을 추가. selected preview surface는 `.aspectRatio(canvasAspectRatio, contentMode: .fit)`를 유지하고 `.scaleEffect(previewZoom)`만 적용해 export/render/canvas semantics를 변경하지 않음. 검증: `git diff --check`, `swift test --filter StaticContract`(185 tests / 47 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | fit 버튼 + 줌 배율 표시 | P2 |
| R3-03 | 비율/해상도 배지 | ✅ 구현(2026-06-16, Codex R1-03/R3-03): `PreviewPanel.swift` transport bar의 ratio-only label을 preview canvas/export resolution badge로 확장. Current/Duration/playback/frame/volume controls는 유지하고, badge는 `viewModel.canvasResolutionBadgeText`와 accessibility label/value/hint로 캔버스 비율 및 계산된 export render size를 표시. R3-05는 별도 행에서 구현 상태를 추적. 검증: `git diff --check`, `swift test --filter StaticContract`(181 tests / 46 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 캔버스 비율·해상도 표시 | P2 |
| R3-04 | **빈 상태 CTA** | ✅ 구현(2026-06-15, UX-06): `PreviewPanel.swift` empty state에 `Import Media` CTA가 있고 `openImportPanel()`→`viewModel.importMedia(urls)` 기존 import 경로로 연결. 검증: UIUX_HANDOFF UX-06의 `git diff --check`, `swift build`, `swift test --filter StaticContract`(135 tests PASS), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. 스크린샷: `/tmp/moviecut-ui-evidence/ux06_preview_policy_final.png`, 최근 빈 상태 증거 `/tmp/moviecut-ui-evidence/r4-01_inspector_context_empty.png`, `/tmp/moviecut-ui-evidence/r1-01_single_export_verify2.png` | 미디어 없을 때 "미디어 추가" 큰 버튼 + 기존 import 경로 연결 | P0 |
| R3-05 | 안전영역 토글 | ✅ 구현(2026-06-17, Codex R3-05): `PreviewPanel.swift` transport bar에 compact safe-zone toggle을 추가하고, enabled 상태에서 fitted preview canvas overlay가 `SafeZoneGuide.standard` Title Safe/Action Safe rectangles와 subtle labels를 `guide.insets`/`guide.colorHex` 기반으로 그림. Overlay는 `.aspectRatio(canvasAspectRatio, contentMode: .fit)` 뒤의 `previewOverlay(for:)`에 포함되고 `.allowsHitTesting(false)`로 기존 clip placeholder/reframe/chroma key/mask/multi-selection/text transform overlays와 render/export/playback/session semantics 변경 없음. | on/off 토글 노출 | P3 |

### R4. 우측 인스펙터 — `App/MovieCutMac/InspectorPanel.swift`, `Inspector/*`
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R4-01 | **선택종류별 패널 스왑** | ✅ 구현(2026-06-16): `InspectorPanel.swift`가 `clip.kind`로 `InspectorBasicMode.audio`/`.text`/`.visual` 컨텍스트를 선택. 오디오는 Volume/Fade Duration/Equalizer/Noise Reduction 중심, 텍스트는 Style 중심, 비디오/이미지는 Transform/Adjust/Effects/Analysis 카드 유지. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(145 tests / 38 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED | 오디오→Volume/Fade/Denoise만, 텍스트→Style만, 비디오→Transform/Adjust/Effects | P0 |
| R4-02 | **서브탭**(Basic/Speed/Animation/Adjustment/Mask) | ✅ 구현(2026-06-16): `InspectorSubtab` Basic/Speed/Animation/Adjustment/Mask 세그먼트가 비디오/이미지 선택 클립에만 노출되고, `InspectorBasicMode.speed` 및 `InspectorEffectsMode.adjustment`/`.mask`/`.animation`으로 기존 섹션을 전환. 오디오/텍스트는 R4-01 컨텍스트별 표면 유지. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(151 tests / 39 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED | 상단 세그먼트 탭으로 서브섹션 전환 | P1 |
| R4-03 | **거버넌스 텍스트 제거(UX-02)** | ✅ 구현(2026-06-16): `InspectorExportSection.swift` export summary의 export-golden 거버넌스 문단/접근성 copy/helper 제거. `ExportFormatStaticContractTests.swift`는 금지 문자열 부재와 사용자용 export controls 유지 계약으로 갱신. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(145 tests / 38 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED | export 패널에 사용자 정보만(포맷/해상도/예상크기), 개발 메모 `#if DEBUG`/제거 | P0 |
| R4-04 | 전역도구 접힘 + Export 하단 고정 | ✅ | 유지 | — |
| R4-05 | **서브탭 깊이: Speed 곡선 에디터** | ✅ 구현(2026-06-18, Codex Phase 3-3): `InspectorBasicSection.swift`의 기존 constant speed slider/presets 아래에 Speed Curve editor를 추가. `SpeedCurvePreset` 기반 Ease In/Ease Out/Flash presets, Add/Reset, normalized time/rate sliders, point delete(최소 유효 곡선 크기 초과 시), accessibility label/hint/value를 제공한다. 모든 편집은 presentation helper가 `SpeedRampPoint`를 clamp/sort한 뒤 기존 `EditorViewModel.updateSelectedSpeedRampPoints(_:)`만 호출하며 `SpeedRampCurve`/export/playback/command/model semantics 변경 없음. Optical-flow smooth slow motion은 별도 기능 backlog로 유지. | Speed 서브탭에서 곡선 point 실편집 | P3 |

### R5. 하단 타임라인 + 도구 바 — `App/MovieCutMac/TimelineView.swift`
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R5-01 | **단일 도구 바 집약** | ✅ 구현(2026-06-16, Codex R5-01): `TimelineView.swift` 헤더 한 줄에 Timeline/Edit/Quick Tools/Zoom이 있고 split/delete/ripple/duplicate/snap start·end/marker/text/sticker/auto tools/zoom에 Reverse Selected Clip/Freeze Selected Frame 버튼이 추가됨. Reverse는 `updateSelectedReversePlayback(!selectedClip.isReversed)`, Freeze는 `freezeSelectedFrame()` 기존 ViewModel 경로만 호출하며 visual clip 선택에만 활성화. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(155 tests / 40 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 룰러 바로 위 한 줄에 split/delete/ripple/duplicate/freeze/reverse/snap/마커 | P0 |
| R5-02 | 줌 슬라이더 + fit | ✅ 구현(2026-06-16, Codex R5-02): `TimelineView.swift` `zoomControls`에 +/- 버튼, `Slider(value:` 기반 연속 줌, 현재 px/s 표시, `Fit Timeline` 버튼이 함께 노출됨. Fit은 실제 타임라인 viewport 폭을 `GeometryReader`로 읽어 `visibleTimelineDuration` 기준 px/s를 계산하고 20...300으로 clamp하는 presentation helper만 사용. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(160 tests / 41 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 연속 줌 슬라이더 + fit | P1 |
| R5-03 | 트랙 헤더(잠금/숨김/음소거) | ✅ 구현(2026-06-16, Codex R5-03): `TimelineView.swift` 트랙 헤더가 `speaker/speaker.slash`, `eye/eye.slash`, `lock/lock.open` 3개 borderless `Button`을 노출하고 각 버튼은 `EditorViewModel`의 `toggleTrackMute(_:)`/`toggleTrackHidden(_:)`/`toggleTrackLock(_:)`를 호출. ViewModel은 기존 `SetTrackPropertyCommand`의 `.isMuted`, `.isHidden`, `.isLocked`만 사용. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(164 tests / 42 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED. | 트랙별 잠금·숨김·음소거 토글 3종 | P1 |
| R5-04 | 메인 비디오 트랙 개념 | ✅ 구현(2026-06-17, Codex R5-04): `TimelineView.swift`가 첫 `.video` 트랙을 `mainVideoTrackId`/`isMainVideoTrack(_:)`로 판정하고, 해당 헤더에 compact `Main` 배지와 subtle header/lane accent를 표시. Lane/header 장식은 `.allowsHitTesting(false)`로 drop/edit/marker/grid/playhead/selection 상호작용을 막지 않으며, `trackHeaderAccessibilityLabel(for:)`가 main video track을 언급. Presentation-only로 track ordering/model/import/export/playback/session semantics 변경 없음. 검증: `git diff --check`, `swift build --disable-sandbox`, `swift test --filter StaticContract --disable-sandbox`; `xcodebuild ... MovieCutMac build`는 sandbox cache write 제한으로 package resolution 전 차단됨 | 메인 트랙 시각 구분 | P3 |

### R6. 횡단(cross-cutting)
| ID | 목표 | 현재 | AC | P |
|---|---|---|---|---|
| R6-01 | 디자인 토큰(다크 팔레트/spacing/타이포/아이콘+레이블) | ✅ UX-07 + Loop 6 visual metric pass: `InspectorShared.swift`의 dark semantic tokens, preview matte/scaffold, selected inspector row flattening, P0/P1/P2 polish가 누적된 latest passing evidence는 `/tmp/moviecut-ui-evidence/current-loop/resume-20260619-004321/metrics_capcut_vs_moviecut_loop6_text_selected.json`이며 mean subregion similarity **0.7528 >= 0.75**, worst `dark_fill` delta **0.0850 <= 0.15**. Historical note: Loop 3/4 blockers(mean 0.6746, worst dark_fill 0.1996, preview_center 0.488, right_inspector 0.624)는 resolved metric history로만 취급한다. | 공통 스타일 헬퍼(`Inspector/InspectorShared.swift` 확장)로 카드/헤더/간격 통일. P2 이후 matching populated recapture는 별도 verification backlog. | P2 |
| R6-02 | 인터랙션 컨벤션 통일 | ✅ IA/P0/P1/P2 pass implemented for current macOS editor surfaces; drag/double-click/hover/snap/toolbar command ownership is statically covered. 표준 워크플로 walkthrough는 verification backlog로 남김. | 드래그/더블클릭/컨텍스트/스냅 동작 일관 | P2 |
| R6-03 | 단축키·VoiceOver 회귀 방지 | ✅ 구현(2026-06-16, UX-08): 타임라인 선택 클립 도구 accessibility label/hint 보강, `UIUXAccessibilityRegressionStaticContractTests.swift`로 Playback/Timeline command menu, Preview/Library/Timeline/Inspector 주요 label marker 고정 | 재배치 후 라벨/단축키 보존(정적계약 테스트로 잠금) | — |

---

## 4. 우선순위 로드맵
- **P0 완료** — R1-01, R3-04, R4-01, R4-03, R5-01.
- **P0 잔여** — 없음.
- **P1 완료** — R1-02, R2-02, R2-03, R2-04, R2-05, R3-01, R4-02, R5-02, R5-03.
- **P1 인터랙션 잔여** — 없음.
- **P2 완료** — R1-03, R3-02, R3-03, R6-01 visual metric parity pass, R6-02 macOS interaction convention pass.
- **P2 선택 backlog** — R2-01 9탭 확장과 Captions/Adjust panel depth는 product decision 후 진행(현재 7탭+Captions/Adjust visual parity가 충분한지 판단 필요).
- **P3 완료** — R5-04, R4 서브탭 깊이(Speed 곡선 에디터).
- **P3 심층 잔여** — 없음(이번 UI 로드맵 기준; optical-flow smooth slow motion은 별도 기능 backlog).
- **Verification backlog** — matching populated side-by-side recapture/metrics after IA/P0/P1/P2, standard workflow walkthroughs(미디어 추가→컷→텍스트→BGM→Export, 자동 자막→스타일), optional iOS sync decision. 현재 문서는 P2 이후 fresh populated recapture를 완료했다고 주장하지 않음.

---

## 5. 작업 방법 (how to work)

### 5.1 착수 순서
1. 이 문서 + `docs/UIUX_HANDOFF.md` 읽기 → §1 현재 상태 스냅샷으로 중복 방지.
2. 남은 **verification backlog**부터 하나씩: matching populated recapture/metrics, 표준 workflow walkthrough, optional iOS/R2-01 scope decision.
3. 변경 후 빌드/테스트/증거 경로를 남기고, fresh populated recapture 없이는 post-P2 visual 완료를 주장하지 않는다.

### 5.2 핵심 파일 맵
| 영역 | 파일 |
|---|---|
| 윈도우/Scene/단축키 | `App/MovieCutMac/MovieCutMacApp.swift` |
| 전체 레이아웃·toolbar | `App/MovieCutMac/ContentView.swift` |
| 좌측 탭 브라우저 | `App/MovieCutMac/MediaLibraryPanel.swift` (`LibraryTab`) |
| 중앙 프리뷰·트랜스포트 | `App/MovieCutMac/PreviewPanel.swift` |
| 우측 인스펙터 | `App/MovieCutMac/InspectorPanel.swift`, `App/MovieCutMac/Inspector/*` |
| export 패널(거버넌스 제거) | `App/MovieCutMac/Inspector/InspectorExportSection.swift` |
| 타임라인·도구·트랙 | `App/MovieCutMac/TimelineView.swift` |
| 공통 스타일/토큰 | `App/MovieCutMac/Inspector/InspectorShared.swift` |

### 5.3 빌드·검증 명령
```bash
swift build
swift test --filter 'StaticContract'   # 뷰 구조 검사 테스트(재배치 시 함께 갱신)
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/MovieCut-*/Build/Products/Debug/MovieCutMac.app
```

### 5.4 규칙 (반드시)
- **프레젠테이션만 변경**: ViewModel 메서드·`EditorSession.dispatch(Command)`·렌더 파이프라인은 호출만.
- **정적계약 테스트 동기화**: `Tests/MovieCutCoreTests/*StaticContractTests.swift`가 특정 문자열/구조를 검사. 뷰 이동 시 의미 보존하며 테스트도 갱신.
- **작은 PR 단위**: 항목(R*-NN) 하나씩 커밋. 커밋은 `feat:`/`refactor:` conventional 형식, **attribution 미포함**(전역 git-workflow 규칙).
- **R4-03(거버넌스 텍스트 제거) 완료**: `InspectorExportSection.swift`의 export-golden 거버넌스 copy를 제거했고, `ExportFormatStaticContractTests.swift`는 사용자-facing export summary/control 계약과 금지 문자열 부재를 검사하도록 갱신됨.

### 5.5 검증 체크리스트 (DoD)
- [ ] side-by-side 스크린샷(CapCut vs 앱) — 영역·상태별
- [ ] 표준 워크플로 완주: ① 미디어 추가→컷→텍스트→BGM→Export ② 자동 자막→스타일
- [ ] `swift test --filter 'StaticContract'` + `xcodebuild … build` 통과
- [ ] VoiceOver 라벨·F-05 단축키 보존

---

## 6. 비고
- macOS 우선. iOS(`App/MovieCutiOS/`)는 별도 후속.
- `docs/UIUX_HANDOFF.md`의 UX-01~08과 본 문서 R1~R6은 대응 관계(예: UX-02 ↔ R4-03, UX-04 ↔ R2, UX-05 ↔ R5, UX-06 ↔ R3). 본 문서가 CapCut 영역 기준의 상세판이다.
