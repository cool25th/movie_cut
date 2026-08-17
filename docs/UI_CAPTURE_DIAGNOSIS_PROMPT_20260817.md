# macOS 간헐적 무창 상태·TCC·세션 의존성 — UI 캡처 하니스 진단·개선 자문 요청

당신은 다음 영역에 정통한 macOS 테스트 인프라 아키텍트입니다.

* SwiftUI·AppKit 앱 라이프사이클
* `NSApplication`, `NSWindow`, `WindowGroup`
* WindowServer와 사용자 GUI 세션
* Launch Services와 앱 활성화
* Apple Events·AppleScript·System Events
* macOS TCC

  * Automation
  * Accessibility
  * Screen & System Audio Recording
* Core Graphics Window Services
* ScreenCaptureKit
* XCUITest 기반 지속적 UI 테스트

아래 관측을 바탕으로 다음을 제시해 주세요.

1. 원인 진단 트리
2. 가설별 판별 실험
3. 오늘 테스트를 재개하기 위한 단기 우회책
4. 권한과 세션 의존성을 줄이는 장기 캡처 아키텍처
5. 재발 시 원인을 자동 분류할 수 있는 자가 진단 체계

코드 저장소에는 접근할 수 없습니다. 제공된 사실만 사용하고, 불명확한 내용은 반드시 다음 중 하나로 구분해 주세요.

* 확인된 사실
* 직접 관측
* 유력 가설
* 대안 가설
* 추가로 확인해야 할 정보

알려진 macOS 버그를 언급할 때는 정확한 OS 버전·빌드와 Apple 공식 문서, 릴리스 노트 또는 Apple Developer Forums 근거가 있는 경우에만 “알려진 버그”로 분류하세요. 근거가 없으면 일반 가설로 표시하세요.

---

## 1. 조사 목표

이번 조사의 핵심은 단순히 “창을 못 찾았다”는 결과를 설명하는 것이 아니라, 다음 상태를 명확히 구분하는 것입니다.

### 상태 A — 앱이 실제로 창을 만들지 않음

* `NSApplication.shared.windows`에도 창이 없음
* SwiftUI scene 또는 AppKit window 생성 단계가 실행되지 않음
* 앱 프로세스는 살아 있지만 UI scene이 구성되지 않음

### 상태 B — 앱 내부에는 창이 있으나 표시되지 않음

예:

* `isVisible == false`
* 최소화됨
* 앱이 숨겨짐
* alpha가 0
* 프레임 크기가 0
* 화면 밖 좌표
* 다른 Space에 위치
* 화면과 연결되지 않음
* 창이 생성된 직후 닫힘

### 상태 C — 창은 WindowServer에 있으나 외부 조회가 실패함

예:

* System Events UI scripting 권한 실패
* Apple Events Automation 권한 실패
* Accessibility 조회 실패
* 프로세스 선택 오류
* 창 메타데이터 필터링
* AppleScript 오류가 빈 문자열로 축약됨

### 상태 D — GUI 세션 또는 WindowServer 상태가 비정상임

예:

* 화면 잠금
* 로그인 윈도우
* Fast User Switching
* 다른 console user
* 디스플레이 sleep
* 원격 화면 공유·원격 제어 세션
* 비활성 Aqua 세션
* WindowServer 재시작 또는 세션 전환

### 상태 E — 캡처 하니스의 타이밍·수명주기 경쟁

예:

* 고정 `sleep 5`가 준비 완료를 보장하지 않음
* `ContentView.task`가 창 표시 전에 실행됨
* 앱이 캡처 전에 창을 닫거나 종료 절차에 진입함
* 이전 실행의 잔류 프로세스를 잘못 조회함
* 여러 인스턴스 중 다른 PID를 조회함

최종 답변은 위 상태 A~E를 판별하는 순서로 구성해 주세요.

---

## 2. 환경

### 2.1 확인된 환경

* 대상 플랫폼: macOS 15 이상
* 하드웨어: Apple Silicon Mac mini
* 정확한 OS 버전과 빌드 번호는 아직 기록되지 않음

  * macOS 26 계열일 가능성이 있으나 확정 정보로 취급하면 안 됨
* 앱 기술:

  * Swift
  * SwiftUI
  * 일부 AppKit 사용
  * SwiftUI `App` 라이프사이클
  * `WindowGroup` 기반
* 대상 앱: macOS 비디오 편집기 `MovieCutMac`

### 2.2 빌드 설정

출시 빌드:

```text
App Sandbox = ON
정상 코드 서명
Mac App Store 배포 대상
```

UI 캡처 하니스 빌드:

```text
Configuration = Debug
ENABLE_APP_SANDBOX = NO
CODE_SIGNING_ALLOWED = NO
xcodebuild로 생성
```

다음 사항은 아직 확인되지 않았습니다.

* 하니스 앱의 실제 bundle identifier
* 빌드마다 앱 번들 경로가 변경되는지
* DerivedData 경로가 변경되는지
* 테스트 앱이 완전히 unsigned인지 또는 ad-hoc signature가 남아 있는지
* `codesign -dv --verbose=4` 결과
* Launch Services 등록 상태
* Info.plist의 다음 항목:

  * `LSUIElement`
  * `LSBackgroundOnly`
  * `NSPrincipalClass`
  * scene 관련 설정
* 실행 중 `NSApplication.activationPolicy`
* state restoration 또는 window restoration 사용 여부

unsigned 빌드, 변동하는 앱 경로, 안정적이지 않은 코드 identity가 TCC 또는 Launch Services 동작에 영향을 줄 수 있는지 별도 가설로 평가해 주세요. 다만 증거 없이 원인으로 단정하지 마세요.

---

## 3. 현재 UI 캡처 하니스 구조

하니스는 사용자 로그인 GUI 세션에서 터미널 에뮬레이터 안의 CLI 에이전트가 실행합니다.

현재 구조는 다음과 같습니다.

1. 앱 번들의 실행 파일을 직접 실행합니다.

   ```bash
   "$APP_BIN" &
   APP_PID=$!
   ```

2. 환경변수로 앱 내부의 하니스 시나리오를 활성화합니다.

   ```text
   MOVIECUT_UITEST_*=1
   ```

3. 앱은 SwiftUI `ContentView.task`에서 비동기 시나리오를 실행합니다.

4. 스크립트는 고정적으로 5초 대기합니다.

   ```bash
   sleep 5
   ```

5. `osascript`와 System Events를 사용해 창 위치·크기를 조회합니다.

   ```applescript
   tell application "System Events"
     if not (exists process "MovieCutMac") then return ""

     tell process "MovieCutMac"
       if (count of windows) is 0 then return ""

       set frontmost to true
       set p to position of window 1
       set s to size of window 1

       return ...
     end tell
   end tell
   ```

6. 반환된 창 좌표를 이용해 전체 화면 캡처에서 해당 영역을 추출합니다.

7. 앱은 하니스 시나리오가 끝나면 스스로 종료합니다.

### 현재 오류 처리의 문제

현재 스크립트는 다음 상태를 모두 유사한 “빈 결과” 또는 `window not found`로 축약할 가능성이 있습니다.

* 대상 프로세스 없음
* 대상 프로세스는 있으나 창 수 0
* Automation 거부
* Accessibility 거부
* AppleScript 구문·실행 오류
* `frontmost` 설정 실패
* 대상 프로세스 이름 중복
* 창 위치·크기 속성 조회 실패
* `osascript`가 stderr에 오류를 출력했으나 stdout은 비어 있음

현재 실제 구현에서 다음 항목을 저장하는지는 확인되지 않았습니다.

* `osascript` 종료 코드
* stdout
* stderr
* AppleScript error number
* 대상 PID
* 실제 선택된 System Events 프로세스의 `unix id`

이들을 반드시 분리해서 기록하는 개선안을 제시해 주세요.

### 중요한 논리 조건

제시된 AppleScript에서는 다음 순서입니다.

1. `count of windows`
2. `frontmost = true`
3. 위치·크기 조회

따라서 `frontmost` 설정 실패는 제시된 코드 그대로라면 이미 반환된 `count of windows = 0`의 직접 원인이 될 수 없습니다.

다만 실제 코드가 다르거나, AppleScript 오류가 상위 스크립트에서 빈 문자열로 변환되는 경우는 별도 확인이 필요합니다.

---

## 4. 증상 타임라인

| 시점    | 관측                                                        |
| ----- | --------------------------------------------------------- |
| T0    | 4개 캡처 상태 모두 정상 통과. 창 탐색과 PNG 캡처 성공                        |
| T1    | 다른 날 4개 중 `with_mask`만 `window not found` 실패              |
| T1 상세 | 앱 프로세스는 살아 있었지만 System Events에서 창 수가 0으로 관측됨              |
| T1 상세 | 전체 화면 캡처에서도 MovieCut 창이 보이지 않음                            |
| T1 상세 | 검은 배경과 QuickTime 녹화용으로 보이는 작은 창 또는 Rec UI가 있는 비정상 화면이 관측됨 |
| T2    | 별도 조치 없이 다시 실행하자 4/4 정상 통과                                |
| T3    | 또 다른 날 4개 상태가 모두 `window not found`로 실패                   |
| T3 상세 | 잔류 MovieCut 프로세스를 kill한 뒤 재시도했지만 동일                       |
| 참고    | 같은 기간, 같은 앱 번들을 `open -n -W`로 실행하는 별도 파리티·E2E 하니스는 정상 작동  |
| 참고    | `open` 경로에서는 프레임 덤프와 출력 생성이 성공                            |
| 참고    | 다른 커밋으로 되돌린 clean tree에서도 직접 실행 하니스 실패가 재현됨               |
| 결론    | 제품 코드 회귀만으로는 설명하기 어려움                                     |

### 해석 시 주의

`open -n -W` 하니스와 직접 실행 하니스는 다음 조건이 동일하다고 아직 입증되지 않았습니다.

* 동일 시나리오
* 동일 환경변수
* 동일 앱 종료 시점
* 동일 캡처 방식
* 동일 권한 사용
* 동일 PID 선택
* 동일 foreground 활성화
* 동일 launch arguments
* 동일 테스트 파일
* 동일 실행 순서

따라서 “`open`은 성공하고 직접 실행은 실패했다”는 관측은 강한 단서이지만 아직 통제된 A/B 실험 결과는 아닙니다.

---

## 5. 우선 검토할 원인 후보

각 후보에 대해 다음 형식으로 답해 주세요.

* 성립 조건
* 현재 관측과 일치하는 점
* 현재 관측과 충돌하는 점
* 확인에 필요한 로그
* 가장 작은 판별 실험
* 해당 가설이 틀렸음을 입증할 결과

### 후보 1 — 고정 대기 5초로 인한 준비 경쟁

SwiftUI 창 생성과 `ContentView.task`가 비동기이므로 5초가 부족했을 가능성입니다.

다만 프로세스가 수십 초 생존한 뒤에도 창이 없었던 관측을 어떻게 설명할 수 있는지 평가해 주세요.

다음을 구분해 주세요.

* 창이 늦게 만들어진 경우
* 창이 만들어졌다가 캡처 전에 닫힌 경우
* `ContentView.task`만 시작되고 scene이 표시되지 않은 경우
* task가 취소 또는 재실행된 경우
* 앱이 종료 준비 상태에 들어갔으나 프로세스가 남은 경우

### 후보 2 — 직접 실행과 Launch Services 실행의 차이

직접 실행:

```bash
"$APP_BIN" &
```

Launch Services 실행:

```bash
open -n -W "/path/to/MovieCutMac.app"
```

다음 차이가 영향을 줄 수 있는지 평가해 주세요.

* 앱 등록
* activation
* foreground 전환
* GUI bootstrap namespace
* scene 생성
* state restoration
* environment 전달
* current working directory
* parent process
* 앱 중복 인스턴스 정책
* 종료 대기 의미
* 코드 identity 또는 TCC attribution

특히 “어떤 날은 직접 실행도 성공하고 다른 날은 실패”하는 간헐성을 설명할 수 있어야 합니다.

### 후보 3 — TCC 권한 또는 TCC identity 문제

다음을 분리해서 판단해 주세요.

1. 터미널 또는 CLI가 System Events에 Apple Events를 보내는 Automation 권한
2. UI scripting을 위한 Accessibility 권한
3. 실제 픽셀 캡처를 위한 Screen & System Audio Recording 권한
4. 대상 앱 자체의 권한
5. `osascript` 프로세스와 터미널 앱 사이의 TCC 책임 귀속
6. unsigned 앱 또는 변경된 실행 경로로 인한 identity 변화

중요:

* “터미널 자식 프로세스이므로 TCC 책임 프로세스는 무조건 터미널”이라고 단정하면 안 됩니다.
* 요청 프로세스, 실제 실행 프로세스, responsible process, 대상 프로세스를 구분해 주세요.
* 실제 귀속은 TCC 로그와 System Settings 표시를 통해 검증하는 절차를 제시해 주세요.

다음 질문에 답해 주세요.

* 권한이 없을 때 System Events가 일반적으로 오류를 내는가?
* 창 수 0을 반환할 가능성이 있는가?
* 오류가 shell wrapper에서 빈 stdout으로 축약됐을 가능성이 있는가?
* 앱 창이 실제로 생성되지 않은 현상까지 TCC로 설명할 수 있는가?
* 권한 문제라면 왜 전체 화면 캡처에서도 앱 창이 보이지 않았는가?

### 후보 4 — 사용자 GUI 세션·WindowServer 상태

다음 상태를 검토해 주세요.

* 현재 console user가 테스트 실행 사용자와 다른 경우
* 화면 잠금
* loginwindow 표시
* 디스플레이 sleep
* Fast User Switching
* 원격 로그인
* Screen Sharing·Remote Management
* VNC 또는 다른 화면 제어 세션
* QuickTime 화면 녹화 또는 녹화 UI
* 디스플레이가 연결되지 않은 Mac mini
* 가상 디스플레이 또는 dummy display
* WindowServer 재시작 직후

QuickTime 녹화 창으로 보였다는 단일 관측만으로 원격 세션 또는 WindowServer 문제를 확정하면 안 됩니다. 이를 판별할 수 있는 세션·디스플레이 사전 점검 방법을 제시해 주세요.

### 후보 5 — 잔류 프로세스·잘못된 인스턴스 선택

현재 AppleScript는 PID가 아니라 다음 이름으로 프로세스를 선택합니다.

```applescript
process "MovieCutMac"
```

다음 문제를 평가해 주세요.

* 같은 이름의 프로세스가 둘 이상 존재
* `open -n`으로 생성된 인스턴스가 잔류
* 이전 프로세스는 창 0개, 새 프로세스는 정상
* System Events가 기대한 PID가 아닌 프로세스를 선택
* 실행 파일 이름과 앱 표시 이름 불일치
* helper 또는 테스트 프로세스와 이름 충돌

하니스에서 `$!`로 얻은 PID와 System Events의 `unix id`를 직접 일치시키는 개선안을 제시해 주세요.

### 후보 6 — 앱 내부에서 창이 닫히거나 표시되지 않는 문제

다음 앱 상태를 검토해 주세요.

* `NSApplication.shared.windows.count`
* `window.isVisible`
* `window.isMiniaturized`
* `window.isKeyWindow`
* `window.isMainWindow`
* `window.frame`
* `window.screen`
* `window.occlusionState`
* `NSApplication.shared.isActive`
* `NSApplication.shared.isHidden`
* `NSApplication.shared.activationPolicy`
* `NSWindow.willCloseNotification`
* `NSWindow.didBecomeVisibleNotification`
* scene phase
* 마지막 창이 닫힌 뒤 앱 프로세스 유지

SwiftUI macOS 앱은 프로세스가 살아 있다는 사실만으로 창이 존재한다고 볼 수 없습니다. 앱 내부 관측으로 이를 확인하는 방안을 제시해 주세요.

### 후보 7 — 코드 서명·경로·Launch Services 등록 불안정

테스트 빌드는 다음 상태입니다.

```text
CODE_SIGNING_ALLOWED = NO
ENABLE_APP_SANDBOX = NO
Debug build
```

다음을 비교하는 실험을 제시해 주세요.

* 완전 unsigned 빌드
* ad-hoc signed 빌드
* 안정된 bundle identifier
* 안정된 고정 경로
* DerivedData 경로
* `/Applications` 또는 전용 테스트 디렉터리
* 직접 실행
* Launch Services 실행

### 후보 8 — OS 버전별 회귀 또는 macOS 버그

OS 버그를 제안할 경우 반드시 다음을 요구합니다.

* 정확한 `sw_vers` 결과
* 정확한 build version
* Xcode 버전
* 재현되는 Mac 모델
* 관련 Apple 릴리스 노트 또는 공식 개발자 자료
* 최소 재현 예제
* 이전 OS와의 비교

공식 근거가 없으면 “알려진 버그”가 아니라 “OS 의존 가능성”으로 표시하세요.

---

## 6. TCC 권한 의미론 정리 요청

다음 작업별로 권한을 분리한 매트릭스를 작성해 주세요.

| 작업                                                  | Automation | Accessibility | Screen Recording | 대상 권한 주체 | 권한 거부 시 예상 실패 |
| --------------------------------------------------- | ---------: | ------------: | ---------------: | -------- | ------------- |
| `osascript`가 System Events에 명령 전송                   |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| System Events로 프로세스 존재 조회                           |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| System Events로 창 수 조회                               |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| 창 position·size 조회                                  |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| `frontmost = true` 설정                               |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| CGWindowListCopyWindowInfo로 PID·bounds 조회           |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| CGWindowListCopyWindowInfo로 title·owner metadata 조회 |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| `screencapture -l`로 창 픽셀 캡처                         |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| ScreenCaptureKit로 창 픽셀 캡처                           |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| 앱 내부에서 `NSApplication.shared.windows` 조회            |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| 앱 내부에서 AppKit view를 bitmap으로 렌더                     |      판정 필요 |         판정 필요 |            판정 필요 |          |               |
| XCUITest screenshot                                 |      판정 필요 |         판정 필요 |            판정 필요 |          |               |

다음도 설명해 주세요.

### 6.1 Automation과 Accessibility의 차이

* Apple Events를 보내는 권한
* System Events가 대상 UI를 조사·조작하는 권한
* 두 권한 중 하나만 있을 때의 실패 양상
* 터미널, `osascript`, System Events, 대상 앱의 역할

### 6.2 Screen Recording의 범위

* 창 목록 조회
* 창 ID·PID·bounds 조회
* 창 제목 또는 민감 metadata 조회
* 실제 픽셀 캡처

모든 창 메타데이터가 Screen Recording 권한 없이는 0건이 된다고 가정하지 말고, 어떤 필드가 제한되는지 공식 API 동작을 기준으로 구분해 주세요.

### 6.3 진단 방법

다음 도구에 대해 지원되는 용도와 한계를 제시해 주세요.

* `tccutil`
* `AXIsProcessTrusted`
* `AXIsProcessTrustedWithOptions`
* Apple Events 권한 판정 API
* Screen Capture preflight·request API
* `log stream`
* Console.app
* System Settings의 Privacy & Security
* TCC 데이터베이스 직접 조회

중요 제약:

* TCC 데이터베이스 직접 수정 금지
* SIP 비활성화 금지
* 보안 정책 완화 금지
* `sudo` 실행을 일반 해결책으로 제안하지 말 것
* 직접 DB 조회가 필요하다면 비공식 진단이라는 점과 Full Disk Access·스키마 변경 위험을 명시할 것
* 지원되는 API와 디버깅용 휴리스틱을 구분할 것

### 6.4 “자연 회복” 해석

아무 조치 없이 다시 작동한 사실을 “TCC 권한이 스스로 회복했다”고 바로 해석하지 마세요.

다음 가능성을 비교해 주세요.

* 다른 앱 인스턴스를 조회했음
* 세션이 정상 상태로 복귀
* 앱이 Launch Services 경로로 실행됨
* 창 생성 타이밍 차이
* 터미널 또는 `osascript` responsible identity 차이
* 앱 경로·코드 서명 변화
* tccd 또는 WindowServer 재시작
* 권한 프롬프트 처리 지연
* 일시적인 UI scripting 오류

---

## 7. 근본 원인 판별 절차

다음 순서로 진단 트리를 설계해 주세요.

### 7.1 단계 0 — 실행 전 환경 스냅샷

최소한 다음 정보를 한 실행 디렉터리에 저장합니다.

```text
run-id
timestamp
sw_vers
OS build
uname
Xcode version
machine model
current UID
console user
parent process chain
terminal app bundle identifier
app bundle path
app executable path
app bundle identifier
codesign 상태
app hash
Info.plist 주요 값
connected display 목록
screen lock 또는 session 상태
TCC preflight 결과
기존 MovieCut PID 목록
```

각 항목에 적합한 지원 명령 또는 API를 제시해 주세요.

### 7.2 단계 1 — 정확한 앱 PID 확보

* 직접 실행 시 `$!` 저장
* Launch Services 실행 시 실제 PID를 신뢰성 있게 확보
* 프로세스 이름이 아닌 PID로 후속 진단
* 실행마다 고유 run-id 전달
* 이전 run-id의 앱과 혼동 방지

### 7.3 단계 2 — 앱 내부 라이프사이클 로그

테스트 하니스 모드에서 앱이 구조화된 JSONL 또는 JSON 파일을 기록하도록 설계해 주세요.

예상 이벤트:

```text
processStarted
appInitialized
applicationWillFinishLaunching
applicationDidFinishLaunching
sceneBodyEvaluated
contentViewAppeared
contentViewTaskStarted
windowCreated
windowBecameVisible
windowBecameKey
scenarioStarted
scenarioReadyForCapture
captureAcknowledged
scenarioFinished
windowWillClose
terminationRequested
applicationWillTerminate
```

각 window 이벤트에 다음 값을 포함합니다.

```json
{
  "runID": "...",
  "pid": 1234,
  "event": "windowBecameVisible",
  "windowNumber": 42,
  "windowTitle": "...",
  "frame": {"x": 0, "y": 0, "width": 1280, "height": 800},
  "isVisible": true,
  "isMiniaturized": false,
  "isKeyWindow": true,
  "isMainWindow": true,
  "hasScreen": true,
  "occlusionState": "...",
  "applicationIsActive": true,
  "applicationIsHidden": false,
  "activationPolicy": "...",
  "timestamp": "..."
}
```

제품 코드 변경은 최소화하되, test-only 컴파일 조건이나 하니스 환경변수로 격리하는 방안을 제시해 주세요.

### 7.4 단계 3 — 외부 관측 3종 비교

같은 PID에 대해 다음을 비교합니다.

#### 앱 내부 관측

```text
NSApplication.shared.windows
```

#### Accessibility·System Events 관측

```text
AX 또는 System Events에서 해당 PID의 window 목록
```

#### WindowServer·Core Graphics 관측

```text
CGWindowListCopyWindowInfo에서 owner PID가 해당 PID인 window
```

판정 예:

| 앱 내부 | AX/System Events | CGWindowList | 의미                                     |
| ---: | ---------------: | -----------: | -------------------------------------- |
|    0 |                0 |            0 | 앱이 창을 만들지 않았거나 이미 닫음                   |
|   1+ |                0 |           1+ | AX·TCC·UI scripting 문제 가능성             |
|   1+ |               1+ |            0 | offscreen·hidden·WindowServer 필터 조건 확인 |
|   1+ |                0 |            0 | 창이 표시되지 않았거나 세션 연결 문제                  |
|    0 |               1+ |           1+ | stale PID·관측 시점·프로세스 혼동 가능성            |

각 경우에 필요한 추가 판별법을 제시해 주세요.

### 7.5 단계 4 — 픽셀 존재 여부 확인

* 전체 디스플레이 캡처
* 특정 window ID 캡처
* 앱 내부 view snapshot
* XCUITest screenshot

픽셀 캡처 실패를 창 생성 실패와 혼동하지 않도록 결과를 분리하세요.

### 7.6 단계 5 — 세션 상태 확인

다음을 구분할 수 있는 방법을 제시해 주세요.

* 현재 console user
* GUI session 활성 여부
* 화면 잠금
* loginwindow
* 디스플레이 sleep
* 원격 로그인
* Screen Sharing·Remote Management
* 디스플레이 미연결
* WindowServer 재시작 여부

공개 API, 명령행 진단, 비공식 휴리스틱을 구분해 주세요.

---

## 8. 통제 실험 설계

다음 변수들을 한 번에 하나씩 바꾸는 A/B 실험을 설계해 주세요.

### 8.1 실행 방식

| 실험 | 실행 방식                                       |
| -- | ------------------------------------------- |
| L1 | unsigned 앱 실행 파일 직접 실행                      |
| L2 | 동일 unsigned 앱 번들을 `open`으로 실행               |
| L3 | ad-hoc signed 앱 실행 파일 직접 실행                 |
| L4 | 동일 ad-hoc signed 앱을 `open`으로 실행             |
| L5 | 필요하면 `NSWorkspace` 또는 별도 launcher helper 사용 |

### 8.2 앱 위치

| 실험 | 앱 위치                                     |
| -- | ---------------------------------------- |
| P1 | DerivedData 내부                           |
| P2 | 고정된 테스트 디렉터리                             |
| P3 | 필요하면 `/Applications` 또는 사용자 Applications |

### 8.3 준비 대기 방식

| 실험 | 대기 방식                                     |
| -- | ----------------------------------------- |
| R1 | 기존 `sleep 5`                              |
| R2 | 최대 timeout을 둔 창 polling                   |
| R3 | 앱이 `ready.json` 또는 Unix socket으로 준비 완료 통지 |
| R4 | 앱 준비 통지 후 하니스 ACK를 받을 때까지 종료 금지           |

### 8.4 프로세스 선택

| 실험 | 선택 방식                         |
| -- | ----------------------------- |
| I1 | 이름 기반 `process "MovieCutMac"` |
| I2 | `$APP_PID`와 `unix id` 기반      |
| I3 | run-id와 PID를 모두 검증            |

### 8.5 세션 조건

| 실험 | 세션                                     |
| -- | -------------------------------------- |
| S1 | 로컬 로그인·화면 unlocked·디스플레이 활성            |
| S2 | 화면 locked                              |
| S3 | 디스플레이 sleep                            |
| S4 | Screen Sharing 또는 Remote Management 연결 |
| S5 | 디스플레이 미연결 또는 가상 디스플레이                  |

### 실험 통제 조건

* 같은 앱 번들
* 같은 파일 hash
* 같은 테스트 시나리오
* 같은 run-id 전달 방식
* 같은 종료 정책
* 같은 캡처 방식
* 같은 TCC 상태
* 같은 OS build
* 같은 전원·디스플레이 상태

`open` 실행에서는 환경변수가 앱에 동일하게 전달된다고 가정하지 마세요. 필요하면 다음을 비교해 주세요.

* launch arguments
* 임시 JSON 설정 파일
* UserDefaults suite
* run-specific configuration file
* 테스트용 IPC

환경 전달 차이가 실험의 교란 변수가 되지 않도록 설계해 주세요.

---

## 9. 고정 `sleep`을 대체할 준비 완료 프로토콜

다음 프로토콜을 평가해 주세요.

```text
1. 하니스가 고유 run-id와 artifact directory 생성
2. 앱 실행
3. 앱이 실제 테스트 window 생성
4. window가 screen에 연결됨
5. scenario UI 상태 적용 완료
6. 최소 한 번의 layout·display cycle 완료
7. 앱이 ready.json을 atomic rename으로 게시
8. 하니스가 ready.json 검증
9. 하니스가 캡처 수행
10. 하니스가 capture-ack 파일 또는 IPC 전송
11. 앱이 ack를 받은 뒤에만 종료
```

`ready.json` 예:

```json
{
  "schemaVersion": 1,
  "runID": "...",
  "pid": 1234,
  "bundleID": "...",
  "windowNumber": 42,
  "windowFramePoints": {
    "x": 100,
    "y": 100,
    "width": 1280,
    "height": 800
  },
  "backingScaleFactor": 2.0,
  "screenID": "...",
  "isVisible": true,
  "isMiniaturized": false,
  "isKeyWindow": true,
  "scenario": "with_mask",
  "state": "readyForCapture"
}
```

다음을 포함한 실패 상태도 정의해 주세요.

```text
PROCESS_DID_NOT_START
APP_DID_NOT_FINISH_LAUNCHING
SCENE_NOT_CREATED
WINDOW_NOT_CREATED
WINDOW_CREATED_NOT_VISIBLE
WINDOW_HAS_NO_SCREEN
WINDOW_CLOSED_BEFORE_CAPTURE
SCENARIO_DID_NOT_FINISH
READY_TIMEOUT
APP_EXITED_EARLY
CAPTURE_PERMISSION_DENIED
AUTOMATION_PERMISSION_DENIED
ACCESSIBILITY_PERMISSION_DENIED
WINDOWSERVER_WINDOW_NOT_FOUND
CAPTURE_RETURNED_EMPTY_IMAGE
SESSION_NOT_INTERACTIVE
DISPLAY_NOT_AVAILABLE
```

기존처럼 모든 상태를 `window not found / Accessibility permission may be required`로 합치지 마세요.

---

## 10. System Events 스크립트 개선 요청

현재 스크립트의 대안으로 다음 특성을 가진 AppleScript 또는 다른 구현을 제시해 주세요.

* PID 기반 대상 선택
* `try/on error`로 AppleScript 오류 번호 기록
* process missing과 window count 0 구분
* `frontmost` 설정 실패 구분
* position·size 조회 실패 구분
* stdout에 구조화된 JSON 또는 안정된 key-value 출력
* stderr와 exit code 보존
* timeout
* 같은 이름의 다중 프로세스 방지

예상 결과 형태:

```json
{
  "status": "WINDOW_FOUND",
  "pid": 1234,
  "windowCount": 1,
  "position": [100, 100],
  "size": [1280, 800],
  "frontmostSet": true,
  "appleScriptErrorNumber": null,
  "appleScriptErrorMessage": null
}
```

권한 거부 예:

```json
{
  "status": "ACCESSIBILITY_OR_AUTOMATION_DENIED",
  "pid": 1234,
  "windowCount": null,
  "appleScriptErrorNumber": -0000,
  "appleScriptErrorMessage": "..."
}
```

실제 오류 번호는 추정해서 만들지 말고, OS 버전에서 관측할 수 있도록 설계해 주세요.

---

## 11. 캡처 아키텍처 비교

다음 안을 비교해 주세요.

각 안에 대해 다음 항목을 평가합니다.

* 캡처 대상
* 실제 화면과의 일치도
* title bar·shadow 포함 여부
* `AVPlayerLayer`·Core Animation·Metal·영상 프리뷰 포함 여부
* SwiftUI overlay·AppKit representable 포함 여부
* sheet·popover·menu 포함 여부
* Accessibility 필요 여부
* Automation 필요 여부
* Screen Recording 필요 여부
* 앱 sandbox에서의 가능성
* 테스트 빌드에서의 가능성
* macOS 15+ 적합성
* active GUI session 필요 여부
* locked screen에서의 동작
* CI 자동화 가능성
* 기존 PNG·dHash 골든 호환성
* 구현 비용
* 장기 유지보수성

### 안 1 — 현재 방식 개선

```text
Launch Services 또는 직접 실행
→ System Events로 창 bounds 조회
→ 전체 화면 캡처
→ bounds crop
```

평가할 사항:

* 권한이 여러 개 필요한 구조인지
* 좌표계·Retina scale·다중 디스플레이 문제
* 메뉴바·Dock·Space 영향
* System Events 의존성

### 안 2 — 앱이 window ID와 frame만 하니스에 전달

```text
앱 내부 NSWindow
→ windowNumber와 frame을 ready.json에 기록
→ 외부 하니스가 해당 window ID를 캡처
```

장점 후보:

* System Events 제거
* Accessibility 제거 가능성
* PID·창 선택 모호성 제거

검토할 사항:

* 픽셀 캡처에는 별도의 Screen Recording이 필요한지
* `screencapture -l` 사용 가능성
* 현대 API로 ScreenCaptureKit 또는 `SCScreenshotManager`를 사용할 수 있는지
* window ID의 실행 간 안정성은 필요하지 않고 run 내부에서만 사용하면 되는지
* window가 실제로 on-screen 상태여야 하는지

### 안 3 — 앱 내부 AppKit view 래스터화

예:

```text
NSView bitmap representation
NSView cacheDisplay
```

검토할 사항:

* 외부 TCC 권한 없이 가능한지
* sandbox에서도 가능한지
* title bar·shadow 누락
* `AVPlayerLayer`, CAMetalLayer, Core Animation surface가 포함되는지
* 실제 화면에 표시되는 결과와 차이가 생기는지
* window가 on-screen이 아니어도 가능한지
* backing scale과 color profile 고정
* 기존 dHash와의 호환성

### 안 4 — SwiftUI ImageRenderer

검토할 사항:

* 현재 live window를 캡처하는 것인지, 별도 SwiftUI view tree를 다시 렌더하는 것인지
* AppKit representable과 player layer 포함 여부
* environment·state·layout 재현성
* 영상 프리뷰와 네이티브 컨트롤의 누락 가능성
* 테스트 전용 렌더 경로가 실제 제품 UI와 달라질 위험

### 안 5 — ScreenCaptureKit 기반 window screenshot

예:

```text
SCShareableContent
SCWindow
SCScreenshotManager
```

검토할 사항:

* Screen Recording 권한
* 앱 자신의 window 캡처에도 권한이 필요한지
* window 탐색을 owner PID 기준으로 할 수 있는지
* active session·locked screen 의존성
* asynchronous API의 테스트 안정성
* macOS 15 이상에서의 적합성
* 권한 최초 승인 뒤 앱 재실행 요구 가능성
* CI 머신 사전 권한 설정

### 안 6 — Core Graphics window metadata + 별도 캡처

```text
CGWindowListCopyWindowInfo
→ owner PID·window ID·bounds 식별
→ 별도 캡처 API
```

검토할 사항:

* Screen Recording 권한이 없을 때 반환되는 metadata 범위
* title이나 owner name에 의존하지 않고 PID·window number로 식별하는 방법
* `.optionOnScreenOnly` 사용 시 offscreen·Space·최소화 창 차이
* metadata 조회와 픽셀 캡처의 권한 차이

### 안 7 — `screencapture -l <windowID>`

검토할 사항:

* Screen Recording 권한 주체
* 터미널 앱과 실행 helper 중 누구에게 권한이 귀속되는지
* locked screen·다른 Space·최소화 창 동작
* Retina 해상도
* shadow와 alpha
* 오류 코드와 빈 이미지 판별

### 안 8 — 정식 XCUITest 전환

검토할 사항:

* `XCUIApplication.launchArguments`
* `launchEnvironment`
* foreground 상태 대기
* `waitForExistence`
* screenshot
* process lifecycle
* active GUI session 필요 여부
* 화면 잠금 상태에서의 한계
* WindowServer 의존성이 완전히 제거되는 것은 아닌지
* 현재 bash 하니스에서 이전하는 비용
* 기존 골든 이미지와의 차이

### 안 9 — `open` 또는 NSWorkspace 기반 실행만 도입

현재 캡처 구조를 유지하되 앱 실행만 Launch Services로 변경합니다.

검토할 사항:

* 가장 작은 단기 우회책인지
* 환경변수 전달 문제
* `-n` 사용으로 인한 다중 인스턴스
* `-W` 사용 시 캡처 프로세스와 대기 구조
* foreground activation
* run-id 및 PID 확보
* 잔류 프로세스 정리
* 근본 원인을 숨기는 임시 우회에 그칠 위험

### 안 10 — 테스트 전용 launcher helper

작은 서명된 helper가 다음을 수행합니다.

```text
NSWorkspace로 앱 실행
→ 실제 PID 확보
→ 앱 readiness IPC 수신
→ 캡처 실행
→ 종료 요청
```

검토할 사항:

* 코드 서명·TCC identity 안정성
* 구현 비용
* CLI agent와 GUI launch context 분리
* 유지보수성
* Mac App Store 출시 앱과의 분리

### deprecated API 처리

현재 SDK에서 deprecated된 화면 캡처 API가 있다면 기본 장기 권장안에서 제외하고, 다음을 명시해 주세요.

* deprecated된 OS 버전
* 권장 대체 API
* 임시 호환 목적으로만 유지할 수 있는지
* macOS 15+ 전용 제품에서 사용할 이유가 있는지

---

## 12. 가장 유력한 단서에 대한 검증 요청

현재 가장 강한 관측은 다음입니다.

> 같은 기간에 Launch Services의 `open`으로 실행한 하니스는 정상 작동했고, 실행 파일을 직접 시작한 UI 캡처 하니스만 무창 상태를 보였다.

이 관측을 설명하는 가설을 우선순위로 정렬해 주세요.

최소한 다음 가설을 포함하세요.

1. Launch Services 실행 시 앱 activation·scene 생성이 더 안정적
2. 직접 실행이 GUI session 또는 bootstrap context를 다르게 상속
3. 직접 실행 하니스의 환경변수가 앱의 조기 종료·창 미생성을 유발
4. 두 하니스의 scenario와 종료 타이밍 차이
5. 직접 실행에서 unsigned identity 또는 경로가 영향을 줌
6. process name 기반 조회가 다른 인스턴스를 선택
7. `open` 하니스는 실제 창을 필요로 하지 않고 프레임 덤프만 성공한 것일 수 있음
8. 화면 또는 세션 상태가 실행 사이에 바뀌었음

### 요구 실험

동일한 앱 번들·동일 시나리오·동일 캡처 방법으로 다음을 연속 반복합니다.

```text
A: direct executable
B: open via Launch Services
A: direct executable
B: open via Launch Services
```

조건:

* 각 방식 최소 20회
* 실행 순서 교차 또는 무작위화
* 실행마다 새 run-id
* 동일 테스트 파일
* 동일 권한 상태
* 동일 화면·세션 상태
* 준비 완료 handshake 사용
* 앱 내부 window state 기록
* System Events와 CGWindowList 결과 기록
* 실패 시 전체 artifact 보존

결과를 다음과 같이 집계하도록 해 주세요.

| launch 방식 | 실행 수 | window created | window visible | AX visible | CGWindow visible | capture 성공 | 조기 종료 |
| --------- | ---: | -------------: | -------------: | ---------: | ---------------: | ---------: | ----: |

이 실험으로 launch 방식 자체의 효과와 기존 하니스 차이를 분리할 수 있는지 평가해 주세요.

---

## 13. 즉시 복구책과 장기 해결책 구분

### P0 — 오늘 테스트 재개

다음 후보를 우선 평가해 주세요.

1. 앱을 `open` 또는 NSWorkspace 경로로 실행
2. 이름 대신 PID로 창 조회
3. 고정 `sleep 5`를 bounded polling으로 교체
4. 앱이 ready signal을 쓰기 전에는 캡처하지 않음
5. 캡처 ACK 전에는 앱이 종료하지 않음
6. `osascript` exit code·stdout·stderr 보존
7. 실행 전 console user·화면 잠금·디스플레이 상태 점검
8. 테스트 시작 전 stale process 정리
9. 권한 미승인 상태를 `window not found`와 분리
10. 앱 내부 window number와 frame을 직접 전달

각 우회책의 기대 효과와 근본 원인을 가릴 위험을 설명해 주세요.

### P1 — 원인 확정

* launch 방식 통제 실험
* unsigned와 ad-hoc signed 비교
* 앱 내부 lifecycle 로그
* AX·CGWindowList·앱 내부 3중 관측
* 세션 상태 수집
* TCC responsible process 확인
* 정확한 OS build별 재현

### P2 — 장기 하니스 개선

권장 후보:

```text
Launch Services 또는 서명된 launcher
+ run-id
+ 앱 readiness handshake
+ 앱이 window number와 frame 제공
+ PID 기반 검증
+ ScreenCaptureKit 또는 적합한 window capture
+ 구조화된 실패 artifact
```

앱 내부 view rasterization과 실제 WindowServer 픽셀 캡처 중 어느 방식을 골든 테스트의 기준으로 삼아야 하는지 평가해 주세요.

---

## 14. 재발 방지용 artifact 설계

실패한 모든 실행에 다음 디렉터리를 남기는 방안을 제안해 주세요.

```text
artifacts/
└── <run-id>/
    ├── environment.json
    ├── launch.json
    ├── app-lifecycle.jsonl
    ├── app-window-state.json
    ├── system-events-result.json
    ├── system-events.stdout
    ├── system-events.stderr
    ├── cg-window-list.json
    ├── tcc-preflight.json
    ├── session-state.json
    ├── process-tree.txt
    ├── unified-log.txt
    ├── full-screen.png
    ├── window-capture.png
    ├── app-self-snapshot.png
    └── result.json
```

`result.json` 예:

```json
{
  "schemaVersion": 1,
  "runID": "...",
  "scenario": "with_mask",
  "launchMode": "directExecutable",
  "result": "WINDOW_NOT_CREATED",
  "appPID": 1234,
  "appReportedWindowCount": 0,
  "systemEventsWindowCount": 0,
  "cgWindowCount": 0,
  "screenCaptureAuthorized": true,
  "accessibilityAuthorized": true,
  "automationAuthorized": true,
  "interactiveSession": true,
  "displayAvailable": true,
  "artifacts": [
    "app-lifecycle.jsonl",
    "session-state.json"
  ]
}
```

개인정보·화면 내용 노출을 최소화하는 보존 정책도 제안해 주세요.

---

## 15. 요청 산출물 형식

### 15.1 실행 요약

10줄 이내로 작성하세요.

반드시 포함할 내용:

* 현재 가장 유력한 원인 1~3개
* 지금 바로 적용할 우회책
* 장기 권장 아키텍처
* 아직 확정할 수 없는 사항

### 15.2 사실·가설 표

| 항목 | 관측 사실 | 유력 가설 | 대안 가설 | 신뢰도 | 판별 검증 |
| -- | ----- | ----- | ----- | --: | ----- |

### 15.3 원인 우선순위

| 순위 | 원인 가설 | 관측과의 정합성 | 반대 증거 | 확정 실험 | 반증 조건 |
| -: | ----- | -------- | ----- | ----- | ----- |

### 15.4 원인 진단 트리

다음 구조를 포함하세요.

```text
프로세스가 시작됐는가?
├─ 아니오 → launch·서명·경로 진단
└─ 예
   ├─ 앱 내부 window count > 0?
   │  ├─ 아니오 → scene·WindowGroup·lifecycle·조기 close 진단
   │  └─ 예
   │     ├─ CGWindowList에 같은 PID window가 있는가?
   │     │  ├─ 아니오 → visibility·screen·session·WindowServer 진단
   │     │  └─ 예
   │     │     ├─ AX/System Events에서 보이는가?
   │     │     │  ├─ 아니오 → Automation·Accessibility·PID 선택 진단
   │     │     │  └─ 예
   │     │     │     ├─ 픽셀 캡처가 성공하는가?
   │     │     │     │  ├─ 아니오 → Screen Recording·세션·capture API 진단
   │     │     │     │  └─ 예 → 성공
```

각 노드에 다음을 넣으세요.

* 실행할 명령 또는 API
* 성공 결과
* 실패 결과
* 다음 분기

### 15.5 TCC 권한 매트릭스

Automation, Accessibility, Screen Recording을 분리하세요.

### 15.6 통제 실험 표

direct launch와 Launch Services launch의 차이를 검증하는 반복 실험을 제시하세요.

### 15.7 대안 캡처 아키텍처 비교표

§11의 10개 안과 필요한 추가안을 비교하세요.

### 15.8 권장 조치 순서

다음 형식으로 작성하세요.

| 순서 | 증분·커밋 범위 | 변경 내용 | 선행 조건 | 완료 판정 | 롤백 기준 |
| -: | -------- | ----- | ----- | ----- | ----- |

### 15.9 구현 예시

저장소 파일명을 추측하지 말고 다음 수준의 예시를 제공하세요.

* PID 기반 AppleScript 또는 AX 조회 의사코드
* readiness JSON 작성 의사코드
* capture ACK 프로토콜
* launch 방식별 bash 구조
* window state 수집 Swift 의사코드
* 실패 artifact 수집 구조

### 15.10 완료 판정 기준

다음 기준을 구체화해 주세요.

* 동일 Mac에서 연속 50회 성공
* direct 또는 Launch Services 중 채택 경로 성공률 100%
* `sleep` 의존 제거
* 잘못된 PID 선택 0건
* 앱이 창을 만들지 않은 상태와 TCC 실패를 자동 구분
* 화면 잠금·세션 비활성 상태에서 명시적 사전 실패
* Accessibility 없이 운영 가능한 구조인지 판정
* 필요한 TCC 권한을 최소화
* 기존 PNG 골든·dHash 비교 무회귀
* 실패 시 원인 분류에 충분한 artifact 생성
* 앱이 capture ACK 전에 종료하지 않음
* stale process와 다중 인스턴스 혼동 0건

---

## 16. 공통 제약

* 제품 코드 수정 최소화
* 하니스·스크립트 수준 해결 우선
* 제품 코드 수정이 필요하면 test-only 경로로 격리
* 출시 빌드의 App Sandbox와 보안 정책 약화 금지
* 지원 OS는 macOS 15 이상
* Apple Silicon 실제 호스트 측정만 인정
* 화면 잠금 또는 비활성 세션 결과를 정상 UI 테스트 결과로 인정하지 않음
* 캡처 결과는 PNG
* 기존 dHash 골든 비교와 호환
* 공식 공개 API 우선
* deprecated API를 장기 기본안으로 권장하지 않음
* TCC 데이터베이스 직접 수정 금지
* SIP 비활성화 금지
* root 또는 `sudo` 실행으로 권한 문제를 우회하지 않음
* OS 버그 주장은 정확한 버전·빌드와 근거 필요
* 저장소에 없는 타입·파일명·함수를 사실처럼 만들지 않음
* 1증분 = 1커밋
* 각 변경 후 전체 빌드·테스트 게이트 통과
* 단기 우회책과 근본 해결책을 명확히 구분
* 원인을 확정하기 전에 권한 초기화나 대규모 구조 변경부터 수행하지 않음
