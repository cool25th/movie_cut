# 코드 검토 지적사항 작업지시서 — V13 배선 3종

> **[상태: 대체됨 — 역사 기록]** 이 문서의 R1~R5 지적사항은 `.kiro/specs/capcut-parity-and-bugfix/` 스펙(2026-07-31)으로 이관·해소됐다. 현역 판정은 그 스펙의 `tasks.md`와 `docs/README.md`를 본다. 이 파일은 역사 기록으로 제자리에 둔다.
>
> 작성일: 2026-07-29
> 대상 브랜치: `feat/wire-v13-gap-trio` (`cfa6f70`, main 미병합 — 3커밋 앞섬)
> 검토 대상: `f82a48e` 카라오케 / `505696f` 프록시 소비 / `cfa6f70` 한국어 카탈로그
> 성격: **검토에서 실증된 지적사항만 기재.** 각 항목은 재현 방법과 정확한 수정 지점을 포함한다.

## 0. 검증된 기준선 (2026-07-29 실측)

| 검증 | 결과 |
|------|------|
| `swift build` | ✅ |
| `swift test` | ✅ **992 tests / 163 suites 통과** (커밋 주장 수치와 일치: 984 → 987 → 992) |
| `xcodebuild MovieCutMac` | ✅ BUILD SUCCEEDED |
| `scripts/verify_gate.sh` | ✅ **GATE_PASS** |
| iOS 빌드 | ❌ 불가 — iOS 26.5 플랫폼 미설치 |

**게이트가 통과하는데도 R1은 실제 사용자에게 깨진 화면을 보여준다.** 게이트는 회귀 방지용이지 정확성 증명이 아니다.

### 브랜치 처리 방침

`feat/wire-v13-gap-trio`는 **아직 main에 병합되지 않았다.** R1은 이 브랜치가 들여온 버그이므로 **같은 브랜치에서 고친 뒤 병합**한다. main에 버그를 넣었다 빼는 커밋을 남기지 않는 편이 이력상 깨끗하다.

---

## 1. R1 — 카라오케 자막 공백 유실 (P0, 출시 차단)

### 문제 (픽셀로 실증됨)

카라오케를 켜면 단어 사이 공백이 사라져 `자동자막이렇게붙어보입니다` 형태로 렌더된다. **export와 preview 양쪽 모두** 동일한 결함을 가진다.

원인은 두 곳에서 반복되는 같은 패턴이다. `split`은 구분자를 **소비**하는데, 재조립 루프가 구분자를 다시 넣지 않는다.

| 파일 | 토큰화 | 재조립 |
|------|--------|--------|
| `Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift` | `:352` | `:382` |
| `App/MovieCutMac/Playback/PlaybackEngine.swift` | `:1461` | `:1477` |

두 지점 바로 위 주석이 **정반대를 주장한다**: "Preserve original whitespace exactly so the highlighted string still matches the layout of the uniform version." 주석도 함께 고칠 것.

### 재현 (이 검토에서 사용한 방법)

하이라이트 색을 기본 색과 **동일하게** 두면 색 차이가 제거되고 레이아웃 차이만 남는다. 이 조건에서 카라오케 출력은 uniform 출력과 **픽셀 동일**해야 한다.

```
실측: PROBE differing-bytes=8904 of 51200  (17% 상이)
```

순수 레이아웃 차이 = 공백 유실.

### 구현 방향

- **단순히 토큰 사이에 `" "`를 넣지 말 것.** 줄바꿈과 연속 공백을 잃는다. `visibleText`의 원본 range를 보존하는 방식으로 분할해야 한다 (예: 구분자를 별도 토큰으로 유지하고 색은 단어 토큰에만 적용, 또는 `NSMutableAttributedString(string: visibleText)`를 만든 뒤 단어 range에만 `addAttribute`).
- **후자를 권장한다.** 원본 문자열을 그대로 쓰므로 공백·줄바꿈이 정의상 보존되고, 폰트/문단 스타일은 전체에 한 번만 걸면 된다.
- 두 지점이 같은 규칙을 따라야 한다 — preview와 export가 어긋나면 이 저장소의 핵심 규율 위반이다.

### 수용 기준

1. **새 테스트: 하이라이트 색 = 기본 색이면 uniform 출력과 픽셀 동일.** 이것이 R1의 단일 판정 기준이다.
2. 기존 카라오케 테스트 3개 유지 통과.
3. 공백 2개, 줄바꿈 포함 텍스트로도 1번이 성립.
4. `swift test` 992개 유지 또는 증가.
5. preview와 export가 같은 시각에 같은 문자열 레이아웃을 만든다.

### 커밋 권장

`fix(moviecut): preserve whitespace when rendering karaoke word highlights`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/REVIEW_FINDINGS_WORKORDER_20260729.md의 R1을 수행해줘.

브랜치 feat/wire-v13-gap-trio에서 작업해. (main 미병합 상태이고, 이 브랜치가
들여온 버그라 여기서 고쳐서 병합하는 게 맞다.)

카라오케 자막을 켜면 단어 사이 공백이 사라진다. split이 구분자를 소비하는데
재조립 루프가 다시 넣지 않는다. 두 곳에 같은 패턴이 있다:
  Sources/MovieCutCore/Rendering/TextOverlayPixelProcessor.swift:352(분할), :382(재조립)
  App/MovieCutMac/Playback/PlaybackEngine.swift:1461(분할), :1477(재조립)

먼저 버그를 스스로 재현해서 확인해줘. 방법: 하이라이트 색을 기본 색과
동일하게 두면 색 차이가 사라지고 레이아웃 차이만 남는다. 이 조건에서
카라오케 출력은 uniform 출력과 픽셀 동일해야 하는데 실제로는 다르다.
(내 실측: 51200바이트 중 8904바이트 상이)

수정 시 주의:
- 토큰 사이에 " "를 넣는 방식은 쓰지 마. 줄바꿈과 연속 공백을 잃는다.
- 권장: 원본 문자열로 NSMutableAttributedString을 만들고 단어 range에만
  addAttribute로 색을 입힌다. 공백이 정의상 보존된다.
- 두 지점이 반드시 같은 규칙을 따라야 한다. preview와 export가 어긋나면
  이 저장소의 핵심 규율 위반이다.
- 두 지점 위의 주석이 "Preserve original whitespace exactly"라고 사실과
  반대로 적혀 있다. 주석도 실제 동작에 맞게 고쳐줘.

테스트를 반드시 추가해: "하이라이트 색 = 기본 색이면 uniform과 픽셀 동일".
이게 R1의 단일 판정 기준이다. 공백 2개와 줄바꿈이 든 텍스트로도 확인해.
기존 골든 픽셀 테스트 패턴(GoldenPixel.assertRendererFunctional)을 따라.

완료 후 scripts/verify_gate.sh를 실행하고 출력을 첨부해.
기준선은 992 tests다. iOS는 이 호스트에서 검증 불가이니 미검증으로 분리해 보고해.
```
</details>

---

## 2. R2 — 기존 카라오케 테스트의 검증 공백

### 문제

R1이 게이트를 통과한 이유다. 테스트 3개 중 **카라오케 경로를 실제로 타는 것은 하나뿐**이고, 그 하나도 잘못된 것을 본다.

| 테스트 (`Tests/MovieCutCoreTests/TextOverlayPixelProcessorTests.swift`) | 실제로 검증하는 것 |
|---|---|
| `karaokeDisabledMatchesUniformBaseline` | 카라오케 **비활성** → fallback 경로만 |
| `karaokeFallsBackWhenTokenCountDisagrees` | 개수 불일치 → fallback 경로만 |
| `karaokeHighlightRecolorsPixelsAcrossWords` (`:156`) | 카라오케 경로를 타지만 **green 채널 총합**만 비교 — 공백이 빠져도 글리프는 같아 총합이 거의 안 변한다 |

R1의 테스트를 추가하면 이 공백은 닫힌다. **R1과 함께 처리하고 별도 세션으로 분리하지 말 것.**

### 참고 (오해 방지)

`guard coreImageRenderingAvailable() else { return }`는 silent skip처럼 보이나 내부에서 `GoldenPixel.assertRendererFunctional()`을 호출하고 항상 `true`를 반환한다. **정상이다.** 이것을 결함으로 재보고하지 말 것.

---

## 3. R3 — 영어 로케일에서 한국어가 읽히는 접근성 레이블 3건

### 문제

`NSLocalizedString`의 **키 자체가 한국어**인 호출부가 17건 있고(대부분 `TimelineView`의 접근성 레이블), 카탈로그가 그중 14건은 영어로 번역했으나 **3건은 영어 값도 한국어로 두었다.** 영어 사용자의 VoiceOver가 한국어를 읽는다.

| 카탈로그 키 (`App/MovieCutMac/Localizable.xcstrings`의 `en` 값) | 호출부 |
|---|---|
| `%@ 오른쪽 트림 핸들` | `App/MovieCutMac/TimelineView.swift:924` |
| `%@ 왼쪽 트림 핸들` | `App/MovieCutMac/TimelineView.swift:915` |
| `%@ 클립 추가 영역` | `App/MovieCutMac/TimelineView.swift:770` |

### 구현 방향

1. 최소 수정: 카탈로그의 `en` 값 3건만 영어로 채운다 (`%@ right trim handle` 등). 나머지 14건이 이미 이 방식이다.
2. 근본 수정(권장): 한국어 키 17건을 영어 키로 바꾸고 카탈로그를 재정렬한다. `sourceLanguage`가 `en`이므로 키도 영어인 편이 일관된다. 단 카탈로그 키 변경이 동반되므로 누락이 없도록 스크립트로 대조할 것.

### 수용 기준

- 영어 로케일에서 접근성 레이블에 한글이 0건.
- 한국어 로케일 문구는 변하지 않는다.
- 카탈로그 키 개수와 코드 사용 키가 계속 일치한다 (현재: 사용 286 / 카탈로그 289).

### 커밋 권장

`fix(moviecut): give korean-keyed accessibility labels english values`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/REVIEW_FINDINGS_WORKORDER_20260729.md의 R3을 수행해줘.

App/MovieCutMac/Localizable.xcstrings에서 접근성 레이블 3건이 영어(en) 값도
한국어로 들어가 있어서, 영어 사용자의 VoiceOver가 한국어를 읽는다:
  "%@ 오른쪽 트림 핸들"  ← TimelineView.swift:924
  "%@ 왼쪽 트림 핸들"    ← TimelineView.swift:915
  "%@ 클립 추가 영역"    ← TimelineView.swift:770

배경: NSLocalizedString의 키 자체가 한국어인 호출부가 17건 있고, 카탈로그가
14건은 영어로 번역했는데 이 3건만 빠졌다.

두 가지 방법이 있으니 판단해서 진행해줘:
 (a) 최소 — 카탈로그의 en 값 3건만 영어로 채운다. 나머지 14건과 같은 방식.
 (b) 근본 — 한국어 키 17건을 전부 영어 키로 바꾸고 카탈로그를 재정렬한다.
     sourceLanguage가 en이니 이쪽이 일관되지만, 키 변경이 동반되므로
     누락이 없도록 스크립트로 코드↔카탈로그를 대조해야 한다.

어느 쪽이든 검증: 영어 로케일 접근성 레이블에 한글 0건, 한국어 문구는 불변,
코드 사용 키와 카탈로그 키가 계속 일치(현재 사용 286 / 카탈로그 289).

scripts/verify_gate.sh 실행하고 출력 첨부해줘.
```
</details>

---

## 4. R4 — iOS 현지화 카탈로그 부재

### 문제

`App/MovieCutiOS/`에 `.xcstrings`가 **없다.** 한국어 UI는 Mac 전용이다. App Store에 iOS도 올릴 계획이므로 격차로 남는다.

Mac 카탈로그 실측: 289키, `ko` 289건 전부 `translated`, `knownRegions`에 `ko` 등록됨 — **패턴은 이미 확립돼 있으니 그대로 따르면 된다.**

### 주의

iOS 소스에 `NSLocalizedString` 래핑이 되어 있는지부터 확인해야 한다. Mac은 8파일에 래핑돼 있었으나 iOS는 확인되지 않았다. 래핑이 없으면 카탈로그만 만들어도 아무 효과가 없다.

### 선행 조건

**iOS 26.5 플랫폼 설치.** 설치 전에는 빌드로 검증할 수 없다.

### 커밋 권장

`feat(moviecut): add korean localization catalog for ios`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/REVIEW_FINDINGS_WORKORDER_20260729.md의 R4를 수행해줘.
선행 조건: iOS 26.5 플랫폼 설치. 안 됐으면 거기서 멈추고 알려줘.

App/MovieCutiOS/에 현지화 카탈로그(.xcstrings)가 없어서 한국어 UI가 Mac
전용이다. Mac 쪽 패턴을 그대로 따라라:
  App/MovieCutMac/Localizable.xcstrings — 289키, ko 전부 translated,
  pbxproj knownRegions에 ko 등록됨

순서:
1. 먼저 iOS 소스에 NSLocalizedString 래핑이 있는지 확인해. Mac은 8파일에
   있었지만 iOS는 확인 안 됐다. 래핑이 없으면 카탈로그만 만들어도 효과가
   없으니, 래핑부터 해야 한다. 사용자 노출 문자열 수를 먼저 세서 보고해줘.
2. 카탈로그 생성 + 한국어 번역. Mac 카탈로그의 기존 번역과 용어를 맞춰
   (예: 같은 UI 개념에 다른 번역어를 쓰지 말 것).
3. xcodegen generate 후 pbxproj에 등록됐는지, knownRegions에 ko가 들어갔는지
   확인. ⚠️ project.yml에 info: 블록을 절대 추가하지 마 — hand-maintained
   Info.plist를 덮어쓴다.
4. iOS 시뮬레이터에서 한국어 로케일로 실행해 실제로 번역이 나오는지 확인.

Info.plist md5를 xcodegen 전후로 비교해서 덮어쓰기가 없었음을 증거로 첨부해.
```
</details>

---

## 5. R5 — 타임라인 클립의 Proxy 배지 (B-I7 파리티 잔여)

### 문제

`505696f`가 프록시 소비를 배선해 B-I7의 핵심을 상환했으나, 기준서 문장의 **"생성 완료 시 클립에 Proxy 배지"** 부분이 남았다. 현재는 미디어 라이브러리 패널에만 표시가 있다.

| 위치 | 현재 |
|---|---|
| `App/MovieCutMac/MediaLibraryPanel.swift:1382,1397` | 초록 체크 아이콘 ✅ 있음 |
| `App/MovieCutMac/TimelineView.swift` | ❌ 클립 배지 없음 |

우선순위는 낮다 — 기능은 동작하고 표시만 없다.

### 커밋 권장

`feat(moviecut): show proxy badge on timeline clips`

<details>
<summary>세션 시작 프롬프트</summary>

```
docs/REVIEW_FINDINGS_WORKORDER_20260729.md의 R5를 수행해줘.

CAPCUT_BENCHMARK_STANDARD.md B-I7이 "생성 완료 시 클립에 Proxy 배지"를
요구하는데, 현재 표시는 미디어 라이브러리 패널에만 있다
(MediaLibraryPanel.swift:1382,1397의 초록 체크 아이콘).
타임라인 클립(TimelineView.swift)에는 없다.

프록시 유무 판정은 기존 idiom을 따라: asset.proxy?.proxyURL != nil
(PlaybackEngine.swift:571, MediaLibraryPanel.swift:1793과 동일)

주의: 프록시 재생이 꺼져 있어도 프록시가 "생성됨"을 표시하는 것이 맞는지,
아니면 실제 사용 중일 때만 표시할지 판단해서 근거와 함께 보고해줘.
CapCut 실동작이 불명확하면 [추정]으로 표시하고 벤치마크 문서에 반영해.

UI 변경이므로 docs/UI_DESIGN_PRINCIPLES.md의 디자인 토큰을 쓰고 새 색/간격을
하드코딩하지 마. IAMenuPositionStaticContractTests도 계속 통과해야 한다.

완료 후 PLATFORM_PARITY_MATRIX와 벤치마크 §7 B-I 행을 갱신해줘.
```
</details>

---

## 6. 이월 항목 (`docs/NEXT_SESSION_WORKORDER_20260729.md`)

이 문서는 **검토 지적사항만** 다룬다. 아래는 그쪽 지시서에 그대로 살아 있다.

| ID | 내용 | 상태 |
|---|---|---|
| W2 | StaticContract 부채 정리 (3단계) | 미착수 — 85/137 파일(62%), 부정단언 248건 |
| W3 | SwiftLint 베이스라인 | 미착수 — error 414 중 326이 `identifier_name` |
| W4~W7 | iOS 파리티 | **차단** — iOS 26.5 플랫폼 미설치 |

### App Store 출시 차단 요소 (별도 추적)

`1266804`에서 권한 문구와 privacy manifest는 상환됐다. 남은 것:

- ❌ 앱 아이콘 (Mac/iOS 양쪽)
- ❌ 코드 서명 / `DEVELOPMENT_TEAM` (`project.yml`에 없음)
- ❌ iOS 빌드 자체 (플랫폼 미설치)

---

## 7. 권장 진행 순서

```
[즉시]  R1 + R2 (같은 세션 — R1의 테스트가 R2를 닫는다)
          ↓
        feat/wire-v13-gap-trio → main 병합
          ↓
[병렬]  R3 (접근성 3건, 작음)  ┃  W2 / W3 (이월)
          ↓
[사용자 조치] iOS 26.5 플랫폼 설치
          ↓
        R4 (iOS 카탈로그) ┃ W4~W7 (iOS 파리티)
          ↓
        R5 (프록시 배지, 낮은 우선순위)
```

**R1을 병합 전에 고칠 것.** 지금 병합하면 main이 깨진 카라오케 렌더를 갖게 된다.

---

## 8. 공통 규칙

`docs/NEXT_SESSION_WORKORDER_20260729.md` §5를 그대로 따른다. 특히:

1. **시작 전 `git log -1 --oneline main`과 `git branch -v`로 위치 확인.** 여러 세션이 동시에 돈다.
2. **자가보고 수치 금지.** 명령을 직접 실행한 출력을 첨부한다. 기준선은 `swift test` **992개**(이 브랜치 기준), main 기준은 984개.
3. **게이트 통과 ≠ 정확성.** R1이 그 반례다 — GATE_PASS인데 사용자 화면이 깨져 있었다. 새 기능은 "무엇이 틀리면 이 테스트가 빨개지는가"를 스스로 물을 것.
4. **StaticContract를 새로 추가하지 말 것.** 동작 테스트로 쓴다.
5. **iOS 관련 주장은 검증 없이 하지 말 것.** 이 호스트에서 iOS는 컴파일조차 안 된다.
6. `project.yml` 변경 시 `xcodegen generate`, 단 `info:` 블록 추가 금지.

## 9. 검토에서 확인된 양호 항목 (건드리지 말 것)

- **Codable 마이그레이션이 안전하다.** `TextClipContent.karaokeEnabled`/`highlightFontColor`, `Project.playbackSettings` 모두 `decodeIfPresent ?? 기본값`이고 인코딩은 기본값이 아닐 때만. 기존 프로젝트 파일이 그대로 열린다. `2e47780`의 CG Codable 충돌을 반복하지 않았다.
- **프록시 설계가 B-I7과 맞다.** export는 의도적으로 원본 유지, 이미지/역재생/프리즈 경로도 원본 유지. 프리셋이 `AVAssetExportPreset960x540`이라 오디오 포함이므로 오디오 트랙에 프록시를 쓰는 것도 타당하다.
- **preview와 export가 같은 카라오케 규칙을 공유한다.** R1은 양쪽에 동일하게 나타나므로 두 경로의 일관성 자체는 지켜졌다. 수정 시에도 이 일관성을 깨지 말 것.
- 테스트가 StaticContract가 아니라 골든 픽셀·동작 테스트다.
