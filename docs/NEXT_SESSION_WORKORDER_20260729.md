# 후속 세션 작업지시서 (실측 기반)

> 작성일: 2026-07-29
> 기준: main `7b5b2ad` (작업트리 clean, untracked `.build-check/` `.zcode/` 제외)
> 목적: 신뢰성 수리(Tasks A~G) 완료 후 남은 작업 7종(W1 완료, 6종 대기)의 세션 시작 프롬프트
> 성격: **모든 수치는 이 문서 작성 시점에 직접 명령을 실행해 얻은 것이다.** 이전 지시서의 자가보고 수치를 옮겨 적지 않았다.

## 0. 검증된 기준선

| 검증 | 명령 | 결과 |
|------|------|------|
| Core 빌드 | `swift build` | ✅ 2.6s, 경고 1건 (`ChromaKeyPixelProcessor.swift:72` CIColorKernel deprecated) |
| **전체 테스트** | `swift test` | ✅ **984 tests / 162 suites 전부 통과, 18.6s** |
| Mac 앱 빌드 | `xcodebuild -scheme MovieCutMac -destination 'platform=macOS'` | ✅ BUILD SUCCEEDED |
| iOS 앱 빌드 | `xcodebuild -scheme MovieCutiOS -destination 'generic/platform=iOS'` | ❌ **불가** — `iOS 26.5 is not installed` |
| 린트 | `swiftlint lint` | ⚠️ 1,022건 (error 414 / warning 608), CI 비블로킹 |

규모: 소스 66.0k줄 (Core 168 / Mac 77 / iOS 25 파일), 테스트 21.2k줄 (137 파일), 커밋 296개.

### 이전 지시서 대비 변경

`docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md`의 Task A~G는 **전부 커밋됨.** 특히 당시 최대 문제였던 두 가지가 해소됐다:

- `swift test` hang (872 pass 후 정지, 재현 2/2) → **984개 완주, 18.6초**
- main red (실패 3건) → **green**

따라서 이 문서가 `docs/archive/RELIABILITY_REPAIR_WORKORDER_20260728.md`를 대체한다.
`docs/archive/CORE_REPAIR_FOLLOWUP_WORKORDER_20260728.md`(iOS 파리티 Task A~E)는 **5개 전부 미착수**이며, 아래 Track 2로 이관·갱신한다.

### 이전 지시서의 죽은 참조 (이 문서에서 교정함)

| 이전 지시서 표기 | 실측 |
|------------------|------|
| `App/MovieCutiOS/ContentView.swift` | 실제 경로는 `App/MovieCutiOS/iOSContentView.swift` |
| macOS harness 진입점 `ContentView.swift:358` | 실제 `App/MovieCutMac/ContentView.swift:25` |
| StaticContract 84개 / 부정단언 225건 / docs단언 38개 | **85개 / 248건 / 43개** (늘었음) |

---

## 1. 트랙 구분

```
Track 1 — 지금 착수 가능 (iOS 플랫폼 불필요)
  W1  IOSPlaybackEngine dead code 제거        ✅ 완료 (7b5b2ad)
  W2  StaticContract 부채 정리 (3단계)         [큰 작업, 세션 분리 권장]
  W3  SwiftLint 베이스라인 확립                [판단 필요]

Track 2 — 선행 조건: iOS 26.5 플랫폼 설치 (사용자 조치)
  W4  iOS 테스트 인프라 구축                   [W5~W7의 선행 조건]
  W5  chroma/segmentation shared processor 전환
  W6  two-source transition iOS 배선
  W7  harness 완주 시나리오 + parity 전체 실행
```

**Track 2 전체가 사용자 조치에 막혀 있다.** Xcode > Settings > Components에서 iOS 26.5를 설치해야 iOS 8.7k줄이 컴파일이라도 된다. 현재 CI는 이 단계를 `continue-on-error`로 두므로 iOS 코드는 사실상 무검증 상태다.

---

## 2. Track 1 — 지금 착수 가능

### W1 — IOSPlaybackEngine dead code 제거 ✅ 완료

**이 문서 작성 중 다른 세션이 완료했다.** 커밋 `7b5b2ad` (`refactor(moviecut): remove dead IOSPlaybackEngine`), 브랜치 `refactor/remove-dead-iosplaybackengine` → main 병합.

병합 후 실측 확인:
- `App/MovieCutiOS/Playback/` 디렉토리 제거됨, `IOSPlaybackEngine` 참조 **0건**
- `swift build` ✅ / `swift test` ✅ **984 tests 통과 (8.3s)** — 테스트 수 변동 없음 (iOS 전용 `#if os(iOS)` 코드였으므로 예상대로)

**남은 미검증**: iOS 빌드로는 확인 불가 (플랫폼 미설치). Track 2 착수 시 함께 확인할 것.

---

### W2 — StaticContract 부채 정리

**실측 근거** (`docs/STATIC_CONTRACT_TRIAGE_20260728.md` 방침은 확정됐으나 실행은 안 됨. 그 사이 수치가 **악화**됐다):

| 지표 | 7/28 문서 | 2026-07-29 실측 |
|------|----------|------|
| 테스트 파일 | 134 | 137 |
| StaticContract 파일 | 84 (63%) | **85 (62%)** |
| 부정 단언 `#expect(!` | 225 | **248** |
| `docs/` 경로 단언 파일 | 38 | **43** |

984개 통과 수치의 상당 부분이 소스 문자열 존재 검사이며 동작 신호가 아니다.

**세 단계로 쪼갠다. 한 세션에 하나씩.**

#### W2-1 — `docs/*.md` 산문 단언 제거

문서 산문은 테스트 대상이 아니다. 문서 오타 수정이 테스트를 깨뜨리는 것은 의존 방향이 거꾸로다.

집중 대상 (`docs/` 참조 상위):

| 파일 | docs 참조 |
|------|----------|
| `P3DocsCleanupStaticContractTests.swift` | 11 |
| `KeyboardShortcutStaticContractTests.swift` | 3 |
| `IAMenuPositionStaticContractTests.swift` | 3 |
| `F06ImportMetadataStaticContractTests.swift` | 3 |

**주의**: 삭제 전 해당 문서가 아직 유효한지 확인할 것. 죽은 문서를 테스트가 살려두고 있었을 수 있다.

#### W2-2 — 결함 고정 부정 단언 전수 조사 (248건)

두 종류를 구분한다:

| 종류 | 예 | 처리 |
|------|-----|------|
| **결함 고정** (기능 부재를 잠금) | `#expect(!iosCompositor.contains("TransitionPixelProcessor.apply"))` | **제거** — 기능 구현을 막는다 |
| **경계 방향** (계층 침투 방지) | `#expect(!viewModel.contains("ExportEngine"))` | 주석 달아 유지 |

판단 기준: **"무언가가 존재하면 안 된다"** → 제거. **"무언가가 다른 계층에 침투하면 안 된다"** → 유지 후보.

부정 단언 상위 파일: `Phase14TimelineDarkFillStaticContractTests`(15), `R402InspectorSubtabStaticContractTests`(12), `R401InspectorContextStaticContractTests`(9), `Phase03BrowseableCardsStaticContractTests`(9), `P3DocsCleanupStaticContractTests`(8).

#### W2-3 — 렌더 프로세서 단언을 골든 픽셀로 승격

가장 가치가 크다. `Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift`가 패턴을 확립했다 — software `CIContext` + `assertRendererFunctional()`로 headless에서 픽셀 assertion이 조용히 skip되던 문제를 해결한 선례다. 승격 순서: 렌더 프로세서 > 시간 매핑 > 오디오 분석.

**수용 기준 (3단계 공통)**
- 테스트 수는 **줄어드는 것이 정상**이다. 줄어든 만큼이 원래 가짜 신호였다.
- 줄어든 뒤에도 `swift test` green.
- 보고에 **삭제 전/후 테스트 수와 3개 지표(StaticContract 파일 / 부정단언 / docs단언) 변화를 실측치로** 기록.
- 삭제한 각 단언이 (a)삭제 (b)승격 (c)유지 중 어디에 해당하는지 근거 1줄.

**커밋**: `test(moviecut): drop docs prose assertions from static contracts` / `test(moviecut): retire defect-locking negative assertions` / `test(moviecut): promote render processor contracts to golden pixel tests`

<details>
<summary>세션 시작 프롬프트 — W2-1 (docs 산문 단언)</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W2-1을 수행해줘.

먼저 현재 수치를 직접 측정해서 보여줘 (기준선: 테스트파일 137, StaticContract 85,
부정단언 248, docs단언 43). 그 다음 docs/*.md 산문을 단언하는 테스트를 제거해.
P3DocsCleanupStaticContractTests(11건), KeyboardShortcut(3), IAMenuPosition(3),
F06ImportMetadata(3)가 상위다.

원칙: 문서 산문은 테스트 대상이 아니다. 다만 문서의 *구조적 사실*
(예: "매트릭스에 N개 defer 항목이 있다")만 검증하는 소수는 남기거나
별도 문서 검증 스크립트로 분리를 검토해.

삭제 전에 그 문서가 아직 유효한지 확인해 — 죽은 문서를 테스트가
살려두고 있었을 수 있다. 죽은 문서면 문서도 같이 정리 대상으로 보고해.

완료 후 swift test를 필터 없이 실행하고 출력을 첨부해. 테스트 수가
줄어드는 건 정상이다(가짜 신호 제거가 목표). 삭제 전/후 4개 지표 변화를
실측치로 보고하고, 각 삭제 건의 근거를 1줄씩 남겨줘.
```
</details>

<details>
<summary>세션 시작 프롬프트 — W2-2 (부정 단언 전수 조사)</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W2-2를 수행해줘.

Tests/ 전체의 부정 단언 248건(`#expect(!`)을 전수 조사해서 두 종류로 분류해:

  (a) 결함 고정 — "이 기능이 존재하면 안 된다"를 잠그는 것. 제거 대상.
      예: #expect(!iosCompositor.contains("TransitionPixelProcessor.apply"))
      이런 건 나중에 그 기능을 구현하면 테스트가 깨지므로 개발을 적극 방해한다.
  (b) 경계 방향 — "이것이 다른 계층에 침투하면 안 된다". 주석 달아 유지.
      예: UI 뷰모델이 코어 서비스를 직접 호출하지 않음

부정단언 상위 파일부터 시작해: Phase14TimelineDarkFill(15), R402InspectorSubtab(12),
R401InspectorContext(9), Phase03BrowseableCards(9), P3DocsCleanup(8).

분류표를 먼저 보여주고, 내 확인 없이 바로 삭제하지 말고 (a)로 분류한 것들의
목록과 근거를 제시해줘. 애매한 건 애매하다고 표시해.

미구현 상태 추적은 docs/PLATFORM_PARITY_MATRIX.md로 충분하다 —
테스트로 잠글 필요 없다.
```
</details>

<details>
<summary>세션 시작 프롬프트 — W2-3 (골든 픽셀 승격)</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W2-3을 수행해줘.

렌더 프로세서의 존재를 문자열로 확인하는 StaticContract 단언을
Tests/MovieCutCoreTests/Support/GoldenPixelHarness.swift 패턴의 실제 픽셀
비교 테스트로 승격해줘.

GoldenPixelHarness는 software CIContext + assertRendererFunctional()로
headless에서 픽셀 assertion이 조용히 skip되던 문제를 이미 해결한 선례다.
반드시 이 패턴을 따라. skip 함정을 재현하지 마.

승격 우선순위: 렌더 프로세서 > 시간 매핑 > 오디오 분석.
Sources/MovieCutCore/Rendering/의 15개 프로세서 중 아직 골든 커버리지가
없는 것부터 찾아서 시작해.

어떤 문자열 단언을 어떤 픽셀 테스트로 대체했는지 대응표를 만들고,
swift test 전체 출력을 첨부해줘. 승격한 테스트가 실제로 실행됐는지
(skip이 아닌지) 확인 가능한 증거도 같이.
```
</details>

---

### W3 — SwiftLint 베이스라인 확립

**실측 근거**: 1,022건 (error 414 / warning 608). CI는 `|| true`로 비블로킹.

error 414건의 규칙별 분해:

| 규칙 | error 수 | 성격 |
|------|---------|------|
| `identifier_name` | **326 (79%)** | `w`, `h`, `x`, `dx`, `dy` 등 수학/기하 짧은 이름 |
| `line_length` | 18 | |
| `function_body_length` | 14 | |
| `force_try` | 12 | 실제 위험 |
| `type_body_length` / `file_length` | 22 | |
| `force_cast` | 8 | 실제 위험 |
| 기타 | 14 | |

**판단이 필요한 지점**: error의 79%가 `identifier_name`이고, 샘플을 보면 `ReframeSmoothing.swift`의 `dx`/`dy`/`w`/`h`처럼 **수학 코드에서 정당한 짧은 이름**이다. 이건 코드 결함이 아니라 룰 설정 문제로 보인다. `.swiftlint.yml`에 `identifier_name: min_length` 완화 또는 `allowed_symbols`/제외 목록을 두면 error가 326건 사라진다.

별개로 `force_unwrapping` 169건은 Tests 108 / Core 46 / Mac 14 / iOS 1로 분포한다. 테스트의 force unwrap은 상대적으로 무해하지만 **Core 46건은 크래시 경로**이므로 별도 검토 가치가 있다.

**수용 기준**
- `identifier_name` 설정 변경 여부를 **근거와 함께 결정**하고 문서화 (그냥 끄지 말 것 — 왜 이 코드베이스에서 정당한지 설명)
- 조정 후 남은 error 수를 실측 보고
- CI를 error에 대해 **블로킹으로 전환할 수 있는지** 판단하고, 가능하면 전환
- `swift test` + Mac 빌드 회귀 없음

**커밋**: `chore(moviecut): establish swiftlint baseline and gate errors in ci`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W3을 수행해줘.

현재 swiftlint 1,022건(error 414 / warning 608)이고 CI에서 비블로킹이다.
목표는 "0건 만들기"가 아니라 **CI에서 error를 블로킹으로 만들 수 있는
상태**를 만드는 것이다.

먼저 swiftlint lint를 직접 실행해서 규칙별 분해를 확인해.
내 실측으로는 error 414건 중 326건(79%)이 identifier_name이고,
샘플이 ReframeSmoothing.swift의 dx/dy/w/h 같은 수학 코드의 정당한
짧은 이름이었다. 이게 정말 그런지 직접 확인하고 판단해줘.

판단해야 할 것:
1. identifier_name을 .swiftlint.yml에서 완화할 것인가? 완화한다면
   그냥 끄지 말고 왜 이 코드베이스에서 짧은 이름이 정당한지 근거를 남겨.
   (수학/기하 코드에 한정한 예외인지, 전역 완화인지도 결정)
2. force_try 12 / force_cast 8은 실제 크래시 경로다. 개별 검토해줘.
3. force_unwrapping 169건 중 Core 46건은 별도 이슈로 기록만 하고
   이번 범위에서는 제외해도 좋다 (Tests 108건은 무해).

조정 후 남은 error 수를 실측하고, .github/workflows/ci.yml의 lint job을
블로킹으로 전환 가능한지 판단해. 가능하면 전환하고, 불가능하면 왜인지 써줘.

마지막에 swift test 전체와 Mac 빌드로 회귀 없음을 확인하고 출력 첨부.
```
</details>

---

## 3. Track 2 — iOS 26.5 플랫폼 설치 후

> **선행 조건 (사용자 조치)**: Xcode > Settings > Components에서 iOS 26.5 설치.
> 확인 명령: `xcrun simctl list devices available | grep -v Unavailable`
> 현재 상태: `iOS 26.5 is not installed` — 물리 기기(`CooL iPhone13프로`)도 ineligible.

**Track 2의 어떤 작업도 이 조치 없이는 "완료"로 처리하면 안 된다.** iOS 코드는 컴파일조차 되지 않으므로, 코드를 쓸 수는 있어도 그것이 빌드되는지조차 알 수 없다.

### W4 — iOS 테스트 인프라 구축 (W5~W7의 선행 조건)

**실측 근거**
- `project.yml`: 5개 타겟(MovieCutMac, MovieCutiOS, MovieCutCoreTests, MovieCutMacTests, MovieCutMacUITests). **iOS 테스트 타겟 없음** (`grep -c MovieCutiOSUITests project.yml` → 0)
- `App/MovieCutiOSUITests/` 디렉토리 **없음**
- iOS 소스에 `MOVIECUT_UITEST` 문자열 **0건** — iOS harness가 전혀 없다

**참조 패턴 (실측 확인됨)**
- macOS harness 진입점: `App/MovieCutMac/ContentView.swift:25` (`.task { await viewModel.runUITestHarnessIfRequested() }`)
- macOS harness 본체: `App/MovieCutMac/UITestHarness.swift:149` (`func runUITestHarnessIfRequested() async`), 게이트 62종
- iOS 진입점 대상: `App/MovieCutiOS/iOSContentView.swift`
- macOS XCUITest 예: `App/MovieCutMacUITests/ImportExportE2ETests.swift`

**⚠️ xcodegen 함정**: `project.yml` 변경 후 `xcodegen generate`가 필요하지만, **`info:` 블록을 추가하면 안 된다.** MovieCutMac/MovieCutiOS의 Info.plist는 hand-maintained이며 (custom UTExportedTypeDeclarations, 마이크 권한) `INFOPLIST_FILE`로 참조된다. `info:` 블록을 넣으면 xcodegen이 덮어쓴다. project.yml에 주석으로 경고가 달려 있으니 지우지 말 것.

**수용 기준**
- iOS 시뮬레이터에서 앱이 빌드 + 실행
- iOS harness가 import → export 파이프라인을 **실제로** 구동
- 생성된 mp4의 존재와 duration을 ffprobe로 확인 (파일 경로와 출력 첨부)

**커밋**: `test(moviecut): add ios simulator test infrastructure`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W4를 수행해줘.

먼저 iOS 플랫폼이 설치됐는지 확인해:
  xcrun simctl list devices available
  xcodebuild -project MovieCut.xcodeproj -scheme MovieCutiOS \
    -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

설치 안 됐으면 거기서 멈추고 알려줘 — 이 작업은 진행 불가다.
(2026-07-29 기준으로는 iOS 26.5 미설치 상태였다)

설치돼 있으면:
1. project.yml에 MovieCutiOSUITests 타겟 추가
   (bundle.ui-testing, platform iOS, TEST_TARGET_NAME: MovieCutiOS)
   ⚠️ info: 블록을 절대 추가하지 마. Info.plist는 hand-maintained이고
   INFOPLIST_FILE로 참조된다. xcodegen이 덮어쓰면 커스텀 UTI 선언과
   마이크 권한이 날아간다. project.yml의 기존 경고 주석도 지우지 마.
2. xcodegen generate
3. App/MovieCutiOS/iOSContentView.swift에 DEBUG harness 진입점 추가.
   macOS 패턴 차용: App/MovieCutMac/ContentView.swift:25의
   `.task { await viewModel.runUITestHarnessIfRequested() }`
   본체는 App/MovieCutMac/UITestHarness.swift:149 참고 (게이트 62종)
4. IOSEditorViewModel에 harness 확장 (import → export → 결과 직렬화)
5. App/MovieCutiOSUITests/에 첫 XCUITest 작성
   (macOS 예: App/MovieCutMacUITests/ImportExportE2ETests.swift)
6. 시뮬레이터에서 실제 실행:
   xcodebuild -scheme MovieCutiOS -destination 'platform=iOS Simulator,name=<설치된기기>' test

수용 기준은 "코드를 썼다"가 아니라 "시뮬레이터에서 실제로 돌았다"이다.
export된 mp4의 경로와 ffprobe duration 출력을 증거로 첨부해줘.
안 된 부분은 안 됐다고 명시하고.
```
</details>

---

### W5 — chroma / background-removal shared processor 전환

**실측 근거**: `App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift`(1,052줄)에서
`ChromaKeyPixelProcessor` **0회**, `PersonSegmentationCompositor` **0회** 호출. 전부 inline 재구현이다.

| 지점 | 실측 위치 |
|------|----------|
| iOS inline segmentation | `IOSCustomVideoCompositor.swift:794` `applyPersonSegmentation` |
| iOS inline chroma key | `IOSCustomVideoCompositor.swift:934` `applyChromaKey` |
| macOS 참조 (chroma) | `App/MovieCutMac/Export/CustomVideoCompositor.swift:544,546` |
| macOS 참조 (segmentation) | `CustomVideoCompositor.swift:1085` `align`, `:1091` `removeBackground` |
| Core 프로세서 | `Sources/MovieCutCore/Rendering/ChromaKeyPixelProcessor.swift`, `PersonSegmentationCompositor.swift` |

**참고**: 이 전환을 막던 `IOSParityMatrixStaticContractTests`의 결함 고정 부정 단언 3건은 `b5d2384`에서 **이미 제거됨**. 이전 지시서의 "assertion을 반전하라"는 지시는 더 이상 유효하지 않다.

**커밋**: `refactor(moviecut): route ios chroma and segmentation through shared processors`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W5를 수행해줘.
선행 조건: W4(iOS 테스트 인프라)가 완료돼 있어야 한다. 아니면 먼저 알려줘.

App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift의 inline 구현을
Core shared processor 호출로 교체해:
  :934 applyChromaKey        → ChromaKeyPixelProcessor.apply
  :794 applyPersonSegmentation → PersonSegmentationCompositor

macOS 참조 구현:
  App/MovieCutMac/Export/CustomVideoCompositor.swift:544,546 (chroma)
  App/MovieCutMac/Export/CustomVideoCompositor.swift:1085,1091 (segmentation)

참고: 이 전환을 막던 IOSParityMatrixStaticContractTests의 부정 단언은
b5d2384에서 이미 제거됐다. 반전할 assertion은 없다 —
있다고 가정하지 말고 현재 파일을 직접 확인해.

검증: iOS 시뮬레이터에서 chroma key와 background removal이 적용된
export를 실제로 만들고, macOS 동일 프로젝트 export와 픽셀 비교해줘.
edgeShrink/softness 파리티가 핵심이다 (이게 안 맞아서 defer됐던 항목).

완료 후 docs/PLATFORM_PARITY_MATRIX.md의 해당 항목을 실측 결과로 갱신해.
```
</details>

---

### W6 — two-source transition iOS 배선

**실측 근거**: `IOSCustomVideoCompositor.swift`에서 `TransitionPixelProcessor` **0회** 호출. single-source만 처리한다.

| 지점 | 실측 위치 |
|------|----------|
| iOS instruction | `IOSCustomVideoCompositor.swift:222` `final class CustomCompositionInstruction` (transition 정보 없음) |
| iOS 요청 진입 | `IOSCustomVideoCompositor.swift:302` `startRequest` |
| iOS 단일 소스 | `IOSCustomVideoCompositor.swift:913` `firstSourceFrame` |
| macOS two-source | `App/MovieCutMac/Export/CustomVideoCompositor.swift:410` `startRequest`, `:437` `TransitionPixelProcessor.apply` |

**참고**: W5와 마찬가지로 관련 결함 고정 단언은 `b5d2384`에서 이미 제거됨.

**커밋**: `feat(moviecut): wire two-source transitions on ios compositor`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W6을 수행해줘.
선행 조건: W4 완료. 아니면 먼저 알려줘.

iOS compositor에 two-source transition 경로를 추가해.
현재 App/MovieCutiOS/Export/IOSCustomVideoCompositor.swift는
single-source만 처리한다 (TransitionPixelProcessor 호출 0회).

작업 지점 (실측):
  :222 CustomCompositionInstruction — transitionEffects / activeTransition(at:) 추가
  :302 startRequest — two-source branch 추가
  :913 firstSourceFrame — secondSourceFrame 헬퍼 추가

macOS 참조: App/MovieCutMac/Export/CustomVideoCompositor.swift
  :410 startRequest의 two-source branch
  :437 TransitionPixelProcessor.apply 호출

참고: 관련 결함 고정 단언은 b5d2384에서 이미 제거됐다.
반전할 assertion이 있다고 가정하지 말고 현재 파일을 직접 확인해.

검증: cross dissolve 시나리오를 iOS 시뮬레이터 export로 실제 렌더링하고,
macOS 동일 시나리오와 프레임 비교해줘. 전환 구간 중간 프레임이
두 소스의 블렌드인지 확인 (single-source면 그냥 한쪽만 보인다).

완료 후 docs/PLATFORM_PARITY_MATRIX.md 갱신.
```
</details>

---

### W7 — harness 완주 시나리오 + parity 전체 실행

**실측 근거**: `App/MovieCutMac/UITestHarness.swift`에 게이트 62종이 있으나 12단계 수동 완주 시나리오에 필요한 4개가 없다.

| 12단계 항목 | 게이트 | 상태 |
|------|--------|------|
| import / speed / ramp / transition / text / BGM / split / delete / ripple / export | 있음 | ✅ |
| **sticker at 5s** | `MOVIECUT_UITEST_STICKER_AT` | ❌ 없음 |
| **trim** | `MOVIECUT_UITEST_TRIM_END_AT` | ❌ 없음 |
| **undo (parity 경로)** | `MOVIECUT_UITEST_UNDO` | ❌ 없음 |
| **play** | `MOVIECUT_UITEST_PLAY` | ❌ 없음 |
| **preview vs export duration 비교** | — | ❌ 없음 |

(`MOVIECUT_UITEST_UNSAVED_GUARD` / `_UNSAVED_RESPONSE`는 `3dcc5cd`에서 추가됨.)

관련 스크립트: `scripts/run_core_editing_parity.sh`(7 시나리오), `scripts/verify_preview_export_parity.py`(frame MAD 비교, duration 비교 없음).

**알려진 제약**: transition 시나리오는 이 호스트의 headless harness에서 `CustomVideoCompositor` build가 완료되지 않는다. working GPU compositor host가 필요하다.

**커밋**: `test(moviecut): drive full manual completion scenario through harness`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/NEXT_SESSION_WORKORDER_20260729.md의 W7을 수행해줘.
선행 조건: W4~W6 완료 권장 (iOS 파리티 검증이 목적이므로).

1. App/MovieCutMac/UITestHarness.swift의 applyParityScenarioEdits에
   빠진 게이트 4개 추가:
     MOVIECUT_UITEST_STICKER_AT
     MOVIECUT_UITEST_TRIM_END_AT
     MOVIECUT_UITEST_UNDO=1
     MOVIECUT_UITEST_PLAY=1
   기존 게이트 62종의 명명/구현 패턴을 따라.

2. scripts/verify_preview_export_parity.py에 duration 비교 추가.
   ffprobe로 export duration을 뽑아 harness의 composition duration과
   1프레임 이내로 일치하는지 확인. 현재는 frame MAD 비교만 있다.

3. scripts/run_core_editing_parity.sh에 12단계 완주 시나리오 추가
   (모든 게이트를 하나의 구동으로 연결).

알려진 제약: transition 시나리오는 이 호스트의 headless harness에서
CustomVideoCompositor build가 완료되지 않는다. 실행이 막히면
"막혔다"고 보고해 — 통과한 것처럼 쓰지 마. 어떤 시나리오가 실행됐고
어떤 게 못 돌았는지 표로 구분해줘.

각 시나리오의 실제 실행 출력과 생성된 mp4 경로를 증거로 첨부.
```
</details>

---

## 4. 권장 진행 순서

```
[완료]     W1 ✅ (7b5b2ad)
             ↓
[병렬 가능] W3 (린트 베이스라인)  ┃  W2-1 → W2-2 → W2-3 (세션 분리)
             ↓
[사용자 조치] iOS 26.5 플랫폼 설치
             ↓
           W4 (선행 조건)
             ↓
           W5 ┃ W6  (병렬 가능, 둘 다 iOS compositor를 건드리므로
             ↓        같은 세션이 아니면 충돌 주의)
           W7 (최종 검증)
```

W2는 세 단계를 각각 별도 세션으로 돌리는 것을 권장한다. 특히 W2-2는 248건 분류에 판단이 많이 들어가므로 단독 세션이 낫다.

---

## 5. 모든 세션 공통 규칙

0. **시작 전에 main 위치를 먼저 확인할 것.** 여러 세션이 동시에 돌 수 있다. 실제로 이 문서를 쓰는 동안 다른 세션이 W1을 완료해 main이 `d0ad5a7` → `7b5b2ad`로 이동했고, 문서가 발행되기도 전에 한 항목이 낡았다. `git log -1 --oneline main`과 `git branch -v`로 시작하고, 담당 작업이 이미 끝났는지 확인한 뒤 착수한다.

1. **자가보고 수치를 신뢰하지 말 것.** 이전 문서의 "N개 테스트 통과"를 옮겨 적지 말고 직접 실행해서 얻은 출력을 첨부한다. 실제로 7/28 문서의 "145개 Core 테스트 통과"는 필터링된 부분 실행 결과였고, 전체 실행은 hang이었다.

2. **DoD는 증거 기반이다.** "구현 완료"는 완료가 아니다. 빌드/테스트/실행 출력이 있어야 완료다. 검증 못 한 항목은 미검증으로 분리해서 보고한다.

3. **기준선**: `swift build` 성공 / `swift test` **984 tests 전부 통과** / Mac `xcodebuild` BUILD SUCCEEDED. 작업 후 이 셋이 유지되는지 확인한다. (W2는 예외 — 테스트 수 감소가 정상)

4. **StaticContract를 새로 추가하지 말 것.** 부채가 이미 62%다. 새 검증이 필요하면 동작 테스트로 쓴다.

5. **xcodegen**: `project.yml` 변경 시 `xcodegen generate` 필요. 단 `info:` 블록은 절대 추가 금지 (hand-maintained Info.plist를 덮어쓴다).

6. **브랜치**: 각 작업은 `fix/<name>` 또는 `refactor/<name>` 브랜치에서 진행 후 main에 fast-forward 병합.

7. **iOS 관련 주장은 검증 없이 하지 말 것.** 이 호스트에서 iOS는 컴파일조차 안 된다. 플랫폼 설치 전까지 iOS 코드 변경은 전부 미검증이다.

---

## 6. 이번 실사에서 확인된 양호 항목 (건드리지 말 것)

- `swift test` 완주 구조 (Task A의 GCD 오프로딩). 블로킹 디코드를 cooperative pool로 되돌리면 hang이 재발한다. CI의 `timeout-minutes: 15`가 이 회귀를 red로 잡아주는 장치다.
- `GoldenPixelHarness`의 `assertRendererFunctional()` 게이트 — headless silent skip을 막는다.
- `project.yml`의 hand-maintained Info.plist 주석 — xcodegen 덮어쓰기 방지.
- CI의 Mac 앱 빌드 단계 (`b75e6be`) — Core 테스트가 못 잡는 App-side 회귀를 잡는다.
