# Stage-1 베타 우선 전환 — 사용자 가이드 + 루프 준비성 검증 (2026-09-19)

> 전환 결정: 사용자 지시 "1번 진행"(베타 우선). 이 문서는 ①사용자만 할 수 있는 단계를
> 최소 노력으로 정리하고 ②루프가 검증한 준비 상태와 발견된 블로커를 기록한다.

## A. 루프 준비성 검증 (2026-09-19 실시 — 사용자 개입 전 가능분)

| 항목 | 상태 | 근거 |
|---|---|---|
| release.sh 자격증명 프리플라이트 | **정상(fail-long)** — MOVIECUT_TEAM_ID 없으면 즉시 명확한 안내로 거부·빌드 착수 없음 | 실측 1회 |
| ExportOptions.plist·release.yml·BETA_GUIDE·PrivacyInfo(Mac/iOS) | **전부 존재** | 파일 확인 |
| MARKETING_VERSION | 0.1.0 (project.yml) | — |
| 베타 전 시나리오 점검 | **완료(2회 4/4 PASS·2026-09-04)** | 체크리스트 §5 [x] |
| **verify_gate 5단계 @HEAD** | **실측 진행(본 문서 커밋 시점 — 결과 하단 기록)** | 베타 경로 전제 |
| iOS 로컬 빌드 가능성 | **가능** — iOS SDK(iphoneos26.5) 존재·generic 빌드 rc=0(9/19 실측). 9/5 게이트 FAIL은 시뮬레이터 런타임 삭제 시절 기록 → **게이트 4/5의 "환경 블록"은 해소 상태** | xcodebuild 실측 |

## B. 사용자 단계 (이 순서대로 — 여기부터는 사람만 가능)

### B-1. Apple Developer Program 가입 (~10분 + 승인 대기)
- https://developer.apple.com/programs → Apple ID로 가입 → **연 $99**
- 개인(Individual) 등록이면 충분 (베타용 — D-U-N-S 불필요)
- 승인은 통상 몇 시간~2일

### B-2. Team ID 확인 (1분)
- https://developer.apple.com → Membership Details 의 **10자리 대문자**
- (또는 Xcode → Settings → Accounts → 팀 선택)

### B-3. Xcode에 계정 추가 (2분)
- Xcode → Settings → Accounts → + → Apple ID 로그인
- 이후 인증서/프로비저닝은 automatic signing이 자동 관리

### B-4. App Store Connect 앱 등록 (5분)
- https://appstoreconnect.apple.com → 내 앱 → 새 앱
- 플랫폼: macOS · 번들 ID: `com.moviecut.mac` · SKU: `moviecut-mac-001`(자유)
- 이름/주 언어는 나중에 수정 가능 — 완벽하게 쓰지 않아도 됨

### B-5. Team ID를 루프에 전달
- 채팅으로 10자리 Team ID만 알려주면 됨. 그 다음부터는 전부 루프가 실행:
  `MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh`
  (verify_gate → archive → export까지 `S5 RELEASE PIPELINE OK` 확인 후 업로드 방법 안내)

### 병렬 준비(선택·나중에도 가능)
- 16:10 스크린샷 4종(1280×800 등 — 1920×1080은 거부됨): 베타 제출엔 TestFlight 스크린샷 불필요, 심사(§6) 시점에 필요
- TestFlight 그룹/테스터 목록: B-4 후 언제든

## C. 발견된 블로커·결정점

1. **없음(예상 블로커 해소)** — 우려됐던 "iOS 플랫폼 삭제로 게이트 4단 불통"은
   실측 결과 해소(iOS SDK 존재·generic 빌드 통과). 시뮬레이터 금지 정책과 무관.
2. 앱 특정 사전 준비 상태의 macOS 시뮬레이터 검증 불가 정책은 베타 경로에 무관
   (릴리스는 Mac generic + iOS generic 빌드만 사용).

## D. 루프 큐 전환 (베타 우선)

- **주 트랙 = release 경로**: Team ID 수신 → release.sh 실행(게이트→archive→export) →
  업로드(Transporter 수동 안내 또는 ASC 키) → TestFlight 그룹 생성 안내 → 베타 메트릭 회수 대기.
- 보조 트랙 = 기존 QAUTO hardening(repair contract·driver exit E2E)은 Team ID 대기 중
  회차 증분으로 유지(베타 경로가 다시 막히는 경우에도 루프가 멈추지 않도록).
- 사용자 대기 최우선 항목 갱신: **B-1~B-5(계정·Team ID)** — 나머지(스크린샷·가격·심사)는 베타 이후.

## 검증 기록 (2026-09-19 실측)

- **verify_gate 5/5 GATE_PASS @HEAD(506f2ef)** — swift build·swift test 전체·xcodebuild Mac·**xcodebuild iOS generic(첫 통과 — 9/5 이후 환경 블록 해소 실증)**·lint. 게이트 기록 `.build-check/history/gate-*.json` 갱신.
- **릴리스 실행 조건 충료: 이제 Team ID만 있으면 `release.sh`가 즉시 archive까지 진행 가능.**
- 부기: 게이트 빌드 캐시로 디스크 27.1→20.5GiB(WARN). 캐시는 release.sh 재실행(동일 게이트 재통과)을 위해 유지 — 릴리스 완료 후 정리 대상.
