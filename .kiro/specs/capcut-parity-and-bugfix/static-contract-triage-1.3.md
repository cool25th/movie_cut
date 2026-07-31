# 깨지는 StaticContract 건별 판정 기록 — 작업 1.3

요구사항 1.1 / 15.1 / 15.2 대응. `design.md` §4.1(깨지는 테스트를 요구사항 1 안에서 처리)과 §4.11(⚠️ 블랭킷 제거 금지 — 건별 사유 기록)의 규율을 따른다.

- 측정 시각: 2026-07-31 (작업 1.3 세션)
- HEAD: `9f720d59cd996d127f02fa3cecc72c0e9b96b179` (커밋 없음. 작업 0.2 / 1.1 / 1.2의 미커밋 변경 위에서 작업)
- 비교 기준선: `baseline.md` = **테스트 1044 / 스위트 169 / 실패 0**

---

## 1. 착수 시점의 red 상태 (직접 실행 출력)

```
$ swift test
✘ Test run with 1044 tests in 169 suites failed after 9.347 seconds with 16 issues.
```

실패한 테스트 함수 **8건 / issue 16건**. 16건 전부 한국어 문자열 단언이다.

`Tests/` 아래 한글 포함 라인은 총 211건이지만, **App 소스를 대상으로 하는 한국어 단언은 이 16건이 전부다.** 근거: 작업 1.2 이후 `grep -rn '[가-힣]' App/MovieCutMac --include='*.swift' | wc -l` = **0**. 즉 App 소스에 한글 리터럴이 남아 있지 않으므로 App 소스를 읽는 한국어 단언은 더 있을 수 없다. 나머지 한글 라인은 `docs/` 산문 단언(작업 8.1 범위)과 한국어 주석·테스트 이름이다.

---

## 2. 판정 원칙

세 가지가 이 16건의 판정을 결정했다.

1. **새 영어 리터럴로 다시 못 박지 않는다.** 요구사항 15.6이 새 StaticContract 추가를 금지하고, `design.md` §6이 "소스 문자열 존재 검사는 어느 항목에서도 수용 기준이 아니다"라고 못 박았다. 한국어 리터럴을 영어 리터럴로 치환하면 같은 종류의 부채를 재생산한다.
2. **삭제는 단언 단위로 한다.** 파일·테스트 함수 단위 삭제 없음. 같은 함수의 비한국어 단언은 전부 보존했다.
3. **접근성 회귀 방지 목적이면 XCUITest로 승격한다.** 승격 대상은 `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`(신규) 한 곳으로 모았다.

---

## 3. 건별 판정표 (16건)

`판정` 열: **삭제** = 결함 고정/문자열 trivia라 제거, **삭제+승격** = 제거하되 의도를 XCUITest에 옮김.

| # | 파일 : 라인(착수 시점) | 단언 | 판정 | 근거 (한 줄) |
|---|---|---|---|---|
| 1 | `UIUXAccessibilityRegressionStaticContractTests.swift:116` | `accessibilityLabel(NSLocalizedString("타임라인", …))` | 삭제+승격 | 타임라인 루트가 레이블 있는 접근성 컨테이너여야 한다는 의도는 유효하나, 소스 리터럴은 결함 자체였다 → 런타임 레이블 확인으로 대체. |
| 2 | `UIUXAccessibilityRegressionStaticContractTests.swift:118` | `accessibilityLabel(String(format: NSLocalizedString("%@ 클립 추가 영역", …), …))` | 삭제+승격 | 트랙 레인 드롭 영역이 트랙 헤더 레이블에서 파생된 레이블을 갖는다는 의도 → 런타임에서 파생 관계(`포함`)로 확인. |
| 3 | `UIUXAccessibilityRegressionStaticContractTests.swift:150` | `accessibilityLabel: "타임라인 축소"` | 삭제+승격 | 아이콘 전용 버튼은 접근성 레이블이 유일한 낭독 수단 → 런타임에서 비어 있지 않고 확대 버튼과 다름을 확인. |
| 4 | `UIUXAccessibilityRegressionStaticContractTests.swift:153` | `accessibilityLabel: "타임라인 확대"` | 삭제+승격 | 3과 동일 (반대 방향 버튼). |
| 5 | `R504MainVideoTrackStaticContractTests.swift:100` | 배열 항목 `"%@ 클립 추가 영역"` (`trackLane` 구간) | 삭제+승격 | 2와 같은 의도의 중복 단언. 같은 배열의 비한국어 마커 10건은 전부 보존. |
| 6 | `R504MainVideoTrackStaticContractTests.swift:119` | `return NSLocalizedString("비디오 트랙 헤더", …)` | 삭제+승격 | 메인이 아닌 비디오 트랙이 일반 트랙 레이블로 폴백한다는 의도 → 픽스처에 비메인 비디오 트랙을 넣어 런타임에서 "메인과 다르게 읽힌다"로 확인. |
| 7 | `R504MainVideoTrackStaticContractTests.swift:121` | `timeline.contains("… %@ 클립 추가 영역 …")` | 삭제+승격 | 2·5와 같은 의도의 3번째 중복. 바로 위의 `accessibilityLabel(trackHeaderAccessibilityLabel(for: track))` 단언은 보존. |
| 8 | `R503TrackHeaderStaticContractTests.swift:40` | `lane.contains("… %@ 클립 추가 영역 …")` | 삭제+승격 | 2의 4번째 중복. 이 함수의 mute/hide/lock 단언 13건은 전부 보존. |
| 9 | `R502TimelineZoomStaticContractTests.swift:61` | `zoomControls.contains(#"accessibilityLabel: "타임라인 축소""#)` | 삭제+승격 | 3의 중복. 같은 함수의 `title:`·버튼 수·readout 단언은 보존. |
| 10 | `R502TimelineZoomStaticContractTests.swift:62` | `zoomControls.contains(#"accessibilityLabel: "타임라인 확대""#)` | 삭제+승격 | 4의 중복. |
| 11 | `Phase04TimelineEditToolbarStaticContractTests.swift:163` | 배열 항목 `accessibilityLabel: "타임라인 축소"` | 삭제+승격 | 3의 중복. 같은 배열의 `title:`/`hint:`/줌 클러스터 레이블 단언은 보존. |
| 12 | `Phase04TimelineEditToolbarStaticContractTests.swift:164` | 배열 항목 `accessibilityLabel: "타임라인 확대"` | 삭제+승격 | 4의 중복. |
| 13 | `Phase23TimelineToolbarIconOnlyStaticContractTests.swift:162` | 배열 항목 `accessibilityLabel: "타임라인 축소"` | 삭제+승격 | 3의 중복. **이 스위트의 주제가 "아이콘 전용"이라 승격 가치가 가장 높은 건**이다. `systemImage:`/버튼 수 단언은 보존. |
| 14 | `Phase23TimelineToolbarIconOnlyStaticContractTests.swift:169` | 배열 항목 `accessibilityLabel: "타임라인 확대"` | 삭제+승격 | 4의 중복. |
| 15 | `Phase33SpeedCurveEditorStaticContractTests.swift:39` | `speedSection.contains("Toggle(\"부드러운 슬로우모션\"")` | **삭제** | 접근성 레이블이 아니라 **화면에 보이는 Toggle 제목**(SwiftUI 암시적 `LocalizedStringKey`) 문자열 trivia. 같은 함수에 남은 `get: { clip.useOpticalFlow }` / `updateSelectedOpticalFlow(newValue)` / `.disabled(clip.playbackRate >= 1.0)` 3건이 컨트롤 실존·배선을 이미 고정한다. 제목의 언어 판정은 작업 1.4. |
| 16 | `Phase33SpeedCurveEditorStaticContractTests.swift:43` | `speedSection.contains("Text(\"내보낼 때 프레임 보간이 적용됩니다\")")` | **삭제** | 순수 카피 문자열. 접근성 요소가 아니고(옆의 `Text`), 대응하는 동작이 없어 승격할 의도가 없다. Toggle 자체는 15의 잔존 단언이 덮는다. |

**요약: 삭제 2건 (15, 16) / 삭제+승격 14건 (1–14).** 승격 14건은 서로 중복이 많아 **고유 의도 5개**로 정리된다: 타임라인 루트 레이블 / 줌 아웃 레이블 / 줌 인 레이블 / 레인 드롭 영역 레이블의 헤더 파생 / 트랙 헤더 레이블 분기(메인 vs 일반 비디오 vs 오디오).

애매하다고 표시할 건은 없었다. 16건 전부 "한국어 리터럴 = 요구사항 1이 제거한 결함"이라는 같은 성질이고, 유지 쪽으로 기울일 근거가 있는 건이 없다.

---

## 4. 무엇을 승격했고 무엇을 작업 1.4에 남겼는가

### 승격 (작업 1.3): `App/MovieCutMacUITests/TimelineAccessibilityLabelUITests.swift`

실행 중인 앱에서 `XCUIElement.label`을 읽어 다음을 확인한다.

1. `timeline.root`가 접근성 트리에 있고 레이블이 비어 있지 않다.
2. `timeline.zoomOut` / `timeline.zoomIn`이 **타임라인 컨테이너 내부에** 있고, 각각 레이블이 비어 있지 않으며, **서로 다르다.**
3. 3개 트랙 헤더 레이블이 모두 비어 있지 않고, 메인 비디오 ≠ 일반 비디오 ≠ 오디오이며, 메인 비디오 레이블은 트랙 이름(`Video 1`)을 품는다.
4. 3개 레인 드롭 영역 레이블이 각각 **자기 트랙 헤더 레이블을 포함**하고, 헤더 레이블과 동일하지는 않다.

**이 테스트는 의도적으로 로케일 독립이다.** 레이블은 런타임에 `Localizable.xcstrings`를 거쳐 결정되므로, 이 호스트(한국어)에서 앱은 정당하게 `'타임라인 축소'`를 보고한다 — 아래 §6의 실측 트리가 그 증거다. 따라서 특정 언어를 단언하지 않고, **레이블이 존재하는가 / 구별되는가 / 파생되는가**만 본다.

`MOVIECUT_UITEST_QUIT`은 설정하지 않는다 (§2.3 접근성 핸드셰이크 제약).

### 작업 1.4에 남긴 것 (여기서 중복 구현하지 않았다)

- 영어 로케일에서 접근성 레이블에 한글 0건 (수용 기준 1.1).
- 한국어 로케일 문구 무변경 (수용 기준 1.2).
- Toggle 제목 `Smooth slow motion` 등 **화면 표시 문자열**의 언어 판정 (판정 15·16이 남긴 유일한 잔여).

즉 1.3은 "레이블이 있는가·구별되는가·파생되는가"(로케일 무관), 1.4는 "레이블이 어느 언어인가"(로케일별 전수)를 맡는다. 교집합이 없다.

---

## 5. 승격을 위해 추가한 것

| 파일 | 내용 | 이유 |
|---|---|---|
| `App/MovieCutMac/TimelineView.swift` | `.accessibilityIdentifier` 5개 추가: `timeline.root`, `timeline.zoomOut`, `timeline.zoomIn`, `timeline.trackHeader.<trackID>`, `timeline.trackLane.<trackID>` | 레이블은 카탈로그를 거쳐 로케일별로 바뀌므로 **레이블로 요소를 찾을 수 없다.** identifier는 현지화되지 않으므로 로케일 독립 앵커가 된다. 작업 0.2가 `cardEditor.*` / `cardCanvas.*` identifier로 같은 일을 한 전례를 따랐다. |
| `Tests/Fixtures/timeline_accessibility_bootstrap.moviecut` | 트랙 3개(video `Video 1` / video `Video 2` / audio `Audio 1`), 클립 0개, 고정 UUID | 판정 6(메인 아닌 비디오 트랙 폴백)을 실제로 도달시키려면 비디오 트랙이 2개 필요하다. UUID를 고정해 테스트가 순서 추측 없이 특정 레인을 지목한다. |
| `MovieCut.xcodeproj/project.pbxproj` | 신규 UI 테스트 파일 등록 4줄 (`PBXBuildFile` / `PBXFileReference` / 그룹 child / Sources 빌드 페이즈) | **`xcodegen generate`를 실행하지 않았다.** 실행하면 `schemes:`에서 스킴을 재생성해 작업 0.2의 `MovieCutMac.xcscheme` 변경을 덮어쓴다. 그래서 손으로 최소 등록만 했고, xcodegen의 알파벳 정렬 위치(`PreviewProjectComposition…` 다음)에 넣어 이후 재생성 시 diff가 최소가 되게 했다. |

`TimelineView.swift`에 추가한 것은 identifier와 주석뿐이다. 문자열 키·레이블·동작은 손대지 않았다.

---

## 6. 이 세션에서 관측한 사실 (부수 확인)

작업 1.3의 진단 실행이 남긴 실측 접근성 트리다. **작업 1.4의 대체물이 아니고**, 1.4는 두 로케일을 직접 측정해야 한다. 다만 작업 1.2가 실제로 동작한다는 런타임 증거다.

한국어 로케일 호스트에서 앱이 보고한 레이블 (발췌):

```
Group,  label: '타임라인'
  Group,  label: '타임라인 확대/축소 컨트롤'
    Button, label: '타임라인 축소'
    Slider, label: '타임라인 확대/축소 슬라이더', value: 80
    Button, label: '타임라인 확대'
    Button, label: 'Fit Timeline'
  Group,  label: '메인 비디오 트랙, Video 1'
  Group,  label: '메인 비디오 트랙, Video 1 클립 추가 영역'
  Group,  label: '비디오 트랙 헤더'
  Group,  label: '비디오 트랙 헤더 클립 추가 영역'
  Group,  label: '오디오 트랙 헤더'
  Group,  label: '오디오 트랙 헤더 클립 추가 영역'
```

두 가지가 이것으로 확인된다.

1. **작업 1.2의 키 교체가 카탈로그를 실제로 경유한다.** 코드의 키는 이제 영어(`"Timeline zoom out"`)인데 화면에는 `'타임라인 축소'`가 나온다 — 즉 한국어 문구가 리터럴이 아니라 `ko` 값에서 온다. 종전 구조에서는 키 자체가 한국어라 이 구분이 불가능했다.
2. **`Fit Timeline` 버튼만 한국어 로케일에서도 영어로 읽힌다.** 카탈로그의 `ko` 값 커버리지 문제로 보인다. 이 건은 **작업 1.4의 범위**이며 여기서 고치지 않았다. (1.4는 "영어 로케일에 한글 0건"뿐 아니라 그 역방향 누락도 보게 된다.)

---

## 7. 실행한 명령과 출력 (전부 이 세션 직접 실행)

### 7.1 착수 전 (red)

```
$ swift test
✘ Test run with 1044 tests in 169 suites failed after 9.347 seconds with 16 issues.
```
실패 테스트 함수 8건 / issue 16건.

### 7.2 완료 후

```
$ swift build
Build complete! (0.47s)                       종료 0, warning 0 (캐시 히트)

$ swift test
✔ Test run with 1044 tests in 169 suites passed after 16.229 seconds.
                                              종료 0, ✘ 0건, Suite 169 시작 / 169 통과

$ python3 scripts/verify_localization_keys.py --fail-on-korean
VERDICT: PASS - 294 code keys all present in 408 catalog keys
                                              종료 0, 한국어 키 0 / 누락 0

$ xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -destination 'platform=macOS' build
** BUILD SUCCEEDED **                         종료 0, error 0 / warning 0 (증분)
```

### 7.3 승격한 XCUITest (정상 서명, `env -u MOVIECUT_UITEST_QUIT`)

```
$ env -u MOVIECUT_UITEST_QUIT xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac \
    -destination 'platform=macOS' \
    -only-testing:MovieCutMacUITests/TimelineAccessibilityLabelUITests test

Test Case '-[MovieCutMacUITests.TimelineAccessibilityLabelUITests
             testTimelineElementsExposeAccessibilityLabels]' passed (18.520 seconds).
     Executed 1 test, with 0 failures (0 unexpected) in 18.520 seconds
** TEST SUCCEEDED **
```

서명은 `Signing Identity: "Sign to Run Locally"` (`CODE_SIGNING_ALLOWED=NO` 미사용).

---

## 8. 기준선 대조

| 지표 | `baseline.md` (0.3) | 작업 1.3 완료 후 | 판정 |
|---|---|---|---|
| 테스트 수 | 1044 | **1044** | 동일 |
| 스위트 수 | 169 | **169** | 동일 |
| 실패 | 0 | **0** | 동일 (착수 시점 8건 실패에서 복구) |
| 테스트 타깃 warning | 고유 3곳 | 고유 3곳 (동일 파일·동일 라인) | 동일 |

**테스트 수가 줄지 않은 이유를 명시한다.** 요구사항 15.4는 "테스트 수가 줄어드는 것은 정상"이라고 하지만, 이 작업이 제거한 것은 **`@Test` 함수가 아니라 함수 내부의 `#expect` 16건**이다. swift-testing의 `1044`는 `@Test` 함수 수를 센다. 함수를 하나도 지우지 않았으므로(§2 원칙 2) 수치가 변하지 않는 것이 정확한 결과다. 줄어든 것은 테스트 수가 아니라 가짜 단언 16건이고, 늘어난 것은 XCUITest 1건이다 — 이 1건은 `swift test`가 실행할 수 없으므로 1044에 포함되지 않는다(`baseline.md` §2와 동일한 구조적 이유).

warning 회귀 판정은 하지 않았다. 두 빌드 모두 증분/캐시 히트였고, `baseline.md` §5가 증분 수치끼리 비교하지 말라고 정했다. 클린 변형(고유 16곳)과 같은 척도의 측정을 하지 않았다.

---

## 9. 손대지 않은 것 (선행 작업 보존 확인)

`git diff --stat`으로 착수 전후 변경량이 동일함을 확인했다.

| 파일 | 착수 전 | 완료 후 | |
|---|---|---|---|
| `App/MovieCutMac/CardNews/CardCanvasView.swift` | 14 | 14 | 작업 0.2 그대로 |
| `App/MovieCutMac/CardNews/CardEditorView.swift` | 89 | 89 | 작업 0.2 그대로 |
| `App/MovieCutMacUITests/CardEditorUITests.swift` | +54 | +54 | 작업 0.2 그대로 |
| `MovieCut.xcodeproj/…/MovieCutMac.xcscheme` | 15 | 15 | 작업 0.2 그대로 |
| `App/MovieCutMac/Localizable.xcstrings` | 6956 | 6956 | 작업 1.2 그대로 |
| `App/MovieCutMac/Inspector/InspectorBasicSection.swift` | 8 | 8 | 작업 1.2 그대로 |
| `scripts/verify_localization_keys.py` | 미추적(신규) | 미추적(신규) | 작업 1.1 그대로 |
| `App/MovieCutMac/TimelineView.swift` | 38 | **47** | 작업 1.2의 38줄 유지 + identifier 5줄·주석 4줄 추가 |

커밋하지 않았다.

---

## 10. 미검증 / 이 작업 범위 밖

1. **로케일별 레이블 언어를 검증하지 않았다.** §6은 한국어 호스트에서의 단발 관측이고, 영어 로케일 실행은 하지 않았다. 작업 1.4의 범위다.
2. **비-CardEditor UI 테스트 3종을 실행하지 않았다.** `ImportExportE2ETests`, `PreviewProjectCompositionUITests`, `UnsavedChangesGuardUITests`는 작업 0.2가 이 호스트에서 이 작업과 무관한 이유로 실패한다고 보고했다. 이번 작업은 `-only-testing`으로 신규 스위트만 돌렸고, 그 3종의 상태를 재측정하지 않았다.
3. **`Fit Timeline`의 `ko` 값 누락을 고치지 않았다** (§6-2). 작업 1.4 판단 사항.
4. **`docs/` 산문 단언은 손대지 않았다.** 이 7개 파일에 남은 한국어 단언 전부가 `docs/CAPCUT_UI_PARITY_REQUIREMENTS.md` / `CAPCUT_UI_SHOWCASE_HANDOFF.md` / `UIUX_HANDOFF.md`의 산문을 대상으로 하며, 문서를 바꾸지 않았으므로 통과 상태다. 제거는 작업 8.1의 범위다.
5. **부정 단언 전수 분류를 하지 않았다.** 이 7개 파일에 `#expect(!…)` 형태의 부정 단언이 다수 남아 있다(예: `R504`의 계층 침투 방지 11건). 요구사항 15.2 / 작업 8.2의 범위이며, 이번에 판정하지 않았다.
6. **XCUITest 호스트 불안정.** 신규 스위트를 4회 실행하는 동안 2회는 테스트 로직과 무관한 환경 실패였다 — 1회는 `Timed out while enabling automation mode.`, 1회는 앱이 foreground에 도달하지 못함. 통과 실행(§7.3)이 최종 결과지만, 이 스위트는 재실행 시 환경 기인 실패가 가능하다.
7. 로그 원본: `/tmp/moviecut-task-1.3/` (`swift-test-before.log`, `swift-test-final.log`, `swift-build-final.log`, `xcodebuild-final.log`, `verify-loc-final.log`, `uitest-final4.log`, `Task1-3-A11y.xcresult`). `/tmp`은 재부팅에 사라지므로 **이 문서가 durable 기록이다.**
