# CA-06 접근성 핵심 경로 매트릭스 (2026-08-24)

> 방향 문서 §3 v1.1 **P0-D** 네 번째(마지막) 항목. 범위(Q6 확정): **핵심 경로
> 임포트→편집→출력**, VoiceOver + 키보드. 방법: 코드 실사(파일:라인 근거) + 기존 계약
> (UX-08 StaticContract 5종, HomeRoutingUITests) 대조. 전수 접근성 감사가 아니라 핵심
> 경로 판정이 목적이다.

## 1. 매트릭스 — Mac 핵심 경로

범례: ✅ 충족 · ⚠️ 부분(결함 등록) · ❌ 차단

| 단계 | 표면 | VoiceOver | 키보드 | 근거 |
|---|---|---|---|---|
| 진입 | 홈/에디터 라우팅 | ✅ 홈 UI 라벨 | ✅ 메뉴 | `HomeRoutingUITests`(하니스 우회 경로 포함) |
| 임포트 | 파일 피커·라이브러리 | ✅ Import 버튼 라벨+힌트, 에셋 그리드 라벨/값(`MediaLibraryPanel` UX-08 계약) | ✅ ⌘⇧I 메뉴 | `MovieCutMacApp.swift:103`, UX-08 media-library 계약 |
| 임포트 | 빈 라이브러리 상태 | ✅ 스켈리톤 카드 VO 숨김 | — | `mediaEmptyGridRhythm.accessibilityHidden(true)`(`MediaLibraryPanel.swift:1216`) |
| 임포트 | 타임라인 배치 | ✅ Add to Timeline 버튼(드래그 이외 경로) | ✅ 버튼 포커스 | UX-08 계약 `"Adds the selected library asset to the timeline."` |
| 편집 | 프리뷰 컨트롤 | ✅ 재생/탐색/볼륨/캔버스 라벨·값·힌트(UX-08 preview 계약 21개 마커) + 타임코드 필드 독립 탐색(CA-27) | ✅ Space·←→·⇧←→·↑↓·J/K/L | `MovieCutMacApp.swift:169-233`(43개 keyboardShortcut) |
| 편집 | 타임라인 | ✅ 타임라인 컨테이너 라벨, 클립 라벨+값, 편집 도구·마커 컨트롤 그룹(63개 a11y 지점) | ✅ 도구 버튼 + NSEvent 시프트 선택 | `TimelineView.swift:177-497,1033` |
| 편집 | 인스펙터 | ✅ 섹션 제목 계약(UX-08 inspector) · ⚠️ 세그먼트 Picker 라벨 접힘(이번 수정) | ✅ 세그먼트 컨트롤 | `InspectorPanel.swift:107` → `.labelsHidden()` 적용(CA-06) |
| 편집 | 실행취소/클립보드 | — | ✅ ⌘Z/⇧⌘Z/⌘C/⌘X/⌘V | `MovieCutMacApp.swift:123-159` |
| 출력 | 익스포트 시작 | ✅ 메뉴·버튼 | ✅ ⌘E | `MovieCutMacApp.swift:116` |
| 출력 | 진행률·취소 | ✅ ProgressView 접근성 값(%), Cancel 버튼+도움말 | ✅ 버튼 | `ContentView.swift:804-821` |
| 출력 | 결과·오류 상태 | ✅ 상태 바 `moviecut.status` 식별자 + 메시지 | — | `ContentView.swift:479` |
| 실패 경로 | 오토회복 경고·미디어 누락·익스포트 거부 | ✅ 경고 라벨·상태 메시지(CA-05 매트릭스 참조) | — | BUG-01 경고 배너, BUG-04 사전검사 메시지 |

## 2. 매트릭스 — iOS 핵심 경로

| 단계 | 표면 | VoiceOver | 근거 |
|---|---|---|---|
| 임포트 | PhotosPicker(시스템 컨트롤) | ✅ 시스템 제공 | `iOSContentView` PhotosPickerItem |
| 편집 | 캔버스·핵심 컨트롤 | ✅ 11개 라벨(`iOSContentView`) | — |
| 편집 | 캔버스 설정·키프레임 | ⚠️ 2·6개 라벨만 | `IOSCanvasSettingsView`·`IOSKeyframeEditorView` |
| 편집 | 인스펙터 하위 뷰 | ❌ **자막·필터·크로마키·효과·어시스턴트 라벨 0건** | `IOSAutoSubtitlesView`·`IOSFilterPickerView`·`IOSChromaKeyView`·`IOSEffectsInspectorView`·`IOSAutoAssistantView` |
| 출력 | 진행 시트 | ✅ 진행률 라벨+값+힌트·취소 라벨+힌트 확인(A11Y-02 해소 — 구현 이미 존재) | `iOSContentView.swift` `IOSExportProgressSheet` |

## 3. 차단·결함 등록

### A11Y-01 (P1, iOS 차단급) — iOS 인스펙터 하위 뷰 VoiceOver 라벨 전무

- 위치: `IOSAutoSubtitlesView`·`IOSFilterPickerView`·`IOSChromaKeyView`·`IOSEffectsInspectorView`·`IOSAutoAssistantView` — `accessibilityLabel` 0건. iOS에서 편집 핵심 경로의 조정 화면들이 VoiceOver로 조작 불가능.
- 수정: 각 뷰 컨트롤에 영어 키 라벨+값(기존 Mac UX-08 패턴 준용) + 계약 테스트.

### A11Y-02 (P2) — iOS 익스포트 진행 시트 접근성 값 미검증

- `IOSExportProgressSheet`의 진행률 텍스트/취소 버튼에 접근성 값·라벨 부재 확인 필요. 수정 시 A11Y-01과 함께 처리.

### A11Y-03 (P3) — 빈 라이브러리 스켈리톤 카드의 시각적 신뢰감

- VO에는 숨겨져 정상(`accessibilityHidden`)이나 외부 리뷰 지적대로 로딩/깨진 자산처럼 보임 — 시각 UX 부채(기능 아님). 빈 상태 안내 카드로 교체 권장.

### 이번 증분 수정 (매트릭스 반영)

- **인스펙터 세그먼트 Picker 라벨 접힘 해소** — `InspectorPanel.swift` 하위 탭 Picker에 `.labelsHidden()` 적용(시각적 접힘 제거, VoiceOver 라벨 유지). 외부 리뷰 지적 2건 중 1건.

## 4. 결론

- **Mac 핵심 경로(임포트→편집→출력): VoiceOver·키보드 모두 충족** — UX-08 계약 5종 + 43개 메뉴 단축키 + CA-05 실패 경로 표면화가 뒷받침. 차단 결함 없음.
- **iOS: 편집 조정 화면이 차단(A11Y-01, P1)** — 임포트/기본 컨트롤은 충족하나 인스펙터 하위 뷰 라벨 전무. iOS 자원 배분(20-30%)을 고려해 P1으로 등록, Mac 우선 정책과 정합.
- 재검증: A11Y-01/02 수정 시 매트릭스 해당 행 갱신. 전수 감사(비핵심 경로 포함)는 본 매트릭스 범위 외.
