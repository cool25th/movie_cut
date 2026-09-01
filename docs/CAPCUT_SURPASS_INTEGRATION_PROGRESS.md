# capcut-surpass 통합 진행 기록 (codex/integrate-capcut-surpass)

계획: [CAPCUT_SURPASS_INTEGRATION_PLAN_20260901.md](./CAPCUT_SURPASS_INTEGRATION_PLAN_20260901.md) ·
2026-09-02 실행. 통합 브랜치 기준: 대상 `b970563`(feat/g25-inc8-app-wiring) + 장편 WIP 2커밋.

## 전제 조건 이행

- 장편 BLOCKER WIP를 독립 커밋으로 정리: `a888c50`(LF-ACTION-01/02 렌더 수정)·`28515a5`(LF-ACTION-05 하니스).
  타 세션 미추적 문서 2건(CAPCUT_SURPASS_INTEGRATION_PLAN·NEXT_SESSION_EXECUTION)은 무접촉.
- 소스 브랜치 `feat/capcut-surpass-7gaps`(646298e) 유지 — 삭제 조건(최종 통합+원격 백업) 미충족.

## 이식 완료 (게이트 GATE_PASS 5/5 · swift test 1,465/218)

| 소스 커밋 | 통합 커밋 | 비고 |
|---|---|---|
| `cc68964` 보컬 분리 UI 호스팅 | `1de73bb` | R401 계약 갱신 + 오디오 전용 노출 단언 |
| `e9f6703` AutoColor 실분석 배선 | `ddbffd8` | stub 삭제·계약 테스트 복원·확장 |
| `10af50b` 자막 word timing | `aff731d` | split/merge 배선. 정렬 경로는 현행 G-01 구조 유지 |
| `9304e8b` autosave coalescing | `4427d3e` | 재작성: BUG-01 오류 노출 보존 + 직렬·최신값 승리·flush 즉시 |
| `233dee7`·`7b240d4` undo 테스트 | `1cca9b3` | 선별: 커버 없는 5개 명령만 (나머지 7개는 기존 스위트 중복) |
| `18e8b74` 베지어 Core | `846d9c1` | 그래프 수학·렌더 clip effect·valueAt 모두 customCurve 퍼널 |
| `eb0eba5` 베지어 UI | `6a7ca71` | BezierCurveEditorView + pbxproj 등록·preset/overshoot 게이트 |

부수: `5357375`(R402 오디오 분기 계약 갱신 — 의도된 구조 변경).

## 미이식 — 계획상 명시된 후속 (감사 판정 완료)

| 소스 커밋 | 판정 |
|---|---|
| `ac589c2`·`cdb7053`·`7ae1055` 10-bit HDR | **3단계 후속** — 계획이 별도 재설계 요구(공통 색관리 계약·`VideoCompressionProfile` 유지·e2e pix_fmt 강화·flag 게이트). 렌더 WIP가 정리된 지금 진입 가능하나 별도 증분 권장 |
| `6a58b16` thermal export | **측정 후 조건부** — serious 상태 장편 완주율 측정이 선행. 미측정 이식 금지 |
| `74b69a1`·`244de25`·`a9341a3`·`fe7bbc4`·`d78c13c`·`827e10d` iOS PlaybackEngine/AudioMix | **미대체 의미만 재구현 대상** — preview 전용 source policy·thermal observer·ducking/EQ placed-span. 구형 엔진 복원 금지 |
| `831578e` flatten digest | **폐기 확정** — 불완전 digest. 전체 렌더 의미 fingerprint 신설 시에만 재추진 |
| `4418fc5`·`6ac0e97`·`646298e` 문서/정리 | **제외** — 낡은 상태표·브랜치 정리 |

## 검증 상태

- 각 기능: 필터 테스트 통과 후 커밋 (계획 규율 준수).
- 1·2단계 완료 시점 각각 `verify_gate.sh` **GATE_PASS 5/5** (swift build·swift test 전체·Mac 빌드·iOS 빌드·lint).
- 미수행: `run_e2e_export.sh`(렌더 변경분에 대해 — 베지어는 Core 유닛 9종이 수학을 pin, E2E는 3단계 HDR 시점에 함께), 원격 백업/push, 소스 브랜치 삭제.

## 3단계 증분 A (2026-09-02, `6489be5`) — 게이트 5/5

- writer 10-bit 서페이스 요청(HDR 프로파일)·양 컴포지터 Rec.2020 HLG colorSpace 렌더(SDR은 기존 경로 무변경).
- guard 정교화: 지속 delivery 경로만 다운그레이드, 명시적 profileOverride는 마스터링/검증 경로로 통과(UI 진입은 여전히 flag 게이트).
- 계약 테스트: HDR writer 설정 10-bit·Main10·Rec.2020/HLG 태그 pin + SDR 8-bit 유지 pin. 기존 v1 게이트 테스트 2건 새 의미로 갱신.
- **FeatureFlag.hdrMaster는 여전히 OFF** — 다음 증분(하니스 profile env + e2e pix_fmt/bit-depth/primaries/transfer/matrix 프로브)에서 실출력 검증 후에만 플립.
- 소스 브랜치 `feat/capcut-surpass-7gaps`는 사용자 지시로 삭제 완료(원격 백업은 통합 브랜치로 충분하다고 판정).

## 다음 작업

1. 3단계 증분 B: 하니스 `MOVIECUT_UITEST_EXPORT_PROFILE` env → `exportVideoWithExplicitBitrate(profileOverride:)` 배선 + `run_e2e_export.sh` HDR 프로브 → 실출력 10-bit/Rec.2020/HLG 확인 후 flag 플립.
2. 4단계: thermal(serious 상태 장편 완주율 측정 먼저)·iOS preview 전용 source policy·thermal observer·ducking/EQ placed-span.
3. 통합 브랜치 병합 결정(사용자).
