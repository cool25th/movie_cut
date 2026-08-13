# PR 초안 — Phase 1 렌더링 신뢰성 + 신뢰성 하드닝 + 관측성/성능/베타 준비

> 저장소가 연결되면 사용할 PR 본문 초안.
> 브랜치: `ready/phase1-render-reliability` (베이스: `ead8ade`).
> 커밋 6개, Core 1177 테스트 / 183 suites 통과, Mac 앱 빌드 성공.

## 실행 순서 (저장소 연결 후)
```bash
git remote add origin <REPO_URL>
git push -u origin ready/phase1-render-reliability
gh pr create --title "Phase 1: render reliability + reliability hardening + observability/beta prep" --body-file docs/PULL_REQUEST_DRAFT.md
```

---

## PR 제목
`Phase 1: render reliability + reliability hardening + observability/beta prep`

## PR 본문

외부 리뷰(제품/기술 진단)의 P0/P1 항목 중 **코드로 가능한 것**을 처리했습니다.
조사 단계에서 리뷰의 여러 가정이 구식/부정확했음이 드러나, 실제 코드베이스 상태에 맞춰 범위를 조정했습니다.

### 커밋

1. **`feat: pin SDR Rec.709 color contract, gate HDR, harden render parity (Phase 1)`**
   - `RenderColorConfiguration`: 모든 CIContext의 working/destination 색공간을 sRGB/Rec.709로 고정 (이전엔 전부 기본값 → preview↔export 색 드리프트).
   - SDR export에 Rec.709 태깅, 소스 색공간 감지.
   - `FeatureFlag` 도입 → HDR 메뉴/플래너 보호 (8-bit 파이프라인이 HDR 태그 붙이는 거짓 라벨 차단).
   - `ClipTransform.affineTransform`/`.isIdentity` Core 헬퍼로 수렴 → preview↔export 드리프트 제거.
   - 검증: `verify_export_color_metadata.py`, nightly 게이트, `verify_gate.sh` 경로 정비.
   - 테스트: ColorSpaceParityTests(7), HDRProfileGatingTests(4), ClipTransformAnchorTests(5).

2. **`feat: add Ken Burns effect and photo-slideshow Quick Start workflow`** (pre-existing 작업 보존)

3. **`feat: harden save/export/relink reliability — disk-full, partial-output, corrupt autosave, missing-media relink (P0 #6)`**
   - `FileOperationError`: 디스크 풀/권한/손상/취소 분류 → 사용자 친화 메시지.
   - export 취소/실패 시 부분 파일 정리 (4개 export 경로).
   - 손상 autosave 더 이상 조용히 무시 안 함 → 분류 + 파일 정리 + 모달.
   - `relinkMedia` (자산 UUID 보존) + File 메뉴 재연결 UI.
   - AppLogTests static-contract false-positive 수정.

4. **`test: triage StaticContract debt — auto-classify, delete fake signal, promote one to behavior (W2)`**
   - `triage_static_contracts.py`: 91개 파일을 KEEP/REPLACE/DELETE/EXCLUDE로 자동 분류 (재실행 가능 부채 원장).
   - defect-lockout(syncToCloud 등) 5개 파일에서 제거.
   - IOSParityMatrix: 소스 문자열 → 동작 테스트(golden)로 승격.

5. **`feat: observability + perf gates — OSLog signposts, SLO thresholds, export thermal gate`**
   - AppLog에 카테고리별 OSSignposter + 핫패스(export.preset, playback.buildComposition) signpost.
   - `PERFORMANCE_SLO.md` + perf 스크립트 realtime 게이트 (Debug ≤1.5×, Release ≤1.2×).
   - ExportEngine thermal 게이트 (.critical 시 시작 거부).
   - MetricKit은 프라이버시 정책 유지로 도입 안 함 (사용자 결정).

6. **`test/docs: add beta pre-flight script + human beta guide (review §8)`**
   - `run_beta_scenarios.sh`: 베태 과제 사전 점검 (자동화 가능 부분).
   - `BETA_GUIDE.md`: 사람 테스터용 6단계 + 정성 메트릭 시트.

### 검증
- Core **1177 테스트 / 183 suites 통과** (회귀 0).
- Mac 앱 빌드 성공.
- 모든 셸/파이썬 스크립트 문법 OK.

### 범위 밖 (별도 진행 필요)
- **S5 서명/배포**: Apple Team ID·자격증명 필요 (사용자 작업).
- **사람 베타 실행**: 코드 불가 — `BETA_GUIDE.md`로 진행.
- **StaticContract REPLACE 70개**: 원장화됨(`STATIC_CONTRACT_TRIAGE_RESULT.md`), 점진적 교체.
- **thermalState gradual 강등**: export 최소 반응만, .fair 단계 강등은 후속.

### 리뷰에 부탁드리는 점
- 색공간 단일화(`RenderColorConfiguration`)가 preview↔export parity를 실제로 보장하는지 실기기에서 확인.
- `relinkMedia` UUID 보존이 실제 워크플로에서 클립 참조를 유지하는지 확인.
- SLO 임계값(1.5×/1.2×)이 합리적인지, 기준 장비에서 측정 후 조정 필요 여부.
