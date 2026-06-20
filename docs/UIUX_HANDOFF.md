# UI/UX 개선 핸드오프 — CapCut/OpenCut 수준 사용성

> 작성일: 2026-06-14 / 브랜치: `main` / 작성 근거: 2026-06-14 실기기 GUI 세션 직접 관찰 + 레이아웃 코드 분석
> 이 문서만 읽고 UI/UX 개선 작업을 바로 시작할 수 있도록 작성됨.
> **전제: 기능(F-01~F-24)은 구현·테스트 완료 상태다. 이 작업은 "기능 추가"가 아니라 "레이아웃·시각 계층·사용성"의 프레젠테이션 레이어 개선이다.** 명령/세션/렌더 아키텍처와 기존 테스트를 깨지 말 것.

---

## 0. 한 줄 요약

기능은 다 있는데 **화면이 그 기능들을 못 보여준다.** 창이 최소 크기로 열려 모든 패널이 짜부라지고, Inspector 한 칸에 7~8개 섹션이 쌓여 클립 편집 UI에 접근조차 어렵다. CapCut/OpenCut의 **탭형 라이브러리 + 큰 프리뷰 + 맥락형 속성 패널 + 도구 바가 붙은 타임라인** 구조로 재배치하고, 간격·계층·다크 테마 폴리시를 입히는 것이 핵심이다.

---

## 0.5 Current status addendum (2026-06-20)

- ✅ **IA/menu-position pass complete**: top toolbar는 project/status/view/export chrome에 집중하고 Split/Delete/Add Marker는 timeline-local이다. preview transport는 bottom-docked, timeline header는 Edit/Markers/Quick Tools/Zoom command center다.
- ✅ **P0/P1/P2 polish complete**: `060b0e5` browser/timeline surfaces, `05ca9a5` preview/inspector hierarchy, `a2b86a0` top chrome density가 반영됨.
- ✅ **P3 docs cleanup performed**: CapCut UI docs now record R1-02/R2-04 as complete, Loop 6 as the latest passing visual metric, and older Loop 3/4 evidence as historical.
- 🟡 **Remaining verification backlog**: standard workflow walkthroughs(미디어 추가→컷→텍스트→BGM→Export, 자동 자막→스타일), matching populated side-by-side recapture/metrics after IA/P0/P1/P2, optional iOS sync decision. Do not claim a fresh post-P2 populated recapture until new evidence exists.

---

## 1. Historical baseline layout map (2026-06-14, not current implementation)

This section preserves the original baseline that motivated the UI/UX work. It is **not** the current implementation after the IA/menu-position pass and P0/P1/P2 polish; the separate `QuickToolsPanel` strip and old min-width map below are historical evidence only.

`App/MovieCutMac/ContentView.swift:10-37`
```
VSplitView                                  // 상하 분할
├─ VStack
│  ├─ HSplitView                            // 좌·중·우 3분할
│  │  ├─ MediaLibraryPanel  (minW 200, maxW 300)   // 얇은 좌측 라이브러리
│  │  ├─ PreviewPanel       (minW 400)             // 중앙 프리뷰
│  │  └─ InspectorPanel     (minW 240, maxW 320)   // 우측 인스펙터(과적재)
│  ├─ QuickToolsPanel                        // 별도 빠른도구 스트립
│  └─ statusBar
└─ TimelineView            (minH 210)        // 하단 타임라인
.frame(minWidth: 1024, minHeight: 460)
```
- 윈도우: `App/MovieCutMac/MovieCutMacApp.swift:11` `WindowGroup` — **`.defaultSize`/`.windowResizability` 없음** → 항상 최소 크기(1024×460)로 열림.
- 핵심 뷰 파일: `ContentView.swift`(레이아웃+toolbar+QuickToolsPanel `:206`+statusBar `:179`), `MediaLibraryPanel.swift`, `PreviewPanel.swift`, `InspectorPanel.swift`, `TimelineView.swift`.

---

## 2. 관찰된 문제 (2026-06-14 실기기 세션 + 코드)

| # | 문제 | 근거 |
|---|---|---|
| P1 | **창이 최소 크기로 열림** → 프리뷰만 크고 타임라인·상단 패널이 짜부라짐 | `WindowGroup`에 defaultSize 없음. 실측 시 ~490px 높이로 열려 트랙 3개가 겨우 보임 |
| P2 | **Inspector 1칸 과적재** — Marker/Assistant/Highlights/Analysis/ClipInfo/Transform/Effects/ChromaKey/AutoCut/Reframe/Text/Export가 한 240~320px 컬럼에 세로로 다 쌓임 | `InspectorPanel.swift`. 창이 짧으면 Export 섹션만 보이고 **클립 편집 UI에 접근 불가** |
| P3 | **거버넌스/면책 텍스트가 UI에 노출** — export 섹션에 "Golden status: no single-fixture..." 류 경고 문단이 그대로 보임 | 별도 세션의 `InspectorExportSection` 작업. 사용자 화면에 개발 내부 메모가 노출돼 비전문적으로 보임 |
| P4 | **라이브러리가 얇은 컬럼** — "Drop media files here"가 구석에 작게. CapCut식 탭형 브라우저(Media/Audio/Text/Sticker/Effect/Transition/Filter) 부재 | `MediaLibraryPanel.swift` (Library/Media/Stickers/Music/SFX 탭은 있으나 좁고 비중 낮음) |
| P5 | **도구가 흩어짐** — QuickToolsPanel(별도 스트립) + 타임라인 헤더 도구 + 컨텍스트 메뉴로 분산. CapCut은 타임라인 위 단일 도구 바에 집약 | `ContentView.swift:206` QuickToolsPanel |
| P6 | **시각 계층·간격 부족** — 섹션 구분이 약하고 여백이 좁아 밀도가 높음. 다크 테마 폴리시(카드/구분선/아이콘+레이블) 약함 | 전반 |
| P7 | **빈 상태/온보딩 부재** — 새 프로젝트 시 "무엇부터 할지" 안내 없음. CapCut은 큰 "미디어 추가" CTA | `PreviewPanel`/`MediaLibraryPanel` empty state 미약 |

---

## 3. 레퍼런스: CapCut / OpenCut 레이아웃 관례

**CapCut 데스크탑**
- 좌상단: **탭형 브라우저** (Media / Audio / Text / Stickers / Effects / Transitions / Filters / Captions …) — 콘텐츠 소스의 중심
- 중앙상단: **큰 프리뷰** + 하단 트랜스포트(재생/프레임이동/타임코드) + 비율·해상도 표시
- 우상단: **맥락형 속성 인스펙터** — 선택 대상에 따라 내용이 통째로 바뀜(비디오 조정 / 오디오 / 텍스트 스타일 / 애니메이션)
- 하단: **풀폭 타임라인** + 그 위 **도구 바**(분할/삭제/크롭/미러/프리즈/속도/되돌리기/줌/자석)
- 우상단 코너: **Export** 단일 버튼

**OpenCut(오픈소스 웹 에디터)**
- 좌측 탭 사이드바(Media/Text/Audio/Stickers/Effects) → 중앙 프리뷰 → 우측 속성 → 하단 타임라인
- 미니멀·넓은 여백·모던 다크 테마, 드래그가 1급 인터랙션

**공통 원칙(우리가 가져올 것)**: ① 콘텐츠는 탭형 브라우저로, ② 속성은 선택 맥락에 따라 바뀌는 단일 패널로, ③ 도구는 타임라인 위 한 줄로 집약, ④ 넉넉한 여백·명확한 구분·아이콘+레이블.

### IA/menu-position pass (2026-06-19)

- top toolbar no longer owns clip editing: Split/Delete/Add Marker는 macOS 상단 toolbar가 아니라 timeline-local command로 고정한다.
- preview transport is bottom-docked: Current/Duration, playback, safe-zone, zoom, volume은 preview 하단 overlay/strip에 두어 canvas 중심성을 유지한다.
- timeline is the edit command center: Edit, Markers, Quick Tools, Zoom cluster가 timeline header에서 split/delete/ripple/duplicate/snap/freeze/reverse/marker 흐름을 담당한다.

---

## 4. UX 백로그 (우선순위순)

상태: ❌ 미착수 / 🟡 부분
각 항목: **목표 → 구현 힌트(파일) → 수용 기준(AC)**. 기능 배선·명령·테스트를 깨지 않는 선에서 프레젠테이션만 변경.

### Tier 0 — 즉시 효과 (quick wins, 반나절~1일)

#### UX-01. 적절한 기본 창 크기 + 리사이즈 정책 — 🟡 다른 세션이 구현(미커밋, 2026-06-14)  **(가장 큰 체감 개선)**
- **목표**: 앱이 충분히 큰 크기(예 1440×900)로 열리고, 모든 패널이 처음부터 보인다.
- **구현**: `MovieCutMacApp.swift` `WindowGroup { … }`에 `.defaultSize(width: 1440, height: 900)` + `.windowResizability(.contentSize)`. `ContentView` minHeight를 720 이상으로.
- **AC**: 새로 실행 시 라이브러리·프리뷰·인스펙터·타임라인이 모두 즉시 보이고, 타임라인 트랙 3개 + 클립 섬네일이 잘림 없이 보인다.

#### UX-02. 거버넌스/면책 텍스트를 사용자 UI에서 제거 ✅ 구현(2026-06-16)
- **목표**: export 패널의 개발 내부 경고 문단("Golden status…", "Do not claim…")을 사용자 화면에서 없앤다.
- **구현**: `App/MovieCutMac/Inspector/InspectorExportSection.swift`의 export-golden 거버넌스 문단, 관련 helper property, visible/accessibility copy를 제거. export summary와 picker/custom bitrate 접근성은 포맷/해상도/프레임레이트/코덱/품질/예상 크기/비트레이트 중심의 사용자용 문구로 유지. `Tests/MovieCutCoreTests/ExportFormatStaticContractTests.swift`는 금지 문자열 부재와 사용자용 export control 보존을 검사하도록 갱신. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(145 tests / 38 suites), `xcodebuild ... MovieCutMac build` BUILD SUCCEEDED.
- **AC**: export 패널에 사용자용 정보(포맷/해상도/예상 크기)만 남고 개발 메모가 안 보인다.

#### UX-03. Inspector를 "맥락형 단일 패널"로 정리 — ✅ 구현(2026-06-14)
- **목표**: 선택이 없으면 빈 안내, 클립 선택 시 그 클립 속성만, 비선택 전역 도구(Marker/Highlights/Assistant/Analysis)는 별도 탭/디스클로저로 접어 기본 숨김.
- **구현**: `InspectorPanel.swift` — 전역 섹션(Marker/Assistant/Highlights/Analysis)을 상단 작은 탭 또는 `DisclosureGroup(isExpanded: false)` 기본 접힘으로. 클립 선택 시 `InspectorBasicSection`/`InspectorEffectsSection`이 최상단에 오도록 순서 변경. Export는 항상 하단 고정 유지.
- **AC**: 클립 선택 즉시 Transform/Effects/색보정 등이 스크롤 없이 보인다(현재는 Export에 묻힘).
- **구현 완료(2026-06-14)**: `InspectorPanel.swift` — 클립 선택 시 `InspectorBasicSection`/`InspectorEffectsSection`/`InspectorAnalysisSection`을 **최상단**에 배치하고, 전역 도구(Marker/Assistant/Highlights/Analysis)는 `projectToolsSections`로 묶어 "Project Tools" `DisclosureGroup`(기본 접힘)으로 이동. 비선택 시엔 전역 도구를 펼쳐 보여줌. 헤더도 선택 맥락에 따라 "Inspector"↔"Clip"으로 전환. Export는 하단 고정 유지. 빌드·static-contract 테스트 통과. (참고: UX-01 창 크기는 다른 세션이 미커밋으로 적용 중 → 클립 편집 UI가 처음부터 넉넉히 보임.)

### Tier 1 — 구조 개선 (2~4일)

#### UX-04. 탭형 라이브러리/브라우저 (CapCut식) ✅ 구현(2026-06-15)
- **목표**: 좌측을 Media/Audio/Text/Stickers/Effects/Transitions/Filters 탭 브라우저로 격상, 폭 확대(320~380).
- **구현**: `MediaLibraryPanel.swift`의 기존 탭(Library/Media/Stickers/Music/SFX)을 확장 — Text/Effects/Transitions/Filters 탭 추가(이미 ViewModel에 텍스트 템플릿/효과/전환 추가 메서드 존재). 각 탭에서 드래그 또는 더블클릭으로 타임라인에 추가.
- **AC**: 한 곳에서 모든 콘텐츠 소스를 탐색·추가할 수 있다. 드래그 인터랙션 유지.
- **구현 완료(2026-06-15)**: `MediaLibraryPanel.swift` — 브라우저 탭을 **Media / Audio / Text / Stickers / Effects / Transitions / Filters** 7개로 재구성. Media의 import/drop/asset drag/Add to Timeline 유지, Audio는 Music+SFX를 한 탭에 그룹화, Text는 Custom Text + `TextTemplate.builtIn` 템플릿 추가, Stickers는 기존 `StickerPickerView` 유지, Effects/Filters/Transitions는 선택 클립에 기존 `updateSelectedEffects`/`updateSelectedTransition` 경로로 적용하고 비선택 시 select-clip empty state 표시. `ContentView.swift`의 좌측 브라우저 폭을 320~380으로 확대. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(127 tests PASS), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.

#### UX-05. 타임라인 위 단일 도구 바 ✅ 구현(2026-06-15)
- **목표**: 분할/삭제/리플삭제/복제/줌/마커/자석/스냅을 타임라인 바로 위 한 줄 아이콘 바로 집약. QuickToolsPanel의 분석 도구(Auto Cut/Detect Scenes/Reframe/Beat 등)도 이 바 또는 라이브러리 탭으로 이동.
- **구현**: `TimelineView.swift` 헤더 영역 확장 + `ContentView.swift:206` `QuickToolsPanel` 통합/이동. 기존 `selectedClipToolbar`(TimelineView)와 합치기.
- **AC**: 편집 도구가 타임라인 근처 한 줄에 모이고, 흩어진 스트립이 사라진다.
- **구현 완료(2026-06-15)**: `ContentView.swift`의 별도 Quick Tools 스트립을 제거하고, `TimelineView.swift` 헤더를 **Timeline / Edit / Quick Tools / Zoom** 단일 행으로 재구성. 기존 selected clip 도구(스냅 시작/끝, Split, Duplicate, layer front/back, Delete, Ripple Delete), QuickToolsPanel 분석 도구(Auto Cut, Detect Scenes, Detect Beats, Clear Beats, Auto Reframe, Noise Reduce, Extract Audio), Marker 컨트롤, Zoom 컨트롤을 타임라인 바로 위로 통합. 기존 ViewModel/Command/렌더 경로는 변경하지 않고 UI 호출 위치만 이동. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(135 tests PASS), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.

#### UX-06. 프리뷰 영역 폴리시 ✅ 구현(2026-06-15)
- **목표**: 큰 프리뷰 + 하단 트랜스포트 정돈(타임코드/재생/프레임/볼륨/비율). 빈 상태에 "미디어 추가" CTA.
- **구현**: `PreviewPanel.swift` — 컨트롤 바 간격·정렬 정리, empty state에 큰 import 버튼(드롭 영역과 연결).
- **AC**: 프리뷰가 시각적 중심이 되고, 빈 상태에서 다음 행동이 명확하다.
- **구현 완료(2026-06-15)**: `PreviewPanel.swift` — 빈 프리뷰 상태를 아이콘/설명/`Import Media` CTA가 있는 centered empty state로 교체하고, CTA는 `NSOpenPanel`→`viewModel.importMedia(_:)` 기존 import 경로에 연결. 하단 트랜스포트는 Current/Duration timecode badge, 중앙 frame-back/play/frame-forward capsule, canvas ratio label, volume slider로 정돈. 선택된 클립 overlay/playback wiring은 유지. 검증: `git diff --check`, `swift build`, `swift test --filter StaticContract`(135 tests PASS), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED.

### Tier 2 — 시각 폴리시 (지속)

#### UX-07. 디자인 토큰·간격·다크 테마 통일 ✅ 구현(2026-06-16)
- **목표**: 섹션 카드, 일관된 패딩(8/12/16), 구분선, 아이콘+레이블, 색/타이포 스케일 통일.
- **구현**: 공통 스타일 헬퍼(예 `InspectorShared.swift` 확장)로 섹션 헤더/카드 컴포넌트화. 하드코딩 spacing 정리.
- **AC**: 패널 간 시각 언어가 일관되고 밀도가 CapCut 수준으로 쾌적.
- **구현 완료(2026-06-16)**: `App/MovieCutMac/Inspector/InspectorShared.swift`에 `MovieCutSpacing`(4/8/12/16), `MovieCutRadius`, `MovieCutTheme`, `MovieCutPanelHeader`, `MovieCutSectionCard`, `movieCutCard`/panel background helper를 추가. `InspectorPanel.swift`는 헤더/스크롤 섹션/Project Tools/Export를 카드·토큰 기반으로 정리했고, `MediaLibraryPanel.swift`는 Library 헤더, 탭, 브라우저 액션 row, empty state, audio 섹션, asset row를 같은 토큰으로 통일. `TimelineView.swift`는 타임라인 헤더/구분선/track surface/clip radius를 토큰화했고, `ContentView.swift`는 status bar와 Quick Tools spacing/background/divider를 통일. `PreviewPanel.swift`의 UX-06 Import Media CTA/transport behavior는 변경하지 않음. 검증: `git diff --check` PASS, `swift build` PASS, `swift test --filter StaticContract` PASS(135 tests / 36 suites), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED. 스크린샷 캡처는 `/tmp/moviecut-ui-evidence/ux07_design_tokens.png`로 시도했으나 현재 macOS 캡처 환경이 검은 프레임만 반환해 시각 AC는 코드/빌드 검증과 별도 경계로 둠.

#### UX-08. 접근성·키보드 유지 ✅ 구현(2026-06-16)
- **목표**: 재배치하면서 기존 accessibilityLabel/Value/Hint와 F-05 단축키가 유지되도록.
- **AC**: VoiceOver 레이블 보존, 단축키 동작 유지.
- **구현 완료(2026-06-16)**: `TimelineView.swift`의 선택 클립 도구바 아이콘 버튼(Snap start/end, Split, Duplicate, layer front/back, Delete, Ripple Delete)에 명시적 `accessibilityLabel`/`accessibilityHint`를 추가해 UX-05/07 재배치 이후에도 VoiceOver가 이미지 이름에 의존하지 않도록 보강. `Tests/MovieCutCoreTests/UIUXAccessibilityRegressionStaticContractTests.swift`를 추가해 `MovieCutMacApp.swift`의 F-05 `CommandMenu("Playback")`/`CommandMenu("Timeline")` 및 주요 shortcut marker, `PreviewPanel.swift`의 Preview/timecode/transport/canvas ratio/volume/import 접근성 marker, `MediaLibraryPanel.swift`의 Library/import/text/tabs/Add to Timeline/asset metadata 접근성 marker, `TimelineView.swift`의 timeline/track/drop/selected toolbar/zoom/clip trim marker, `InspectorPanel.swift`/`InspectorShared.swift`의 Inspector/Clip/Project Tools/Markers/AI Assistant/Auto Highlights/Analysis Results 섹션 label marker를 정적 계약으로 고정. 검증: `git diff --check` PASS, `swift build` PASS, `swift test --filter StaticContract` PASS(141 tests / 37 suites), `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build` BUILD SUCCEEDED. VoiceOver 실기기 리딩·스크린샷 검증은 별도 검증 범위로 두며, 여기서는 라이브 VoiceOver 또는 화면 캡처 증거를 주장하지 않음.

---

## 5. 규칙 (반드시 지킬 것)

- **프레젠테이션만 변경**: ViewModel 메서드·`EditorSession.dispatch(Command)`·렌더 파이프라인은 그대로. UI는 기존 메서드를 호출만.
- **기존 테스트 깨지 마라**: static-contract 테스트가 특정 문자열/구조를 검사한다. 뷰를 옮길 때 깨지면 테스트도 같이 갱신(단, 의미 보존). `swift test` + `xcodebuild … MovieCutMac build`로 매번 확인.
- **R4-03/UX-02 완료**: `InspectorExportSection.swift`/`ExportFormatStaticContractTests.swift`의 export-golden 거버넌스 copy 제거와 정적계약 갱신은 2026-06-16에 완료됨.
- **iOS 동기화는 선택**: 이 UX 작업은 macOS 우선. iOS(`App/MovieCutiOS/`)는 별도.
- **작은 작업 단위**: 남은 verification/scope-decision 항목을 하나씩 처리하고, 각 항목 후 빌드/스크린샷/evidence 경로를 남긴다.

---

## 6. 현재 권장 작업 순서

1. **Matching populated recapture/metrics** — IA/P0/P1/P2 이후 MovieCut과 CapCut을 가능한 같은 상태(video+audio+text selected)로 다시 캡처하고 Loop 6 기준을 재확인한다.
2. **Standard workflow walkthroughs** — 미디어 추가→컷→텍스트→BGM→Export, 자동 자막→스타일을 실제 앱에서 완주하고 docs/evidence 경로를 남긴다.
3. **Optional scope decisions** — R2-01 9탭 확장/Captions·Adjust depth와 iOS sync 여부를 product decision으로 분리한다.

## 7. 빌드·검증

```bash
swift build
swift test --filter 'StaticContract'   # 뷰 구조 검사 테스트
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
open ~/Library/Developer/Xcode/DerivedData/MovieCut-*/Build/Products/Debug/MovieCutMac.app
```

## 8. 핵심 파일 맵 (UI)
| 영역 | 파일 |
|---|---|
| 윈도우/Scene/메뉴/단축키 | `App/MovieCutMac/MovieCutMacApp.swift` |
| 전체 레이아웃·toolbar·QuickTools·statusBar | `App/MovieCutMac/ContentView.swift` |
| 좌측 라이브러리(탭) | `App/MovieCutMac/MediaLibraryPanel.swift` |
| 중앙 프리뷰·트랜스포트·오버레이 | `App/MovieCutMac/PreviewPanel.swift` |
| 우측 인스펙터(섹션 집합) | `App/MovieCutMac/InspectorPanel.swift`, `App/MovieCutMac/Inspector/*` |
| 타임라인·트랙·도구 | `App/MovieCutMac/TimelineView.swift` |
| 공통 스타일/표시명 | `App/MovieCutMac/Inspector/InspectorShared.swift` |
