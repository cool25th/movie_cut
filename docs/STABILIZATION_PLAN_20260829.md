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
| STAB-02 | P0 | **Mac ExportEngine A/V 펌프 병렬화** — App/MovieCutMac/Export/ExportEngine.swift L1561-1578: video 펌프 완전 종료 후 audio 펌프 시작. writer 역압이 audio 진행을 요구하면 video가 영구 정지(W4 ProRes 타임아웃 클래스). **iOS RENDER-02(2026-08-26)의 태스크그룹 병렬 pump가 참조 구현** — 포팅 + 한쪽 실패 시 reader/writer 전체 취소·부분 파일 정리 + 제품 경로 취소·시간제한 | 루프 | W4 ProRes·명시적 비트레이트 경로 3회 연속 + 취소 단위테스트 + 부분파일 정리 실측 |
| STAB-03 | P1 | **iOS 제품 결함 4건** — ① stepFrame(±1/fps≈0.033s)이 0.25s seek 임계값(PreviewView.swift L230)에 흡수 — 명시적 스텝은 임계값 우회 ② 루프/정지를 AVPlayerItemDidPlayToEndTime 알림으로(periodic observer 추정 폐지, L174-193) + observer 클로저 MainActor 격리 명시 ③ security-scoped 접근을 Task 내부에서 열고 닫기(iOSContentView.swift L361-365 — 현재 defer가 Task 예약 직후 종료) ④ fileExporter 성공 후 중복 saveProject 제거 | 루프 | iOS 테스트 + 스텝/루프는 AVPlayer 실제 프레임·시간 실측(VM 숫자만의 확인 금지) |
| STAB-04 | P0 | **W 측정 양분화** — 현행 run_w_scenarios.sh는 2~4초 합성 픽스처·자동 덕킹 하드코딩 범위·STT 무실행 성공. ① 현행을 `run_w_smoke.sh`로 개명(빠른 회귀용) ② `run_w_acceptance.sh` 신설: W1 60초 세로 토킹헤드(STT 실측 — 헤드리스 TCC 강제 크래시 선례 2026-08-19 세션 32: 사용자 TCC 사전 승인 또는 앱 UI 경유 필요)·W4 5분 멀티트랙 마스터(그레이딩+오디오 믹스+ProRes)·W5 카드뉴스 문서 편집기 경로·덕킹 실제 감지 경로·작업시간 예산·출력 품질(길이·fps·코덱·메타데이터) 검증 | 루프+사용자 | acceptance 5/5 × 3회 연속(실제 길이·UI 경로·결과 품질 포함) |
| STAB-05 | P1 | **파리티 통합 완결성** — ① freeze-frame 전체 실행 FAIL(MAD 9.69) vs 단독 PASS(0.99) 순서·리소스 의존 플래이크 원인 규명·결정론화 ② normal_delete 실제 gap 생성 ③ cross-dissolve 통합 경로 재편입(run_core_editing_parity.sh L167-173 스킵 주석 — 헤드리스 buildComposition hang, GPU 컴포지터 가용 호스트 의존. 환경 차단 시 명시적 기록). 완료 전까지 "18/18 완전 파리티" 표기 금지 — 대체 경로 명시 표기 | 루프 | cross-dissolve 포함 18/18 × 3회 연속(또는 환경 차단 근거와 함께 대체 경로 명시) |
| STAB-06 | P1 | **CI 분할** — iOS 전체 61테스트가 30분 제한(.github/workflows/ci.yml L85) 내 미완주(1,047.8s에 8PASS 후 중단 선례). 빠른 상태 테스트 / AVFoundation 렌더 테스트(직렬 실행·명시적 simulator UUID·개별 타임아웃) 분리 + nightly에 W smoke·파리티 스윕 추가. yaml 작성·로컬 검증은 루프, **원격 실행 검증은 사용자 push 후** | 루프+사용자 | 원격 CI 현재 코드 전체 녹색(사용자 push 전제) |
| STAB-07 | P2 | **MetricKit 방침 제안** — docs/REQUIREMENTS.md §13.8(관측성 확대)과 App/MovieCutMac/AppLog.swift("MetricKit 의도적 미도입 — 완전 온디바이스") 충돌. 제안만 작성(온디바이스 MXMetricManager 한정 채택 vs 요구 폐기), 결정은 사용자 | 루프 제안·사용자 결정 | DECISIONS 문서에 상신 후 사용자 결정 기록 |
| STAB-08 | P2 | **LOOP_STATE 자동 생성** — 누적 서술식 상태 문서를 게이트 JSON(w.json·파리티·verify_gate 출력) 기반 상태표 생성 스크립트로 전환(외부 리뷰 #9: LOOP_STATE W 5/5 vs 실측 4/5 모순의 구조적 해법) | 루프 | 생성 재현성 + 최근 3회 게이트 결과 자동 반영 실측 |

## 2 사용자 대기 항목 (루프 실행 불가 — 회차 보고만)

- **122 로컬 커밋 push — 완료(2026-08-29)**: 스택 PR 5본으로 분할(히스토리 재작성 없이 기존 커밋 경계에서 분할, 순서 병합): [#19](https://github.com/cool25th/movie_cut/pull/19) Core·오디오·효과+인프라 → [#20](https://github.com/cool25th/movie_cut/pull/20) 감사+결함 수정 → [#21](https://github.com/cool25th/movie_cut/pull/21) 포맷·파리티·iOS 통합 → [#22](https://github.com/cool25th/movie_cut/pull/22) CA 큐·벤치마크 → [#23](https://github.com/cool25th/movie_cut/pull/23) 리뷰 #2 반영·안정화(라이브 브랜치 — 이후 STAB 증분이 이 PR로 흘러듦). **원격 CI 결과는 이 PR들에서 관찰 가능 — STAB-06 원격 검증 창구.** 병합 순서 준수 필요.
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
- **Phase 3+ — 베타 준비 이후**: DEVELOPMENT_DIRECTION §3 체인 복귀(실기기 3/3·soak·백그라운드/디스크 부족/취소/재열기/외장 미디어·signed archive·베타 데이터손실 0건 → CapCut급 속도·선택 FCP급 품질).

## 4 기존 기록과의 관계 (중복·충돌 방지)

- **STAB-02**는 2026-08-26 RENDER-02 세션이 iOS에서 확립한 태스크그룹 병렬 pump의 Mac 포팅. 2026-08-19 세션 34의 ProRes 수습(graph AAC 직접 리드)은 유지 — STAB-02는 그 경로의 구조적 방어.
- **BUG-CA12-01**(메인 디스패치 전달 정지)은 별개 클래스 — STAB-02 검증 중 재관찰 시 기존 에스컬레이션 항목에 추가 기록만.
- **PARITY-TOL-01**은 이미 종결(2026-08-28) — STAB-05의 플래이크 제거는 별개 문제.
- **경계 분리(EditorViewModel 부채)**: STAB 창구 동안은 STAB 우선. 내부 승격 리팩터 승인 대상은 그대로 유지.
- **W 측정 분쟁**: STAB-01(watchdog)·STAB-02(펌프) 완료 전까지 W 결과 보고 시 측정 환경(완주/와치독 개입 여부)을 함께 기록.
- soak·실기기 등 사용자 대기 항목은 STAB과 **병렬 진행 가능** — STAB 완료 보고 시 함께 리마인드.

## 5 완료 후 판정 규칙

Phase 2 종료 시점에 EXECUTION_PLAN §4 1단계 게이트를 재실측 대조하고, Phase 1 판정(x/7)을 핸드오프에 재기록한다. 재측정 근거 없이 기존 수치 재인용 금지.
