# MovieCut 안정성 fuzz 베이스라인

> 측정일: 2026-08-02 / 재현: `SEED=1722484800 bash scripts/run_fuzz_stability.sh` / 빌드: **Debug + sandbox OFF**
> 목적: 랜덤 + 적대적 harness 입력 조합에서 **크래시 0건**과 **정확한 에러 보고**를 자동 검증한다. 기존 harness 스크립트들은 모두 `wait "$pid" 2>/dev/null || true`로 **프로세스 exit code를 무시**해 segfault를 잡지 못했는데, 이 게이트는 exit code를 직접 검사해 그 구멍을 채운다.

## 측정 방법

`scripts/run_fuzz_stability.sh`가 55개 시나리오를 generic export harness(`MOVIECUT_UITEST=1`, `UITEST_DONE` 경로)로 구동한다. 고정 시드(`SEED=1722484800`)로 재현 가능하다.

**3축 검증** (기존 스크립트는 축 1을 검사하지 않았다):
1. **exit code == 0** — segfault(139)/abort(134)/SIGKILL timeout(137) 직접 감지. `wait "$pid"` 후 `$?` 검사, `|| true` 제거.
2. **`error=none` AND `composition_error=none`** — 실패가 `error=` 필드로 보고됐는지. 크래시 없이 throw/catch로 전파되는 게 정상.
3. **`clips=<N>`이 예상과 일치** — "조용히 무시되는" 입력(빈 import, 클립 없는 효과, 잘못된 transition, 비숫자 파라미터)이 의도된 클램프/폴백으로 처리됐는지 확인.

**입력 풀**(경계값 + 시드 랜덤):
- speed: `-2, 0, 0.25, 0.5, 1, 2, 4, 100, abc, (empty)` — 음수/0/100x는 harness가 0.25~4.0으로 클램프(`SetClipSpeedCommand.swift:63`), 비숫자는 스킵.
- split/trim 위치: `0.5, 1.0, 1.5, -1, 999, (empty)` — 범위 밖/음수는 VM 게이트가 `lastErrorMessage`로 보고하거나 harness가 클램프.
- transition rawValue: `crossDissolve, wipeLeft, notARealKind, (empty)` — 잘못된 값은 `?? .crossDissolve` 폴백(`UITestHarness.swift:2364`).
- 동시 효과: color/grade/hsl_curves/mask/text 중 0~2개 무작위.

## 결과 (55 시나리오)

```
total=55  pass=53  crash=0  error=2  unexpected_clips=0
```

### 경계값 시나리오 (12개)

| 시나리오 | 입력 | 결과 | 비고 |
|---|---|---|---|
| 빈 IMPORT | `MOVIECUT_UITEST_IMPORT=""` | **ERROR_REPORTED** `error=The file couldn't be opened.` clips=0 | 빈 타임라인 export 시도 → AVFoundation 에러 보고. 크래시 없이 `error=`로 전파 = 정상 |
| 존재하지 않는 파일 | `IMPORT="/nope/missing.mp4"` | **ERROR_REPORTED** `error=작업을 완료할 수 없음` clips=1 | import 단계에서 AVFoundation probe 실패 → throw → `setDropError` → `lastErrorMessage`. 한국어는 시스템 로케일 `localizedDescription` |
| 효과 단독(CLIP 있음) | `COLOR=1` | PASS clips=1 | import가 첫 클립을 선택하므로 효과 정상 적용 |
| 잘못된 TRANSITION | `TRANSITION=notATransition` | PASS clips=1 | `?? .crossDissolve` 폴백 — 조용히 대체, 크래시 없음 |
| 음수 speed | `SPEED_RATE=-2` | PASS clips=1 | 0.25로 클램프 |
| 0 speed | `SPEED_RATE=0` | PASS clips=1 | 0.25로 클램프 |
| 100x speed | `SPEED_RATE=100` | PASS clips=1 | 4.0으로 클램프 |
| 비숫자 speed | `SPEED_RATE=abc` | PASS clips=1 | `Double()` 파싱 실패 → 스킵, 기본 속도 유지 |
| 5개 효과 동시 | COLOR+GRADE+HSL+MASK+TEXT_AT=0.5 | PASS clips=1 | 전부 한 클립에 적용, 크래시 없음 |
| 범위 밖 split | `SPLIT_AT=999` | PASS clips=1 | VM 게이트가 `lastErrorMessage` 보고 후 스킵 |
| 음수 split | `SPLIT_AT=-5` | PASS clips=1 | 동일 |
| 음수 trim | `TRIM_AT=-1` | PASS clips=1 | harness가 0으로 클램프 후 처리 |

### 랜덤 시나리오 (43개, 시드 1722484800)

전부 **PASS clips=1**. 대표 극단 조합 예:
- `random_18`: speed=100, split=-1, transition=notARealKind → PASS
- `random_20`: speed=-2, split=1.5, transition=crossDissolve → PASS
- `random_30`: speed=0, split=-1, transition=notARealKind → PASS
- `random_42`: split=999(범위 밖), transition=notARealKind → PASS

43개 전체 결과는 `bash scripts/run_fuzz_stability.sh`로 재현 가능(동일 시드).

## 해석

**크래시 0건 확정.** 55개 시나리오(음수/0/100x speed, 잘못된 transition rawValue, 범위 밖/음수 split·trim, 5개 효과 동시 적용, 비숫자 파라미터, 빈/잘못된 파일 경로) 전부에서 exit code 0. 기존 스크립트들이 `|| true`로 가렸던 segfault 가능성을 이 게이트가 exit code 직접 검사로 배제했다.

**2건의 error 보고는 정상 동작이다.** 빈 IMPORT와 존재하지 않는 파일은 harness가 실패를 `error=` 필드로 정확히 보고했다 — 크래시 없이 throw → catch → `lastErrorMessage` → status 라인으로 전파되는, 의도된 실패 보고 경로다. 이것이 fuzz 게이트가 확인하려던 "실패를 숨기지 않고 보고한다"는 계약이다.

**"조용히 무시되는" 입력 6종의 동작이 검증됐다** (harness 감사가 식별한 항목):
- speed 음수/0/100x → 0.25~4.0 클램프, error=none. ✓
- 비숫자 speed/split → 스킵, error=none, clips 유지. ✓
- 잘못된 transition → crossDissolve 폴백, error=none. ✓
- 범위 밖/음수 split → VM 게이트가 error 보고 또는 스킵. ✓

이들은 버그가 아니라 의도된 입력 정규화이며, fuzz 게이트는 그 정규화가 크래시 없이 일어남을 확인했다.

## 한계

1. **generic export 경로만 검증.** parity harness(`MOVIECUT_UITEST_PARITY=1`)의 `applyParityScenarioEdits` 게이트들은 별도. parity 경로는 `run_parity_sweep.sh`이 13개 시나리오로 이미 커버한다.
2. **Debug + sandbox OFF.** sandbox ON에서의 크래시 가능성은 별도 측정 대상이나, sandbox는 보안 경계지 크래시 결정 인자가 아니다(`perf_4k_sandbox.sh`가 이미 렌더링 결과 동일함을 보임).
3. **43개 랜덤 시나리오는 한 시드.** 다른 시드(`SEED=<n>`)로 더 넓은 조합을 돌릴 수 있으나, 경계값 12개가 조사가 식별한 전부의 "조용히 무시" 입력을 커버하므로 랜덤은 보강 역할이다.
4. **B-U7(크래시 후 복구 제안)은 이 게이트 범위 밖.** 복구 NSAlert에 accessibility 식별자가 없고 `MOVIECUT_UITEST=1` 게이트가 alert를 스킵해 자동 검증이 현재 불가하다 — 별도 작업(UI 식별자 + 게이트 우회 + XCUITest)으로 진행 중.
5. **단일 클립 fixture.** 다중 클립 타임라인에서의 극단 배치(겹치는 클립, 0-duration 클립)는 다음 fuzz 확장에서 다룬다.

## 2026-08-14 nightly 러너 재확인 — REVIEW 2건의 정체

CI 러너에서 nightly가 처음 완주한 시점에 동일한 2건(`boundary_01_empty_import`,
`boundary_02_missing_file`)이 `status=ERROR_REPORTED`로 다시 관측됐다. 위 본문의
결론 그대로다: 빈 IMPORT 목록과 존재하지 않는 경로(`/nope/missing.mp4`)는
harness가 `error=` 필드로 **정확히 보고하는 의도된 실패 경로**이며, fuzz 게이트의
REVIEW 분류는 "정상 에러 보고"로 해석된다. 재현 시드: `SEED=1722484800`.
크래시 0건 · 클립 카운트 예상치 일치(빈 import=0, 단일 import=1). 이후 nightly에서
이 2건이 ERROR_REPORTED로 나오면 정상, crash/exit≠0이 나오면 즉시 회귀다.
