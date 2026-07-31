# 현지화 키 전수 조사 기록 — 작업 1.1

요구사항 1.3 / 1.4 대응. 이 문서의 모든 숫자는 이 세션에서 직접 실행한 `scripts/verify_localization_keys.py` 출력이다.
손으로 센 수치는 없다. 비교 기준선은 `baseline.md`(작업 0.3)뿐이다.

- 산출물: `scripts/verify_localization_keys.py` (신규, 실행 권한 있음, 읽기 전용, 네트워크·외부 프로세스 없음)
- 측정 시각: 2026-07-31 (작업 1.1 세션)
- HEAD: `9f720d59cd996d127f02fa3cecc72c0e9b96b179`
- 카탈로그: `App/MovieCutMac/Localizable.xcstrings` (작업 트리 상태 = 커밋되지 않은 선행 변경 포함. **되돌리지 않았다**)

---

## 1. 스크립트가 하는 일

1. `App/MovieCutMac`의 `.swift` 46개를 주석 인식 렉서로 훑는다. 행 주석 / 중첩 블록 주석 / 이스케이프 / raw 문자열(`#"…"#`) / 멀티라인(`"""`) / 문자열 보간을 구분한다.
2. `NSLocalizedString(...)` 호출부의 첫 인자를 키로 뽑는다. 첫 인자가 리터럴이 아니면 **동적 호출부**로 따로 집계한다.
3. 리터럴이 아닌 모든 문자열 리터럴도 위치와 함께 모아 둔다. SwiftUI의 암시적 `LocalizedStringKey`(`Text("…")`, `Button("…")`, `Toggle("…")`)는 이 경로로만 보인다.
4. 코드 키 집합 ↔ 카탈로그 키 집합을 대조하고, 카탈로그 미사용 키를 **간접**(키 텍스트가 코드 리터럴로 존재) / **고아**(어디에도 없음)로 나눈다.
5. 한글 포함 키를 경로별로 분류해 호출부와 함께 출력한다.

사용법:

```
python3 scripts/verify_localization_keys.py                 # 사람이 읽는 리포트 + VERDICT
python3 scripts/verify_localization_keys.py --json          # stdout은 순수 JSON, VERDICT는 stderr
python3 scripts/verify_localization_keys.py --self-test     # 렉서 규칙 자기 검증
python3 scripts/verify_localization_keys.py --fail-on-korean # 작업 1.2의 게이트로 쓸 수 있다
python3 scripts/verify_localization_keys.py --catalog <path> --source-root <dir>
```

종료 코드: `0` 대조 통과 / `1` 누락·보간 키(옵션에 따라 한국어 키) / `2` 사용법·IO 오류.
이 작업에서는 카탈로그를 **수정하지 않는다.** 스크립트에 쓰기 경로가 없다.

---

## 2. 실행한 명령과 실측 출력

### 2.1 렉서 자기 검증

```
$ python3 scripts/verify_localization_keys.py --self-test
self-test: 18/18 checks passed        (종료 코드 0)
```

### 2.2 기본 대조 (작업 트리 카탈로그)

```
$ python3 scripts/verify_localization_keys.py
```

| 항목 | 실측 |
|---|---|
| 코드가 사용하는 키 (distinct, `NSLocalizedString` 리터럴) | **295** |
| 카탈로그 키 | **405** |
| 카탈로그에 없는 코드 키 | **0** |
| 코드가 직접 참조하지 않는 카탈로그 키 | **110** (간접 92 / 고아 18) |
| `NSLocalizedString` 호출부 | **346** (리터럴 키 339 / 동적 7 / 보간 0) |
| 렉싱한 문자열 리터럴 | 3337 (멀티라인 2, raw 0) |
| 한국어 키 (`NSLocalizedString`) | **17** |
| 카탈로그의 한국어 키 | **19** |
| `NSLocalizedString` 없이 카탈로그에 닿는 한국어 리터럴 | **2** |
| 카탈로그 항목이 없는 한국어 리터럴 | **4** |
| **한국어 키 후보 합계 (모든 경로)** | **23** |
| 카탈로그 `en` 값이 한국어인 항목 | **0** |

```
VERDICT: PASS - 295 code keys all present in 405 catalog keys (note: 17 Korean key(s) still used in code)
```

`--fail-on-korean`을 켜면:

```
VERDICT: FAIL - 23 Korean key candidate(s) in code (17 via NSLocalizedString,
                2 via catalog-matched literal, 4 literal(s) with no catalog entry)   (종료 코드 1)
```

### 2.3 HEAD 카탈로그와의 대조 (참고 실행)

```
$ git show 9f720d5:App/MovieCutMac/Localizable.xcstrings > /tmp/…/Localizable.HEAD.xcstrings
$ python3 scripts/verify_localization_keys.py --catalog /tmp/…/Localizable.HEAD.xcstrings
```

- HEAD 카탈로그 키 296 → 작업 트리 405. **추가 109건, 삭제 0건**(순수 additive).
- HEAD 기준 누락 2건이 작업 트리에서 해소되어 있다:
  `'Thermal pressure: preview is using the proxy. …'` (TimelineView.swift:1151),
  `'proxy playback on due to thermal pressure'` (TimelineView.swift:1167).
- HEAD에서도 `en` 값이 한국어인 항목은 **0**이다 (아래 §4 참고).

### 2.4 iOS 타깃 참고 실행 (이 작업 범위 아님)

```
$ python3 scripts/verify_localization_keys.py --source-root App/MovieCutiOS
```

`NSLocalizedString` 호출부 **0**, 카탈로그 항목 없는 한국어 리터럴 **30**. 요구사항 14(작업 9.6·9.7)의 대상이며 여기서 손대지 않았다.

---

## 3. 한국어 현지화 키 표면 — 작업 1.2 인계 목록 (23건)

### 3.1 `NSLocalizedString` 키가 한국어 (17건, 전부 카탈로그에 존재)

| 키 | 호출부 |
|---|---|
| `%@ 오른쪽 트림 핸들` | `TimelineView.swift:950` |
| `%@ 왼쪽 트림 핸들` | `TimelineView.swift:941` |
| `%@ 클립 추가 영역` | `TimelineView.swift:788` |
| `드래그하여 타임라인을 프레임 단위로 스크럽합니다.` | `TimelineView.swift:547` |
| `비디오 클립` | `TimelineView.swift:1585` |
| `비디오 트랙 헤더` | `TimelineView.swift:1603` |
| `비트 마커` | `TimelineView.swift:606` |
| `스티커 클립` | `TimelineView.swift:1590` |
| `오디오 클립` | `TimelineView.swift:1587` |
| `오디오 트랙 헤더` | `TimelineView.swift:1605` |
| `자동 컷 제거 예정 구간` | `TimelineView.swift:767` |
| `재생 헤드` | `TimelineView.swift:545` |
| `클릭하거나 드래그하여 프리뷰를 스크럽합니다.` | `TimelineView.swift:639` |
| `타임라인` | `TimelineView.swift:161` |
| `타임라인 룰러` | `TimelineView.swift:638` |
| `텍스트 클립` | `TimelineView.swift:1592` |
| `텍스트 트랙 헤더` | `TimelineView.swift:1607` |

요구사항 1의 근거가 지목한 3건(`TimelineView.swift:788, 941, 950`)이 모두 포함된다.

### 3.2 `NSLocalizedString`을 경유하지 않고 카탈로그에 닿는 한국어 키 (2건)

SwiftUI 암시적 `LocalizedStringKey`다. 직접 grep으로는 `NSLocalizedString` 필터에 걸려 보이지 않는다.

| 키 | 위치 | 형태 |
|---|---|---|
| `모션 트래킹` | `Inspector/InspectorBasicSection.swift:226` | `Text("모션 트래킹")` |
| `내보낼 때 프레임 보간이 적용됩니다` | `Inspector/InspectorBasicSection.swift:644` | `Text("…")` |

### 3.3 카탈로그 항목이 아예 없는 한국어 UI 리터럴 (4건) — 실제 사용자 노출 결함

영어 로케일에서 카탈로그 조회가 실패해 **키 텍스트(한글)가 그대로 표시된다.**

| 리터럴 | 위치 | 현지화 경로 |
|---|---|---|
| `타임라인 축소` | `TimelineView.swift:413` | `timelineToolbarIconButton(accessibilityLabel:)` → `NSLocalizedString($0)` @ `TimelineView.swift:202` |
| `타임라인 확대` | `TimelineView.swift:433` | 위와 동일 |
| `영역 조정` | `Inspector/InspectorBasicSection.swift:246` | `Button("영역 조정")` 암시적 키 |
| `부드러운 슬로우모션` | `Inspector/InspectorBasicSection.swift:635` | `Toggle("부드러운 슬로우모션", isOn:)` 암시적 키 |

앞 2건은 **동적 `NSLocalizedString` 호출부를 통과하는 실제 런타임 키**이며 카탈로그에 없다. 즉 요구사항 1.3("코드 키 집합 ↔ 카탈로그 키 집합 일치")의 현재 위반 건이다. 직접 스캔만 하는 대조로는 잡히지 않고, 리터럴 풀 대조가 있어야 드러난다.

### 3.4 동적 키 호출부 (7건) — 키가 변수로 들어온다

| 위치 | 스니펫 |
|---|---|
| `ContentView.swift:310` | `NSLocalizedString(accessibilityLabel, …)` |
| `ProjectSettings/CanvasSettingsView.swift:146` | `NSLocalizedString(kind.rawValue, …)` |
| `TimelineView.swift:201` | `NSLocalizedString(title, …)` |
| `TimelineView.swift:202` | `NSLocalizedString($0, …)` (accessibilityLabel 경유) |
| `TimelineView.swift:203` | `NSLocalizedString(hint, …)` |
| `TimelineView.swift:228` | `NSLocalizedString(title, …)` |
| `TimelineView.swift:264` | `NSLocalizedString(accessibilityLabel, …)` |

작업 1.2에서 키를 영어로 바꿀 때 이 7곳의 **호출자 인자**도 함께 봐야 한다. 호출부 문자열만 고치면 누락된다.

---

## 4. 요구사항 1의 근거와 실측이 어긋나는 지점 (요구사항 문서는 수정하지 않았다)

`requirements.md` 요구사항 1은 "카탈로그의 `en` 값 3건이 한국어(`%@ 오른쪽 트림 핸들`, `%@ 왼쪽 트림 핸들`, `%@ 클립 추가 영역`)"라고 적었다. 실측은 다르다.

| 키 | 작업 트리 `en` | HEAD `en` |
|---|---|---|
| `%@ 오른쪽 트림 핸들` | `%@ right trim handle` | `%@ right trim handle` |
| `%@ 왼쪽 트림 핸들` | `%@ left trim handle` | `%@ left trim handle` |
| `%@ 클립 추가 영역` | `%@ clip add region` | `%@ clip add region` |

- 세 항목 모두 `en` / `ko` 값이 채워져 있고 `en`은 영어다. 스크립트의 "카탈로그 `en` 값이 한국어인 항목"은 작업 트리·HEAD 양쪽에서 **0**이다.
- 따라서 요구사항 1이 인용한 그 증상은 이 체크아웃에서 재현되지 않는다. HEAD 이전에 이미 메워졌거나, 요구사항이 더 오래된 스냅샷을 근거로 작성됐다.
- **그래도 요구사항 1의 결함 자체는 살아 있다.** §3.3의 4건은 카탈로그 항목이 없어 영어 로케일에서 한글이 그대로 노출된다. 그리고 §3.1·§3.2의 19건은 `sourceLanguage=en` 카탈로그에 한국어 키가 남아 있는 구조적 원인이며, 이것이 요구사항 1.1의 근본 수정 대상이다.
- 요구사항 문서 문구 조정은 사용자 판단 사항이므로 이 작업에서 건드리지 않았다.

---

## 5. 전수성(exhaustiveness)을 어떻게 보장했는가

1. **호출부 회계가 닫힌다.** 렉서가 찾은 `NSLocalizedString` 식별자 346건 = 리터럴 키 339 + 동적 7 + 보간 0. 분류 안 된 호출부가 남으면 리포트에서 드러난다.
2. **독립 grep 교차 검증** (렉서와 다른 구현):
   - `grep -ro --include="*.swift" "NSLocalizedString" App/MovieCutMac | wc -l` → **346**. 렉서와 일치. 즉 주석·문자열 속 언급이 0건이라는 뜻도 된다.
   - `grep -rn 'NSLocalizedString("[^"]*[가-힣]' App/MovieCutMac | wc -l` → **17**. §3.1과 일치.
   - `grep -rn '"[^"]*[가-힣][^"]*"' App/MovieCutMac | grep -v NSLocalizedString | wc -l` → **6**. §3.2(2) + §3.3(4)과 일치.
   - `grep -rn '[가-힣]' App/MovieCutMac | wc -l` → **23**. 위 17 + 6과 일치 = 한글이 주석에는 없다.
3. **메커니즘 전수 확인.** 이 코드베이스에 존재하는 현지화 경로는 `NSLocalizedString`과 SwiftUI 암시적 `LocalizedStringKey`뿐이다. 다음은 저장소 전체에서 **0건**으로 확인했다: `String(localized:`, 명시적 `LocalizedStringKey`, `localizedStringWithFormat`, `NSLocalizedStringFromTable`, `String.LocalizationValue`, `LocalizedStringResource`, `Bundle…localizedString(forKey:`. (`.localized*` 히트는 전부 `localizedDescription` / `localizedStandardCompare` / `localizedCapitalized`로 현지화 키와 무관.)
4. **한글 판정 범위.** 음절(AC00–D7A3)만 보지 않고 자모(1100–11FF), 호환 자모(3130–318F), 확장 A/B(A960–A97F, D7B0–D7FF)까지 본다.
5. **렉서 규칙 자기 검증 18건** (`--self-test`): 주석 처리된 호출 무시, 문자열 안의 `NSLocalizedString` 언급 무시, 여러 줄 호출, 이스케이프 해석, raw·멀티라인 리터럴이 이후 스캔을 망치지 않음, 동적·보간 키 분리, 한글 판정.
6. **결정성.** 모든 목록은 정렬 출력, 부작용 없음, 재실행 시 동일 출력. 방금 재실행으로 확인.

---

## 6. 기준선 대조 (`baseline.md` = 테스트 1044 / 스위트 169 / 실패 0)

스크립트만 추가한 변경이므로 Swift 코드·프로젝트 파일은 손대지 않았다.

| 명령 | 결과 | 기준선 대비 |
|---|---|---|
| `swift build` | `Build complete! (0.38s)`, 종료 0 | 동일 (성공). 완전 캐시 히트라 컴파일 액션 0건 |
| `swift test` | `✔ Test run with 1044 tests in 169 suites passed after 10.163 seconds.`, 종료 0, `✘` 0건 | **1044 / 169 / 0 — 기준선과 정확히 동일** |
| `xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **`, 종료 0 | 동일 (성공) |

warning 회귀 판정은 하지 않았다. Swift 파일을 바꾸지 않았고 두 빌드 모두 캐시 히트라 이번 실행의 warning 수(0)는 기준선의 클린 변형 수치(고유 16곳)와 **같은 척도가 아니다**. 기준선 §5가 정한 규칙대로 증분 수치끼리 비교하지 않았다.

---

## 7. 미검증 / 이 작업 범위 밖

1. **앱 레벨 XCUITest를 돌리지 않았다.** 영어 로케일 접근성 레이블 실측은 작업 1.4의 범위다.
2. **카탈로그를 수정하지 않았다.** 키 교체와 재정렬은 작업 1.2다. `Localizable.xcstrings`의 선행 변경(+109 키)은 그대로 보존했다.
3. **StaticContract 처리 안 했다.** `Tests/` 아래 한글 포함 Swift 라인 **211건**(`grep -rn '[가-힣]' Tests | wc -l`)이 있고 `NSLocalizedString` 문자열 언급 166건이 있다. 건별 판정은 작업 1.3이다. 이 숫자는 파일 수도 단언 수도 아니라 **라인 수**다.
4. **iOS 30건**(§2.4)은 요구사항 14 / 작업 9.6·9.7 대상이다.
5. **고아 카탈로그 키 18건**은 이번에 제거하지 않았다. 대부분 `'%@ pages'`, `'Page %@ of %@'`, `'Point %@'` 같은 CardNews 계열 서식 키이며, 작업 0.2의 CardNews 편집과 관련이 있을 수 있다. 정리 여부는 작업 1.2 또는 문서 정리(작업 10) 판단 사항이다.
6. 스크립트는 동적 키 호출부로 **어떤 리터럴이 흘러드는지 데이터플로로 추적하지 않는다.** §3.3의 분류는 리터럴 존재 여부에 기반하고, 그 4건의 경로는 사람이 코드를 읽어 확인했다. 이 한계는 리포트의 분류 이름(`candidate`)에 반영되어 있다.
