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

## 1. Apple Developer 자격 확보 (사용자)

- [ ] Apple Developer Program 가입 (연 $99, https://developer.apple.com/programs)
- [ ] **Team ID 확인** (10자리 대문자):
  - Xcode → Settings → Accounts → 팀 선택 → "Team ID" 또는
  - https://developer.apple.com → Membership Details
- [ ] Xcode에 계정 추가 (Xcode → Settings → Accounts → +) — automatic signing이 인증서를 관리

## 2. App Store Connect 등록 (사용자, 1회)

- [ ] https://appstoreconnect.apple.com → 내 앱 → 새 앱
  - 플랫폼: macOS · 번들 ID: `com.moviecut.mac` · SKU: 자유 (예: `moviecut-mac-001`)
  - 이름/주 언어는 나중에도 수정 가능
- [ ] (선택) App Store Connect API 키 생성: 사용자 및 액세스 → 통합 → 팀 키
  — 키 ID / Issuer ID / .p8 파일을 보관 (업로드 자동화용, §5에서 사용)
- [ ] **iOS 앱·Universal Purchase 정렬(결정 대기)** — Q2(2026-08-22)가 "Universal Purchase 동반"으로 결정됐으나 본 체크리스트는 Mac 선행(S5). iOS 앱 레코드 등록(`com.moviecut.ios` 가정)·구매 호환 설정·iOS 스크린샷/심사 항목은 Mac 출시 전 동시인지 이후인지 **착점을 별도 결정**해 §2-§6에 추가할 것. (2026-09-24 감사에서 불일치로 식별)

## 2.5 유료 판매 행정 (사용자 — 2026-09-24 보강, 유료 앱 전제)

> 스토어 계정(Apple ID) 경로 확정에 따른 항목. 무료 출시 후 전환 시에도 동일.

- [ ] **Paid Applications 계약 체결 + 은행·세금 정보 등록** — ASC에서 유료 앱 판매의 필수 선행(미체결 시 유료 심사 제출 불가). 국내 사업자/세무 처리(매출 발생 시)도 함께 검토.
- [ ] **가격 층 확정(CA-07 — 사용자 전용)** + **가족 공유(Family Sharing) 활성화 여부** 결정 — 일회성 구매 앱에서 가족 공유는 매출·호감 양축에 직접적.
- [ ] **유료 메이저 업데이트 채널 해석 확정** — MAS는 기존 앱에 대한 유료 업데이트를 직접 지원하지 않음(신규 SKU 방식 필요). Q2의 "일회성 구매 + 유료 메이저 업데이트(FCP식)"가 ①MAS 무료 업데이트 지속+메이저는 신규 SKU, ②직배포 병행, ③다른 해석 중 무엇인지 확정해 문서화할 것. (2026-09-24 감사에서 미결정으로 식별)
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
