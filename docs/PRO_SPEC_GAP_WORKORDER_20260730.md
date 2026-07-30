# Pro 스펙 대조 갭 작업지시서 — 2026-07-30

> 작성일: 2026-07-30 / 브랜치: `main` (기준 커밋 `d8bfc8c`, 작업트리 clean)
> 출처: 외부 "Principal macOS Architect" Pro 아키텍처 스펙(5 Phase)을 현 코드베이스와 대조
> 성격: **코드 수정 없음.** repo-wide grep + `Info.plist` / `project.pbxproj` / `.github/workflows` 직접 열람으로 도출
> 선행 문서: [V13 갭 분석](GAP_ANALYSIS_V13_FUNC_UI_20260729.md) · [후속 세션 지시서](NEXT_SESSION_WORKORDER_20260729.md) · [Pro 로드맵](MOVIECUT_PRO_ROADMAP_20260622.md)

---

## 0. 이 문서의 범위와 한계

외부 스펙은 **0에서 시작하는 그린필드 전제**다. 우리는 소스 65.2k줄 / 테스트 141파일 / 커밋 300개 상태이므로 스펙을 순서대로 실행하는 것은 재작성 지시가 된다. 따라서 이 지시서는 스펙에서 **우리에게 실제로 없는 것만** 추출했다.

### 0-1. 이 세션에서 실측한 것 / 안 한 것

| 구분 | 내용 |
|------|------|
| **실측함** | 파일 존재 여부(`find`), 심볼 사용처(`grep`), `Info.plist` 키 덤프(`plistlib`), `project.pbxproj` 서명 설정, CI 워크플로 단계, `Localizable.xcstrings` 키/언어 수 |
| **실행 안 함** | `swift build` / `swift test` / `xcodebuild` — **이 지시서에 빌드·테스트 수치를 옮겨 적지 않았다.** 마지막 기록된 green은 7/29 지시서의 `984 tests / 162 suites`이며, 그것은 이 문서의 측정치가 아니다 |

**착수 세션은 기준선을 직접 재측정하고 시작할 것.** 이 문서의 수치를 인용하지 말고 직접 실행한 출력을 붙일 것.

### 0-2. 다른 문서가 이미 다루는 것 — 여기서 중복 착수 금지

| 항목 | 담당 문서 |
|------|----------|
| iOS 플랫폼 미설치 / iOS 파리티 (W4~W7) | [NEXT_SESSION_WORKORDER](NEXT_SESSION_WORKORDER_20260729.md) Track 2 |
| StaticContract 부채 (W2) · 린트 베이스라인 (W3) | 동 문서 Track 1 |
| 배선 격차 (워드 캡션·미배선 서브시스템 1,279줄) · 홈 화면 · 블렌딩 모드 | [V13 갭 분석](GAP_ANALYSIS_V13_FUNC_UI_20260729.md) §3 |

---

## 1. 착수하지 않기로 한 것 (의도적 이탈 — 근거 포함)

스펙이 요구하지만 **따르지 않는다.** 후속 세션이 "스펙에 있으니 해야 한다"고 판단하지 않도록 근거를 남긴다.

| 스펙 요구 | 결정 | 근거 |
|-----------|------|------|
| Metal 전면 재작성 (MTKView·CAMetalLayer·MSL 셰이더) | **보류 유지** | [PERF_BASELINE](PERF_BASELINE_20260622.md) — CoreImage 합성이 export +9%, preview 5.51ms/frame. 병목 아님이 양 경로 측정으로 확정. 단 **S6에서 4K·무거운 합성 측정 후 재확인**(같은 문서 §한계 1·2가 명시한 재검토 트리거) |
| SwiftData 영속화 | **채택 안 함** | 문서형 앱에는 현재의 JSON + `actor ProjectStore`가 적합. 단 스키마 마이그레이션 부재는 별개 문제 → **S1** |
| Touch Bar (`NSTouchBar`) | **채택 안 함** | 단종 하드웨어. 투자 대비 도달 사용자 없음 |
| Intel Universal Binary | **arm64 우선 유지** | Pro 포지셔닝 + 단일 개발 흐름. 결정만 문서화하고 재론 금지 |
| SPM 다중 모듈 분해 (`TimelineKit`/`MediaEngine` 등) | **전면 재편 안 함** | 단 지적 자체는 유효 — `EditorViewModel.swift` **6,268줄** 단일 파일이 App 계층 테스트 사각지대다. 모듈 분해가 아니라 **파일 분해**로 별도 처리(이 지시서 범위 밖, 백로그) |

---

## 2. 트랙 구분

```
Track R — 출시 차단 (순서 의존, 반드시 이 순서)
  S1  프로젝트 스키마 마이그레이션 경로        [S2의 선행 조건]
  S2  Security-Scoped Bookmark 저장/복원       [S3의 선행 조건]
  S3  App Sandbox + entitlements
  S4  앱 아이콘 · 번들 메타데이터
  S5  서명 · 공증 · 배포 파이프라인

Track T — 주장 방어 (Track R과 병렬 가능, 가장 저렴)
  S8  STT 온디바이스 강제 + 폴백 고지

Track P — 성능·신뢰 (Track R과 병렬 가능)
  S6  4K · 열 · 메모리 실측                    [S7·Metal 결정의 입력]
  S7  thermalState 기반 프록시 자동 강등

Track U — Pro 편집 조작
  S9  J/K/L · 툴 모드 · slip/slide · Cmd+스크롤 줌

Track O — 관측
  S10 OSLog · MetricKit 최소 도입

Track D — 착수 전 결정 필요
  S11 캡처 입력 (카메라 / 화면 녹화 / Continuity Camera)
```

**무인 자율 큐(`AUTONOMOUS_WORK_*.md`)에 넣지 말 것.** S1·S2는 `Sources/MovieCutCore/**`의 public 모델을 변경하고, S3·S5는 빌드 설정·배포를, S6~S9는 판단을 요구한다. 셋 다 [무인 안전 정책](archive/AUTONOMOUS_WORK_20260729.md)의 금지 항목이다.

---

## 3. 공통 규칙

1. **별도 브랜치**에서 작업. main 직접 수정 금지.
2. 각 항목 완료 후 `scripts/verify_gate.sh` 실행. `GATE_PASS`가 아니면 revert 후 사유 기록.
3. **테스트 수는 유지 또는 증가.** 감소 시 조사 기록 필수.
4. **StaticContract(소스 문자열 존재 검사)로 DoD를 대체 금지.** [V13 §1](GAP_ANALYSIS_V13_FUNC_UI_20260729.md)이 확인했듯 통과 수치의 62%가 동작 신호가 아니다. 이 지시서의 모든 DoD는 **실행 산출물**(명령 출력 · 파일 해시 · 스크린샷 · 재시작 후 동작)로만 충족된다.
5. **자가보고 수치 금지.** 보고에 쓰는 모든 숫자는 그 세션에서 직접 실행한 명령의 출력이어야 한다.
6. 커밋 메시지는 각 항목에 명시된 형식을 따른다.

---

## Track R — 출시 차단

> 이 트랙 전체가 App Store 등록 목표(세션 메모리 `moviecut-appstore-goal`)의 실제 차단 요소다. **S1 → S2 → S3 순서를 지킬 것.** 순서를 어기면 샌드박스를 켠 순간 기존 프로젝트가 열리지 않는다.

### S1 — 프로젝트 스키마 마이그레이션 경로

**실측 근거**

| 사실 | 위치 |
|------|------|
| `schemaVersion: Int` 필드가 존재하고 인코딩/디코딩됨 | `Sources/MovieCutCore/Models/Project.swift:21,105,123` |
| 그 값을 **읽고 분기하는 코드 0건** — `grep -rl "migrat" Sources/` → 0 | — |
| 유일한 소비처는 병합 시 `max()` | `Sources/MovieCutCore/Cloud/CloudSyncService.swift:498` |
| 디코딩은 `try container.decode(Int.self, ...)` 무조건 요구 | `Project.swift:105` |

즉 **버전 번호를 쓰기만 하고 아무도 읽지 않는다.** 출시 후 스키마가 한 번이라도 바뀌면 기존 프로젝트는 열리지 않거나 조용히 오해석된다. S2가 `MediaAsset`에 필드를 추가하므로 **S2 이전에 반드시 선행**해야 한다.

**작업 내용**

1. `ProjectStore.load`에 버전 분기 도입: `schemaVersion > currentSchemaVersion` → 명시적 "더 새 버전의 프로젝트" 오류(사용자에게 앱 업데이트 안내), `<` → 마이그레이터 체인 통과.
2. 마이그레이터 프로토콜 + 등록 지점 신설(`Storage/ProjectMigration.swift` 등). v1 → v2 마이그레이터는 S2에서 추가되므로 여기서는 **체인 골격과 v1 항등 마이그레이터**까지.
3. 알 수 없는 미래 키에 대한 디코딩 관용성 결정(무시 후 보존 vs 손실) — 손실이면 사용자 경고 경로까지.

**수용 기준 (DoD)**

- 구버전 JSON 픽스처(현행 v1 프로젝트 파일)를 커밋하고, 그것을 로드하는 테스트가 **실제로 로드에 성공**함을 보인다(문자열 검사 아님).
- 미래 버전(`schemaVersion: 999`) 픽스처 로드 시 **크래시가 아닌 명시적 오류**가 나오고, 그 오류 메시지가 UI까지 도달함을 확인한 스크린샷.
- `swift test` 전체 출력 첨부.

**커밋**: `feat(moviecut): add project schema migration chain`

---

### S2 — Security-Scoped Bookmark 저장/복원

**실측 근거**

| 사실 | 위치 |
|------|------|
| `startAccessingSecurityScopedResource` 계열 **사용 0건** | repo 전체 |
| 미디어 참조는 원본 URL 문자열을 그대로 직렬화 | `Sources/MovieCutCore/Models/MediaAsset.swift:20` (`public var originalURL: URL`, `CodingKeys.originalURL`) |
| 파일 접근 진입점 8곳 (`NSOpenPanel`/`NSSavePanel`) | `MovieCutMacApp.swift:29,44` · `MediaLibraryPanel.swift:1666` · `EditorViewModel.swift:839,861,898,970,1009` |
| 프록시 파일도 URL로 참조 | `Sources/MovieCutCore/Models/ProxyInfo.swift:6` |

**샌드박스를 켜는 것은 체크박스 하나가 아니라 저장 포맷 변경이다.** 현재 구조로 S3를 먼저 하면 앱 재시작 후 모든 미디어 참조가 끊긴다.

**작업 내용**

1. `MediaAsset`에 북마크 데이터 필드 추가(예: `originalBookmark: Data?`) + `ProxyInfo`의 프록시 경로도 앱 컨테이너 내부로 이전할지 결정(컨테이너 내부면 북마크 불필요 — **이쪽이 단순**하므로 우선 검토).
2. 패널 8곳에서 URL 획득 직후 북마크 생성, 로드 시 resolve + stale 처리(재선택 유도 UI 포함).
3. 접근 범위 관리: `startAccessing`/`stopAccessing` 짝 보장(액터 경계에서 누수되지 않도록).
4. S1의 마이그레이터 v1 → v2 추가: 북마크 없는 기존 프로젝트를 로드할 때의 동작 정의(경로가 살아 있으면 북마크 재생성, 아니면 재선택 요청).

**수용 기준 (DoD)**

- **샌드박스를 켠 빌드**에서: 미디어 import → 저장 → **앱 완전 종료 후 재실행** → 프로젝트 재열기 → preview 재생 + export 성공. 각 단계 스크린샷 + export 산출물 해시.
- stale 북마크 경로: 파일을 다른 위치로 옮긴 뒤 재열기 → 재선택 UI가 뜨고 복구되는 것을 확인한 녹화.
- v1 프로젝트 마이그레이션 후 위 시나리오 동일 통과.

**위험**: `MediaAsset`은 public API다. 무인 작업 금지 항목이며, 변경 시 `CloudSyncService`·`UITestHarness`·테스트 픽스처 전반이 함께 움직인다.

**커밋**: `feat(moviecut): persist security-scoped bookmarks for media access`

---

### S3 — App Sandbox + entitlements

**실측 근거**: `.entitlements` 파일 **0개**(repo 전체). `project.pbxproj`에 `CODE_SIGN_ENTITLEMENTS` / `ENABLE_APP_SANDBOX` 설정 **0건**. 즉 현재 앱은 **샌드박스 미적용**이며 App Store 제출 자체가 불가능하다.

권한 문자열과 프라이버시 매니페스트는 **이미 있다** — 재작업 금지:
- `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` (`App/MovieCutMac/Info.plist`, `App/MovieCutiOS/Info.plist`)
- `App/MovieCutMac/PrivacyInfo.xcprivacy`, `App/MovieCutiOS/PrivacyInfo.xcprivacy` (커밋 `1266804`)

**작업 내용**

1. `App/MovieCutMac/MovieCutMac.entitlements` 신설: `com.apple.security.app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`, `device.microphone`, 필요 시 `device.camera`(S11 착수 전에는 넣지 말 것 — 미사용 권한은 심사 리스크).
2. `project.yml`에 `CODE_SIGN_ENTITLEMENTS` 연결. **`info:` 블록은 절대 추가하지 말 것** — hand-maintained `Info.plist`를 xcodegen이 덮어쓴다(`project.yml` 주석 참조).
3. iOS 타깃도 동일 처리 + iOS 전용 누락 키 보강: `UILaunchScreen`, `UISupportedInterfaceOrientations`, Photos 도입 시 `NSPhotoLibraryUsageDescription` (현재 iOS plist 키는 10개뿐).
4. 샌드박스 상태에서 깨지는 경로 전수 확인: 프록시 생성 출력 위치(`ThumbnailGenerator.swift:226` 부근), autosave 경로(`ProjectStore` — Application Support는 컨테이너로 리다이렉트됨), export 저장 위치, 임시 파일(`ReverseRenderService`).

**수용 기준 (DoD)**

- 샌드박스 활성 빌드에서 **import → 편집 → 프록시 생성 → export → 자동 저장 → 재시작 복구** 전 경로 통과. 각 단계 증거.
- `codesign -d --entitlements - <앱경로>` 출력으로 실제 적용된 entitlement 목록 확인.
- Console에서 샌드박스 위반(`deny file-read*` 등) 로그 **0건** 확인 출력.

**커밋**: `feat(moviecut): enable app sandbox with scoped file entitlements`

---

### S4 — 앱 아이콘 · 번들 메타데이터

**실측 근거**: `.xcassets` / `AppIcon` **0개**(양 타깃). `CFBundleShortVersionString`은 양쪽 `1.0` 하드코딩, `CFBundleVersion`은 `1`. 카테고리(`LSApplicationCategoryType`)·저작권(`NSHumanReadableCopyright`) 없음.

**작업 내용**: `Assets.xcassets` + 전 사이즈 AppIcon(mac 16~1024, iOS 전 사이즈), `LSApplicationCategoryType`(`public.app-category.video`), `NSHumanReadableCopyright`, 버전/빌드 번호를 빌드 설정에서 주입하도록 변경(`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION`).

**수용 기준**: 빌드 산출물 `.app`의 Finder 아이콘 스크린샷 + `defaults read <앱>/Contents/Info` 출력에 위 키가 실제로 존재.

**커밋**: `feat(moviecut): add app icons and bundle metadata`

---

### S5 — 서명 · 공증 · 배포 파이프라인

**실측 근거**: `notarytool` / `codesign` / `create-dmg` / Sparkle 참조가 `scripts/`·`.github/`에 **0건**. CI는 `CODE_SIGNING_ALLOWED=NO` 빌드만 수행하며 릴리스 잡이 없다. `project.pbxproj`의 `CODE_SIGN_IDENTITY`는 iOS 기본값(`iPhone Developer`) 잔존, `DEVELOPMENT_TEAM` 미설정.

**작업 내용**

1. **먼저 배포 경로를 결정한다**: App Store 단독 / 직접 배포(공증+Sparkle) / 양쪽. App Store 목표 메모(`moviecut-appstore-goal`)상 App Store가 1순위이나, Sparkle은 App Store 빌드에 **포함 불가**이므로 양쪽이면 빌드 구성이 갈린다. 결정 없이 코드부터 쓰지 말 것.
2. `scripts/release.sh`: archive → export(`-exportOptionsPlist`) → `codesign --deep --options runtime` → `xcrun notarytool submit --wait` → `xcrun stapler staple` → DMG 패키징.
3. 자격 증명은 **키체인 프로파일 참조만**(`--keychain-profile`). API 키·팀 ID·비밀번호를 스크립트나 저장소에 넣지 말 것.
4. CI: 릴리스 태그 트리거 잡 추가. 시크릿 미설정 환경에서는 건너뛰되 **조용히 통과시키지 말 것**(현행 iOS 단계의 `continue-on-error`가 만든 무검증 상태를 반복하지 않는다).

**수용 기준 (DoD)**

- 공증된 산출물에 대해 `xcrun stapler validate <앱>` 및 `spctl -a -vvv -t install <앱>` 출력 첨부(둘 다 accepted).
- 다른 사용자 계정 또는 격리 속성이 붙은 상태(`xattr -w com.apple.quarantine`)에서 실행되는 것을 확인한 스크린샷.
- 스크립트가 비밀값을 로그에 출력하지 않음을 확인.

**커밋**: `ci(moviecut): add signing, notarization and packaging pipeline`

---

## Track T — 주장 방어

### S8 — STT 온디바이스 강제 + 폴백 고지

**실측 근거** — `Sources/MovieCutCore/Transcription/SpeechTranscriptionProvider.swift:99`:

```swift
request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
```

온디바이스 인식을 지원하지 않는 로케일/기기에서는 이 값이 `false`가 되어 **오디오가 애플 서버로 전송된다.** 사용자에게 알리는 경로도 없다.

이는 [Pro 로드맵 §2](MOVIECUT_PRO_ROADMAP_20260622.md)의 차별화 명제("완전 오프라인·프라이버시 우선", "온디바이스 AI")와 정면으로 충돌하며, `PrivacyInfo.xcprivacy` 및 App Store 심사 답변과도 어긋날 수 있다. **Track R보다 싸고 위험은 크다.**

**작업 내용**

1. 기본 정책을 **온디바이스 강제**로 변경: `requiresOnDeviceRecognition = true`.
2. 미지원 시 조용한 서버 폴백 대신 (a) 명시적 실패 + 사유 메시지, 또는 (b) 사용자가 명시적으로 동의한 경우에만 서버 경로 — **기본값은 (a)**.
3. 앱 문구/문서에서 "온디바이스"라고 말하는 지점을 전수 확인하고 실제 동작과 일치시킨다.
4. Whisper Core ML 도입은 **이 항목의 범위가 아니다**(Core ML 모델 0개, 별도 스펙 필요). 여기서는 거짓 주장을 먼저 없앤다.

**수용 기준 (DoD)**

- 온디바이스 미지원 로케일을 강제한 상태에서 자막 생성 시도 → **네트워크 요청이 발생하지 않음**을 확인(예: 네트워크 차단 상태에서 동일 동작, 또는 Instruments Network 트레이스). 출력 첨부.
- 실패 시 사용자에게 보이는 메시지 스크린샷.
- 지원 로케일에서는 기존대로 자막이 생성됨을 확인한 산출물.

**커밋**: `fix(moviecut): require on-device speech recognition`

---

## Track P — 성능·신뢰

### S6 — 4K · 열 · 메모리 실측

**실측 근거**: `scripts/perf_baseline.sh`는 1280×720 픽스처를 만들어 1080p로 export하는 Debug 단일 실행이다. [PERF_BASELINE §한계](PERF_BASELINE_20260622.md)가 재검토 트리거로 명시한 **(1) 무거운 합성 (2) 4K·장시간**은 아직 측정되지 않았다. 4K는 export 프리셋에만 존재하고(`ExportPreset.swift`/`ExportSettings.swift`) 성능 근거가 없다.

외부 스펙은 "4K 60fps 실시간 · 4GB 이하"를 요구하므로, 현재 우리는 **그 주장을 할 근거도 반박할 근거도 없다.**

**작업 내용**

1. `scripts/perf_baseline.sh`를 확장하거나 `scripts/perf_4k.sh` 신설: 3840×2160 픽스처, (a) passthrough (b) 색보정 (c) **전환+마스크+다중 레이어 동시**(최악 케이스) 3경로.
2. 측정: export wall-clock · realtime 배율 · **peak RSS** · preview 프레임당 렌더 시간. Release 빌드도 함께(현 베이스라인은 Debug).
3. Instruments 검증 1회: Time Profiler + Allocations (또는 signpost 기반) — 어느 경계가 비용을 내는지.
4. 결과로 **Metal defer 결정을 명시적으로 유지 또는 철회**하고 [PERF_BASELINE](PERF_BASELINE_20260622.md)에 추가 기록.

**수용 기준 (DoD)**

- 재현 스크립트 커밋 + 표(경로 × 시간/배율/peak RSS/프레임당 렌더).
- 4GB 상한에 대한 판정(초과/이내)과 근거 수치.
- Metal 결정 문장 1개("유지" 또는 "철회 및 착수 조건") — 애매하게 남기지 말 것.
- **G-04 필름스트립 측정의 교훈 준수**: sleep 루프 wall-time을 성능 지표로 쓰지 말 것(`PERF_BASELINE` G-04 절이 그것을 measurement artifact로 판정했다).

**커밋**: `perf(moviecut): measure 4K composite and memory baseline`

---

### S7 — thermalState 기반 프록시 자동 강등

**실측 근거**: `ProcessInfo.processInfo.thermalState` 참조 **0건**. 프록시는 존재하고 재생에 소비되지만(`PlaybackEngine.swift:570`) 전환은 **수동 토글**뿐이다. 프록시 해상도 선택(`ProxyResolution`: 480/540/720/1080p)도 수동이다.

**작업 내용**: 열 상태 관측 → `.serious`/`.critical`에서 프록시 재생 자동 활성화(및 해상도 강등), 회복 시 원복. **사용자에게 왜 바뀌었는지 알리는 표시 필수**(자동으로 화질이 떨어지는데 이유가 안 보이면 버그로 읽힌다 — `ProxyBadgeState`가 이미 idle/active를 구분하므로 그 표시 체계를 확장).

**수용 기준 (DoD)**

- 열 상태를 주입 가능한 형태로 추상화하고, 상태 전이별 동작을 **동작 테스트**로 검증(문자열 검사 금지).
- 실제 앱에서 강등/복귀 시 UI 표시가 바뀌는 것을 확인한 스크린샷 2장.
- 사용자가 자동 강등을 끌 수 있는 설정 경로 확인.

**선행**: S6(어느 지점에서 강등이 필요한지의 근거).

**커밋**: `feat(moviecut): downgrade to proxy playback under thermal pressure`

---

## Track U — Pro 편집 조작

### S9 — J/K/L · 툴 모드 · slip/slide · Cmd+스크롤 줌

**실측 근거**

| 기능 | 실측 |
|------|------|
| J/K/L 전송 제어 | `keyboardShortcut("j"/"k"/"l")` **0건** |
| 툴 모드(선택/블레이드) | `toolMode`/`EditTool`/`bladeTool` **0건** — split은 `Cmd+B` 단일 명령만 |
| slip / slide / roll 편집 | `slip` 0건, `rollEdit` 0건 |
| ripple | `RippleDeleteCommand`는 **있음**. ripple *트림/편집 도구*는 없음 |
| Cmd+스크롤 줌 | Mac 앱에 `scrollWheel` 처리 없음(줌은 `+`/`-` 키만) |
| 스냅 | **있음** — 클립 경계 + 마커 (`SnapEngine.swift:33`) |

현재 단축키는 `MovieCutMacApp.swift`에 20여 개 존재하나 전부 메뉴 명령 기반이다. Pro 포지셔닝에서 가장 체감이 큰 격차다.

**작업 내용**

1. J/K/L: 역재생/정지/재생 + 연타 배속(J·J = 2배속 역방향 등). `PlaybackEngine.playbackRate`가 이미 있으므로 배선 중심.
2. 툴 모드 상태 도입(선택 / 블레이드)과 커서 피드백. 블레이드 모드 클릭 = 해당 지점 split(`SplitClipCommand` 재사용).
3. slip/slide: 드래그 + modifier. `ClipTrimMath`/`ClipTimeMapping`이 시간 매핑을 이미 담당하므로 **새 수학을 만들지 말고 그것을 확장**할 것.
4. Cmd+스크롤 줌: 기존 `TimelineZoomLevel`에 연결. 커서 위치 기준 줌 앵커링 포함.

**수용 기준 (DoD)**

- 각 조작에 대해 **XCUITest 또는 harness 시나리오**로 동작 확인(`MOVIECUT_UITEST_*` 관례 준수 — `UITestHarness.swift:133~` 참조).
- slip/slide는 **timeline↔source 시간 일관성**을 반드시 검증한다. 이 영역은 과거에 깨져 있었다(`269d50a`, `dfde012`, `1d8882a`, `0115e6c` — V13 §2-2).
- 조작 전후 export 결과가 preview와 일치함을 확인(preview+export 동시 증거 — V13이 요구한 판정 기준).

**커밋**: `feat(moviecut): add JKL transport and blade/slip editing tools`

---

## Track O — 관측

### S10 — OSLog · MetricKit 최소 도입

**실측 근거**: `OSLog`/signpost 사용은 `FilmstripGenerator.swift`·`TimelineFilmstripStore.swift` **2파일뿐**. MetricKit·크래시 리포팅 **0건**. 출시 후 회귀를 감지할 수단이 없다.

**작업 내용**: 서브시스템별 `Logger` 카테고리 도입(playback/export/import/ai), 실패 경로 로깅 표준화, MetricKit 수집 여부 결정. **프라이버시 명제상 외부 전송 텔레메트리는 기본 비활성 또는 미도입** — 로컬 진단 로그 위주로 설계하고, 전송이 필요하면 명시적 옵트인 + `PrivacyInfo.xcprivacy` 갱신.

**수용 기준**: 로그 카테고리 목록 + `log stream --predicate` 로 실제 출력이 잡히는 것을 확인한 캡처. 개인 식별 가능 정보가 로그에 들어가지 않음을 확인.

**커밋**: `feat(moviecut): add structured logging for core subsystems`

---

## Track D — 착수 전 결정 필요

### S11 — 캡처 입력 (카메라 / 화면 녹화 / Continuity Camera)

**실측 근거**: `AVCaptureDevice`는 **마이크 권한 확인에만** 사용된다(`VoiceoverRecordingView.swift:197,202,218`). 비디오 캡처 세션·화면 녹화 경로 0건.

CapCut에는 있고 우리에겐 없는 실제 기능 격차지만, **범위가 크고**(캡처 세션·장치 선택·프리뷰·인코딩·권한·`device.camera` entitlement) 현재 어느 로드맵 Phase에도 배정돼 있지 않다.

**요구**: 착수 전에 (a) Pro 포지셔닝에서 캡처가 필수인지 (b) 카메라/화면 녹화/Continuity 중 무엇부터인지 결정. 결정 없이 코드부터 쓰지 말 것. 결정되면 별도 스펙 문서를 만들고 이 항목은 그쪽으로 이관한다.

---

## 4. 권장 착수 순서

| 순위 | 항목 | 이유 |
|------|------|------|
| 1 | **S8** | 가장 싸고, 마케팅 주장·심사 답변과 코드가 어긋나는 유일한 항목 |
| 2 | **S1 → S2 → S3** | 출시 차단이며 저장 포맷을 건드리므로 늦을수록 비싸다 |
| 3 | **S6** | Metal 결정 근거가 만료 상태. S7의 선행 |
| 4 | S4 → S5 | 배포 경로 결정 후 |
| 5 | S7, S9, S10 | |
| — | S11 | 결정 대기 |

---

## 5. 세션 시작 프롬프트

<details>
<summary>S8 — STT 온디바이스 강제</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S8을 수행해줘.

먼저 Sources/MovieCutCore/Transcription/SpeechTranscriptionProvider.swift:99를
직접 열어서 현재 코드를 확인하고 보여줘.
  request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
이 줄 때문에 온디바이스 미지원 로케일에서는 오디오가 애플 서버로 나간다.

이걸 온디바이스 강제로 바꾸고, 미지원 시 조용한 서버 폴백 대신 명시적 실패 +
사유 메시지를 사용자에게 보여주도록 해줘. 서버 경로를 남긴다면 반드시
사용자의 명시적 동의를 거치게 하고, 기본값은 "실패"다.

그 다음 앱 문구·docs에서 "온디바이스"/"오프라인"을 주장하는 지점을 전수 grep해서
실제 동작과 일치하는지 확인하고, 어긋나는 곳을 고쳐줘.

Whisper Core ML 도입은 이 작업 범위가 아니다. 거짓 주장을 먼저 없애는 게 목표다.

DoD: 네트워크 요청이 실제로 발생하지 않음을 확인한 증거(네트워크 차단 상태
재현 또는 트레이스)와 실패 메시지 스크린샷. 문자열 존재 검사 테스트로
대체하지 말 것. 마지막에 scripts/verify_gate.sh 출력 첨부.
```
</details>

<details>
<summary>S1 — 스키마 마이그레이션 (S2의 선행)</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S1을 수행해줘.

Sources/MovieCutCore/Models/Project.swift:21의 schemaVersion은 쓰기만 하고
읽는 코드가 없다 (grep -rl "migrat" Sources/ → 0). 유일한 소비처는
CloudSyncService.swift:498의 max()다. 먼저 이걸 직접 확인해서 보여줘.

ProjectStore에 버전 분기와 마이그레이터 체인을 도입해줘:
  - schemaVersion > current  → 크래시가 아니라 "더 새 버전의 프로젝트" 명시적 오류
  - schemaVersion < current  → 마이그레이터 체인 통과
지금은 v1 항등 마이그레이터까지만. v1→v2는 S2(북마크)에서 추가된다.

알 수 없는 미래 키를 만났을 때 보존할지 버릴지도 결정하고 근거를 남겨줘.
버리는 쪽이면 사용자 경고 경로까지 만들어야 한다.

DoD: 현행 v1 프로젝트 JSON 픽스처를 커밋하고 그것이 실제로 로드되는 테스트,
schemaVersion:999 픽스처가 명시적 오류를 내는 테스트, 그 오류가 UI까지
도달하는 스크린샷. swift test 전체 출력 첨부.
```
</details>

<details>
<summary>S2 — Security-Scoped Bookmark (S1 완료 후)</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S2를 수행해줘. S1이 끝났는지 먼저 확인해.

현재 security-scoped bookmark 사용이 repo 전체에 0건이고, MediaAsset은
originalURL을 그대로 직렬화한다(Models/MediaAsset.swift:20). 파일 접근
진입점은 8곳이다: MovieCutMacApp.swift:29,44 / MediaLibraryPanel.swift:1666 /
EditorViewModel.swift:839,861,898,970,1009. 착수 전에 직접 grep으로 재확인해줘.

MediaAsset에 북마크 데이터를 추가하고 8곳에서 생성·해제 짝을 보장해줘.
ProxyInfo의 프록시 파일은 앱 컨테이너 내부로 옮기면 북마크가 불필요해지니
그쪽을 먼저 검토하고 판단 근거를 남겨줘.
S1의 마이그레이터에 v1→v2를 추가해서 기존 프로젝트도 열리게 해야 한다.

MediaAsset은 public API다. CloudSyncService·UITestHarness·테스트 픽스처가
함께 움직이니 영향 범위를 먼저 보고해줘.

DoD: 샌드박스를 켠 빌드에서 import→저장→앱 완전 종료→재실행→재열기→
preview 재생→export까지 통과한 스크린샷과 export 해시. 파일을 옮긴 뒤의
stale 북마크 복구 시나리오 녹화. v1 프로젝트 마이그레이션 후 동일 통과.
```
</details>

<details>
<summary>S6 — 4K · 열 · 메모리 실측</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S6을 수행해줘.

scripts/perf_baseline.sh는 720p 입력 → 1080p export의 Debug 단일 실행이다.
docs/PERF_BASELINE_20260622.md가 재검토 트리거로 명시한 "무거운 합성"과
"4K·장시간"은 아직 측정되지 않았고, 그래서 Metal defer 결정의 근거가
만료 상태다.

4K(3840x2160) 측정 스크립트를 만들어줘. 경로 3개: passthrough / 색보정 /
전환+마스크+다중 레이어 동시(최악 케이스). Release 빌드도 함께 측정.
지표: export wall-clock, realtime 배율, peak RSS, preview 프레임당 렌더 시간.

중요: 같은 문서의 G-04 절이 1ms sleep 루프 wall-time을 measurement artifact로
판정했다. 그 실수를 반복하지 말고 os_signpost + monotonic clock으로
실제 작업 구간을 재라.

마지막에 Metal defer를 유지할지 철회할지 한 문장으로 결정하고
PERF_BASELINE 문서에 추가 기록해줘. 애매하게 남기지 말 것.
4GB 메모리 상한 판정도 수치로.
```
</details>

<details>
<summary>S3 — App Sandbox + entitlements (S2 완료 후)</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S3을 수행해줘. S2 완료가 전제다.

현재 .entitlements 파일이 0개고 project.pbxproj에 ENABLE_APP_SANDBOX /
CODE_SIGN_ENTITLEMENTS 설정이 없다. 먼저 직접 확인해서 보여줘.

주의 1: 권한 문자열(NSMicrophoneUsageDescription 등)과 PrivacyInfo.xcprivacy는
이미 있다(커밋 1266804). 다시 만들지 마.
주의 2: project.yml에 info: 블록을 절대 추가하지 마. hand-maintained
Info.plist를 xcodegen이 덮어쓴다. project.yml 주석에 명시돼 있다.
주의 3: 아직 쓰지 않는 권한(카메라 등)은 넣지 마. 심사 리스크다.

샌드박스를 켠 뒤 깨지는 경로를 전수로 찾아줘: 프록시 생성 출력 위치,
ProjectStore autosave, export 저장 위치, ReverseRenderService 임시 파일.

DoD: 샌드박스 활성 빌드에서 import→편집→프록시→export→autosave→재시작 복구
전 경로 통과 증거, codesign -d --entitlements - 출력, Console에
샌드박스 위반 로그 0건 확인.
```
</details>

<details>
<summary>S9 — Pro 편집 조작</summary>

```
docs/PRO_SPEC_GAP_WORKORDER_20260730.md의 S9을 수행해줘.

실측: J/K/L 0건, toolMode/EditTool 0건, slip 0건, rollEdit 0건,
Cmd+스크롤 줌 없음(+/- 키만). RippleDeleteCommand와 SnapEngine(클립 경계+마커)은
이미 있다. 착수 전 직접 grep으로 재확인해줘.

한 세션에 전부 하려 하지 말고 J/K/L → 툴 모드(선택/블레이드) → Cmd+스크롤 줌
→ slip/slide 순으로 하되, 이번 세션 범위를 먼저 선언하고 시작해.

slip/slide는 새 시간 계산을 만들지 말고 ClipTrimMath / ClipTimeMapping을
확장해. 이 영역은 과거에 timeline↔source 일관성이 깨져 있었다
(269d50a, dfde012, 1d8882a, 0115e6c). 같은 실수를 반복하지 마.

DoD: UITestHarness.swift:133~ 의 MOVIECUT_UITEST_* 관례를 따르는 시나리오로
동작 확인 + 조작 후 preview와 export 결과가 일치함을 동시에 보이는 증거.
문자열 존재 검사로 대체 금지.
```
</details>
</content>
</invoke>
