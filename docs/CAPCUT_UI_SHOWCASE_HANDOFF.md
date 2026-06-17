# CapCut UI 기능 가시화 — 작업 핸드오프

> 작성일: 2026-06-17 / 기준 브랜치: `feat/core-backend-expansion` / 직전 커밋: `4f8019f`(darken editor shell)
> **이 문서만 읽고 다른 세션에서 바로 착수할 수 있도록 작성됨.** 상위 요구사항/가드레일은 `docs/CAPCUT_UI_PARITY_REQUIREMENTS.md`, 기능 갭은 `docs/GAP_ANALYSIS_V6.md` 참고.

---

## 0. 한 줄 배경

기능은 50개 중 ~40개가 백엔드까지 구현됨. 문제는 **(1) 기능이 좌측 레일/카드가 아니라 타임라인 툴바에 텍스트로 흩어져 안 보이고, (2) 패널이 CapCut보다 너무 밝음**(populated 상태 coarse similarity 0.46, `dark_fill` 좌측 0.28 vs 0.60·인스펙터 0.39 vs 0.96·타임라인 0.38 vs 0.97). 이 작업은 **프레젠테이션만** 바꾼다 — `EditorSession.dispatch`/렌더 파이프라인/ViewModel 메서드는 호출만.

---

## 1. 가드레일 (반드시 준수)

- **아키텍처 불변**: 프레젠테이션 레이어만 변경. Command/Session/렌더 시그니처 변경 금지.
- **IP**: CapCut 아이콘/색/문구 복제 금지 → SF Symbols 매핑·자체 자산.
- **회귀 잠금**: 재배치 후에도 accessibility label/단축키 보존. `*StaticContractTests.swift` 깨지 않기(깨지면 라벨 보존하며 테스트 갱신).
- **Swift 6 strict concurrency** 유지(`SWIFT_STRICT_CONCURRENCY: complete`).

---

## 2. 작업 단위 (P0 → P3, 위에서부터)

### Phase 0 — 기능 가시화 (P0, 최우선)
| ID | 작업 | 파일·앵커 | 수용기준 |
|---|---|---|---|
| 0-1 | 가로 스크롤 pill 탭 → **세로 아이콘 레일**(56–64px 고정), 10탭 상시 노출 | `MediaLibraryPanel.swift:117` `libraryTabBar`, `LibraryTab` enum `:1187`, 좌측 frame `ContentView.swift:13` | 10탭 잘림 없이 노출, 활성탭 강조, drop import 보존 |
| 0-2 | **Smart/AI 탭 신설** — Auto Cut·Detect Scenes·Detect Beats·Auto Reframe·Noise Reduce·Extract Audio를 2열 카드(아이콘+이름+설명+실행)로 | `QuickToolsPanel`(`ContentView.swift:292`)을 `MediaLibraryPanel` 새 탭으로 이전 | 각 기능 카드 노출, 비활성 사유 표시, 기존 `viewModel.run*` 호출만 |
| 0-3 | Effects/Filters/Transitions/Stickers를 **선택 전에도 카드 갤러리 브라우징** | `MediaLibraryPanel.swift:296` `effectsTabContent`~`filtersTabContent`/`transitionsTabContent` | 선택 없어도 카탈로그 노출, 적용만 비활성 힌트 |
| 0-4 | 타임라인 툴바에서 AI 도구 제거 → split/delete/ripple/duplicate/snap/marker/freeze/reverse/zoom만 | `TimelineView.swift:44-78`, `QuickToolsPanel` 사용처 `:67` | 편집 도구만 한 줄, 텍스트 라벨→아이콘+툴팁 |

Progress note (2026-06-17): Phase 0-1 implemented with the 60px library rail and verified by `Phase01LibraryRailStaticContractTests`; Phase 0-2 implemented with Smart tab 2-column cards for Auto Cut, Detect Scenes, Detect Beats, Auto Reframe, Noise Reduce, and Extract Audio, verified by `Phase02SmartToolsStaticContractTests`; Phase 0-3 implemented with browseable Effects/Filters/Transitions/Stickers card galleries before clip selection, visible inactive reasons for clip-required apply cards, and direct sticker cards using `viewModel.addSticker(sticker)`, verified by `Phase03BrowseableCardsStaticContractTests`; Phase 0-4 implemented with an edit-only timeline toolbar for split/delete/ripple/duplicate/snap/marker/freeze/reverse/zoom, no timeline `QuickToolsPanel`, and icon buttons with help/accessibility labels, verified by `Phase04TimelineEditToolbarStaticContractTests`. Phase 0 complete.

### Phase 1 — 다크 셸 정합 (P0/P1)
| ID | 작업 | 파일·앵커 | 수용기준 |
|---|---|---|---|
| 1-1 | 네이티브 macOS 툴바 → 인앱 커스텀 다크 상단 바(또는 `.toolbarBackground` 강제) | `ContentView.swift:39` `.toolbar`, `MovieCutMacApp.swift` | 상단 바 `dark_fill` ≥ 0.9, 단축키/VoiceOver 보존 |
| 1-2 | 인스펙터 기본값 **Export 폼 → 프로젝트/클립 정보 카드**, Export는 우상단 드롭다운에만 | `InspectorPanel.swift`, `Inspector/InspectorExportSection.swift` | 선택 없을 때 폼 대신 정보, 인스펙터 brightness 148→<60 |
| 1-3 | 카드/보더 밀도↓로 dark_fill 상승(elevated 카드 다발→near-flat 행, border opacity↓) | `Inspector/InspectorShared.swift:18` 토큰 + 사용처 | 타임라인/인스펙터 `dark_fill` CapCut ±0.15 |
| 1-4 | 타임라인 트랙/클립 unselected 밝기↓, 룰러·그리드 대비 정리 | `TimelineView.swift:83-93`, 토큰 `trackBackground` | 타임라인 brightness 157→<60 |

Progress note (2026-06-17): Phase 1-1 implemented with native macOS `.toolbarBackground` modifiers forcing `MovieCutTheme.panelBackgroundRaised` visible for `.windowToolbar`; existing toolbar items, VoiceOver markers, and `MovieCutMacApp.swift` command shortcuts remain in place, verified by `Phase11DarkTopToolbarStaticContractTests`. Phase 1-2 implemented with a compact ProjectOverviewInspectorView that replaces the no-selection export form with Project/Canvas/Timeline/Export Summary/Select a clip cards, removes the always-visible inspector export settings section, and keeps export available through the top-right toolbar control, verified by `Phase12InspectorDefaultStaticContractTests`. Phase 1-3 implemented with darker near-flat shared card tokens for inspector/timeline-adjacent surfaces plus reduced divider and border opacity, verified by `Phase13CardDensityStaticContractTests`. Phase 1-4 implemented with darker timeline track/ruler tokens, subtler ruler/grid line drawing, lower unselected clip opacity, and selected clip stroke visibility preserved, verified by `Phase14TimelineDarkFillStaticContractTests`. Phase 1 complete.

### Phase 2 — 인터랙션·폴리시 (P1/P2)
- 2-1 좌측 미디어 빈 상태 → 큰 Import CTA 카드(`MediaLibraryPanel` mediaTabContent).
- 2-2 hover 미리보기 강화(effects/filters 텍스트 affordance → 실제 미리보기).
- 2-3 타임라인 툴바 아이콘 전용 + 일관 툴팁(R6-02).
- 2-4 타이포/간격 토큰 CapCut 밀도 미세조정.

Progress note (2026-06-17): Phase 2-1 implemented with a large Media tab import/drop CTA card, prominent `Import Media` button calling the existing import panel, accepted media hints, and preserved panel-level drop import behavior, verified by `Phase21MediaImportCTAStaticContractTests`. Phase 2-2 implemented with deterministic local visual hover preview swatches for Effects, Filters, Adjustments, and Transitions while preserving click-to-apply behavior, verified by `Phase22HoverVisualPreviewStaticContractTests`. Phase 2-3 implemented with shared compact icon-only timeline toolbar buttons for edit, marker, and zoom actions, localized help, and preserved accessibility labels and hints, verified by `Phase23TimelineToolbarIconOnlyStaticContractTests`. Phase 2-4 implemented with shared `MovieCutTypography` and `MovieCutSpacing.xxSmall` density tokens applied narrowly to panel headers, shared cards, input fields, Media library browser/CTA/card text, and Timeline toolbar/readout text while preserving existing commands and accessibility strings, verified by `Phase24TypographyDensityStaticContractTests`. Phase 2 complete.

### Phase 3 — 심층 (P2/P3, 잔여)
- R3-05 안전영역 토글 · R5-04 메인 트랙 시각 구분 · Speed 곡선 에디터.

---

## 3. 명령어 (복붙용)

```bash
cd /Users/cool-mini4/MyDev/automation/movie_cut

# 0) 프로젝트 재생성 — project.yml 수정 시에만 (UI Swift 파일만 수정하면 불필요)
xcodegen generate

# 1) 빌드 — 주 경로. xcodebuild는 샌드박스에서 캐시 쓰기로 막힌 기록 있어 swift build 우선
swift build

# 2) 포커스 테스트 — UI 정적 계약(라벨/구조 회귀)
swift test --filter StaticContract

# 3) 전체 테스트
swift test

# 4) 앱 타깃 빌드 검증 (샌드박스 밖 / 일반 셸에서)
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build

# 5) 린트 — swiftlint 필요(미설치 시 skip): brew install swiftlint
bash scripts/lint.sh        # 또는: swiftlint lint --strict

# 6) 화이트스페이스/충돌 마커 체크
git diff --check
```

**작업 루프(각 작업 단위마다):** `swift build` → `swift test --filter StaticContract` → `xcodebuild ... MovieCutMac build` → 스크린샷 before/after.

---

## 4. 시각 검증 (지표 왜곡 주의)

- ⚠️ 기존 `vp_loop1` similarity 0.97은 **빈 검은 화면끼리** 비교라 무의미. **반드시 클립이 채워진 populated 상태**로 캡처.
- 증거 디렉터리: `/tmp/moviecut-ui-evidence/`. 캡처: `screencapture -l$(window_id) out.png` 또는 `screencapture -R x,y,w,h out.png`.
- 영역별(`top_bar/left_browser/preview/inspector/timeline`) brightness·`dark_fill`·coarse similarity 측정.
- **목표:** populated mean similarity **0.46 → 0.75+**, 각 영역 `dark_fill` CapCut ±0.15.
- side-by-side 비교/metrics 스크립트는 repo에 없음(ad-hoc) → populated 캡처 기준으로 재작성 필요.

---

## 5. 핵심 파일 맵

| 영역 | 파일 |
|---|---|
| 윈도우/Scene/단축키 | `App/MovieCutMac/MovieCutMacApp.swift` |
| 전체 레이아웃·toolbar | `App/MovieCutMac/ContentView.swift` |
| 좌측 탭 브라우저(`LibraryTab`)·QuickTools 이전 대상 | `App/MovieCutMac/MediaLibraryPanel.swift` |
| 중앙 프리뷰·트랜스포트 | `App/MovieCutMac/PreviewPanel.swift` |
| 우측 인스펙터 | `App/MovieCutMac/InspectorPanel.swift`, `App/MovieCutMac/Inspector/*` |
| Export 패널 | `App/MovieCutMac/Inspector/InspectorExportSection.swift` |
| 타임라인·도구·트랙 | `App/MovieCutMac/TimelineView.swift` |
| 공통 스타일/다크 토큰 | `App/MovieCutMac/Inspector/InspectorShared.swift` (`MovieCutTheme` `:18`) |

---

## 6. 새 세션 부트스트랩 프롬프트 (복붙)

```
docs/CAPCUT_UI_SHOWCASE_HANDOFF.md 를 읽고 Phase 0-1(세로 아이콘 레일 전환)부터 착수해.
프레젠테이션 레이어만 수정(가드레일 §1 준수), 각 작업마다 swift build →
swift test --filter StaticContract → xcodebuild MovieCutMac build 로 검증하고
populated 상태 스크린샷으로 before/after 확인. StaticContract 테스트는 라벨 보존하며 갱신.
```
