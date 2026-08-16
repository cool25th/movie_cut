# PR 초안 — Phase 1 렌더링 신뢰성 + 신뢰성 하드닝 + 관측성/성능/베타 + snapshot 인프라

> 저장소가 연결되면 사용할 PR 본문 초안.
> 브랜치: `ui-snapshot-infra` (베이스: `ead8ade`).
> 커밋 10개, Core 1177 테스트 / 183 suites 통과, Mac 앱 21 단위 테스트 통과, 빌드 성공.

## 실행 순서 (저장소 연결 후)
```bash
git remote add origin <REPO_URL>
git push -u origin ui-snapshot-infra
gh pr create --title "Phase 1: render reliability + reliability hardening + observability + snapshot infra" --body-file docs/PULL_REQUEST_DRAFT.md
```

---

## PR 제목
`Phase 1: render reliability + reliability hardening + observability + snapshot infra`

## PR 본문

외부 리뷰(제품/기술 진단)의 P0/P1 중 **코드로 가능한 것**을 처리했습니다.
조사 단계에서 리뷰의 여러 가정이 구식/부정확했음이 드러나, 실제 코드베이스에 맞춰 범위를 조정했습니다.

### 커밋 (10개)

1. **`feat: pin SDR Rec.709 color contract, gate HDR, harden render parity (Phase 1)`**
   - `RenderColorConfiguration`: 모든 CIContext의 working/destination 색공간을 sRGB/Rec.709로 고정 (이전엔 전부 기본값 → preview↔export 색 드리프트, 핵심 parity 버그).
   - SDR export에 Rec.709 태깅, 소스 색공간 감지.
   - `FeatureFlag` 도입 → HDR 메뉴/플래너 보호 (8-bit 파이프라인이 HDR 태그 붙이는 거짓 라벨 차단).
   - `ClipTransform.affineTransform`/`.isIdentity` Core 헬퍼로 수렴 → preview↔export 드리프트 제거.
   - 검증: `verify_export_color_metadata.py`, nightly 게이트, `verify_gate.sh` 경로 정비.

2. **`feat: add Ken Burns effect and photo-slideshow Quick Start`** (pre-existing 작업 보존)

3. **`feat: harden save/export/relink reliability (P0 #6)`**
   - `FileOperationError`: 디스크 풀/권한/손상/취소 분류 → 사용자 친화 메시지.
   - export 취소/실패 시 부분 파일 정리. 손상 autosave 더 이상 조용히 무시 안 함.
   - `relinkMedia` (자산 UUID 보존) + File 메뉴 재연결 UI.

4. **`test: triage StaticContract debt (W2)`**
   - `triage_static_contracts.py`: 91개 파일을 KEEP/REPLACE/DELETE/EXCLUDE로 자동 분류 (재실행 가능 부채 원장).
   - defect-lockout 5개 제거. IOSParityMatrix 소스 문자열 → 동작 테스트(golden)로 승격.

5. **`feat: observability + perf gates`**
   - AppLog 카테고리별 OSSignposter + 핫패스 signpost. `PERFORMANCE_SLO.md` + perf realtime 게이트. ExportEngine thermal 게이트 (.critical 시 시작 거부).
   - MetricKit은 프라이버시 정책 유지로 도입 안 함 (사용자 결정).

6. **`test/docs: beta pre-flight + human guide (review §8)`**
   - `run_beta_scenarios.sh` (사전 점검) + `BETA_GUIDE.md` (사람 6단계 + 정성 메트릭 시트).

7. **`test: extend UI snapshot regression to multi-state goldens + nightly gate`**
   - `ui_capture.sh`/`ui_regression.sh`를 단일 상태 → 명명된 다중 상태로 일반화 (bash 3.2 호환).
   - dhash 회귀를 nightly 게이트로. 골든 2개(import_only, populated_editor) — 정상 에디터 화면 검증.

8. **`fix: capture permission error + inspector tab truncation (found via UI goldens)`**
   - `ui_capture.sh`가 sandbox를 안 꺼서 harness import가 `NSCocoaErrorDomain:257`로 실패 → 골든이 "import 에러 화면"이었음. `ENABLE_APP_SANDBOX=NO`로 수정 + 정상 화면 재캡처.
   - 인스펙터 세그먼트(5개 탭) 잘림 "Mask"→"Mas" → minWidth 288 + `.controlSize(.small)`로 해결. 캡처로 5개 라벨 온전 표시 확인.

9. **(정리) UIRegressionInfrastructureStaticContractTests 갱신 + 이 PR 초안 갱신**
   - 스크립트 일반화로 깨진 StaticContract 단언을 parametrized 패턴 + 파일 시스템 골든 존재 검증으로 전환.

### 검증
- Core **1177 테스트 / 183 suites 통과** (회귀 0).
- Mac 앱 단위 테스트 **21개 통과**. 빌드 성공.
- 모든 셸/파이썬 스크립트 + CI/nightly YAML 문법 OK.

### 조사가 정정한 리뷰 가정 (누적)
1. "85개 StaticContract 파일" → 실제 91개 (5개는 이미 동작 테스트).
2. "docs 산문 단언 38개 파일" → 이미 0개.
3. "단일 Render Graph를 새로 지어라" → 이미 픽셀 단위로 존재.
4. "S4 아이콘·메타데이터 0건" → 이미 완료.
5. "OSLog/MetricKit/thermalState 0건" → OSLog·thermalState는 이미 작동 중 (MetricKit만 의도적 부재).
6. "카드뉴스·iOS UI를 숨겨라" → 진입점 자체가 0개 (이미 안전).

### 범위 밖 (별도 진행 필요)
- **S5 서명/배포**: Apple Team ID·자격증명 필요 (사용자 작업).
- **사람 베타 실행**: 코드 불가 — `BETA_GUIDE.md`로 진행.
- **StaticContract REPLACE 70개**: 원장화됨, 점진적 교체 (harness 보강 → 골든 확대 후).
- **thermalState gradual 강등** (.fair 단계): export 최소 반응만, 단계 강등은 후속.

### 리뷰에 부탁드리는 점
- 색공간 단일화(`RenderColorConfiguration`)가 preview↔export parity를 실제로 보장하는지 실기기 확인.
- `relinkMedia` UUID 보존이 실제 워크플로에서 클립 참조를 유지하는지 확인.
- SLO 임계값(1.5×/1.2×)이 합리적인지, 기준 장비 측정 후 조정 필요 여부.
- 내부 라벨(Transform/Blend) 잘림이 minWidth 증가로 해결됐는지 클립 선택 상태에서 확인.
