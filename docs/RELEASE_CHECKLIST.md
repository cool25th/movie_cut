# MovieCut 출시 체크리스트 (S5 — Mac App Store)

> 코드 쪽 파이프라인은 완료돼 있습니다(`scripts/release.sh`, `scripts/ExportOptions.plist`,
> `.github/workflows/release.yml` — 커밋 `dc559a3`). 이 문서는 **사용자만 할 수 있는**
> 자격증명/등록/배포 단계를 순서대로 정리한 것입니다. 각 단계가 끝나면 체크박스를 채우세요.

---

## 0. 전제 (이미 완료됨)

- [x] Mac App Store 단독 배포 결정 (공증/Developer-ID 불필요)
- [x] `scripts/release.sh` — verify_gate(5단계) → archive(Release, 서명) → export(app-store-connect) → 선택 업로드, 자격증명 없으면 **fail-loud**
- [x] `.github/workflows/release.yml` — 수동 트리거(Actions → Release → Run workflow)

## 0.5 베타 준비 게이트 G1~G6 (QAUTO-04 — 2026-09-21 채택)

> 판정식: **G1~G5 중 하나라도 FAIL 또는 BLOCKED면 External NOT READY.** G6은 베타 품질 수치 게이트로 §5.1과 동일 계약.
> BLOCKED(사용자 대기)는 PASS-equivalent가 아니다(QAUTO-05 규약 준용) — 대기 사유와 해제 조건을 항상 명시.

| 게이트 | 범위 | 판정 근거 | 현재 자가 채점(2026-09-21) |
|---|---|---|---|
| G1 Build | 빌드·테스트·정적 검증 | verify_gate 5/5 @ candidate SHA + 동일 SHA 원격 CI green | 🟡 **PASS@HEAD(2026-09-19 실측)** — candidate SHA=CI SHA 동일성 증거는 배포 시점 채점(QAUTO-05) |
| G2 Project | 프로젝트 무결성 | QAUTO-02 게이트(전 버전 마이그레이션 round-trip·손상 fail-closed·undo 무결성) + autosave/복구 E2E | ✅ **PASS(2026-09-21 승격)** — QAUTO-02 완료(`ProjectIntegrityGateTests` 5/5·Core 1,485/224 전수 통과)·autosave/복구 E2E 상환 완료 |
| G3 Media | 미디어 생존성·입력 호환 | CA-03 감사+BUG-01/02/04/05 수리 완료·CA-04 포맷 매트릭스 PASS(실측)·relink 실경로 테스트 | ✅ **PASS** (잔여: iOS 실기기 relink 수동 확인 — G4로 이관) |
| G4 Device | 실기기 검증·권한 | G-27 실기기 3종(최저/중간/최신) 시나리오 Blocker 0 + TCC lifecycle(NotDetermined→Allow/Deny·revoke) | 🔴 **BLOCKED(사용자 대기)** — 실기기 2종 확보 필요·1/3 완료(iPhone 13 Pro 2026-08-22) |
| G5 Operational | 배포 증거 체인 | QAUTO-05: main SHA→CI→Archive→Signing→TestFlight→실기기 cold launch→Import/Edit/Save/Reopen/Export 증거 | 🔴 **BLOCKED(사용자 대기)** — 계정/Team ID(Stage-1 가이드 B-1~B-5) |
| G6 Beta UX | 베타 품질 수치 | §5.1 Beta Launch Gate 8종 + 계측 인프라(CA-30 1차 완료 — 로컬 JSONL 퍼널 양 플랫폼 배선·반출 UI는 2차) | 🟡 수치표 등록 완료(CA-29)·계측 구현 1차 완료(2026-09-21)·반출 표면·실기기 잔여 |

## 0.7 출시 증거 정리 (2026-10-12 — ChatGPT 외부 리뷰 45회차 판정 지시 이행)

> **규약(45회차 2차 판정)**: 각 항목은 **PASS / FAIL / NOT_RUN / BLOCKED_USER** 4상태로만 기록하고, 상태마다 마지막 실측일·실측 SHA(또는 환경)·증거 위치를 연결한다. **준비 문서 작성은 그 테스트의 PASS가 아니다.** 이전 기록의 대기 항목이 해소됐다는 증거가 없으면 임의로 PASS로 승계하지 않고 마지막 상태와 증거일을 유지한다. 배포 체인의 단계(빌드 생성 → ASC 업로드·처리 완료 → 테스터 실제 설치)는 서로 다른 단계로 구분해 증거를 남긴다.

| 항목 | 상태 | 마지막 실측 | 증거 |
|---|---|---|---|
| G1 Build(Mac) | **PASS** | 2026-09-24 21:05 · HEAD=acccc65 | `.build-check/history/` verify_gate 5/5 GATE_PASS(swift build·xcodebuild·lint·swift test·measurement) |
| G1 Build(iOS) | **PASS** | 2026-09-19 · HEAD=해당 회차 | verify_gate iOS 단계(4단 환경 블록 해소 후 generic 빌드 rc=0) — 후속 CI green은 배포 시점 채점 |
| G2 Project | **PASS** | 2026-09-21 · Core 1,485/224 | `ProjectIntegrityGateTests` 5/5(QAUTO-02 CLOSED)+autosave/복구 E2E — 본 표 §0.5 G2 행 |
| G3 Media(Mac) | **PASS** | 2026-09 이전 실측 | CA-04 포맷 매트릭스 PASS+CA-03 감사·BUG-01/02/04/05 수리 기록 — QAUTO06 코퍼스 6/6(2026-09-22·`QAUTO06_MEDIA_CORPUS_20260922.md`) 재보강 |
| G3 Media(iOS relink) | **NOT_RUN** | — | iOS 실기기 relink 수동 확인 미실측(G4 이관 항목과 함께) |
| G4 Device | **BLOCKED_USER** | 1/3: iPhone 13 Pro 2026-08-22 | G-27 시나리오 1/3 완료 기록 — 대기: 실기기 2종(최저/최신)·해제 조건: 기기 확보 후 G-27 잔여 2종 Blocker 0 |
| G5 Operational | **BLOCKED_USER** | — | 대기: Team ID(Stage-1 가이드 B-1~B-5)·해제 조건: 계정 수신 후 QAUTO-05 체인(main SHA→CI→Archive→Signing→TestFlight→실기기 cold launch→경로 증거) 실행 |
| G6 Beta UX | **NOT_RUN** (인프라 1차 PASS) | 계측 배선 2026-09-21 | CA-29 수치표 등록·CA-30 1차(로컬 JSONL 퍼널 양 플랫폼) — §5.1 8종 수치 측정은 실기기 베타 후. 반출 UI 2차 잔여 |
| §3 첫 아카이브 | **NOT_RUN** | — | release.sh fail-loud 프리플라이트 검증만(2026-09-19) — 실 archive는 Team ID 후 |
| §5.1 사전 점검 시나리오 | **PASS** | 2026-09-04 · 2회 연속 4/4 | `run_beta_scenarios.sh` — 임포트→첫 컷→출력(3.000s·1920x1080)·색 보정·9:16 세로(1080x1920 기하 실측)·autosave 복구(recovered_clips=1)·ffprobe 검증. **주의: Mac 호스트 실측 — 실기기·배포 빌드 증거 아님(45회차 판정 명시) |
| 배포 단계 구분 증거(빌드→업로드·처리→테스터 설치) | **NOT_RUN** | — | ASC 계정 전제 — 각 단계별 증거는 G5 해제 후 QAUTO-05 체인으로 구분 수집 |

**판정 이력**: 위 상태의 유일한 근거 원장은 본 섹션과 §0.5 표 — 다른 문서의 "완료" 서술은 이 표의 상태·증거일에 종속된다. 2026-10-10 판정의 지시(4/4 PASS를 배포 증거로 승계 금지)에 따라 seed promotion wiring CLOSED(2026-10-10)는 출시 증거가 아니다.

## 0.8 베타 사용자 경로 시나리오 1세트 (2026-10-18 고정 — 45회차 판정 지시: "실기기 수신 후 그대로 실행할 수 있는")

> **용도**: 실기기·배포 대상 빌드에서 사용자 경로 1줄을 처음부터 끝까지 관통해 증거를 남기는 실행 시트. §0.7의 4상태 규약으로 판정 기록. **상태: NOT_RUN(실기기·Team ID 대기)** — §5.1 사전 점검(`run_beta_scenarios.sh` 4/4, Mac 호스트)과 별개이며, 사람 테스터 과제는 `BETA_GUIDE.md`(사용성 측정)와 별개다. 하니스 재사용: 기계 단계는 `run_g27_device_e2e.sh`(devicectl·import→preview→export→audio→save→reopen)와 동일 하니스 체계 — 본 시트는 그 위의 경로 순서·판정·증거 위치를 고정한다(신규 시스템 신설 아님).
>
> **실행 전제**: G5 해제(Team ID)→배포 대상 빌드 설치(§3·§5)·Developer Mode 기기 페어링(`xcrun devicectl list devices`)·TEAM_ID 설정(`docs/G27_DEVICE_VERIFICATION_GUIDE.md`).

| # | 단계 | 입력·절차 | 기대 결과 | 증거(저장 위치) |
|---|---|---|---|---|
| 1 | 설치·Cold Launch | 배포 빌드 설치→완전 종료 후 cold launch | 홈 화면 도달·크래시 0 | 빌드 버전+launch 성공 기록 — G27 런 로그 |
| 2 | Import | 기기 녹화본 1개+제공 픽스처(solid_red_320x240_2s) 임포트 | 미디어 라이브러리 2개 표시·썸네일 생성 | 임포트 로그+썸네일 확인 — G27 런 로그 |
| 3 | Edit | 클립 1 트림→클립 순서 변경 | 타임라인 즉시 반영 | 편집 전후 상태 기록 — G27 런 로그 |
| 4 | Undo | 방금 트림 취소 | 편집 전 클립 길이 복원 | undo 결과 기록 — G27 런 로그 |
| 5 | Save·Reopen | 저장→앱 완전 종료→재실행→프로젝트 재열기 | 클립 구성·편집 상태 동일 | reopen 후 상태 비교 기록 — G27 런 로그 |
| 6 | Export | 1080p 프리셋으로 출력 | 출력 파일 생성·작업 완료 표시 | 파일 존재+크기 — 기기에서 확인 후 호스트 반출 가능분은 ffprobe 재검증 |
| 7 | Playback | 출력 파일 재생(기기 플레이어) | 처음→끝 재생·A/V 싱크 이상 0 | 재생 완료 기록+문제 시 화면녹화 — 진단 반출(CA-30 Share Beta Diagnostics) 병행 |

**판정 기록 방식**: 각 단계 PASS/FAIL+측정값을 회차 보고에 기록하고 §0.7 표의 G4/G5 상태를 갱신한다. FAIL 시: BUG lifecycle 7단계로 등록(재현 최소화 우선)·1줄 FAIL이어도 증거 파일 없이 PASS로 기록하지 않는다. **"시나리오 시트 작성"은 그 실행이 PASS라는 뜻이 아니다 — 현재 상태 NOT_RUN.**

## 0.9 배포 설정 읽기 전용 점검 (2026-10-19 — 45회차 판정 지시: "누락과 사용자 결정 필요 항목만 정리한 점검 결과")

> **성격**: 구성 파일의 읽기 전용 점검 — 실측 아님·설정 PASS는 배포 PASS가 아니다. 점검 대상: project.yml·Entitlements 2종·PrivacyInfo 2종·Info.plist 2종·ExportOptions.plist·release.sh.

| 항목 | 관측값 | 판정 |
|---|---|---|
| Bundle ID | `com.moviecut.mac` / `com.moviecut.ios`(+tests 서브 번들 3종 — 배포 타깃 아님) | §2 ASC 등록 예정 ID와 일치 — **누락 없음** |
| 버전 | MARKETING_VERSION 0.1.0·CURRENT_PROJECT_VERSION 1 | 릴리스 시 루프가 갱신+xcodegen generate(§7 관례) — 사용자 결정 불필요 |
| Signing | automatic signing·TEAM_ID는 env로 fail-loud(release.sh)·ExportOptions엔 `__TEAM_ID_PLACEHOLDER__`(커밋 금지 계약 유지) | **Team ID만 사용자 대기(§1·§5 BLOCKED_USER 유지)** |
| Entitlements(Mac) | app-sandbox·files.user-selected.read-write·files.bookmarks.app-scope·device.microphone | MAS 필수 4종 정합·**camera/network 의도적 미포함(App Review 리스크 회피 — 코드 주석에 설계 근거 기록)** |
| Entitlements(iOS) | 빈 dict(항상 샌드박스·Photos/문서 picker 런타임 권한 — 설계 주석) | 최소 원칙 정합 |
| 권한 설명 | NSMicrophoneUsageDescription·NSSpeechRecognitionUsageDescription(양 플랫폼) | 미사용 권한 설명 없음. **iOS 사진 임포트는 SwiftUI PhotosPicker(PHPicker·out-of-process)라 사진 라이브러리 권한 설명 불필요 — 구현 확인 완료(PhotosPicker 사용 3파일)** |
| 개인정보 | PrivacyInfo.xcprivacy 양 플랫폼 존재 | §6 "데이터 수집 없음" 응답과 정합 |
| Scheme/Release | xcodegen 생성(project.yml)·release.sh fail-loud 프리플라이트가 2026-09-19 실측 검증 | §3 첫 아카이브 NOT_RUN 유지(§0.7) |
| 베타 제외 기능 | 기능 동결 합의로 신규 기능 미편입·제외 플래그 특이사항 없음. 잔여: 계측 반출 UI 2차(CA-30)·thermal 측정(환경 차단·CODEX 축) | 신규 누락 없음 — 잔여는 §0.5/§0.7 표에 이미 추적됨 |

**점검 결론**: 배포 설정의 신규 누락 0건·코드/구성 정합 — **사용자 결정 필요 항목은 기존 BLOCKED_USER와 동일(Team ID·계정·스크린샷·실기기)**. 이 점검으로 G5가 열리는 것은 아니다. 이후 설정 변경 시 본 섹션을 갱신한다(읽기 전용 점검의 재실행).

## 0.10 AI Photo Montage preview/apply/undo 검증 준비 (2026-10-20 고정 — 45회차 판정 지시: "이미 구현된 AI Montage 경로의 검증"·사용자 경로로)

> **구현 확인(호출 경로 추적·읽기 전용)**: Mac 전용 — `AIMontageSection`(View)→`EditorViewModel.applyPhotoMontage`(`EditorViewModel+AssistantProvider.swift:68`): ①`PreparedAssetStore.preparePhotoAssets` ②`session.snapshotWithRevision` ③`PhotoMontagePlanner.plan`(프로덕션 플래너) ④`EditingPlanCompiler.compile`(원자적 배치 준비) ⑤`session.dispatch(batchCommand·planId·expectedRevision)`(적용 — **planId로 이중 디스패치 거부**) ⑥`refreshFromSession`. 준비①~④는 프로젝트를 변경하지 않는다(미리보기 지점) — 적용은 ⑤ 단 한 번. 기존 E2E 스위트 `AIPhotoMontageE2ETests` 존재. **주의: GURU 리팩터(49a0668~bfa18bd)가 EditorViewModel 등을 변경 — 검증 실행은 리팩터 안정화(커밋 종료) 후 HEAD에서.**

| # | 단계 | 입력·절차 | 기대 상태(관찰 지점) | 증거 |
|---|---|---|---|---|
| 1 | 제안 준비(plan) | 고정 입력: 픽스처 사진 N장(+음악 1 옵션)·targetDuration·9:16 — `plan` 호출 | **프로젝트 미변경**(revision 불변·타임라인 트랙/클립 수 불변)·plan.actions가 제안 내용을 보유 | plan 스냅샷 기록 |
| 2 | 준비·미리보기(compile) | `compile`로 prepared 배치 생성 | **프로젝트 미변경**(동일 관찰 지점) — 이 지점까지가 "미리보기" | prepared 라벨+액션 수 기록 |
| 3 | Apply(dispatch) | prepared 배치 디스패치 | **의도한 편집만 반영**: revision+N·클립 N 추가·캔버스 프리셋 반영·부수 변경 0·동일 planId 재디스패치는 거부 | dispatch 전후 revision·타임라인 상태 비교 기록 |
| 4 | Undo | undo 1회 | **적용 전 상태 복원**(revision·트랙/클립 수가 3 직전과 동일) | undo 전후 비교 기록 |
| 5 | Save·Reopen | 저장→재시작→재열기 | 편집 의미 유지(적용 상태 그대로) | reopen 후 상태 비교 |
| 6 | Export | 9:16 프리셋 출력 | 출력 성공·기하 1080x1920 | ffprobe(호스트 반출분) |

**판정 기록 방식**: §0.7 4상태 규약 준용 — **현재 상태 NOT_RUN**(시나리오 시트 작성은 실행 PASS가 아님). **고정 입력 사용 시 검증 범위는 실행·복구 경로다 — planner 미호출·고정 plan 결과를 "AI 제안 품질까지 검증"으로 표시하지 않는다**(45회차 판정 명시). Mac 호스트 소형 검증(`AIPhotoMontageE2ETests` 스위트)이 선행 가능 — 실기기 불필요. 실행 조건: ①GURU 리팩터 커밋 종료 확인 ②guard가 테스트 실행 허용(WARN 시 소형 스위트라도 재컴파일 리스크 평가) — 이행 전까지 본 시트는 고정 상태 유지.

## 1. Apple Developer 자격 확보 (사용자)

- [ ] Apple Developer Program 가입 (연 $99, https://developer.apple.com/programs)
- [ ] **Team ID 확인** (10자리 대문자):
  - Xcode → Settings → Accounts → 팀 선택 → "Team ID" 또는
  - https://developer.apple.com → Membership Details
- [ ] Xcode에 계정 추가 (Xcode → Settings → Accounts → +) — automatic signing이 인증서를 관리

## 2. App Store Connect 등록 (사용자, 1회)

- [ ] https://appstoreconnect.apple.com → 내 앱 → 새 앱
  - 플랫폼: macOS + iOS(동시 출시 결정 — 아래 항목)·번들 ID: `com.moviecut.mac` / `com.moviecut.ios` · SKU: 자유 (예: `moviecut-001`)
  - 이름/주 언어는 나중에도 수정 가능
- [ ] **iOS·Mac 동시 출시(2026-09-24 결정 — "Mac과 동시")·Universal Purchase** — 단일 앱 레코드에 양 플랫폼으로 등록해 **구매 1회 공유**. 동시 출시 결정으로 **G4(실기기 검증 — 현재 1/3 BLOCKED)와 CODEX-04(PhotosPicker P1)가 출시 critical path가 됨** — iOS 검증 레인이 늦어지면 Mac 출시 일정도 함께 늦어짐(양 플랫폼 동일 빌드 버전 심사 권장).
- [ ] iOS 심사 메타: iPhone 스크린샷(6.9" 필수 + 선택)·iPad 지원 여부 확인(device family — 프로젝트 설정에서 결정)·iOS 개인정보 응답(Mac과 동일 — `PrivacyInfo.xcprivacy` iOS 타깃 포함 확인)
- [ ] (선택) App Store Connect API 키 생성: 사용자 및 액세스 → 통합 → 팀 키
  — 키 ID / Issuer ID / .p8 파일을 보관 (업로드 자동화용, §5에서 사용)

## 2.5 유료 판매 행정 (사용자 — 2026-09-24 보강, 유료 앱 전제)

> 스토어 계정(Apple ID) 경로 확정에 따른 항목. 무료 출시 후 전환 시에도 동일.

- [ ] **Paid Applications 계약 체결 + 은행·세금 정보 등록** — ASC에서 유료 앱 판매의 필수 선행(미체결 시 유료 심사 제출 불가). 국내 사업자/세무 처리(매출 발생 시)도 함께 검토.
- [ ] **가격 층 확정(CA-07 — 사용자 전용)** — **잠정 추천 $29.99(2026-09-24)**. 옵션 분석은 `DECISIONS_20260822.md` 2026-09-24 추가 결정 섹션(Q16) 참조. 최종 확정은 베타 3-B "지불 의향" 점수 회수 후(출시 한시가→정상가 스케줄 옵션 병행 가능).
- [x] **가족 공유(Family Sharing): 끔(2026-09-24 결정 — "우선은 끄기")** — ASC 앱 설정에서 비활성화. 유료 전체 앱·IAP 없음이라 앱 내 코드 영향 0건. 이후 켜는 것은 언제든 가능(정책 변경 시 매출 영향 재검토).
- [x] **유료 메이저 업데이트 채널 해석 확정(2026-09-24 — Q17 ④)**: **1.x 업데이트 무료·유료 메이저는 2.0 필요 시점에 신규 SKU/IAP 중 재결정**. MAS 하드 룰(유료 앱 SKU 내 업데이트는 구매자에게 영원히 무료·업그레이드 가격 메커니즘 없음)과 선택지 4종 분석은 `DECISIONS_20260822.md` Q17 참조. Q2 "FCP식" 표현은 정정 기록 완료(REQUIREMENTS §13.15-2 동일 정정).
- [ ] **환불·지원 응대 기준** — 환불 처리는 Apple측(앱 내 계정·구매 상태 코드 없음 — 유료 전체 앱은 receipt 검증도 선택). 지원 URL 정책(문의 → 진단 붙여넣기 워크플로, BETA_GUIDE §2 마무리 항목과 동일 절차) 1줄 문서화.

## 3. 첫 아카이브 (로컬)

```bash
MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh
```

- [ ] verify_gate 5단계(swift build·swift test 전체·Mac 빌드·iOS 빌드·lint) 통과 후 archive → export까지 `S5 RELEASE PIPELINE OK` 출력 확인
- 실패 시: `.build-check/last_gate.log` (게이트) 또는 `build/release/` 로그 — 서명 오류면 Xcode 계정(§1)부터 재확인
- 생성물: `build/release/export/MovieCutMac.app`

## 4. 제출

방법 A — 자동 (키 만든 경우):
```bash
MOVIECUT_TEAM_ID=XXXXXXXXXX UPLOAD=1 \
MOVIECUT_ASC_KEY_ID=XXX MOVIECUT_ASC_ISSUER_ID=xxx-xxx \
MOVIECUT_ASC_KEY_PATH=/path/AuthKey_XXX.p8 \
bash scripts/release.sh
```

방법 B — 수동 (간단):
- [ ] `open -a Transporter "$PWD/build/release/export/MovieCutMac.app"` → Transporter에서 배달
- 또는 App Store Connect 웹에서 빌드 업로드

방법 C — GitHub Actions:
- [ ] 저장소 Settings → Secrets → Actions에 `MOVIECUT_TEAM_ID` 추가
- [ ] Actions → Release → Run workflow (자격증명 없으면 fail-loud로 빨개짐 — 정상)

## 5. TestFlight 베타 (사용자)

### 5.1 베타 출시 게이트 — 수치 기준 (2026-09-21 채택, 방향 자문 반영)

> 원천: `AI_REVIEW/FEEDBACK_20260921_DIRECTION.md` P0 + `LOCAL_BETA_DIAGNOSTICS_DESIGN_20260921.md` §4.
> 전제: 실기기 3종(최저/중간/최신) × 대표 워크플로우 3종 이상 Blocker 0 (G-27).
> 측정 인프라(CAPCUT_FEATURE_BACKLOG CA-30) 승인 전까지는 대리 판정으로 G-27 러너 Blocker 0 + `run_beta_scenarios.sh` 4/4를 사용한다.

| 게이트 | 기준 |
|---|---|
| Import 성공률 | ≥ 98% |
| 첫 프로젝트 Export 성공률 | ≥ 95% |
| 재실행 후 프로젝트 복구 | 100% |
| A/V sync critical defect | 0 |
| 편집 중 crash | < 1% session |
| Photos 권한 상태별 dead-end | 0 |
| 20분 편집 후 thermal 사용불가 | 0 |
| P0/P1 UI blocker | 0 |

베타 품질 지표(Unaided First Export ≥80%→90%·첫 출력 median ≤10분/P80 ≤15분·7일 내 두 번째 프로젝트 ≥40% 등)의 측정 설계는 `LOCAL_BETA_DIAGNOSTICS_DESIGN_20260921.md` — 오프라인 원칙 유지(로컬 JSON·opt-in 반출만).

- [ ] App Store Connect → TestFlight → 빌드 선택 → 그룹 생성(내부 테스터 10~20명)
- [ ] 테스터에게 `docs/BETA_GUIDE.md` 전달 (6단계 과제 + 정성 메트릭 시트 + 마무리 진단 회수)
- [x] 베타 전 사전 점검: `bash scripts/run_beta_scenarios.sh` PASS 확인 (호스트에서 1회) — **실행 완료(2026-09-04 루프, 2회 연속 4/4 PASS)**: ①임포트→첫 컷→출력(dur=3.000s·1920x1080) ②색 보정→출력 ③9:16 세로 출력(1080x1920 기하 실측) ④autosave 저장·재시작 복구(recovered_clips=1). 각 단계 wall-clock 3.2~4.1s·ffprobe 검증. 루트 커밋 시점 HEAD에서 측정.
- [ ] 회수 기한 1주 후 메트릭 취합 → 출시/차기 우선순위 판단 (가이드 §5 기준)

## 6. 심사 제출 (사용자)

- [ ] App Store 정보: 스크린샷 — **macOS는 16:10 비율 4종 규격만 허용(1280×800 · 1440×900 · 2560×1600 · 2880×1800, 1~10장). 1920×1080(16:9)은 업로드 거부됨 — 2026-09-03 정정, 구문 "1920×1080 이상"은 오류였음** —, 설명, 키워드, 지원 URL, 개인정보 처리방침 URL
- [ ] 개인정보 응답: 데이터 수집 없음 (온디바이스 전 처리 — `PrivacyInfo.xcprivacy`와 일치)
- [ ] 연령 등급 설문 (영상 편집 — 통상 4+)
- [ ] 제출 → 심사 대기 (통상 1~3일)

## 7. 참고

- 인증서/프로비저닝은 automatic signing이 처리 — 수동 관리 불필요
- export 옵션은 `scripts/ExportOptions.plist` (팀 ID는 실행 시 치환, 커밋되지 않음)
- 버전은 `project.yml`의 `MARKETING_VERSION` (현재 0.1.0) — 릴리스마다 올리고 `xcodegen generate`
- 릴리스 게이트 근거: nightly가 green인 커밋에서만 트리거할 것 (review §7 Product Reliability Gate)
