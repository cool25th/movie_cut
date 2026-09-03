# Phase 3-A 검증 매트릭스 — 백그라운드·디스크 부족·취소·재열기·외장 미디어 (2026-09-04)

> STABILIZATION_PLAN_20260829.md §3 Phase 3-A의 "검증 매트릭스" 축 5종을 측정 증거로 완결하는 원장.
> CA05(2026-08-24)는 **종이 감사**였고 — 그 12행(취소)의 "catch 경로 동일 정리" 주장이 STAB-02 실측에서 거짓(펌프 continuation 누수 파킹·크래시)으로 판명된 사례가 이 매트릭스의 존재 이유. 각 축은 측정 증거(스크립트·테스트·커밋) 또는 명시적 불가 사유로만 판정한다.

| 축 | 판정 | 측정 증거 |
|---|---|---|
| **취소 (Mac)** | ✅ 측정 완료 | `scripts/run_e2e_cancel.sh` **3/3 PASS** (정직 3조건: UITEST_DONE+error≠none+부분출력 부재 — 구 판정의 파킹 앱 가짜PASS 함정은 게이트 자체 수리) + `ExportCancelMidFlightTests` 2/2×3회 — 커밋 73854f1. 실측이 결함 2종을 적발·수리: 펌프 continuation 누수 파킹(취소 폴러+once-guard)·취소 writer finishWriting 크래시(선검사) |
| **취소 (iOS)** | ✅ 측정 완료 | `IOSExportCancelMidFlightTests` 2/2(반복 발사 취소→실패·부분 삭제·엔진 리셋 / sanity 2s 완주) + iOS 전체 83/20 — 커밋 c917c55 (BUG-ACC-09, Mac 패턴 포팅) |
| **재열기 (autosave 복구)** | ✅ 측정 완료 | `run_beta_scenarios.sh` step 4 `recovery=recovered_clips=1` — 2회 연속 4/4 PASS 중 포함 (2026-09-04, c981222) |
| **외장 미디어 (소실/재연결)** | ✅ 측정 완료 (소실 클래스) | `ExportMediaPreflightTests` — 도달 불가 미디어가 렌더 **이전** 프리플라이트에서 명시 거부+재연결 안내 (BUG-04 수정분) · `MediaRelinkTests` (재연결 취소/실패) · CA03 감사 원장. 물리적 언플러그·외장 볼륨 지연은 실기기/수동 관찰 항목 |
| **디스크 부족 (익스포트 ENOSPC)** | ✅ 측정 완료 (이 문서와 동일 증분) | `scripts/run_diskfull_gate.sh` **2/2 PASS** — 1MB 스크래치 DMG 볼륨에 ~1.64MB ProRes 익스포트로 **실 ENOSPC 미드플라이트 유발**: 분류 메시지 `error=디스크 가득참` 표면·목적지 아티팩트 부재·UITEST_DONE 정상(파킹/크래시 없음)·CONTINUATION MISUSE 0건. CA05 11행의 종이 주장(분류+부분 정리)은 취소 행과 달리 **실측으로 참** 판명 |
| **디스크 부족 (autosave)** | ✅ 시뮬레이션 측정 | `AutosaveFailureSurfacingTests` — 실패 주입 경로의 비차단 경고 표면(BUG-01 수정분). 실ENOSPC가 아니라 시뮬레이션임을 명시(컨테이너 autosave 축의 실 꽉찬 볼륨 재현은 파괴적 — 미측정 사유 기록) |
| **백그라운드 (macOS)** | ✅ 구조적 증거 | macOS AppKit 앱은 iOS식 서스펜션 부재(프레임워크 동작) — 하니스 E2E 전부(베타 4 시나리오·취소·디스크 풀 게이트)가 헤드리스=백그라운드 구동에서 완주한 것이 그 자체로 증거. 별도 측정축 아님 |
| **백그라운드 (iOS 서스펜션)** | ⏸ 실기기 관찰 | iOS의 백그라운드 서스펜션/재개 동작은 시뮬레이터로 실측 불가 — G-27 실기기 2종(사용자 대기)에서 관찰 |

**잔여(전부 사용자/환경 대기)**: iOS 서스펜션(실기기)·물리적 외장 언플러그(실기기/수동)·autosave 실ENOSPC(파괴적 — 시뮬레이션 커버로 종결 판정).

**부기**: 디스크 풀 게이트의 러너 와치독 종료 시 셸 잡 제어 메시지("Terminated: 15") 1건 노출 — 판정 무영향(코스메틱).
