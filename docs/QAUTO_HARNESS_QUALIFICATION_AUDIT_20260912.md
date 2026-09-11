# QAUTO-01 1차 — 측정 하니스 자격 감사 (2026-09-12)

- 원장: CAPCUT_FEATURE_BACKLOG.md §0.5.1 QAUTO-01(2026-09-12 승인 — ChatGPT 외부 리뷰 1회차 BACKLOG 반영)
- 방법: **정적 감사**(스크립트 실행 없음 — 8하니스 × 8축, file:line 증거) + 최위험 결함 3건 보강 + 보강 검증 실측.
- 8축 정의: 양성 컨트롤 / 음성 컨트롤 / degeneracy 검사 / dataset 핀 / harness 핀 / threshold 핀 / clean re-run / evidence 바인딩.
- 판정 체계: PASS(축 충족) · PARTIAL(부분) · MISSING(부재). "빠른 성공 불신" 원칙대로 주요 주장은 본 세션이 원문 재확인했다(§검증 기록).

## 요약 (8축 × 8하니스)

| 하니스 | 양성 | 음성 | degen. | dataset핀 | harness핀 | thresh핀 | rerun | evidence |
|---|---|---|---|---|---|---|---|---|
| run_ca12_ab_benchmark | PARTIAL | MISSING | PARTIAL | **PASS** | **PASS** | **PASS** | **PASS** | **PASS** |
| run_ca18_diarization | PARTIAL | MISSING | PARTIAL→**보강** | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_ca21_scene_detection | **PASS** | PARTIAL | **PASS** | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_ca22_proxy_gate | PARTIAL | **PASS** | **PASS** | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_ca04_format_matrix | PARTIAL | MISSING | PARTIAL→**보강** | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_beta_scenarios | MISSING | MISSING | PARTIAL | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_parity_sweep | PARTIAL | MISSING | **PASS** | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |
| run_ca01_offline_gate | **PASS** | **PASS** | PARTIAL | PARTIAL | MISSING | **PASS** | **PASS** | MISSING |

공통 강점: **threshold 핀·clean re-run은 8/8 충족**(임계값 하드코딩+사전등록·mktemp 격리+trap 정리 — env 우회 우려 없음). 공통 약점: **evidence 바인딩 0/8(CA-12 제외)·harness 핀 1/8** — 판정이 터미널 stdout에만 존재하고 재감사 불가.

## 하니스별 상세 (근거: file:line)

### run_ca12_ab_benchmark.sh (+ ab_benchmark_metrics.py · make_ab_fixtures.sh)
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PARTIAL | `ab_benchmark_metrics.py:565` `cmd_self_test` known-answer 15종 존재 — 그러나 드라이버가 호출 안 함(→ **보강 ②**) |
| 음성 | MISSING | 실패 경로는 export 부재뿐(`run_ca12:212`) — 고의 손상 expect-fail leg 부재 |
| degen. | PARTIAL | 0바이트 export는 FAIL(`:212-215`) — all-black/constant 콘텐츠는 측정만 되고 게이트 안 됨(`ab_benchmark_metrics.py:362-364`) |
| dataset핀 | PASS | `make_ab_fixtures.sh:36-40` SHA-256 핀·`:166-169` PIN MISMATCH 거부·`:124-134` manifest |
| harness핀 | PASS | `run_ca12:107,114` app_commit 기록·`:109-113` machine/OS·`:35` 타임스탬프 run dir |
| thresh핀 | PASS | 판정 threshold 없음(기록기) — env 변수(REPS/WATCHDOG)는 실행 손돌이일 뿐 |
| rerun | PASS | `:161-162` rep당 산출물 삭제·`:167` pkill·`:255` fixture 재생성+재핀 |
| evidence | PASS | `:377-381` baseline.json + `:107-135` conditions.json(app_commit·전원·발열 포함) |

### run_ca18_diarization.sh (+ DiarizationMeasurementTests.swift)
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PARTIAL | 지상진리 manifest(`run_ca18:37-52,67-73`)는 known-answer 입력 — 그러나 혼동율 산식 자체 자기검사 부재 |
| 음성 | MISSING | `perturb` 축은 강건성 변형이지 expect-fail 아님 — 파이프라인 고의 손상 시 FAIL 입증 부재 |
| degen. | **MISSING→보강 ①** | **0검출 시 `confusion()`이 빈 배열 순회로 혼동율 0 → 거짓 PASS**(`DiarizationMeasurementTests.swift:260` 루프·`twoMeans:172` 1개 미만 즉시 반환 — 본 세션 원문 확인). 병합 결함(p95)은 수리돼 있으나(`:100-103`) 0검출은 무방비 |
| dataset핀 | PARTIAL | manifest 유효성 검사는 있음(`:73`) — 그러나 `say` TTS 런타임 생성(`:42`)이라 macOS 버전별 목소리 변동, SHA 핀 없음 |
| harness핀 | MISSING | 전 증거가 trap 삭제되는 mktemp(`:24-25`)·git sha/일시 미기록 |
| thresh핀 | PASS | 혼동 ≤10%·RTF ≤0.5 하드코딩+사전등록(`Tests:282-287`, 헤더 `:17-21`) — env 우회 없음 |
| rerun | PASS | fresh mktemp·deterministic 12발화 스케줄·manifest 검증 게이트 |
| evidence | MISSING | 성공 시 증거 전량 폐기·판정은 stdout만(`:89-92`) |
| 검증 기록 | — | EOF 수리·p95 임계·manifest 존재 본 세션 재확인(`Tests:61-68,100-103`) |

### run_ca21_scene_detection.sh (+ SceneChange*Tests.swift)
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PASS | 상시 known-answer: 히스토그램 합≈1·하드컷 임계 통과·동일 프레임≈0(`SceneChangeHistogramMathTests.swift:23,35,37-38`) |
| 음성 | PARTIAL | all-zeros 결함 시그니처 고정(`:23` "2026-09-04 defect signature")·T3 무컷 expect-zero(`MeasurementTests:120-121`) — 드라이버 수준 fault injection 부재 |
| degen. | PASS | 합≈1이 전부-0 추출 차단·무컷 0검출 요구·0검출 recall 0으로 FAIL(`:130,134`)·드라이버 `[ -s ]`+가짜그린 가드(`run_ca21:57-59,79-82`) |
| dataset핀 | PARTIAL | lavfi 결정론 생성+expected_cuts manifest(`:61-68`) — SHA 핀 없음 |
| harness핀 | MISSING | mktemp trap 삭제(`:26-27`)·sha/일시 미기록 |
| thresh핀 | PASS | recall/precision ≥0.80·RTF ≤1.0 하드코딩+사전등록(`:134-136`, 헤더 `:12-21`) |
| rerun | PASS | fresh mktemp·concat 재인코딩 정석(`:40-43`)·fixture `[ -s ]` |
| evidence | MISSING | measure.log가 /tmp 휘발(`:73`)·artifacts 기록 없음 |

### run_ca22_proxy_gate.sh
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PARTIAL | leg B가 성공 관측 가능성 입증(`:100-103`) — check()/field() 헬퍼 자체 자기검사 부재 |
| 음성 | PASS | leg A(미스케줄 `eq 0`)·leg C(취소 유지 `eq 0/eq 1`) — 항상생성 회귀를 잡음(`:96-97,108-109`) |
| degen. | PASS | 빈 필드 읽기가 FAIL로 귀결(`:75,83-84` `-n` 요구) |
| dataset핀 | PARTIAL | fixture 존재 확인만(`:28-29`) — lavfi 결정론(`:33-35`) |
| harness핀 | MISSING | stdout 전용(`:117-122`)·WORK trap 삭제 |
| thresh핀 | PASS | eq/ge 상수 하드코딩(`:96-115`)·watchdog 360s(`:64`) |
| rerun | PASS | fresh mktemp·leg당 정리(`:53-54`)·trap kill |
| evidence | MISSING | 파일 출력 전무(`:117-121`) |

### run_ca04_format_matrix.sh
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PARTIAL | golden known-answer 내장(회전 영역 red/blue `:145-158`·luma ±6 `:123-124`) — 측정 헬퍼(awk 비교기 `:87`) 자체 검사 부재 |
| 음성 | MISSING | expect-fail leg 부재(`registered()` allowlist는 현재 빈 목록 `:43-47`) |
| degen. | **PARTIAL→보강 ③** | CFR 검사 `[ "$r" = "$a" ]`가 **양쪽 probe 실패(빈 문자열) 시 공허 통과**(`:105` — 본 세션 원문 확인. `json()`의 `\|\| true` 주석 `:92-95`가 빈 판독을 보장). 같은 시나리오의 nb_frames awk 검사가 빈 값을 잡아 시나리오 전체는 FAIL됨 — 그러나 CFR 축 자체는 공허 |
| dataset핀 | PARTIAL | fixture 존재 확인(`:17-21`) — SHA/manifest 없음 |
| harness핀 | MISSING | stdout 전용·WORK trap 삭제(`:32-33`) |
| thresh핀 | PASS | duration ±0.12·frames 130–170·luma ±6·A/V 50ms 전부 하드코딩 |
| rerun | PASS | fresh mktemp+trap(`:32-34`) |
| evidence | MISSING | stdout 전용(`:190-195`) |

### run_beta_scenarios.sh
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | MISSING | PASS가 산출물 존재 판정만(`:66-72`) — known-answer 없음 |
| 음성 | MISSING | expect-fail 전무 |
| degen. | PARTIAL | 빈 산출물 FAIL(`:48-49`) — 그러나 비어있지 않은 무효 export는 통과(dur/dim이 '?' 폴백 미단언 `:70-71`) |
| dataset핀 | PARTIAL | fixture 존재 확인(`:27-28`) — SHA 없음 |
| harness핀 | MISSING | stdout 표 전용·`.secs` 휘발(`:41,73`) |
| thresh핀 | PASS | 판정 기준(존재+복구 계약 필드) 하드코딩(`:103-108`) |
| rerun | PASS | 스텝당 정리(`:59-60`)·fresh mktemp |
| evidence | MISSING | stdout 전용 |

### run_parity_sweep.sh
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PARTIAL | `passthrough` 시나리오가 known-good 앵커(`:133`) — 판정은 비교기 문자열 매칭(`:111`)이고 비교기 자기검사 부재 |
| 음성 | MISSING | expect-fail 시나리오 없음 |
| degen. | PASS | `parity_done` 아님 FAIL(`:94`)·dumped<1 FAIL(`:95`)·빈 export FAIL(`:100-102`) |
| dataset핀 | PARTIAL | fixture 존재 확인(`:26-27`) — SHA 없음 |
| harness핀 | MISSING | key=value stdout 전용(`:14,96,112`) |
| thresh핀 | PASS | TOLERANCE=2.0 상수(PARITY-TOL-01(a) `:24-25,33`) |
| rerun | PASS | 시나리오당 정리(`:65-67`)·240s watchdog·집계 전파(`:149-155`) |
| evidence | MISSING | 산출 파일·타임스탬프·env 기록 없음 |

### run_ca01_offline_gate.sh
| 축 | 판정 | 근거 |
|---|---|---|
| 양성 | PASS | 프로파일 유효성 probe: 차단 프로파일 하 루프백 `nc`가 **실패해야** 통과(`:47-51` "a broken profile would make the leg vacuously pass")·SAMPLES≥10(`:191-192`) |
| 음성 | PASS | 접속 시도가 의도적으로 있고 반드시 거부됨(`:47-49`)·위반/소켓 0 단언(`:102-103,189-190`) |
| degen. | PARTIAL | `[ -s ]`·duration 2.0±0.15·SAMPLES≥10 — 그러나 위반 grep 경로가 `log show` 무음 실패 시 0을 읽을 수 있음(`:99-100` `|| true`) |
| dataset핀 | PARTIAL | fixture 존재 확인(`:29-30,110-111`) — SHA 없음 |
| harness핀 | MISSING | stdout 전용·LOG_SINCE 휘발(`:67`)·WORK trap 삭제 |
| thresh핀 | PASS | duration·위반==0·소켓==0·samples≥10 전부 하드코딩 |
| rerun | PASS | simctl 재설치·결과 삭제·빌드 재시도(`:122-133,153,159`) |
| evidence | MISSING | 최종 판정 stdout(`:195-196`) |

## 본 세션 검증 기록 (감사 주장 재확인 — 빠른 성공 불신)

1. **CA-18 0검출 거짓 PASS — 원문 확인 후 보강**: `DiarizationMeasurementTests.swift:260`의 `confusion()`은 `detected` 순회라 빈 배열에서 0 반환, `twoMeans`는 1개 미만에서 `([0], false)` 즉시 반환(`:172`) → 0검출=혼동율 0=거짓 PASS. **보강**: `detected.isEmpty` → 명시적 FAIL(강제 실패 — 측정 무효를 좋은 점수로 채점하지 않음).
2. **CA-12 self-test 미호출 — 확인 후 보강하며 호출형 교정**: `cmd_self_test` 존재(`ab_benchmark_metrics.py:565`), 드라이버 호출부 없음 확인. 감사 보고의 `--self-test` 표기는 부정확 — **실제로는 위치 인자 서브커맨드 `self-test`**(argparse `add_subparsers(required=True)`). 플래그로 호출 시 rc=2로 즉시 적발(단독 실행으로 확인). 교정 후 단독 실행: **15 known-answer 전부 PASS**(`self-test: PASS (0 failure(s))`).
3. **CA-04 공허 동일 — 확인 후 보강**: `:105` `[ "$r" = "$a" ]`는 양쪽 빈 판독에서 참. 보강: `[ -n "$r" ] && [ "$r" = "$a" ]`. 표현식 단위 확인: 빈 probe → bad 발화·실매치 → 통과.
4. **CA-18 드라이버 재측정(보강 검증)**: 아래 §실측 기록.

## 보강 실측 기록

- **CA-12 self-test(단독)**: `python3 scripts/ab_benchmark_metrics.py self-test` → `self-test: PASS (0 failure(s))` — psnr/ssim/delta_e/mad/banding/chroma/blind 시드 결정론 15종 known-answer 통과. 드라이버는 이제 측정 전 상시 실행.
- **CA-04 가드 표현식**: 빈 probe → bad 발화 확인·실매치 통과 확인(셸 단위). 게이트 전행 재실행은 다음 CA-04 회차(§잔여).
- **CA-18 전행 재측정**: `bash scripts/run_ca18_diarization.sh` → **CA18 DIARIZATION MEASUREMENT FAIL(명시적 실패 유지)** — 세그먼트 12/12 검출·혼동율 synth 40.1%·perturb 31.9%(2026-09-05 실측과 완전 동일 — 재현 확인), degeneracy 가드는 정상 경로에 영향 없음. 보강 후에도 게이트 차단 유지 — **UI 착수 승인 없음 불변**. 스크래치 0 잔존(trap 정리 확인).

## Top gaps(감사 도출·보강 반영 후 잔여)

1. ~~CA-18 0검출 거짓 PASS~~ → **보강 ① 완료**(전행 재측정으로 정상 경로 무손상 확인).
2. **CA-18·CA-21 harness/evidence 핀 부재**: 증거가 trap 삭제되는 /tmp에만 존재 — 사전등록 규율이 사후 감사 불가. → QAUTO-01 잔여(artifacts 기록+app/harness sha 바인딩).
3. ~~CA-12 self-test 미호출~~ → **보강 ② 완료**(서브커맨드형 교정 포함).
4. **evidence 바인딩 0/8(CA-12 제외)**: 판정이 터미널에만 존재 — 빌드/기기/일시와 무결. → QAUTO-01 잔여(공통 recorder 패턴 `.build-check/history/` 연계 검토).
5. ~~CA-04 공허 동일~~ → **보강 ③ 완료**(전행 재실행 잔여).
6. **dataset 핀 부재(CA-12 제외 7종)**: 존재 확인 또는 런타임 생성만으로 임계 판정이 입력 바이트에 무결. CA-18 TTS는 macOS 버전별 목소리 변동 위험. → QAUTO-01 잔여.
7. **음성 컨트롤 4종 MISSING(CA-12·04·beta·parity)**: 고의 손상 시 FAIL 입증 leg 부재. → QAUTO-01 잔여(하니스별 1leg 추가).

## QAUTO-01 잔여(다음 증분 후보)

- evidence/harness 핀 공통화(CA-18·21 우선 — 판정 JSON을 `.build-check/history/`에 기록하는 recorder 패턴)
- dataset SHA 핀 확장(make_fixtures 계열에 make_ab_fixtures의 핀·거부 패턴 이식)
- 음성 컨트롤 leg 4종(CA-12·04·beta·parity)
- beta 시나리오 dur/dim 단언화('?' 폴백 제거)
- 감사 범위 확장: run_e2e_export·run_e2e_cancel·run_diskfull_gate·run_g25_nulltest·run_motion_tracking_gate·run_longform_soak 등 threshold 보유 나머지 하니스

## 부수 비고

- 이 감사로 제품 소스는 1줄도 변경하지 않음(연구 측정 하니스+게이트 스크립트만). verify_gate 대상 아님 — 해당 스위트 단독 재측정으로 검증.
- 측정 실행 1회(CA-18)의 스크래치는 드라이버 trap이 정리 — 잔존 확인 섹션 참조.
