# 안정화 계획 — 2026-08-29 (외부 리뷰 #2 반영)

> **입력**: 사용자 제공 외부 종합 리뷰(2026-08-29) — 판정 "후기 알파·베타 진입 전 안정화 단계".
> Phase 1 `6/7` 표기는 본 계획 완료 시점까지 보류 — 재측정에서 W 워크플로·핵심 파리티·실기기 게이트가 미충족(산식상 확정 가능 최대 4/7)이며, W 게이트 정의 자체가 대표 작업보다 약함.
> **지위**: 본 문서는 안정화 창구의 실행 계획이자 STAB 항목 원장이다. 루프 실행 가능 미완료 항목이 남아 있는 동안 우선순위 분쟁에서 방향 문서 §3보다 우선한다(크론 프롬프트 편입 — LI-004, 사용자 병합 지시가 승인 근거).
> 완료 후 베타 준비·CapCut급 속도·선택 FCP급 품질은 DEVELOPMENT_DIRECTION_20260815.md §3 체인으로 복귀한다.

## 0 원칙

- **측정 증거만** — 완료 판정은 verify_gate 5단계 + 증분 게이트 E2E 실측. 자기 보고 수치 금지(기존 루프 규율 승계).
- **3회 연속 판정** — 외부 재측정 W 4/5(W4 ProRes 90초 timeout)와 내부 재실측 W 5/5(2026-08-28, "watchdog 파이프류·재현 안 됨" 판정)의 분쟁은 단발 실행으로 못 닫는다. 조건부 결함은 통과 N번 뒤 hang할 수 있으므로, STAB-01·STAB-02 완료 후 **동일 커맨드 3회 연속**으로만 판정한다.
- **실행 주체 분류** — 각 항목은 `루프`(자율 회차 실행 가능) / `루프+사용자`(루프는 준비, 잔여는 사용자 조건) / `사용자`(루프 실행 불가 — 보고만)로 표기. 원격 push는 루프 금지(크론 프롬프트 6항).
- **범위** — 기능 추가가 아니라 "실제 작업이 끝까지 빠르고, 같은 결과로, 반복해서 성공한다"는 증거의 확보. 기능 확장(CapCut 속도·FCP 품질 트랙)은 본 계획 범위 외.

## 1 항목 원장 (STAB)

| ID | 우선순위 | 항목 | 주체 | 완료 기준 |
|---|---|---|---|---|
| STAB-01 | P1 | **완료(2026-08-29)** — watchdog 고아 sleep 재수습 — run_w_scenarios.sh 기존 "수습" 주석(L81-86)은 `kill $watchdog` **후에** `pkill -P $watchdog`를 호출: subshell 사망 시 내부 sleep이 PID 1로 재부모화되어 빈 결과. run_longform_soak.sh는 pkill -P조차 없음(최악 2400초 잔류). 정석: sleep PID 직접 기록·trap 회수, 또는 프로세스 그룹 kill | 루프 | 양 스크립트 완주 직후 고아 sleep 잔류 0 실측(pgrep) |
| STAB-02 | P0 | **완료(2026-08-29, 메인 세션 수동 회차)** — Mac ExportEngine A/V 펌프 병렬화: 태스크그룹 동시 pump(iOS RENDER-02 패턴 포팅) + 펌프 실패 시 양 reader/writer 즉시 해체(취소된 리더의 copyNextSampleBuffer→nil로 형제 continuation 재개 — 그룹 대기 교착 방지) + writer `.cancelled`→CancellationError + 활성 세션 추적·cancelExport 확장(제품 경로 취소 배관). 원 설명: video 펌프 완전 종료 후 audio 펌프 시작은 writer 역압 하 영구 정지 가능(W4 ProRes 타임아웃 클래스) | 루프 | **W4 3회 연속(84,957B 동일) + W 전체 5/5 × 3회 연속(15/15) + 고아 0 — W 측정 분쟁 판정: 외부 4/5 재현 안 됨·내부 5/5 확정.** verify_gate 5/5. 잔여: 취소 E2E 단위테스트(라이브 export 테스트 인프라 부재 — 후속 소형 증분) |
| STAB-03 | P1 | **완료(2026-08-29, 메인 세션 수동 회차)** — iOS 제품 결함 4건: ① stepFrame `frameStepTick` 발행 → 뷰 강제 시크(0.25s 임계값 우회) ② 루프/정지를 AVPlayerItemDidPlayToEndTime 알림으로 이관 + observer MainActor 격리 ③ security scope을 Task 내부에서 개폐 ④ fileExporter 성공 후 중복 saveProject 제거. 원 설명: 스텝이 임계값에 흡수·observer 종료 추정·scope 조기 종료·이중 저장 | 루프 | iOS 전체 62테스트/15스위트 PASS(신규 엔드 핸들러·틱 단언) + verify_gate 5/5. **뷰 배선(틱→시크·알림 등록)은 유닛테스트 불가 — 실기기/수동 확인 항목(G-27 연계)으로 잔여** |
| STAB-04 | P0 | **1차 완료(2026-08-29, 메인 세션 수동 회차) — W 측정 양분화**: ① 현행 스크립트 `run_w_smoke.sh`로 개명(헤더에 스모크 지위 명시) ② `W_STRICT=1` 하니스 모드 — w1 세로 영상 임포트(strict 게이트)·STT 미실행 시 명시적 FAIL(TCC 게이트 표출)·실제 덕킹 분석 경로(autoDuckOtherAudio) ③ `make_w_acceptance_fixtures.sh`(60초 실발화 say·세로 720x1280·5분 마스터·120BPM) ④ `run_w_acceptance.sh`(ffprobe 품질 검증 — 세로 기하·길이·코덱·A/V 싱크·시간 예산 + 와치독/앱 파킹 회수 정석). **게이트가 즉시 실결함 3건 포착(백로그 §1.15)**: BUG-ACC-01(P1·ProRes 오디오 길이 합산 2+4→6s)·BUG-ACC-02(P1·실덕킹 분석 파킹)·BUG-ACC-03(P2·비트 수율). 스모크 W 5/5 회귀 무관통·verify_gate 5/5. **2차 진행(2026-08-30)**: BUG-ACC-01·04 수정 + **w2·w4 acceptance 3회 연속 PASS**(w4: prores·300.00s·A/V 0.000·180-216s≤예산. 탐침 공탐은 접두사 누락 rc=1 판명·수정). **잔여**: w1(CA12-01 계열 파킹 해소 + 사용자 STT TCC)·w5(카드뉴스 기능 — §K) — 5/5×3은 이후. 러너 계측 3건 완료(디스크 검사·보존 위생·탐침) | 루프+사용자 | 1차 완료 + 2차 w2·w4 레그 ×3 달성 |
| STAB-05 | P1 | **진행중(2026-08-31 3차 — cross-dissolve 재편입 완료: 구조 검증형 3/3 결정적 통과·행업은 STAB-02로 이미 소멸 확인·디졸브 창은 BUG-ACC-06 등록)** — BUG-ACC-05 해결(갭 직후 검정 스냅숏 — 어웨이-앤-백 재렌더, normal_delete 12회 연속 통과·motion 회귀 소유 판정으로 기각 후 갭 한정 게이트). 잔여: freeze 백투백 플래이크(9.69·12.03 — 빌드 간 수치 변동 관찰)·cross-dissolve 재편입·18/18×3. 원 1차 기록 — 스냅숏 폴백 재시도 적용(부하 플래이크 완화 — 완화 후 전체스위트 1회 ALL PASS·백투백 3연속에서는 freeze t=3.0 MAD 9.69·motion 12.03 지속 = 완화 불충분), **실갑 normal_delete 적용 → BUG-ACC-05(P1·프리뷰 갭 BLACK) 즉시 노출·등록**. 잔여: BUG-ACC-05 루트코즈·freeze 백투백 플래이크 지속 조사·18/18×3. 원 설명 — ① freeze-frame 전체 실행 FAIL(MAD 9.69) vs 단독 PASS(0.99) 순서·리소스 의존 플래이크 원인 규명·결정론화 ② normal_delete 실제 gap 생성 ③ cross-dissolve 통합 경로 재편입(run_core_editing_parity.sh L167-173 스킵 주석 — 헤드리스 buildComposition hang, GPU 컴포지터 가용 호스트 의존. 환경 차단 시 명시적 기록). 완료 전까지 "18/18 완전 파리티" 표기 금지 — 대체 경로 명시 표기 | 루프 | cross-dissolve 포함 18/18 × 3회 연속(또는 환경 차단 근거와 함께 대체 경로 명시) |
| STAB-06 | P1 | **로컬 완료(2026-08-31 — 원격 검증 대기)**: iOS 잡 분할(상태 4스위트 fast·AV 11스위트 2직렬 스텝·개별 타임아웃 — 분할 커버리지 4+11=15 실증·실행시간 실측 0.55s/40.2s/5.0s) + nightly W smoke 추가(파리티 스윕·E2E·퍼즈는 기존 포함) + 낡은 cross-dissolve 스킵 주석 갱신. yaml 파싱·스위트명 매핑 15/15 검증. **원격 실행은 사용자 push 후** — iOS 전체 61테스트가 30분 제한(.github/workflows/ci.yml L85) 내 미완주(1,047.8s에 8PASS 후 중단 선례). 빠른 상태 테스트 / AVFoundation 렌더 테스트(직렬 실행·명시적 simulator UUID·개별 타임아웃) 분리 + nightly에 W smoke·파리티 스윕 추가. yaml 작성·로컬 검증은 루프, **원격 실행 검증은 사용자 push 후** | 루프+사용자 | 원격 CI 현재 코드 전체 녹색(사용자 push 전제) |
| STAB-07 | P2 | **제안 작성 완료·사용자 결정 대기(2026-08-31)** — `DECISIONS_20260822.md` **Q13 상신**: 안 A(온디바이스 MXMetricManager 구독 한정 채택·네트워크/서버 코드 추가 없음·미디어·편집 데이터 전송 없음 — Apple 익명 집계 경유·OS 수준 옵트인 기본 OFF가 §13.10 원칙과 정합) 제안, 안 B(§13.8 요구 폐기), 안 C(베타 후 재검토) 대안. 사실 관계(전송 범위·플랫폼 호환 macOS 12+/Q3 macOS 14) 포함. 원 설명: docs/REQUIREMENTS.md §13.8(관측성 확대)과 App/MovieCutMac/AppLog.swift("MetricKit 의도적 미도입 — 완전 온디바이스") 충돌. 제안만 작성, 결정은 사용자 | 루프 제안·사용자 결정 | DECISIONS 문서에 상신 후 사용자 결정 기록 |
| STAB-08 | P2 | **완료(2026-08-31)** — 이력 레코더(verify_gate·W smoke·파리티 → `.build-check/history/*.json`) + `gen_loop_state_report.py`(최근 3회·`--check-reproducible` 2회 렌더 동일 실측·`docs/LOOP_STATE_REPORT.md` 생성) + Part 9 재감사(M1~M4 정정 확인·MC-07 갱신). 잔여: worst MAD 캡처(레코더 파싱 확장 시 후속 소형) | **LOOP_STATE 자동 생성 + 문서 정합** — 누적 서술식 상태 문서를 게이트 JSON(w.json·파리티·verify_gate 출력) 기반 상태표 생성 스크립트로 전환(외부 리뷰 #9 전반: LOOP_STATE W 5/5 vs 실측 4/5 모순의 구조적 해법) + **경쟁분석 문서의 구현 정합 재감사(리뷰 #9 후반 — iOS 행 낡은 표기 재확인)** | 루프 | 생성 재현성 + 최근 3회 게이트 결과 자동 반영 실측 + 경쟁분석 정합 재감사 기록 |

## 2 사용자 대기 항목 (루프 실행 불가 — 회차 보고만)

- **122 로컬 커밋 push — 완료(2026-08-29)**: 스택 PR 5본으로 분할(히스토리 재작성 없이 기존 커밋 경계에서 분할, 순서 병합): [#19](https://github.com/cool25th/movie_cut/pull/19) Core·오디오·효과+인프라 → [#20](https://github.com/cool25th/movie_cut/pull/20) 감사+결함 수정 → [#21](https://github.com/cool25th/movie_cut/pull/21) 포맷·파리티·iOS 통합 → [#22](https://github.com/cool25th/movie_cut/pull/22) CA 큐·벤치마크 → [#23](https://github.com/cool25th/movie_cut/pull/23) 리뷰 #2 반영·안정화(라이브 브랜치 — 이후 STAB 증분이 이 PR로 흘러듦). **원격 CI 결과는 이 PR들에서 관찰 가능 — STAB-06 원격 검증 창구.** 병합 순서 준수 필요.
- **BUG-ACC-01 완료(2026-08-29, STAB-04 후속 회차)**: 원인은 조정 레이어의 오디오 스트립 편입(빌더 가드 추가) — 스모크 w4 6.000s→4.000s 양 경로 실측·Core 유닛·스모크 W 5/5. **신규 BUG-ACC-04 등록**(5분 마스터 출력 간헐 전면 실패 2/4·오류 무표면·prores 스텝 거짓 OK — acceptance 러너 증거 보존 보강 완료, app.log로 다음 판정) — STAB-04 2차 관련.
- **soak 2run — 완료(2026-08-29, STAB-01 세션에서 달성)**: 기기가 조용해진 시점에 재수습된 watchdog 하 2런 완주 — run1 wall 803.2s/RSS 1,476MB·run2 700.5s/1,080MB·RSS 성장 0.0%·결정성 9/9·A/V Δ0.0·**GATE PASS** + 고아 sleep 잔류 0(내장 단언 7회·외부 pgrep 교차 0건).
- **G-27 실기기 잔여 2종** — 기기 연결·잠금 해제 후 `TEAM_ID=98ZKV9N9T4 bash scripts/run_g27_device_e2e.sh`.
- **MACUI-01·U-08** — TCC/AX 환경 복구(접근성 권한 또는 재부팅).
- **STAB-07 MetricKit 결정** — 제안 접수 후.

## 3 Phase 순서와 종료 기준

세션당 1 증분 원칙(기존 루프 규율)으로 순차 소진. 소형 2개까지 병행 허용.

- **Phase 0 — 검증 인프라**: STAB-01 → STAB-06(yaml 작성; 원격 검증은 사용자 병행).
  종료: 고아 프로세스 0 실측 + CI 구성 완료(원격 녹색은 사용자 push 후 추적).
- **Phase 1 — 제품 결함**: STAB-02 → STAB-03.
  종료: 각 항목 단위·통합 테스트 PASS + STAB-02 완료 시점부터 W4 ProRes 3회 연속.
- **Phase 2 — 측정 재설계**: STAB-04 → STAB-05 → STAB-08 → STAB-07 제안.
  종료: **실제 W acceptance 5/5 × 3회 연속 + 파리티 18/18(통합 포함) × 3회 연속**. 이 시점에 Phase 1 게이트 재산정(§4 게이트 대조).
- **Phase 3+ — 베타 준비 이후** (리뷰 권장 2~4단계 전항 원장화 — STAB 창구 종료 후 이 체크리스트가 복귀 큐):
  - **3-A 베타 준비(리뷰 2단계)**: 실기기 3/3(G-27 — 현재 1/3·사용자) · 30~60분 프로젝트 soak 2회 연속(✅ 2026-08-29 달성) · 백그라운드/디스크 부족/취소/재열기/외장 미디어 검증 매트릭스 · signed archive 실증 · 검토 가능한 PR 단위 push 상시 유지(✅ 체계화 — 스택 PR) · 10~30명 베타 중대 데이터 손실 0건.
  - **3-B CapCut급 제작 속도(리뷰 3단계)**: W1/W2 사용자 완주 시간·클릭 수 측정 · 첫 출력 ≤10분·반복 작업 CapCut 대비 1.2배 이내 · 한국어·영어 자막 WER/CER·워드 타밍 실측(STT TCC 전제) · iOS 정밀 타임라인·템플릿 검색·Auto Style·**카드뉴스 완성(백로그 §K — G-20 브랜드 킷·G-21 페이지 일괄 출력·G-22 대본 분배·U-10 진입점 — W5 acceptance 경로의 전제)**.
  - **3-C 선택 FCP급 품질(리뷰 4단계)**: ProRes/H.264/HEVC 색·시간·오디오 메타데이터 일관성(BUG-ACC-01 계열 포함) · G-29 10비트 HLG·SDR/HDR 혼합 색관리 · 프록시·재연결·캐시·장편 신뢰성 · 실제 CapCut/FCP 출력 블라인드 A/B 비열등 검증(하니스는 CA-12 — CODEX-10/11 수정 전제).
  - **3-D 복귀 큐**: 경계 분해 잔여(F-17 TTS·F-13 자막·F-19 리프레임 — internal 승격 리팩터 승인 대상) · G-29 · BUG-CA12-01 에스컬레이션 · 비목표 유지(멀티캠·Auditions·FCPXML 전체 호환·서드파티 플러그인·클라우드 동기화).

## 4 기존 기록과의 관계 (중복·충돌 방지)

- **STAB-02**는 2026-08-26 RENDER-02 세션이 iOS에서 확립한 태스크그룹 병렬 pump의 Mac 포팅. 2026-08-19 세션 34의 ProRes 수습(graph AAC 직접 리드)은 유지 — STAB-02는 그 경로의 구조적 방어.
- **BUG-CA12-01**(메인 디스패치 전달 정지)은 별개 클래스 — STAB-02 검증 중 재관찰 시 기존 에스컬레이션 항목에 추가 기록만.
- **PARITY-TOL-01**은 이미 종결(2026-08-28) — STAB-05의 플래이크 제거는 별개 문제.
- **경계 분리(EditorViewModel 부채)**: STAB 창구 동안은 STAB 우선. 내부 승격 리팩터 승인 대상은 그대로 유지.
- **W 측정 분쟁**: STAB-01(watchdog)·STAB-02(펌프) 완료 전까지 W 결과 보고 시 측정 환경(완주/와치독 개입 여부)을 함께 기록.
- soak·실기기 등 사용자 대기 항목은 STAB과 **병렬 진행 가능** — STAB 완료 보고 시 함께 리마인드.

## 5 완료 후 판정 규칙

Phase 2 종료 시점에 EXECUTION_PLAN §4 1단계 게이트를 재실측 대조하고, Phase 1 판정(x/7)을 핸드오프에 재기록한다. 재측정 근거 없이 기존 수치 재인용 금지.
