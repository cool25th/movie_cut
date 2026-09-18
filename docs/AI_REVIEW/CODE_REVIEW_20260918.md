# 코드 리뷰 — AI 리뷰 루프 인프라 전체 (2026-09-18)

- 범위: `fff21d3`~`69dde83`(20 커밋)의 코드 파일 전수 — 스크립트 11종·`DiarizationMeasurementTests.swift`(수정 1곳)·`qa/baselines/dataset-lock.json`
- 방법: 핵심 4종(`check_dataset_pins`·`disk_guard`·`disk_attribution`·드라이버 trap) 전문 정독 + 의심 패턴 3건 실제 실행 검증(EXIT trap rc 보존·깨끗한 이력 operator_attention·STOP 해제 관측 횟수)
- **종합 판정: 견고 — P2 이상 0건. 제품 소스 무변경(유일한 Swift 수정=CA-18 degeneracy 가드·전행 재측정 2회 무손상 확인)**

## 검증으로 확인된 강점

- fail-closed 일관성: 핀 4상태·journal 양방향 1:1 대조·컨트롤 실패 시 실측 거부·매니페스트 collision — 전부 오류 시 종료 방향
- **EXIT trap 원본 rc 보존 실증**(exit 23 → 최종 rc 23) — `rc=$?` 첫 문 캡처 → 매니페스트 → 원복 rc 순서 정확(10회차 피드백 계약 충족)
- 세션이 밟은 함정 3회(set -e/pipefail 무음 종료·run_id 절단·GiB 환산)는 코드 주석+메모리에 문서화돼 재발 방지
- 실측 무손상: CA-18/21 결과가 장비 추가 전후 동일(40.1/31.9%·0.875/1.000)·direct 이중계산 수정 반영

## P3 3건 (기능 영향 없음·정합성)

1. **`disk_guard.sh:141-145` — BLOCK 이력이 전혀 없는 이력에서 `operator_attention_required` 항상 true**: `released_at=None → since_release_ok=False → attention=True`. 실측 재현(GO만 있는 합성 이력 → attention true). 현재 이력엔 실제 BLOCK이 있어 표시는 맞으나 "차단된 적 없으면 주의 불필요"이 논리적으로 옳음 — 신규 환경에서 플래그 영구 켜짐.
2. **`disk_guard.sh:91-102` — 주석("≥12GiB 2회 연속 관측 시 해제")과 코드(1회 관측 해제) 불일치**: 실측 재현(STOP 직후 12GiB 단일 관측 → 즉시 BLOCK). 실질 영향 작음(BLOCK도 build/test 금지 유지)이나 계약-구현 정합성 결함.
3. **`check_dataset_pins.sh:206` — lock 항목에 `sha256` 키 부재 시 python exit 1 → `set -e`로 요약 없이 무음 종료**: 현재 커밋된 lock은 유효하나, 본 저장소 3회 밟은 무음 종료 함정의 미잔 패턴.

## P4 2건 (메모)

- `check_dataset_pins.sh:86` — 2부 분 spec(`file:fixture_id`)에서 `oracle_role`이 fixture_id와 동일값 중복 기록(콜론 분해 엣지)
- `disk_attribution.sh:40` — `read -r CUR_TS`가 ts 무공백 가정(ISO 형식이라 현재 항상 참·암묵 가정)

## 처분 결과 (2026-09-18 수리 완료)

- **P3 1·2 수리 완료**: ①`ever_gated`(BLOCK/STOP 이력 전무 시 attention 불필요) ②STOP 해제 ≥12GiB **2회 연속 강제**(BLOCK 해제 경로와 동일 방식 — 주석·코드 일치).
- **검증(합성 5케이스+실가드)**: A 깨끗한 이력 → attention false(기록 3건 실재 확인) / B 단일 12GiB → STOP 유지 / C 12.5→12.8 2회 연속 → BLOCK 복귀 / D 2회차 미달 → STOP 유지(리셋) / E BLOCK 이력 → attention true 회귀 없음 / 실가드 GO 27.88GiB·attribution 실제 LARGE_RECOVERY(Δ+10.82) 캡조+post-event baseline.
- **수리 중 신규 함정 발견·기록**: macOS bash 3.2에서 `$()` 내부 heredoc 주석의 아포스트로피가 파서를 깨뜨림(최소 재현 확인) — 주석 문구로 회피.
- **P3 3 + P4 2 수리 완료(같은 날 후속)**: ③verify의 sha256 부재 항목 → 명시 `HASH_ERROR`(무음 종료 제거) · P4-1 spec 2부 분에서 role=fid 중복 → `unassigned` · P4-2 attribution read를 `|` 구분자로(공백 무가정).
- 검증: 변형 lock(git 저장소 합성) → HASH_ERROR+exit 1·spec 3형태(3부/2부/무식별) 정상·실 lock 6종 MATCH 회귀·attribution 실실행 정상.
- 테스트 함정 1건 추가 기록: 합성 lock 검증 시 `git init` 누락하면 LOCK_ROOT가 스크립트 루트로 폴백해 rel 접두 매칭 실패(오판 방지 — 합성 저장소는 git init 필수).
