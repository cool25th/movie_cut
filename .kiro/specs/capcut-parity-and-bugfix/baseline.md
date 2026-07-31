# 기준선 측정 기록 — 작업 0.3

이 문서는 **이 스펙의 유일한 기준선**이다. 이후 모든 작업의 빌드·테스트 수치는 여기 적힌 값과만 비교한다.
`docs/` 아래 다른 문서의 과거 수치(예: `PERF_BASELINE_*`, `verify_gate.sh` 주석의 "baseline 984 tests")는 **인용하지 않는다.**

아래 값은 전부 이 세션에서 직접 실행한 명령의 출력이다. 추정치·문서 인용치는 없다.

---

## 측정 환경

| 항목 | 값 |
|---|---|
| 측정 시각 | 2026-07-31T00:55+0900 (측정 시작) |
| macOS | 26.5.2 (25F84) |
| Xcode | 26.6 (17F113) |
| Swift | Apple Swift 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101), swift-driver 1.148.6 |
| Target triple | arm64-apple-macosx26.0 |
| HEAD | `9f720d59cd996d127f02fa3cecc72c0e9b96b179` |

### 작업 트리 상태 (측정 시점, `git diff --stat`)

기준선은 **클린 트리가 아니다.** 작업 0.2가 남긴 의도된 변경과 이 스펙과 무관한 선행 변경이 함께 있다.

```
 App/MovieCutMac/CardNews/CardCanvasView.swift                  |   14 +-
 App/MovieCutMac/CardNews/CardEditorView.swift                  |   89 +-
 App/MovieCutMac/Localizable.xcstrings                          | 6877 ++++++++++---------
 App/MovieCutMacUITests/CardEditorUITests.swift                 |   54 +
 MovieCut.xcodeproj/xcshareddata/xcschemes/MovieCutMac.xcscheme |   15 +-
 5 files changed, 3774 insertions(+), 3275 deletions(-)
```

미추적: `.kiro/` (스펙 문서)

---

## 1. `swift build`

```
$ swift build
```

- 종료 코드: **0**
- 마지막 상태 줄: `Build complete! (3.23s)`
- `/usr/bin/time -p`: `real 5.72` / `user 2.67` / `sys 1.46`
- 진단: **warning 1건 / error 0건**
  - 유일한 warning: `Sources/MovieCutCore/Rendering/ChromaKeyPixelProcessor.swift:72:42` — `'init(source:)' was deprecated in macOS 10.14: Core Image Kernel Language API deprecated.` `[#DeprecatedDeclaration]`

**이 수치는 증분 빌드다.** 기존 `.build/`가 살아 있어 `[2/2] Emitting module MovieCutCore`만 돌았다. 따라서 warning 1건은 **전체 warning 수가 아니라 이번에 다시 컴파일된 범위의 수**다.

### 1b. 전체 컴파일 변형 (같은 명령, 별도 scratch 경로)

`.build/`를 지우지 않고 전체 컴파일 수치를 얻기 위한 변형이다. (`.build/`에는 작업 0.2의 실패 첨부물과 xcresult가 들어 있어 삭제하지 않는다.)

```
$ swift build --scratch-path /tmp/moviecut-baseline-0.3/scratch-build
```

- 종료 코드: **0**
- 마지막 상태 줄: `Build complete! (21.86s)` (`[170/170]` 컴파일 액션)
- `/usr/bin/time -p`: `real 23.30` / `user 54.55` / `sys 10.25`
- 진단: **warning 방출 119건 / error 0건**, **고유 발생 지점 7곳**
  (119 vs 7의 차이는 같은 선언이 여러 컴파일 단위에서 반복 방출된 것이다)

고유 7곳 (Core 계층 전부):

| 위치 | 내용 |
|---|---|
| `Analysis/BeatDetectionProvider.swift:158:35` | `tracks(withMediaType:)` deprecated (macOS 13.0) |
| `Analysis/SilenceDetectionProvider.swift:121:54` | `duration` deprecated (macOS 13.0) |
| `Analysis/SilenceDetectionProvider.swift:125:35` | `tracks(withMediaType:)` deprecated (macOS 13.0) |
| `Media/WaveformGenerator.swift:74:40` | `tracks(withMediaType:)` deprecated (macOS 13.0) |
| `Media/WaveformGenerator.swift:105:52` | `timeRange` deprecated (macOS 13.0) |
| `Media/DragDropHandler.swift:75:17` | `NSItemProvider` non-Sendable capture in `@Sendable` closure |
| `Rendering/ChromaKeyPixelProcessor.swift:72:42` | CI Kernel Language deprecated (macOS 10.14) |

---

## 2. `swift test`

```
$ swift test
```

- 종료 코드: **0**
- 권위 있는 요약 줄: `✔ Test run with 1044 tests in 169 suites passed after 9.634 seconds.`
- XCTest 요약 줄: `Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.005) seconds`
- `/usr/bin/time -p`: `real 21.18` / `user 29.04` / `sys 2.62`
- 실패 표시(`✘`): **0건**. `known issue` 문자열: **0건**
- 완주 확인: `◇ Test "…" started` 969건 ↔ `✔ Test "…" passed` 969건, `◇ Suite` 169건 ↔ `✔ Suite` 169건 (나머지 `Test case` 7줄은 파라미터화 케이스 시작 줄)
- 테스트 타깃 빌드 진단: **warning 3건 / error 0건**
  - `Tests/MovieCutCoreTests/CGCodableParityTests.swift:100:13` — `keyedForm` 미사용
  - `Tests/MovieCutCoreTests/ProjectSchemaMigrationTests.swift:142:13` — `project` 미사용
  - `Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift:27:5` — `nonisolated(unsafe)` 불필요 (`CIContext`는 `Sendable`)

**기준선 숫자 3개 (이후 비교의 기준):** 테스트 1044 / 스위트 169 / 실패 0.

이 실행에 실제로 포함된 골든 스위트 (skip 아님, `✔ Suite … passed`):
`Background Removal Golden`, `Color Correction Golden`, `Color Grade Golden`.

**`XCTest 0 executed`는 결함이 아니라 구조다.** SwiftPM 테스트 타깃에는 XCTest 케이스가 없고 전부 swift-testing이다. 앱 레벨 XCUITest(`App/MovieCutMacUITests/`)는 `swift test`가 실행할 수 없다 — 이 명령의 1044건에 **포함되지 않는다.**

---

## 3. `xcodebuild -scheme MovieCutMac`

정상 서명으로 실행했다. `CODE_SIGNING_ALLOWED=NO`를 쓰지 않았다 (`scripts/verify_gate.sh`의 게이트 호출과 이 점이 다르다).

```
$ xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -destination 'platform=macOS' build
```

- 종료 코드: **0**
- 결과 줄: `** BUILD SUCCEEDED **`
- `/usr/bin/time -p`: `real 51.30` / `user 2.26` / `sys 2.31`
- 서명: `Signing Identity: "Sign to Run Locally"` (앱 본체 + `MovieCutMac.debug.dylib` + `__preview.dylib`)
- DerivedData: 기본 경로 (`~/Library/Developer/Xcode/DerivedData/MovieCut-defaidzsyazhaqdppetzjmucslvb`)
- 빌드된 타깃: `MovieCutCore`, `MovieCutMac` (**`build` 액션은 UI 테스트 타깃을 빌드하지 않는다**)
- 진단: **warning 10건 / error 0건** (고유 9곳). 증분이므로 파일 단위 컴파일은 12건뿐이었다

### 3b. 클린 변형 (별도 derivedDataPath)

```
$ xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -destination 'platform=macOS' \
    -derivedDataPath /tmp/moviecut-baseline-0.3/dd-clean build
```

- 종료 코드: **0**, 결과 줄 `** BUILD SUCCEEDED **`
- `/usr/bin/time -p`: `real 79.74` / `user 2.38` / `sys 1.49`
- 진단: **warning 방출 34건 / error 0건**, **고유 발생 지점 16곳** = App 9곳 + Core 7곳
  (Core 7곳은 §1b와 동일 집합)

App 계층 고유 9곳:

| 위치 | 내용 |
|---|---|
| `EditorViewModel.swift:1928:11` | `catch` 블록 도달 불가 (`do`에서 throw 없음) |
| `Effects/ChromaKeyView.swift:55:29` | nonisolated 컨텍스트에서 main actor 격리 `updateSettings` 호출 |
| `Effects/ChromaKeyView.swift:63:29` | 동일 |
| `Effects/ChromaKeyView.swift:71:29` | 동일 |
| `Effects/ChromaKeyView.swift:79:29` | 동일 |
| `Export/ChromaKeyCompositor.swift:8:9` | `Sendable` 클래스의 가변 저장 프로퍼티 `chromaKeySettingsByTrackID` |
| `Export/ExportEngine.swift:365:57` | `render(imageURL:duration:renderSize:outputURL:)` 결과 미사용 |
| `Playback/PlaybackEngine.swift:191:62` | `Any`가 `Sendable` 미준수 |
| `Playback/PlaybackEngine.swift:683:61` | `render(...)` 결과 미사용 |

---

## 기준선 요약표

| 명령 | 결과 | 소요 (도구 보고 / wall) | warning | error |
|---|---|---|---|---|
| `swift build` (증분) | 성공 | 3.23s / 5.72s | 1 | 0 |
| `swift build` (별도 scratch, 전체 컴파일) | 성공 | 21.86s / 23.30s | 119 방출 (7곳) | 0 |
| `swift test` | 1044 tests / 169 suites **passed** | 9.634s / 21.18s | 3 (테스트 타깃) | 0 |
| `xcodebuild … build` (증분, 기본 DerivedData) | `** BUILD SUCCEEDED **` | — / 51.30s | 10 (9곳) | 0 |
| `xcodebuild … build` (별도 derivedDataPath, 클린) | `** BUILD SUCCEEDED **` | — / 79.74s | 34 방출 (16곳) | 0 |

**3종 전부 통과했다. 이 기준선에 red 항목은 없다.**

---

## 이 측정으로 확인하지 않은 것 (미검증)

이후 작업이 이 항목들을 "기준선에서 이미 확인됨"으로 인용하지 않는다.

1. **앱 레벨 XCUITest 결과.** 이 작업에서 `xcodebuild test`를 돌리지 않았다. §3의 `build` 액션은 UI 테스트 타깃을 빌드조차 하지 않는다. 작업 0.2가 보고한 UI 테스트 상태(CardEditor 계열 통과, 비-CardEditor 3개 클래스 실패)는 **그 작업의 측정이며 여기서 재측정하지 않았다.** UI 테스트 수치가 필요한 작업은 직접 다시 측정한다.
2. **파리티 스크립트 수치.** `scripts/run_core_editing_parity.sh`의 MAD·duration은 작업 2.3의 범위다. 이 문서에 파리티 수치는 없다.
3. **릴리스 구성.** 세 명령 모두 스킴 기본값(Debug)으로 돌았다. Release 빌드는 측정하지 않았다.
4. **iOS.** 이 작업에서 iOS 스킴을 빌드하지 않았다 (작업 9.1의 범위).
5. **경고 수의 증분 의존성.** `swift build` / `xcodebuild`의 warning 수는 캐시 상태에 따라 달라진다. 이후 비교는 **§1b·§3b의 클린 변형 수치**(7곳 / 16곳, 방출 119 / 34)를 기준으로 한다. 증분 수치끼리 비교하면 의미가 없다.

---

## 이후 작업이 지켜야 할 비교 규칙

- 테스트 수 변화를 보고할 때 기준은 **1044 / 169 / 실패 0**이다.
- warning 회귀를 판정할 때 기준은 **고유 발생 지점 16곳**(Core 7 + App 9)이다. 방출 건수(34)는 컴파일 단위 수에 따라 흔들리므로 보조 지표로만 쓴다.
- 빌드 시간은 캐시 상태에 크게 좌우된다. 시간 회귀를 주장할 때는 캐시 상태(증분 / 클린)를 함께 적는다.
- 로그 원본: `/tmp/moviecut-baseline-0.3/` (`swift-build.log`, `swift-build-clean.log`, `swift-test.log`, `xcodebuild.log`, `xcodebuild-clean.log`). `/tmp`은 재부팅에 사라지므로 **위 표가 durable 기록이다.**
