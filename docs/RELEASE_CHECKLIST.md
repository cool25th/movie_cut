# MovieCut 출시 체크리스트 (S5 — Mac App Store)

> 코드 쪽 파이프라인은 완료돼 있습니다(`scripts/release.sh`, `scripts/ExportOptions.plist`,
> `.github/workflows/release.yml` — 커밋 `dc559a3`). 이 문서는 **사용자만 할 수 있는**
> 자격증명/등록/배포 단계를 순서대로 정리한 것입니다. 각 단계가 끝나면 체크박스를 채우세요.

---

## 0. 전제 (이미 완료됨)

- [x] Mac App Store 단독 배포 결정 (공증/Developer-ID 불필요)
- [x] `scripts/release.sh` — verify_gate(4단계) → archive(Release, 서명) → export(app-store-connect) → 선택 업로드, 자격증명 없으면 **fail-loud**
- [x] `.github/workflows/release.yml` — 수동 트리거(Actions → Release → Run workflow)

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

## 3. 첫 아카이브 (로컬)

```bash
MOVIECUT_TEAM_ID=XXXXXXXXXX bash scripts/release.sh
```

- [ ] verify_gate 4단계(build/1177테스트/Mac/iOS) 통과 후 archive → export까지 `S5 RELEASE PIPELINE OK` 출력 확인
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

- [ ] App Store Connect → TestFlight → 빌드 선택 → 그룹 생성(내부 테스터 10~20명)
- [ ] 테스터에게 `docs/BETA_GUIDE.md` 전달 (6단계 과제 + 정성 메트릭 시트)
- [ ] 베타 전 사전 점검: `bash scripts/run_beta_scenarios.sh` PASS 확인 (호스트에서 1회)
- [ ] 회수 기한 1주 후 메트릭 취합 → 출시/차기 우선순위 판단 (가이드 §5 기준)

## 6. 심사 제출 (사용자)

- [ ] App Store 정보: 스크린샷(1920×1080 이상), 설명, 키워드, 지원 URL, 개인정보 처리방침 URL
- [ ] 개인정보 응답: 데이터 수집 없음 (온디바이스 전 처리 — `PrivacyInfo.xcprivacy`와 일치)
- [ ] 연령 등급 설문 (영상 편집 — 통상 4+)
- [ ] 제출 → 심사 대기 (통상 1~3일)

## 7. 참고

- 인증서/프로비저닝은 automatic signing이 처리 — 수동 관리 불필요
- export 옵션은 `scripts/ExportOptions.plist` (팀 ID는 실행 시 치환, 커밋되지 않음)
- 버전은 `project.yml`의 `MARKETING_VERSION` (현재 0.1.0) — 릴리스마다 올리고 `xcodegen generate`
- 릴리스 게이트 근거: nightly가 green인 커밋에서만 트리거할 것 (review §7 Product Reliability Gate)
