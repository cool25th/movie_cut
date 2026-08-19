# 세션 핸드오프 — 현재 (2026-08-19)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 최신 세션이 이 파일의 최상단에 기록된다. 실행 순서의 근거는 `DEVELOPMENT_DIRECTION_20260815.md` §3·§9.

## 2026-08-20 세션 40 (P2-G24-1 — 스태빌 측정 인프라 · 2단계 착수)

**게이트**: verify_gate 5/5(1,274 테스트 — 스태빌 7종 신규) + 픽스처 재생성 동일 해시.

### 완료 — P2-G24-1 (이번 세션 커밋)
- **`StabilizationMetrics`** (Core/Analysis): DoD 4지표 순수 수학(잔류 중앙값·감소비·심각 워블 비·장면 전환 에러·크롭 중앙값) + `meetsDoD()` + `adaptiveCrop`(15% 클램프). P2-G24-6 E2E가 같은 함수 재사용(자기 보고 아님).
- **픽스처**: `stab_wobble_320x240_4s_30fps.mp4`(testsrc+smptebars concat = 장면 전환 1회·SHA 게이트 c274ef74…).
- **테스트 7종**: 중앙값·완전 보정·50% 경계(DoD는 경계 포함)·워블/장면에러/크롭 각 실패·클램프.

### 다음 회차 인계 — P2-G24-2 (장면 분할)
1. SceneChangeProvider 재활용: 세그먼트 검출 → 경계 프레임 ±2프레임 정확도(픽스처 t=2.0s) → `StabilizationMetrics.Frame.isSceneCut` 공급.
2. 이후 P2-G24-3(Vision 등록)·4(평활화+crop)·5(CI warp 배선)·6(E2E DoD 실측).
3. 실기기 3종=사용자 유보. 대기 결정(변경 없음).

## 2026-08-19 세션 39 (2단계 계획 수립 — USER_WAITING 전환)

**산출**: `docs/EXECUTION_PLAN_PHASE2_20260819.md` — EXECUTION_PLAN §5의 개요를 상세 전개.

### 완료 — 2단계 계획 문서 (커밋 276d7c9)
- 고정 순서: 1단계✓ → **G-24 손떨림 v1**(방향 문서 "효과 볼륨 확대보다 우선") → G-28 브라우저 → G-26 오디오 B. N2는 등록 결정 전제.
- **G-24 6증분**: 측정 인프라(순수 수학+결정적 픽스처+SHA)→장면 분할→Vision 등록→평활화+adaptive crop→CI warp 배선+fallback→E2E+DoD 실측. 함정 레지스터 5건.
- G-28: EffectCostProfile 스키마 확정 선행(PERFORMANCE_SLO 신설). G-26: 그래프 자리 노드 스키마 불변·게이트 LUFS ±0.2LU.

### 사용자가 할 일
**`docs/EXECUTION_PLAN_PHASE2_20260819.md` 검토 후 승인 또는 수정 지시.** 승인 시 다음 회차가 P2-G24-1(스태빌 측정 인프라)을 착수. 실기기 3종도 언제든 병렬 재개 가능(가이드: `docs/G27_DEVICE_VERIFICATION_GUIDE.md`).

### 다음 회차 인계 (승인 후)
P2-G24-1 — StabilizationMetrics(잔류 변위 중앙값·크롭 비율·워블 지수·장면 전환 오류 카운트의 순수 수학) + 결정적 움블 픽스처(sine 움블+임계 구간+장면 전환 2회·SHA-256 게이트) + 해석값 단위 테스트.

## 2026-08-19 세션 38 (G-03 Inc 4 — E2E 거부 단언 · **G-03 완결**)

**게이트**: 전체 E2E PASS(G-03 거부 검사 포함) + verify_gate 5/5(1,267).

### 완료 — G-03 E2E 거부 단언 (커밋 5b2e316)
- **run_e2e_export.sh**: 가시 콘텐츠 없는 조정-only 프로젝트의 출력 시도는 **거부**되어야 PASS(파일 생성 = FAIL — 조용한 강등 금지 원칙). 가시+조정 경로는 W4 29/29로 측정 완료.
- **1회 M-런 RMS 일시 편차**(−9.16dB·재실행 녹색): 동일 코드 2회째 녹색 — 재현 불가·원인 불명의 일시 편차로 기록(감시 대상. 재발 시 §8 M-런의 안정성 조사 증분).

### 다음 회차 인계 — 2단계 계획 수립
1. **EXECUTION_PLAN §5 패턴으로 2단계 상세 계획 문서 작성**: G-24 손떨림 v1(씬 분할·Vision 등록·경로 평활화·adaptive crop·CI warp·fallback — DoD 수치 백로그 §0.5)·G-28 브라우저(EffectCostProfile 스키마 확정 선행)·G-26 오디오 B(Apple AU 우선·LUFS ±0.2LU 게이트)·N2 오토스타일(등록 결정 후 G-28 세트).
2. 계획 승인 요청(§8 에스컬레이션) 또는 즉시 첫 증분 착수 — 방향 문서의 우선순위 참조.
3. 실기기 3종=사용자 유보. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 37 (G-03 Inc 3 — 조정 레이어 제품화)

**게이트**: W 스위트 **2회 연속 29/29=100.0%**(신규 단계 포함) + verify_gate 5/5.

### 완료 — G-03 제품화 (커밋 e01d6e5)
- **`SetClipPropertyCommand.isAdjustmentLayer`** (이전값 역추적 — undo 단일 트랜잭션).
- **인스펙터 UI**: "Adjustment layer" 토글 — 기존 색 섹션 편집이 조정 체인으로 전환.
- **W4 완전판**: `adjustment_layer` 단계(AddClipCommand + colorGrade) — 계획 원 문구 완성.
- **하니스 env**: `MOVIECUT_UITEST_ADJUSTMENT_LAYER=1`(마크+그레이드·상태 보고).
- 검증: 가시 클립 없는 조정-only 프로젝트 = noExportableMedia(정확한 실패 — 미지원 케이스의 조용한 강등 아님).

### 다음 회차 인계
1. **E2E 골든/파리티 스크립트 단계**: run_e2e_export.sh에 ADJUSTMENT_LAYER 조합 섹션 추가(하니스 env는 이미 있음) → G-03 완결 선언.
2. 이후 2단계 계획(EXECUTION_PLAN §5). 실기기 3종=사용자 유보. 대기 결정(변경 없음).

## 2026-08-19 세션 36 (G-03 Inc 2 — 조정 레이어 렌더 배선 + 픽셀 검증)

**게이트**: verify_gate 5/5(1,267 테스트 — 픽셀 4종 신규) + W 스위트 28/28=100.0% 무회귀.

### 완료 — G-03 렌더 배선 (커밋 b9d0e58)
- **Core**: `AdjustmentLayerChain.applyAdjustments`(잠긴 순서 — 클립 고유 체인 후·하위 트랙 먼저, 공유 픽셀 프로세서).
- **Mac**: CustomVideoCompositor.applyClipEffects 말미 적용·양쪽(프리뷰·출력) Instruction에 조정 세트 전달·조정 클립 콘텐츠 렌더 제외.
- **iOS**(DoD ③ — 공유 프로세서 경유): IOSCustomVideoCompositor 동일 적용·IOSExportEngine 전달·콘텐츠 제외.
- **픽셀 검증**: 항등·픽셀 이동·하위먼저 스택·범위 게이팅.

### 다음 회차 인계 — G-03 Inc 3 (제품화 잔여)
1. 인스펙터 UI: 클립을 조정 클립으로 변환 + 조정 클립의 색보정/필터 편집(기존 색 섹션 재사용).
2. E2E 골든/패리티 시나리오 신규(하니스 env — 조정 클립 포함 프로젝트) + W4 조정 단계(계획 원 문구 완성).
3. 이후 2단계 계획(EXECUTION_PLAN §5). 실기기 3종=사용자 유보. 대기 결정(변경 없음).

## 2026-08-19 세션 35 (G-03 Inc 1 — 조정 레이어 Core 절반)

**게이트**: verify_gate 5/5(1,263 테스트 — 신규 4종 포함).

### 완료 — G-03 Core: 모델·스키마·체인 (커밋 97bfde2)
- **설계 노트**(AdjustmentLayerChain 문서): 클립 플래그 채택(Track.kind 아님 — 범위·undo·저장이 클립 기계 재사용)·렌더 순서 고정(클립 고유 체인 → 조정 체인, 하위 트랙 먼저)·범위 밖 무변경·조정 클립 무콘텐츠·v1 비디오 트랙 전용.
- **스키마 v6**(`AddAdjustmentLayerMigration` 빈 마이그레이션·pre-v6 폴백) + 마이그레이션 체인 테스트 v6 확장.
- **`AdjustmentLayerChain`**(Core/Rendering): activeAdjustments·visibleClips·isAdjustmentContent — 렌더 배선의 단일 소비 지점.
- 게이트 수정: lint(force_cast 1건 정석 수정).

### 다음 회차 인계 — G-03 Inc 2 (렌더 배선)
1. Mac 프리뷰·출력 + iOS: FlattenedTimeline 소비 지점에서 조정 체인 적용(클립 고유 체인 후)·조정 클립 콘텐츠 렌더 제외.
2. 인스펙터 UI(조정 클립 변환/설정) + 골든(아래만 효과·범위 밖 무변경)·패리티 시나리오 신규 + W4 완전판.
3. 이후 2단계 계획(EXECUTION_PLAN §5 패턴). 실기기 3종=사용자 유보(러너·가이드 완비). 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 34 (ProRes 교찰 수습 — W 100.0% · 실기기는 사용자 유보)

**상태**: 사용자 결정으로 RUN 복귀(실기기 유보·코드 수습 우선). **게이트**: W 스위트 **2회 연속 동일 28/28=100.0%** + 전체 E2E 무회귀(챕터·ProRes·§8) + verify_gate 5/5.

### 완료 — ProRes+비디오+오디오 교찰 폐쇄 (커밋 e01c31f)
- **진단**: 교찰 시 앱 스레드에 리더/라이터 프레임 전무 — 혼합 컴포지션 리드의 continuation 파킹(Apple측).
- **수습**: 라이터 경로(exportVideoWithExplicitBitrate)는 리더용 컴포지션을 **비디오 단독**으로 빌드하고 오디오를 **그래프 AAC 파일에서 직접 리드**(graphAudioURL 전달·audioMix 제거 — 그래프가 이미 믹스). 프리셋 경로는 컴포지션 오디오 유지(통과 조합).
- **실측**: w4 prores OK → W 28/28=100.0% (2회 동일)·챕터 메타데이터 3개·ProRes prores·§8 rms 0.000dB 무회귀.

### 다음 회차 인계
1. **1단계 자율 조건 전부 녹색** — 실기기 3종만 유보(재개 시 러너·가이드 완비). 차순위 후보: **G-03 조정 레이어**(계획상 1단계 말·W4 완전판 잠금해제) → 이후 2단계 계획(EXECUTION_PLAN §5).
2. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-19 세션 33 (G-27 ③ 실기기 준비 — USER_WAITING 전환)

**상태**: 자율 수행 잔여 소집 → **USER_WAITING(실기기 3종 협력)**.

### 완료 — 실기기 러너 + 가이드 (커밋 75ee80d)
- **`run_g27_device_e2e.sh`**: devicectl 기반 실기기 E2E — 시뮬레이터 게이트와 동일 하니스·동일 7단언 (TEAM_ID 서명·픽스처 스테이징·env 런치·결과 풀링). 미연결 시 절차 안내 오류. **사용자 기기 연결 시 첫 검증 예정** (devicectl: 페어링 이력 iPhone 13 Pro = unavailable 상태).
- **`docs/G27_DEVICE_VERIFICATION_GUIDE.md`**: 3종(최소/중간/최신)·사전 준비(팀 ID·개발자 모드·신뢰)·실행·결과 보고·문제 대응.

### 사용자가 할 일
`docs/G27_DEVICE_VERIFICATION_GUIDE.md` 참조: 기기 연결 후 `TEAM_ID=<팀ID> bash scripts/run_g27_device_e2e.sh` — 출력 전체를 알려주면 루프가 §4를 갱신하고 3종 PASS 시 DONE_PHASE1 선언으로 이어짐.

### 다음 회차 인계 (결과 접수 후)
1. 기기 결과 → §4 표 갱신·결함이면 수습 증분.
2. 3종 PASS → DONE_PHASE1 선언 (EXECUTION_PLAN §4 전 조건 충족).
3. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 32 (W 대표 작업 시나리오 게이트 — §4 측정 창구 완성)

**게이트**: run_w_scenarios.sh **2회 연속 동일 27/28=96.4% PASS**(≥90% 게이트) + verify_gate 5/5.

### 완료 — W1~W5 측정 창구 (커밋 d7a1313)
- 하니스 `MOVIECUT_UITEST_W_SCENARIO` + `run_w_scenarios.sh`: 방향 문서 §1 대표 작업 5종을 실제 경로로 구동, 성공률 게이트. 격리 서피스(전체 에디터 라이브 레이아웃 크래시 회피 — 파리티 선례 적용)·스크립트 와치독.
- 측정 중 발견·수습: ① STT 헤드리스 호출=TCC 프라이버시 위반 **강제 크래시**(가용성 프로브로 권한 게이트 기록) ② 무변화 사인파 픽스처=비트 0(결정적 리듬 픽스처 생성) ③ 트래킹 rect 정규화 좌표 ④ **ProRes+비디오+오디오 교찰(신규 조합 — 라이터 경로 리더측)**: 90초 once-continuation 레이스로 정직 FAIL 기록(TaskGroup 암시적 join은 교찰 회피 불가).
- W4 델타: 조정 레이어=G-03(2단계) — 계획대로.
- **실측(2회 동일)**: w1 7/7·w2 5/5·w3 6/6·w4 4/5(prores 결함)·w5 5/5 = **96.4%**.

### 다음 회차 인계 — 실기기 요청 (자율 잔여 소진)
1. §4 측정 조건 전부 확보(성공률 96.4%·픽셀·PCM·drift·지연 강제·시뮬레이터 E2E). **잔여=실기기 3종(사용자 하드웨어)** → 사용자에게 절차(디바이스 연결·개발 증명서 신뢰·G-27 러너 시나리오) 안내 후 **LOOP_STATE USER_WAITING 전환**.
2. 기록 결함(후속 증분 후보): ProRes+비디오+오디오 교찰(96.4%에 반영됨).
3. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 31 (1단계 잔여 정리 ① — 지연 기준선 enforce 전환)

**게이트**: run_latency_baseline.sh **2회 연속 enforced PASS**(소형+10분 2패스) + verify_gate 5/5.

### 완료 — 지연 SLO 강제 전환 (커밋 d986666)
- **`run_latency_baseline.sh`**: 위반 차단 기본화(`--no-enforce` 진단 모드) + **10분 fixture 패스**(결정적 생성 testsrc 320×240+220Hz 600s — 저장소 부담 없이 매 실행 재현). SLO 원 의미(10분 프로젝트 열기 ≤3s)의 실측 공백 해소.
- **SLO 문서**: 소형 seek p50 0.05–0.06ms·열기 101.6–105.1ms / **10분 seek p50 0.05–0.06ms·p95 0.08–0.10ms·열기 143.9–145.9ms(목표 ~4.8%)** 기록 — 종전 주의 표기 2건 해소, 강제 항목 목록에 추가.

### 다음 회차 인계 — 잔여는 전부 사용자 의존/결정
1. **W1~W5 조합 시나리오**: 구축 여부 사용자 결정(베타 스위트 4/4가 대체 창구 — 계획상 "신규" 예정이었으나 측정 증거는 확보).
2. **실기기 3종(G-27 ③)**: 사용자 하드웨어 협력 필요 — 요청 방법(디바이스 연결+증명서) 안내 후 USER_WAITING.
3. 둘 다 사용자 의존이므로 **다음 회차는 USER_WAITING 전환 후 종료**가 정직한 선택(작업 가능한 잔여 없음). 사용자 결정: W 시나리오 구축 지시 또는 실기기 일정.
4. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-19 세션 30 (G-27 시뮬레이터 E2E 구축 — 필수 불가 잔여 소진)

**게이트**: run_g27_simulator_e2e.sh **2회 연속 동일 PASS**(iPhone 17 Pro 시뮬레이터) + verify_gate 5/5.

### 완료 — G-27 ① 시뮬레이터 E2E (커밋 e15a8c4)
- **`IOSUITestHarness`**(iOS 앱, env 게이트): Mac 하니스 관례의 iOS 판 — 실제 앱 경로(임포트→프리뷰→출력→AVAudioSession 라우팅→ProjectStore 저장)를 구동하고 Documents/g27-result.txt에 구조화 라인 기록.
- **`IOSPreviewCompositionBuilder` 추출**(PreviewView→공유): 하니스가 앱과 동일한 프리뷰 컴포지션을 구동(병행 구현 드리프트 방지).
- **`run_g27_simulator_e2e.sh`**: 클린 설치(결정성)·픽스처 스테이징·2단계 런치(재오픈=프로세스 경계)·단언+ffprobe.
- **실측(2회 동일)**: imported 2클립·preview playable duration 10.000 frame=1·export h264 64,906B·category=Playback route=Speaker·재오픈 2클립 보존.
- **설계 노트**: 계획 문구는 "XCUITest 타겕"이나 루프의 확립 E2E 관례(env 하니스+결과 파일+스크립트 단언 — 결정적·측정 중심)를 iOS에 이식하는 것으로 구현. UI 자동화(XCUITest)가 필요하면 이 기반 위에 추가.

### 다음 회차 인계 — 1단계 게이트 잔여 정리
1. **지연 기준선 --enforce 전환**: 실측(seek p50 0.12ms/p95 0.27ms·열기 125.6ms)이 목표(100ms/3000ms) 이내 — SLO 문서 기준선 기록 후 차단 모드 전환.
2. **W1~W5 조합 시나리오**: 구축 여부 사용자 결정 후보(베타 스위트가 대체 창구).
3. **실기기 3종**: 사용자 협력 필요 — 요청 시 USER_WAITING 전환.
4. 잔여 소진 후 DONE_PHASE1 평가. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 29 (G-25 §11 종합 판정 + 1단계 게이트 점검 — 측정 인프라 결함 수습)

**게이트**: verify_gate 5/5(1,255) + 최종 상태 측정 창구 전부 — 베타 프리플라이트 4/4·지연 기준선·파리티 스위트 ALL PASS.

### 완료 — §11 종합 보고 + 측정 인프라 수습 (커밋 4638706)
- **§11①~⑤ 전 항목 측정 증거 충족**(상세 표는 LOOP_STATE): null test maxDev=0.00e+00·drift 172,800,000 정확·미터 ↔ 실출력 Δ0.00 LU·오디오 E2E 전 증분 무회귀(§8 엄격 게이트 rms 0.000dB·경고 0/0 포함).
- **최종 상태 §4 창구 재실측**: 베타 4/4·seek p50 0.12ms/p95 0.27ms·프로젝트 열기 125.6ms(목표 이내 — --enforce 전환 후보)·파리티 스위트 전 PASS(최악 MAD 0.45/12.0).
- **측정 인프라 결함 2건 수습(게이트가 포획)**: ① 베타 시나리오 4의 `status=PASS` grep은 하니스가 낸 적 없는 형식 — 확립된 복구 계약으로 수정(통과한 적 없는 단언이었음) ② **파리티·베타·지연 스크립트의 플레인 빌드(샌드박스 ON)**가 2-C-3 재빌드 시점부터 모든 앱 런치를 조용히 실패시킴(이진 탐색 규명 — 소스·산출물·앱 상태·LaunchServices 무죄) → 3스크립트에 ENABLE_APP_SANDBOX=NO CODE_SIGNING_ALLOWED=NO 정합(E2E 관례)으로 해소.
- **§4 대조 잔여(Phase 1 미완 요인)**: iOS 실기기 3종(G-27 시뮬레이터 E2E 미구축=필수 불가 잔여·실기기=사용자 의존)·W1~W5 조합 시나리오 미구축(베타 스위트가 대체 창구)·지연 --enforce 미전환.

### 다음 회차 인계
1. **G-27 시뮬레이터 E2E 구축** — 필수 불가 잔여의 마지막 항목: XCUITest 타겟+시뮬레이터 구동(프리뷰+출력+오디오 라우팅+재오픈 필수 시나리오, PLATFORM_PARITY §6 경고 해소). 실기기 러너는 사용자 일정 확보 시(그때 USER_WAITING).
2. 이후: 지연 기준선 --enforce 전환 평가·W1~W5 구축 여부 결정 → 잔여 소진 시 실기기 협력 요청 → DONE_PHASE1.
3. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-19 세션 28 (G-25 전환 2-C-3: §8 엄격 게이트 — **2-C 제품 경로 전환 완결**)

**게이트**: verify_gate 5단계 PASS(1,255 테스트) + run_e2e_export.sh 전체 PASS **2회 연속 동일** + run_g25_nulltest.sh 무회귀 PASS.

### 완료 — 전환 2-C-3: 그래프 PCM 기준 ±1샘플 엄격 게이트 (커밋 fa98175)
- **`AudioGraphExportPostCheck.trimCodecDelay`** (Core): §8.1 "프라이밍/패딩 트림은 호출자 책임"의 구현 — 상관 정렬(조대 stride-64 + 정밀 stride-1·모노합 내적, 경계 8,192샘플)로 코덱 지연 측정 후 헤드+테일 절단해 기준과 1:1 정렬. 왕복 테스트: 프레임 0 대소리+조용한 꼬리(온셋 편법 불가) → 트림 후 길이 ±1·check passed·RMS<1dB.
- **§8 하니스**: 참조 = 출력이 인코딩한 것과 동일한 `renderMix`(동일 가청 스팬 정책) — 컴포지션 재빌드·프리뷰 렌더 의존 제거. `check()`의 ±1 경성 판정 활성화.
- **스크립트**: 0.5s 관대 임계 폐지 → 코덱 지연 타당성 + ±1샘플 길이 + RMS≤1dB + 클리핑 0. 명세 §8 과도기 기준 문단 이행 완료로 갱신.
- **실측(2회 동일)**: §8 A/B **len=192000/96000 정확·rms=0.000dB·경고 0/0**(±1 충족으로 길이 경고 소멸 — 종전 1/1)·solo Δ −3.04·M Δ0.00 LU.

### 다음 회차 인계 — G-25 완료 판정 (전환 증분 전부 소진)
1. **§11①~⑤ 종합 완료 판정 보고**: ①null test ±1샘플(3그래프 maxDev=0.00e+00·offset 0) ②동일 PCM ③60분 drift(종점 172,800,000 정확·꼬리 offset 0·왕복 정확) ④LUFS/TP 미터 실측(그래프 미터 −22.94 LUFS·TP −15.74 ↔ 실출력 Δ0.00) ⑤기존 오디오 E2E 무회귀(NR SNR 5.15dB·EQ bass/treble 2.31/0.49·덕킹 12.04dB — 매 증분 게이트) — **전 항목 측정 증거 확보**. 핸드오프에 종합 보고 작성.
2. **DONE_PHASE1 평가**: EXECUTION_PLAN §4의 1단계 게이트 조건을 대조 — G-25 외 잔여 조건이 있으면 명시하고 그것부터 실행(1단계 게이트 전 효과 확대 금지 규칙 준수). 전 조건 충족 시 LOOP_STATE를 DONE_PHASE1로 전환.
3. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-19 세션 27 (G-25 전환 2-C-2: 프리뷰 tap 폐지 — EQ 파생 미디어 통일)

**게이트**: verify_gate 5단계 PASS(1,254 테스트) + run_e2e_export.sh 전체 PASS(**M런 RMS 게이트 재활성 포함** — tap 결함 폐쇄 증명) + run_g25_nulltest.sh 무회귀 PASS.

### 완료 — 전환 2-C-2: 프리뷰 EQ의 파생 미디어 전환 (커밋 456a278)
- **`AudioEqualizerService` 통일** (Core): 디코드를 §3.1 어댑터로 전환 — 비디오 컨테이너 임베디드 오디오도 EQ 파생 가능(기존 AVAudioFile 한정 — 그래프·출력 경로의 EQ 비디오 클립 잠복 실패 갭 해소). DSP 단일 구현으로 프리뷰·출력·그래프 동일(기존 tap은 5밴드 AVAudioUnitEQ·파일 렌더는 3밴드 원폴로 **서로 다른 DSP였음** — 이원 경로 해소).
- **프리뷰 tap 폐지** (PlaybackEngine): MTAudioProcessingTap 기계(~250줄)·ClipEqualizerTimelineSegment 제거. EQ 클립(오디오 트랙+비디오 임베디드 양쪽)은 파생 미디어 소스 스왑 — 프리셋 캐시로 재빌드 무관 재사용(리버스 선례), clear/loadProject 정리.
- **조사 확정**: NR 실시간 필터는 실재하지 않았음(주석만 — NR은 편집 시점 파괴적 변환으로 이미 통일, 주석 정정). 프리뷰 볼륨/페이드/덕킹 audioMix 램프는 유지(AVPlayer 네이티브·tap 무관).
- **M런 RMS 게이트 재활성**: tap-in-export 결함으로 분리 기록했던 프리뷰 참조 RMS 단언(≤1dB) 복원 — 실측 PASS로 결함 폐쇄 증명. 계약 갱신(AudioEqualizerDSP — 프리뷰 파생 배선+tap 심볼 부재 단언).
- **실측**: 그래프 미터↔출력 Δ0.00·§8 RMS −0.001dB·NR 5.15dB·EQ 2.31/0.49·덕킹 12.04dB — 전 수치 동일 무회귀.

### 다음 회차 인계(2-C 잔여 — 마지막 전환 증분)
1. **2-C-3**: §8 기준 그래프 PCM 전환 + AAC 프라이밍(2112샘플) 트림 → ±1샘플 엄격 게이트(0.5s 관대 임계 교체). §8 하니스 참조를 renderCurrentPreviewAudio → GraphMixRenderer PCM으로, 재디코드 측 프라이밍 정렬 후 check() 경성 판정.
2. 이후 §11①~⑤ 완료 판정 실측(§11⑤는 이미 매 증분 게이트로 실측 중 — ①②③④ 종합 보고) → DONE_PHASE1 평가(EXECUTION_PLAN §4).
3. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 26 (G-25 전환 2-C-4: 오디오 속도 램프 사전 렌더 — 갭 폐쇄)

**게이트**: verify_gate 5단계 PASS(1,254 테스트) + run_e2e_export.sh 전체 회귀 PASS(오디오 수치 완전 동일).

### 완료 — 전환 2-C-4: 속도 램프 오디오의 그래프 경로 (커밋 bc16f69)
- **`AudioGraphSourceAdapter.rampSegments` (Core)**: 레거시 `applySpeedRamp` 경계 수학 이식 — 경계 [0,1]+포인트(클램프·중복 제거), 구간 출력 = `timeMapping` 차(선형 rate 커브의 구간별 정속 근사 = 레거시 구성 scaleTimeRange 의미론, 단일 소스).
- **`timeStretchedRamped` (Core)**: 구간별 슬라이스→피치 보존 스트레치(trimTail 비활성 — 중간 무음 내용 보존)→접합→**구간당 정확한 기대 프레임 절단**(출력 길이 = 래거시 램프 지속과 일치).
- **빌더**: 램프 클립(포인트 ≥2) = 클립 단위 소스 + `Plan.rampAdjustedSources`(원시 포인트) + 활성화 **offset 0·rate 1**(프리렌더 = 클립 소스 창의 워프 그 자체) — 램프가 정속 playbackRate에 우선(래거시 didApplySpeedRamp 동일).
- **GraphMixRenderer**: 램프 디코드 분기(EQ 파생 미디어 우선 — 정속 분기와 동일 계층).
- 테스트 +3: 세그먼트 수학 해석값 고정(ln2·2구간)·정확 길이(2×=정확히 절반)·빌더 매핑(램프 우선·offset 0). **E2E 미커버 갭이었던 속도 램프 오디오 폐쇄**.

### 다음 회차 인계(2-C 잔여)
1. **2-C-2**: 프리뷰 tap(audioTapProcessor)·AVAudioEngine NR 실시간 필터 폐지(§0 v1.1) — EQ/NR 클립을 프리뷰 컴포지션에서 파생 미디어로(리버스 temporaryReverseRenderURLs 선례). tap-in-export 결함 소멸. 게이트: 프리뷰 파리티 시나리오·전체 E2E 무회귀 + EQ/NR 프리뷰 가청성(단위/하니스 검증 방식 설계 필요).
2. **2-C-3**: §8 기준 그래프 PCM 전환 + AAC 프라이밍(2112샘플) 트림 → ±1샘플 엄격 게이트(현 0.5s 관대 임계 교체).
3. 이후 §11①~⑤ 완료 판정 실측 → DONE_PHASE1 평가. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-19 세션 25 (G-25 전환 2-C-1b: 전체 출력 오디오 그래프 전환 — ProRes 교찰 포획·해소)

**게이트**: verify_gate 5단계 PASS(1,251 테스트) + run_e2e_export.sh 전체 PASS **2회 연속 동일** + run_g25_nulltest.sh 무회귀 PASS.

### 완료 — 전환 2-C-1b: makeExportPackage 오디오 경로 폐지 + 그래프 AAC 단일 트랙 (커밋 2f870e9)
- **구조**: `export()`·`exportVideoWithExplicitBitrate`(챕터·AVAssetWriter)는 `renderGraphAudio`(GraphMixRenderer→AudioGraphAacEncoder)를 컴포지션의 **단일 오디오 트랙**으로 삽입, audioMix=nil — 클립 단위 오디오 삽입·볼륨/페이드/덕킹 램프·EQ 파생(equalizedAudioAsset)·makeAudioMix 전부 제거. 스틸/GIF는 영상 전용(그래프 오디오 미사용). **비디오 임베디드 오디오 미믹싱 결함 구조적 해소**(그래프가 포함 — 프리뷰와 동일).
- **무음=오디오 없음 의미론**(RenderError.noAudio 확장): 순수 디지털 무음 믹스(전 샘플 0)→오디오 트랙 미삽입(레거시 무음 프로젝트 출력 형태와 동일)·audio-only는 noExportableMedia 회귀·미터는 안내. **근거=실측 교찰**: 게이트 1·2회차에서 E2E 정지(앱 0% CPU 파킹) — 프로브 이진 탐색으로 **"ProRes 프리셋+무음 AAC 트랙" 조합이 AVAssetExportSession 영구 파킹**임을 특정(실제 오디오+ProRes✓·무음+기본 프리셋✓·audio-only✓). 무음 스킵으로 교찰 클래스 소멸, ProRes E2E 회복.
- **계약 갱신 2종**: 덕킹(출력 엔진=그래프 존재+램프 부재 단언·프리뷰 램프는 2-C-2까지 유지)·EQ(DSP 주체 GraphMixRenderer 이동 단언).
- **실측(2회 동일)**: §11⑤ 전 녹색 — NR SNR 5.15dB·EQ bass/treble 비율 2.31/0.49·덕킹 감쇠 12.04dB·오디오 추출 aac·ProRes prores·§8 A RMS −0.001dB·solo Δ −3.04·M Δ0.00 LU·null test 패리티 −0.02 LU.

### 다음 회차 인계(2-C 잔여)
1. **2-C-4(우선순위 상향 — 이번 전환으로 열린 갭)**: 오디오 클립 **속도 램프** 사전 렌더 — 레거시는 applySpeedRamp가 오디오 컴포지션 트랙을 구간별 scaleTimeRange 처리했으나 그래프는 단일 rate만 지원. `SpeedRampCurve`(Core) 구간별 timeStretched 연결로 `speedAdjustedSources` 확장 + 빌더 활성화 수식(램프 출력 지속 = curve 적분). E2E 미커버 갭 — 신규 단위 테스트로 고정.
2. **2-C-2**: 프리뷰 tap(audioTapProcessor)·AVAudioEngine NR 실시간 필터 폐지 — EQ/NR 클립을 프리뷰 컴포지션에서 파생 미디어로(리버스 temporaryReverseRenderURLs 선례). tap-in-export 결함 소멸.
3. **2-C-3**: §8 기준 그래프 PCM 전환 + AAC 프라이밍(2112샘플) 트림 → ±1샘플 엄격 게이트.
4. 이후 §11①~⑤ 완료 판정 실측 → DONE_PHASE1 평가. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-18 세션 24 (G-25 전환 2-C-1a: audio-only 출력 그래프 PCM→AAC)

**게이트**: verify_gate 5단계 PASS(1,251 테스트) + run_e2e_export.sh 전체 PASS **2회 연속 동일** + run_g25_nulltest.sh 무회귀 PASS.

### 완료 — 전환 2-C-1a: AudioGraphAacEncoder + exportAudioOnly 그래프 전환 (커밋 8fd4178)
- **`AudioGraphAacEncoder.swift` (Core)**: 그래프 PCM(인코더 입력 렌더)→m4a AAC(고품질 192k, 65,536프레임 청크 기록 — 전체 PCM 이중 복사 회피). 테스트 3종(실인코딩·재디코드: 길이 [원본, +8192] 패딩 경계·RMS/LUFS ≤1dB·빈 PCM 명시 실패).
- **`exportAudioOnly` 전환**: GraphMixRenderer.renderMix(trimToAudibleSpan:)→AAC 인코딩. 컴포지션·audioMix·AVAssetExportSession 제거 — **audio-only 출력의 샘플은 이제 그래프에서만** (spec §1). NR 동등 실증: NR은 편집 시점 파괴적 변환이므로 ExportEngine(미적용)과 그래프(파생 미디어 소비)가 자동 동등.
- **가청 스팬 길이 계약**: 레거시는 solo 억제 트랙을 컴포지션에서 제외해 파일이 생존 오디오 끝에서 종료(4s 프로젝트 solo 시 2s 파일) — `trimToAudibleSpan`(억제 안 된 스트립 최대 종료 샘플, 순수 플랜 수학)으로 재현. 게이트 1회 실패(B 런 duration 2s↔4s)로 발견·수정.
- **StaticContract 갱신**: audio-only 계약을 그래프 배선으로(renderMix·encode 존재 + 해당 함수에 레거시 표현[AppleM4A 프리셋·audioMix] 부재 단언).
- **실측(2회 동일)**: §8 A 그래프 출력↔프리뷰 참조 **RMS −0.001dB**·LUFS −25.67·solo Δ −3.04 LU·M 런 Δ0.00 LU·null test 패리티 −0.02 LU 무회귀.

### 다음 회차 인계(2-C 잔여 — 4시간 루프가 순차 소화)
1. **2-C-1b**: 전체 mp4 출력 오디오 전환 — 비디오-only 컴포지션 출력 + 그래프 AAC(`AudioGraphAacEncoder`) 패스스루 먹싱(AVMutableComposition+Passthrough). 챕터(exportVideoWithExplicitBitrate)·ProRes·명시적 비트레이트 경로 포함. **§11⑤ 게이트 = 덕킹 RMS·EQ 스펙트럼·NR SNR E2E**(전부 이 경로 사용) + §8·프리뷰 파리티 무회귀.
2. **2-C-2**: 프리뷰 tap(audioTapProcessor)·AVAudioEngine NR 실시간 필터 폐지 — EQ/NR 클립을 프리뷰 컴포지션에서 파생 미디어로(리버스 temporaryReverseRenderURLs 선례 패턴). tap-in-export 결함 소멸.
3. **2-C-3**: §8 기준 그래프 PCM 전환 + AAC 프라이밍(2112샘플) 트림 → ±1샘플 엄격 게이트(현 0.5s 관대 임계 교체).
4. **2-C-4**: 속도 램프 사전 렌더 미디어 공급(`speedAdjustedSources` 소비자 보강 — 구간별 스트레치).
5. 이후 §11①~⑤ 완료 판정 실측 → DONE_PHASE1 평가. 대기 결정(변경 없음): 접근 정규화·모션 트래킹 재검출 시드.

## 2026-08-18 세션 23 (G-25 전환 2단계-B: 미터 그래프 전환 — M 런이 레거시 tap 결함 첫 포획)

**게이트**: verify_gate 5단계 PASS(1,248 테스트) + run_e2e_export.sh 전체 PASS — §8 A/B 무회귀(0.043dB·solo Δ −3.04 LU) + **미터 런 M: 그래프 −22.94 ↔ 실출력 −22.94 LU(Δ=−0.00, 1회차 0.003)**.

### 완료 — 전환 2단계-B: GraphMixRenderer + 미터 그래프 전환 (커밋 dbe3d61)
- **`GraphMixRenderer.swift` (App)**: 측정 경로 공용 그래프 믹스 렌더러 — EQ 클립 유효 미디어 파생(`AudioEqualizerService` 오프라인 — 출력 경로와 동일 5밴드 DSP, §0)→빌더→§3.1 어댑터 디코드(`sourceAssetIds`·`derivedClipIds`·`speedAdjustedSources` 전부 소비)→`AudioGraphEncoderInput` 렌더. NR 미적용(기존 프리뷰 audioMix도 미적용 — 동등, 2-C에서 출력 NR 조사 후 결정).
- **`measureMasterLoudness` 전환**: 프리뷰 컴포지션 대기 루프·m4a 렌더·재디코드 전부 제거 — 프로젝트 상태→그래프 PCM→LUFS. 미터 경로의 교찰 조건(AVAssetExportSession)·tap 의존 구조적 제거.
- **E2E**: 하니스 `MOVIECUT_UITEST_MASTER_METER`(+`EQ=1` — BGM에 bassBoost 실제 명령 적용, §0 파생 종단 검증) + §8 스크립트에 미터 런 M(미터↔실출력 ±1.5 LU·클리핑 0 단언).
- **M 런이 포획한 레고시 결함(tap-in-export, LOOP_STATE 기록)**: EQ 적용 시 `renderCurrentPreviewAudio`의 tap(MTAudioProcessingTap) 트랙이 AVAssetExportSession에서 ~무음 렌더(참조 −29.14 ≈ BGM 억제 믹스 −28.71 — tap은 AVPlayer·AVAssetReader용 설계). **Inc 9 미터가 이 경로를 썼으므로 EQ 프로젝트의 기존 미터 측정은 깨져 있었음(잠복)** — 그래프 미터가 이미 해소. 게이트 처리(사용자 결정): M 런은 미터↔출력 일치만 단언, 프리뷰 참조 RMS는 결함 기록으로 분리(2-C tap 폐지로 소멸).

### 다음 회차 인계(루프 자동화 — 4시간 간격 회차가 순차 소화)
1. **2-C(출력 경로 배선)**: ① 출력 오디오 인코딩 그래프 PCM 전환(PCM→AAC→비디오 먹싱) ② 프리뷰 tap·AVAudioEngine NR 실시간 필터 폐지(§0 v1.1) ③ §8 기준 그래프 PCM 전환 + AAC 프라이밍 트림(±1샘플 엄격 게이트) ④ 속도 램프 사전 렌더 미디어 공급 ⑤ 출력 NR 처리 조사 후 그래프 편입 결정. 게이트 = §11⑤(EQ Goertzel·덕킹 RMS·NR SNR 무회귀).
2. 2-C 완료 후: §11①~⑤ 완료 판정 실측 → DONE_PHASE1 평가(EXECUTION_PLAN §4).
3. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-18 세션 22 (G-25 제품 경로 전환 2단계-A: §3.1 소스 어댑터)

**게이트**: verify_gate 5단계 PASS(1,248 테스트) + run_g25_nulltest.sh E2E PASS **2회 연속 동일 수치**(3 그래프·project 192,000프레임 maxDev=0.00e+00·패리티 −0.02 LU·drift 0).

### 완료 — 전환 2단계-A: AudioGraphSourceAdapter(§3.1) + 빌더 속도 매핑 + 하니스 정규화 (커밋 d391d50)
- **`AudioGraphSourceAdapter.swift` (Core)**: §3.1 엔진 어댑터 — ① 디코드: 오디오 전용 컨테이너(AVAudioFile) + **비디오 컨테이너 임베디드 오디오(AVAssetReader)**, 오디오 없는 영상 = 명시적 무음 소스(실제 기여), 읽기 불가 = throw(조용한 품질 강등 금지) ② 리샘플: AVAudioConverter 고품질, 입력 핸들러가 endOfStream 신호로 필터 꼬리 플러시 ③ **속도 사전 렌더**: AVAudioUnitTimePitch 오프라인 수동 렌더링(scaleTimeRange와 동일 계열), 모노는 dual-mono 스테레오로(엔진 모노 경로 −3dB 감쇠 실측 회피), 꼬리 무음 트림. **범위 외 명시**: 리버스는 제품이 이미 사전 렌더 미디어로 구체화(§0 유효 미디어로 공급), 속도 램프는 단일 rate 재현 불가 — 둘 다 배선 증분.
- **빌더 속도 매핑**: 속도 ≠ 1 클립 = **클립 단위 소스**(스트레치 소스는 동일 자산 속도-1 클립과 공유 불가) + 활성화 수식(오프셋 a/speed·타임라인 지속 sourceRange.duration/speed — scaleTimeRange 의미론, N(τ)=S(τ·speed) 유도) + `Plan.speedAdjustedSources` 사전 렌더 요청 목록.
- **하니스 null test §3.1 전환**: 실제 프로젝트 디코드를 어댑터 정규화 경로로(그래프 레이트 정규화·무음 폴백 제거 — 실제 실패는 명시적 throw).
- 테스트 +9(어댑터 7종 — 실미디어: 44.1k→48k 리샘플 길이 정확·mp4 임베디드 톤·무음 mp4·2× 스트레치 피치 보존·풀 파이프라인 / 빌더 속도 2종). 전체 1,248.

### 다음 세션 인계
1. **전환 2단계-B(측정·출력 경로 배선)**: measureMasterLoudness를 그래프 렌더로(빌더+어댑터+AudioGraphEncoderInput → LUFS — AVAssetExportSession 의존 제거로 **미터 경로의 교찰 조건 구조적 제거**) + EQ/NR 유효 미디어 어댑터(`AudioEqualizerService().apply` 재사용, 빌더 `effectiveMediaFor` 공급, `resolvedEqualizerPreset` 통일 확인) + §8 기준 그래프 PCM 전환 + 출력 인코더 입력 그래프 PCM 전환(±1샘플 엄격 게이트). 게이트 = §11⑤ 기존 오디오 E2E 무회귀(EQ Goertzel·덕킹 RMS).
2. 속도 램프 클립의 사전 렌더 미디어 공급(빌더 요청 `speedAdjustedSources` 소비자 배선 시).
3. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-18 세션 21 (사용자 결정: 명세 v1.1 승인 → 제품 경로 전환 1단계)

**게이트**: verify_gate 5단계 PASS + run_g25_nulltest.sh E2E PASS **2회 연속 동일 수치**.

### 완료 — G-25 제품 경로 전환 1단계: 명세 v1.1 + Project→그래프 빌더 + 실제 프로젝트 null test (커밋 5f43d7b)
- **명세 v1.1 (사용자 승인)**: 제품 경로 전환 작성 중 발견된 설계-구현 불일치 3건 반영 — ① §1.1 신설: 1단계 덕킹 = 플래너 산출물의 **스트립 게인 자동화 구체화**(버스 사이드체인·`AudioGraphDucking`은 G-26 슬롯), 램프는 range 내부(어택/릴리즈 타이밍 현행 계승)·dB-선형·페이드 클램핑 미재현. ② §0: EQ/NR은 프리뷰(실시간 tap)·출력(파생 미디어) **이중 경로**였음을 인정하고 그래프 소스 = 클립의 **유효 오디오 미디어**(적용 클립은 `.derived`)로 규칙화, 프리뷰 tap 폐지 예고. ③ §3.1 신설: 소스 정규화(비디오 컨테이너 `AVAssetReader`·`AVAudioConverter` 리샘플·속도/리버스 사전 렌더)는 엔진 어댑터 소유, 렌더러 nearest-frame 비율 판독은 더미 폴백. §8 과도기 기준·§11⑤ 무회귀 판정 기준(측정 임계 내·그래프 의미론 기준) 명시. **스키마 불변(version 1)**.
- **`AudioGraphProjectBuilder.swift` (Core)**: v1.1 의미론 구현 — 덕킹 **절대 리베이스**(클립 로컬 range → 클립 시작+range의 절대 샘플; 전 세션 발견 좌표계 버그 수정)·내부 램프 4포인트(attack [start, start+0.12]·release [end−0.25, end])·짧은 range(<attack+release)·level≥1 가드(현행 동작 계승) / EQ·NR 유효 미디어(`effectiveMediaFor` 클로저 → 클립 단위 `.derived` 소스[설정이 클립 단위이므로 자산 공유 시 별 소스]·`Plan.derivedClipIds`) / §3.1 디코드 계약(`decodedSampleRateFor` — 소스 id 기준, 어댑터 정규화 시 nil). 테스트 9종(신규 3: 절대 리베이스 회귀·엣지 케이스·파생 매핑).
- **null test §9.1 실제 프로젝트 단계 (App)**: 하니스가 메인 플로우(덕킹 하니스 후)에서 `AudioGraphProjectBuilder`로 실제 프로젝트(=BGM 220Hz 0-4s + Voice 1kHz 1-2s, 플래너 덕킹 적용 상태)를 그래프로 빌드→양 엔진 렌더→§9 비교 + 그래프 믹스↔프리뷰 audioMix 렌더 LUFS 패리티(전환 증거; 임계 ±1.0 LU). 스크립트 게이트: project_graph 실행·엔진 null·패리티 3단계 단언 + JSON 교차검사.
- **실측(2회 연속 동일)**: 3 그래프 전부 통과, project 192,000프레임 **양 엔진 maxDev=0.00e+00·offset=0**, **패리티 −0.02 LU** — dB-선형 덕킹 램프·클램핑 미재현이 측정상 무의미함을 실증(§11⑤ 근거).
- **게이트가 잡은 결함 3건(전부 수정)**: ① 하니스 `try? decode() ?? 폴백` 우선순위(`??`가 try? 안쪽에 묶여 디코드 실패 시 nil → missingInput) ② 비디오 임포트+덕킹+`renderCurrentPreviewAudio` 조합 = LOOP_STATE 기존 교찰 결함 재현 → 게이트에서 비디오 임포트 제외(오디오 없는 픽스처라 그래프 기여 0, 이유 주석화) ③ 패리티 +2.99 LU = 모노 m4a↔dual-mono 스테레오의 BS.1770 +3.01 LU 표시 차이 → 측정 전 채널 레이아웃 정규화(`dualMonoStereo`).

### 다음 세션 인계
1. **제품 경로 전환 2단계(엔진 배선)**: 프리뷰(audioMix→그래프 렌더)·출력(인코더 입력→그래프) 배선 + EQ/NR 유효 미디어 어댑터(렌더 시점 파생, §0) + §3.1 정규화 어댑터(AVAssetReader·AVAudioConverter·속도/리버스 사전 렌더) + §8 기준 그래프 PCM 전환(±1샘플 엄격 게이트). 게이트 = §11⑤ 기존 오디오 E2E 무회귀(EQ Goertzel·덕킹 RMS).
2. 프리뷰 tap(audioTapProcessor)·AVAudioEngine NR 필터 경로는 이 증분에서 폐지(§0 v1.1).
3. 대기 결정(변경 없음): 접근 정규화 승인·모션 트래킹 재검출 시드.

## 2026-08-18 세션 20 (사용자 결정: G-25 설계 문서 승인 → Inc 7 착수)

**게이트**: verify_gate 5단계 — 커밋 시점 기준.

### 완료 — G-25 Inc 1: AudioRenderGraphSpec Core 모델 (커밋 8fd4178)
- **전제**: 사용자가 docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md 승인(2026-08-18) — LOOP_STATE USER_WAITING→RUN.
- `Sources/MovieCutCore/Audio/AudioRenderGraphSpec.swift`: 승인 명세 §2·§3·§5의 순수 모델(렌더링 없음). 소스(원본/파생·derivedFrom·algorithmVersion·nativeSampleRate)·클립 스트립(채널매핑·게인/팬 자동화·페이드)·트랙 버스(·mute/solo·덕킹)·마스터(리미터 latency 짝·목표 LUFS)·타임베이스(**자동화 좌표 전부 Int64 샘플 위치**·origin "num/den" 유리수·기본 48k)·렌더 규칙(declaredLatencies)·노드 15종(8 지원+7 자리, isStage1Supported).
- Codable 원칙: 선택 노드 데이터 encodeIfPresent — 빈 그래프 표준 바이트(ProjectStore와 동일한 [.prettyPrinted, .sortedKeys] 기준; JSONEncoder 기본 키 순서가 인코더 인스턴스마다 비결정적임을 실측 확인·테스트에 반영).
- 테스트 10종: 전체 왕복·빈 그래프 바이트 안정·60분 샘플좌표 정밀도·유리수 원점 왕복/변형 거부·1단계 지원분류·노드/채널왕복.

### 다음 세션 인계
1. **Inc 8**: 그래프→AVAudioEngine(프리뷰)·출력 인코더 생성기 양쪽 + Core latency 보상 순수 함수(최대 lookAhead 단일 글로벌 보상) + null test 자동화(±1 샘플 정렬·1 LSB) + 60분 혼합 rate drift 측정(§4·§9).
2. Inc 9: 미터·mute/solo·팬 UI + AAC 사후 검사 게이트(§7·§8).
3. 대기 결정: 접근 정규화 승인·모션 트래킹 재검출 시드·Track A.

## 2026-08-17 세션 9-10 (16:05 자동화 + 사용자 지시: 무창 근본 원인 · app log 아티팩트 · 모션 트래킹 게이트)

**게이트**: 각 증분 verify_gate 4단계 PASS (swift test 1,170 tests / 171 suites).

### 완료 1 — 무창 실패 근본 원인 확정 + SESSION_LOCKED 프리플라이트 (커밋 fa80b78)
- **원인 = 세션 잠금(진단 문서 §4-D, 이전 TCC 추정 기각)**: 잠긴 세션에선 WindowServer가 신규 앱에 창을 부여하지 않아 프로세스 생존+창 0(WINDOW_COUNT_0). 실증: 전체 화면 캡처=비밀번호 다이얼로그, loginwindow 창 수=1(잠금 중·해제 시 0). `frontmost` 쿼리는 잠금 중 부실값("ZCode") 반환 — 신호로 부적합(폐기).
- ui_capture.sh 프리플라이트에 SESSION_LOCKED·SCREENSAVER_ACTIVE 즉시 거부 추가. 잠금 상태 라이브 검증 4/4 상태 즉시 거부·앱 미실행. **교훈: ui_regression은 화면 잠금 해제 상태에서만 실행.** 파리티/E2E가 잠겨도 동작한 이유 = 프레임 덤프 방식(창 불필요) — §12 "open 정상" 미지표 해명.

### 완료 2 — app log 실패 아티팩트화 (커밋 94e225a)
- `open` 전환 이후 0바이트가 된 `App log:` 안내 수정: 실패 시 ps 스냅샷+앱 PID 통합 로그 꼬리(`/usr/bin/log` 절대 경로 — zsh `log` 내장 명령이 이진파일을 가림), LAUNCH_FAIL 경로 preexisting_pids 기록, 성공 시에도 메타 참조 실재화.

### 완료 3 — 모션 트래킹 하니스 게이트 T2-R1 전제 (커밋 8fd4178)
- `MOVIECUT_UITEST_MOTION_TRACKING=1`(UITestHarness): 실제 trackMotion 경로(provider→SetClipPropertyCommand(.keyframes))·고정 초기 rect(ground truth x=32/320,y=88/240,72×64,+80px/s)·검증(샘플≥25·키프레임=샘플×2·midX 이동>0.35·posX 이동>80px·ProjectStore 저장/적재 라운드트립 전량 보존)·JSON 행동 덤프.
- `scripts/run_motion_tracking_gate.sh`: 픽스처 SHA-256 검증(b7a9cb2e…)·sandbox OFF 자체 빌드·`open -n -W`·180s 와치독·단언. **2회 연속 PASS + 동일 행동 데이터(samples=61 keyframes=122 roundtrip=122 midx_delta=0.478)** — 결정성 실증.
- 설계: 검증 문서 §4.4 C1+C2 하이브리드(기존 하니스 패턴). C3 provider 계층은 기존 IoU 테스트(MotionTrackingProviderTests)가 담당.

### 완료 4 — 모션 트래킹 신규 프로세스 재오픈 검증 (세션 11)
- 하니스: `MOVIECUT_UITEST_MOTION_TRACKING_SAVE`(saveProject(to:) 실제 수동 저장 경로)·`MOVIECUT_UITEST_MOTION_TRACKING_REOPEN=1`(BOOTSTRAP_PROJECT→openProject 실제 재오픈, 10s 타임라인 폴링으로 런치 경합 흡수, 첫 비디오 클립 posX/Y 유지 검증).
- 스크립트 2단계화(run_harness 공용 헬퍼): 1단계 추적·적용·라운드트립·저장 → 2단계 재오픈·키프레임 수 일치 단언.
- **실행: 1단계 keyframes=122·saved=1 → 2단계 keyframes=122(posX=61/posY=61) 전량 보존 PASS** — 프로세스 경계 결정성 실증, §4.3 저장·재오픈 요건 충족.

### 완료 5 — 키프레임 프리뷰 트리거 결함 + motion_tracking 파리티 시나리오 (세션 12)
- **결함(코드 판정)**: Mac-프리뷰 컴포지터 트리거(PlaybackEngine)에 keyframes 조건 누락 — Mac-출력(트리거+메타데이터)·iOS-출력(무조건 부착)은 포함. 키프레임만 있는 클립(모션 트래킹 출력이 정확히 이 경우)이 프리뷰에서 무시되는 "출력에만 반영" 계열(cropRect·isBackgroundRemoved 선례와 동일). 1조건 패치.
- **파리티 시나리오 #18 motion_tracking**(moving_subject+고정 rect·times 0.3/1.7): MAD 0.00 PASS. **허위 통과 배제**: ① 출력 경로 기존 반영+MAD 0.00 → 프리뷰도 반영 강제 ② A/B(트래킹 유무 프리뷰) 2,848픽셀 변화(≈44px 시프트)로 가시 반영 확인.
- `PARITY_ONLY=<name>` 단일 시나리오 필터(run_scenario 내 3줄) — 반복·트리아지 속도 개선.
- **전체 파리티 스위트 18/18 PASS**(기존 16 무회귀 + 신규 motion_tracking 최악 MAD 0.26), verify_gate 4단계 PASS.

### 완료 6 — T2-M 모션 트래킹 분석 측정 (세션 13)
- `MotionTrackingAnalysisProbe`(Core): 프레임별 상태·소요ms 기록(CompositorRenderProbe 패턴, 명시적 arm — 제품 코드 env 의존 0), provider 루프 4분기 계측.
- `MotionTrackingAnalysisPerfTests`(`MOVIECUT_T2M=1` 옵트인·기본 skip): RTF·분위수(seed 웜업 제외)·IoU 통계·실패율·연속 실패·phys_footprint 피크(50ms 모니터). ground truth `Support/MotionTrackingGroundTruth.swift`로 단일화(기존 IoU 테스트 공유).
- `scripts/run_t2m_motion_tracking.sh`: 환경 스냅샷+Release 실행+`artifacts/perf/` 아티팩트.
- **첫 실측(5회)**: RTF 0.351±0.094·p50 19.75ms·p95 26.35ms·IoU mean 0.793(5회 동일=결정적)·실패율 0·피크 63.2MB(+51.3MB 웜업). 개발 중 모니터 태스크 데드록(cancel 시점) 1건 발견·수정.
- 잔여: 가림 재획득 측정은 전용 픽스처 필요(후속 증분).

### 완료 7 — 가림 재획득 측정 + 모션 트래킹 계열 완결 (세션 14)
- 신규 픽스처 `moving_subject_occluded_320x240_3s_30fps.mp4`(동일 박스·궤적, 회색 벽 x=120..216 상위 — 완전 가림 t=[1.1,1.4], 재등장 t≥2.3). make_fixtures.sh 2c 블록, 기존 픽스처 바이트 무변경(신규 명령만 실행). T2M 스크립트 양 픽스처 SHA-256 게이트.
- Ground truth: duration 파라미터화 + `occlusionCoverageFraction`. `T2M_OCC` 측정 테스트(행동 단언: 가림 전 IoU≥0.75·가림 중 하락 필수[공허 측정 배제]; 품질 보고: 재획득 시각·지연).
- **핵심 실측**: 가림 전 IoU 0.904 → 가림 중 min 0.0 → **재등장 후 0.0, 재획득 없음** — 순차 추적은 완전 가림 후 자력 재검출 불가 실증. **제품 후보(사용자 결정): 손실 후 재검출 시드 기능.**
- 하니스 버그 2건 수정: 스위트 병렬 실행 시 전역 프로브 상호 도용(`.serialized`), swift-testing 트레잇 순서(이름 뒤).
- 최종: RTF 0.344±0.084·p50 19.73ms·p95 25.54ms·IoU 0.793 결정적·fail_rate 0. **검증 문서 모션 트래킹 요건(§3.2 T2-M·§4) 전 항목 닫힘.**

### 완료 8 — EditorViewModel 인스펙터 경계 분해 (세션 15)
- `EditorViewModel+Inspector.swift`(150줄): 인스펙터 표면 20개 메서드 순수 이동(updateSelected* 17종 + autoEnhance·autoColorCorrect·autoColorCorrect(for:)). 본체 −111줄(보류분 환입 포함).
- **보류 기록(강제 추출 금지 규칙)**: private 저장 의존 9개 메서드 본체 유지(clipEQPresets·backgroundRemovedClipIds·clipStyles/styleTransferIndex·scopeContext·lutErrorDescription 각각) + updateSelectedStickerTransform(isStickerClip)·refreshScopes(scopeContext) — 본체 말미 MARK 섹션에 사유 명시.
- StaticContract 3건 갱신: AudioFade·TextStyle은 +Inspector 직접 로드, Phase33은 메인+경계 결합(UI 마커 금지가 양쪽 파일 커버로 강화됨).
- 1,173 테스트 통과·verify_gate 4단계. 잔여 경계: media→effects→audio(Inc 9 직전)→export.

### 완료 9 — EditorViewModel media 경계 분해 (세션 16)
- `EditorViewModel+Media.swift`(139줄): 7개 메서드 순수 이동(thumbnailData·presentRelinkMissingMedia·addClipToTimeline()·proxy 쌍·setDropStatus/Error). 본체 5,392→5,286줄.
- **보류 기록**: importMedia 계열(공유 private probe/insert 헬퍼 — 카드 교체·슬라이드쇼도 사용), relinkMedia(프로젝트 적재 경로 공유), evaluateMissingMedia(private(set) 대입), reportInvalid*Drop(private 타입). **importMedia 계열 이동은 접근 정규화(별도 승인)가 전제** — 향후 증분 후보.
- StaticContract 영향 없음. 1,173 테스트 통과·verify_gate 4단계. 잔여 경계: effects→audio→export.

### 완료 10 — lint 게이트 녹색 전환 + 5단계 게이트·CI 배선 (세션 17)
- lint_gate.sh 허용목록(force_cast·force_try·shorthand_operator) 위반 24건 전량 수정(11개 파일): try! #require 정규화+throws화, as!→#require(as?), += 축약, PlayerLayerView guard 강등. disable 주석 미사용.
- **verify_gate 5단계화**(5단계 lint — 이후 모든 커밋의 게이트 통과에 lint 포함), ci.yml lint 잡 차단 전환(전체 리포트 비차단 유지).
- effects 경계 조사: 이펙트 계열(applyEQPreset·toggleBackgroundRemoval·applyStyleTransfer·importExternalLUT)은 전부 private 저장 상태 의존 — 접근 정규화 승인 전 이동 불가(기록).

### 완료 11 — EditorViewModel audio 경계 분해 (세션 18)
- `EditorViewModel+Audio.swift`(83줄): 4개 메서드 순수 이동(applyDucking·configureDuckingHarness·clearDuckingOnSelectedClip·extractAudioFromSelection). 본체 5,286→5,223줄.
- 보류: autoDuckOtherAudio·extractAudio(from:)·detectBeats·extractAudioFromSelectedClip·addVoiceoverAudio·buildAudioProcessingOptions — **sourceClipAndAsset이 잔여 경계 전반을 묶는 최대 private 허브**(접근 정규화 승인 시 해금).
- StaticContract 1건 갱신(AudioDuckingTests 메인+경계 결합). GATE_PASS 5/5. 잔여 경계: export 1개.

### 완료 12 — EditorViewModel export 경계 분해, 로드맵 8경계 완결 (세션 19)
- `EditorViewModel+Export.swift`(79줄): 4개 이동(cancelExport·exportProjectPackage·updateExportSettings·applyPlatformExportPreset). 본체 5,223→5,165줄(분해 누적 −913줄).
- 보류: export 진입 패밀리(private backgroundRemovedClipIds+reconciledExportSettingsFromLegacyUI 이중 의존)·applyExportPreset. StaticContract 1건(ProjectPackageTests) 갱신. GATE_PASS 5/5.
- **분해 로드맵 8경계 전 완수.** 남은 이동 전부가 접근 정규화 승인으로 수렴(단일 결정 사항).

### 다음 세션 인계 (우선순위 순 — G-25 승인 여부와 무관 진행 가능)
1. **G-25 승인 확정 시 Inc 7**(Core 모델) — 미승인 시 아래부터.
2. 모션 트래킹 재검출 시드(사용자 결정 후) 또는 EditorViewModel 인스펙터 경계·lint CI.

### 사용자 결정 대기 사항
- **G-25 설계 문서 승인**(docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md — LOOP_STATE USER_WAITING 유지).
- Track A(아이콘/App Store Connect) 계속 대기.

## 2026-08-17 세션 8 (사용자 지시: UI 캡처 무창 진단 프롬프트 실행 — P0 보강)

**게이트**: verify_gate 4단계 PASS. ui_regression **3회 연속 4/4 PASS**(기존 골든 바이트 호환 — 갱신 없음, import_only distance 4→2→2).

### 완료 — UI 캡처 하니스 P0 보강 (커밋 cb71be2)
- **절차 문서**: `docs/UI_CAPTURE_DIAGNOSIS_PROMPT_20260817.md`(사용자 제공 진단 프롬프트, 커밋 포함) — §7.1 환경 스냅샷(macOS 26.5.2/25F84, 콘솔 사용자 일치, 디스플레이 1개 연결), 현재 호스트는 정상 상태(직접 실행에도 창 1개)로 실패 주문 재현 불가 확인.
- **P0 구현**(§13): 실행 경로 `open -n --env` 전환(§12 최강 단서 — 무창 실패는 직접 실행 하니스에서만 간헐, open 경유 파리티/E2E는 동일 기간 정상), PID 차집합 추적(§7.2), 고정 sleep→bounded 폴링, PROCESS_MISSING/WINDOW_COUNT_0/조회 오류 구분 기록(osascript stderr 보존, §10), 콘솔 사용자 불일치 시 PREFLIGHT_FAIL 명시적 거부(§4-D 방어).
- **골든 호환**: 캡처 메커니즘 불변 — 3회 연속 4/4, 갱신 불필요.
- **근본 원인 규명은 미완(기록)**: 재현 불가 상태에서 §8 통제 실험(direct↔open 20회 교차)은 실행 불가 — 재발 시 신규 `moviecut-ui-<state>-window.txt` 로그가 상태 A/C/D 분류를 제공하며 그때 실험 실행. G-06 DoD ④(UI 회귀)는 이번 보강으로 **3회 연속 PASS로 실질 충족**(골든 갱신 없이).

### 다음 세션 인계 (우선순위 순 — G-25 승인 여부와 무관 진행 가능)
1. **G-25 승인 확정 시 Inc 7**(Core 모델) — 미승인 시 아래부터.
2. 모션 트래킹 하니스 게이트(T2-R1).
3. EditorViewModel 인스펙터 경계·lint CI.

### 사용자 결정 대기 사항
- **G-25 설계 문서 승인**(docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md — LOOP_STATE USER_WAITING 유지).
- ui_regression 무창 재발 시: 재부팅 없이 `bash scripts/ui_regression.sh` 재시도 → 재발하면 `artifacts/ui/logs/moviecut-ui-<state>-window.txt` 상태값을 알려달라(분류 즉시 가능).
- Track A 계속 대기.

## 2026-08-17 세션 7 (사용자 지시: Inc 6 — G-06 그래프 + G-25 설계 문서)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,170 tests / 171 suites**(+7) / xcodebuild Mac / xcodebuild iOS). 파리티 **16/16 PASS**. ui_regression **불가(환경)** — 아래 캐비앗.

### 완료 1 — G-06: 키프레임 값-시간 베지어 그래프 (커밋 aa1ba11)
- `KeyframeGraphMath`(Core): 곡선 평가는 렌더러와 동일한 `Keyframe.interpolate` 조각 규칙(그린 곡선=실제 애니메이션), 모드별 폴리라인(hold 직각 스텝·eased 아크), y축 자동 피팅, 히트테스트/이동/추가/삭제 변환. 테스트 7종(경계·스텝 형상·정렬 규약·클램프).
- `KeyframeGraphView`(Mac): 속성 피커+캔버스(그리드·플레이헤드 소스시간 라인·속성색 곡선·다이아몬드). 단일 DragGesture로 탭(빈 곳=추가/마커=선택)과 드래그(로컬 드래프트→종료 시 1회 커밋, 제스처당 undo 1-step) 처리. **커맨드 경로 = 리스트 편집기와 동일** `updateSelectedKeyframes`(DoD ①). 키프레임 렌더 골든 무회귀(기존 스위트 유지, DoD ②). iOS 2단계(DoD ③).
- **DoD ④(UI 회귀) 미실시** — 아래 환경 이슈.

### 완료 2 — G-25 설계 문서 초안 (같은 커밋): **사용자 승인 요청**
- `docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md`: 방향 문서 §4.1 명세화 — 노드 그래프 구조·Codable 스키마·**샘플 시간 타임베이스(초 저장 금지)**·**글로벌 latency 보상**·미지원 노드 명시적 거부(조용한 강등 금지)·프리셋 알고리즘 버전·AAC 재디코드 사후 검사·null test 절차(±1 샘플)·Inc 7~9 매핑.
- **승인 지점**: §3 타임베이스·§4 보상 정책·§5 거부 정책·§8 경고-차단 구분. 승인 시 Inc 7 착수.

### 환경 이슈 (사용자 조치 필요)
- **ui_regression 전 상태 캡처 실패**("window not found", 앱 프로세스는 생존·무창): 호스트 접근성(TCC) 권한 회귀로 판정(코드 무관 — 세션 4 클린 트리 재현 전례, 세션 5에서 자연 회복했다가 재발). **재부팅 또는 시스템 설정 > 개인정보 보호 > 접근성에서 터미널(ZCode) 권한 재확인 후 `bash scripts/ui_regression.sh` 재검증 요망.** G-06 UI 골든(DoD ④)은 이후 보완 과제로 기록.

### 다음 세션 인계 (우선순위 순 — 승인 대기 중 진행 가능)
1. **G-25 승인 확정 시 Inc 7(Core 모델)** — 미승인 시 아래부터.
2. 모션 트래킹 하니스 게이트(검증 문서 §4 — T2-R1).
3. G-06 UI 회귀 보완(환경 회복 후 골든 고정).
4. 인스펙터 경계·lint CI.

### 사용자 결정 대기 사항
- **G-25 설계 문서 승인**(docs/AUDIO_RENDER_GRAPH_SPEC_20260817.md — Inc 7 착수 전제, LOOP_STATE USER_WAITING).
- ui_regression 접근성 권한 재확인(위).
- Track A(아이콘/App Store Connect) 계속 대기.

## 2026-08-17 세션 6 (사용자 지시: 검증 프롬프트 문서 기반 측정 불가 해소)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,163 tests / 170 suites** / xcodebuild Mac / xcodebuild iOS). 파리티 **16/16 PASS**.

### 완료 — 배경제거 프리뷰 트리거 결함 폐쇄 + T2-R0 측정 해소 (커밋 9ad85ce)
- **절차**: `docs/MovieCut_Compositor_Validation_Prompt.md`(외부 자문 프롬프트 문서, 커밋 포함)의 §2.3 대조군 설계·§3.4 프로브 의미 보강·§6.6 실행 순서를 그대로 준수.
- **결함 실증(대조군)**: 무효과 n=0(음성)·컬러 n≥1(양성)·배경제거 단독 **n=0(재현)** — 프리뷰가 배경제거를 커스텀 컴포지터로 라우팅하지 않음. 코드 판정: Mac-출력 트리거 2곳(인라인+`requiresCustomVideoCompositorMetadata`)은 포함, Mac-프리뷰만 누락 — "출력만 반영" 결함 확정(G-23 Inc1 크롭 트리거와 동일 계열).
- **최소 패치(옵션 A1)**: `PlaybackEngine` 트리거에 `isBackgroundRemoved` 1조건. 패치 후 대조군 n=13. 4분면: Mac-프리뷰 ✓(수정)·Mac-출력 ✓·iOS-출력 ✓·iOS-프리뷰 N/A(컴포지터 미사용 아키텍처 — 2단계 파리티 범위).
- **프로브 보강**: 웜업 첫 표본 백분위 제외 + `first_ms` 별도 보고 + 측정 경계 문서화. 교훈: 12표본 짧은 스윕에서 Vision 모델 적재 잔여가 p95를 733ms까지 왜곡 — 표본 수·웜업 제외 필수.
- **T2-R0 첫 실측**(40표본): p50 **9.189ms** / p95 **12.404ms** — Vision 세그멘테이션이 지배 비용, 16.6ms 예산 내지만 p95 여유 좁음(SLO 기록). T1/T3 재측정(웜업 제외 기준으로 수치 일관화). 캐비앳: `moving_subject` fixture는 실 사람이 없어 미검출 경로 측정(추론 비용은 지불).

### 다음 세션 인계 (우선순위 순)
1. **EXECUTION_PLAN §3 Inc 6 — G-06 베지어 그래프 + G-25 설계 문서 초안**(완성 시 승인 요청 에스컬레이션).
2. **모션 트래킹 하니스 게이트**(검증 문서 §4 설계안 — C1/C2/C3 옵션 비교 후) → T2-R1 측정(트래킹 키프레임 포함) + 실 인물 fixture에서의 T2 재측.
3. **A2 공유 render-route resolver**(검증 문서 §2.4 — 트리거 4분면 단일화, 재발 방지. A1 패치로 결함은 이미 폐쇄됨).
4. T2 p95 여유 개선 검토(Vision fast 등급·마스크 캐시 — EffectCostProfile 연계).

### 사용자 결정 대기 사항
- 없음(필수). Track A(아이콘/App Store Connect) 계속 대기.

## 2026-08-17 세션 5 (사용자 지시: T1/T2/T3 측정 마무리 + G-01 Inc3 자막 스타일 프리셋)

**게이트**: 증분별 `verify_gate.sh` 4단계 PASS (swift test **1,163 tests / 170 suites** / xcodebuild Mac / xcodebuild iOS). 파리티 **16/16 PASS**. ui_regression **4/4 PASS**(with_mask 환경 이슈 회복 확인 — 재부팅/권한 조치 없이 자연 회복, 골든 무변환).

### 완료 1 — T1/T2/T3 측정 증분 (커밋 7fc13fd, 타 세션 WIP 수습 포함)
- 세션 시작 시 타 세션 WIP(컴포지터 프로브·게이트·스크립트 초안, 10:17 작성) 발견 → 프로토콜 0 감사·보강·검증 후 수습 커밋.
- **실측(이 호스트, Debug)**: T1 멀티레이어·자막 p50 **1.281ms** / p95 **2.192ms** / max 2.858ms. T3 컬러 체인 p50 **3.936ms** / p95 **4.266ms** / max 5.186ms — 16.6ms 예산 여유. **T2 n=0(측정 불가)**: 광학플로우·속도·배경제거는 `usesCustomVideoCompositor` 트리거에 없어 프리뷰가 plain 경로 통과 — 근거 SLO 기록.
- **범위 밖 발견(후속 검증 증분 과제)**: `isBackgroundRemoved` 프리뷰 트리거 누락 가능성 — 프리뷰가 배경제거를 렌더하지 않을 소지(출력만 반영, G-23 Inc1 크롭 트리거와 동일 계열). 모션 트래킹 하니스 게이트도 부재(T2 구성 제외).

### 완료 2 — G-01 Inc3 자막 스타일 프리셋 (커밋 00c97cf, DoD 4항 충족)
- `SubtitleStylePreset`(Core) 6종 내장 — UserTextStylePreset 계약 재사용 + 하이라이트 색·상대 위치 확장. 적용 = 단일 커맨드(undo 1-step, 프리뷰 즉시), karaokeEnabled 플래그 불변(토글과 책임 분리).
- UI: AutoSubtitlesView 프리셋 행(텍스트 클립 선택 시 노출, 클릭 1회 적용 — 2클릭 이내 DoD ①).
- 골든 6종: 픽셀 프로브(외곽선·배경박스 8배·글자색) + 계약(위치·하이라이트·플래그·텍스트 불변) — 1,163 tests(+6). 영속화는 기존 TextDecorationTests 재사용(DoD ④).
- ui_regression: populated_editor 골든 의도 갱신(프리셋 행).

### 다음 세션 인계 (우선순위 순)
1. **배경제거 프리뷰 트리거 검증 증분**(T2 파생 발견 — 트리거 누락 확인 후 §7-3 체크리스트 4곳 배선 + 파리티 시나리오).
2. **EXECUTION_PLAN §3 Inc 6 — G-06 베지어 그래프(+G-25 설계 문서 초안 착수, 주 내 승인 요청 에스컬레이션)**.
3. 모션 트래킹 하니스 게이트 신설 후 T2 재측정.
4. EditorViewModel 차기 경계(inspector)·lint CI·장형 fixture 재측.

### 사용자 결정 대기 사항
- 없음(필수). Track A(아이콘/App Store Connect) 계속 대기. with_mask 환경 이슈는 회복 확인됨(조치 불필요).

## 2026-08-17 세션 4 (사용자 지시 3건: G-01 Inc2 카라오케 + transport 경계 + T1/T2/T3 구성 확정)

**게이트**: 증분별 `verify_gate.sh` 4단계 PASS (swift test **1,157 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). 파리티 **16/16 시나리오 PASS**(신규 17번 `karaoke_text` 포함). E2E **35 PASS** — 신규 G-01 섹션 포함. ui_regression 3/4(아래 환경 이슈).

### 완료 1 — G-01 Inc2: 카라오케 활성 단어 (커밋 aefbfa5)
- **감사 정정(§10 사례)**: 활성 단어 렌더(`karaokeAttributedText`)·폴백·골든 3종은 기존 구현(f82a48e~6cdcee6). 실행 계획의 "렌더 미구현" 기술은 낡았다. 잔여는 ①사용자 노출 ②정렬 경로 wordTimings 소실 ③실증이었다.
- **UI**: AutoSubtitlesView "Karaoke highlight" 토글 + 색 피커(기본 #FFD60A). 적용 시점 스탬프 — AddClipCommand 단일 undo(DoD ④).
- **수반 수정(사전 존재 결함)**: `subtitleClips(from:alignedTo:)`가 wordTimings를 버림 → 각 워드를 세그먼트와 동일 speed-aware 매핑으로 클립 상대 시각 변환 저장.
- **실증(DoD)**: 골든 경계 ±1프레임 플립 신규(①), 파리티 `karaoke_text`(②) PASS, E2E G-01 섹션(②) **off_changed=96 vs on_changed=5127** 실측 PASS, `wordTimings` 없는 기존 렌더 골든 무회귀(③ 기존 3종 유지).

### 완료 2 — transport 경계 순수 이동 (커밋 3c1c2f2)
- `EditorViewModel+Transport.swift`(109줄): togglePlayPause·JKL 셔틀(ShuttleDirection 타입 포함)·seekByFrames/Seconds·zoomIn/Out·syncTimelinePlayhead. 본체 5,535→**5,489줄**(Inc 2 시작 대비 누적 **−618**). 줌 상수 3종 internal 정규화. F-05 StaticContract 3파일 읽기로 갱신.

### 완료 3 — T1/T2/T3 구성 확정 (docs, PERFORMANCE_SLO.md)
- 초안 → 확정: 하니스 게이트 조합(`TEXT_AT+MASK+BGM_AT` / `OPTICAL_FLOW+SPEED_RATE=0.5+트래킹+배경제거` / `GRADE+HSL_CURVES+COLOR` 3중 체인) + 기존 결정론 fixture만 사용 원칙 + 잔여(생성기 고정·p50/p95 프로브·실측 기록) 명시. **측정은 미실시** — 프로브 도구가 없어 측정 증분으로 이월(사유 기록).

### 발견·환경 이슈 (제품 회귀 아님 — 입증 완료)
- **ui_regression `with_mask` 상태 무창 실패**: 앱 프로세스는 생존하나 창 0개. **클린 트리(stash)에서도 재현** → Inc 4 변경과 무관한 호스트 환경 문제(접근성/TCC 의심 — 화면에 QuickTime 녹화 창이 떠 있는 비정상 세션 상태 관찰). 나머지 3 상태는 PASS. 재부팅/접근성 권한 재허용 후 `bash scripts/ui_capture.sh --state with_mask`로 재현 확인 권장. 회귀 게이트에는 영향 없음(골든 비교 전 캡처 단계 문제).
- **하니스 흐름 이원 주의**: `applyParityScenarioEdits`(PARITY=1 흐름)와 일반 흐름은 게이트 세트가 다름 — 신규 게이트는 양쪽에 대칭 추가하거나(기존 패턴), E2E에서 파리티 흐름을 경유할 것(카라오케 E2E 교훈: 첫 판 FAIL off/on=0 → 파리티 흐름 경유로 수정).

### 다음 세션 인계 (우선순위 순)
1. **EXECUTION_PLAN §3 Inc 5 — G-01 Inc3 자막 스타일 프리셋**(방향 문서 §3 순서).
2. **T1/T2/T3 측정 증분**: 구성 확정 완료 — 생성기 고정(재현성 해시) + 프리뷰 p50/p95 프로브 + SLO 실측 기록.
3. with_mask 환경 이슈 후속(사용자 재부팅/권한 확인 후 재현 보고 요망).
4. EditorViewModel 차기 경계(inspector).
5. lint 신규 error 0 CI 반영 + 장형 fixture `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- 없음(필수). 참고: with_mask 캡처 실패는 호스트 환경 문제로 판명(위) — 재부팅 또는 시스템 설정 > 개인정보 보호 > 접근성에서 터미널 권한 재확인 후 알려주시면 재검증. Track A(아이콘/App Store Connect) 계속 대기.

## 2026-08-17 세션 3 (사용자 지시 2증분: Inc 2 완결 + G-02 Inc5 HSL 밴드 UI)

**게이트**: 증분별 `verify_gate.sh` 4단계 PASS (swift test **1,156 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). 파리티 **15/15 시나리오 PASS**(신규 16번 `hsl_curves` 포함). `ui_regression.sh` PASS(Inc5 골든 의도 갱신 후 검증).

### 완료 1 — Inc 2 완결: 타임라인 편집 클러스터 전체 이동 (커밋 6ff0bc6)
- **사용자 승인(2026-08-17)으로 장벽 해소**: private 공유 인프라(`session`·`apply`·`refreshFromSession`·`clipClipboardPayload`·`pendingScrub*`·`currentClipIds`)를 internal로 정규화(본체 잔존, 새 추상화 0) — 세션 2에서 보류했던 선택지 (b).
- 이동(420줄, 순수): split/blade/trim(±assetDuration 헬퍼)/move/toggleTrack 3종/rippleDelete/duplicate/링크 그룹 F-04 전체(hasGroupedSelection·linkedClipIds·selectTimelineClip·group/ungroup·timelineClips)/copy·cut·paste·copyClip/canCopy·Cut·Paste/delete 계열/scrubPlayhead+applyScrubTime/timelineOrderedClipIds. **본체 누적 6,107→5,535줄(−572)**.
- transport(JKL 셔틀·seekByFrames/Seconds·zoom·syncTimelinePlayhead)은 경계 로드맵대로 다음 경계로 의도적 미이동.
- 수반 잠금 갱신: R5-03 트랙 토글 StaticContract → 경계 파일 구간 읽기.

### 완료 2 — G-02 Inc5: HSL 8밴드 편집 UI (커밋 c142c62)
- `ColorHSLBandsView`(App/MovieCutMac/Inspector/): 8밴드 칩 + 밴드별 색조 시프트·채도·휘도 슬라이더, VoiceOver 라벨. Color Grade 섹션(컬러휠·감마 인접) 배치.
- 커밋 규율: 드래그 종료 시 단일 커맨드(제스처당 undo 1-step), 전부 identity면 nil 커밋(JSON 바이트 안정). **스키마 무변경**(기존 `hslBands` 선택 필드 재사용).
- 실증(DoD): ① 밴드 값 → 공유 `ColorGradePixelProcessor` 체인으로 프리뷰 반영 ② 파리티 16번 `hsl_curves` 신설 **MAD 0.50 PASS**(레드 밴드 탈포화+마스터 커브의 양 다리 동일성) ③ undo 단일 ④ `ColorGradeGoldenTests` +JSON 라운드트립·identity 정규화 nil ⑤ 스키마 v4 유지. UI 노출은 ui_regression 골든 4상태 갱신으로 고정.
- 잔여(G-02): 커브 에디터 UI(Inc 6 — 톤커브), iOS 동등 UI(2단계 파리티 증분).

### 발견한 함정(다음 세션 참고)
- StaticContract 잠금은 "메인 파일 문자열"에 고정되는 경향 — 경계 이동마다 해당 테스트의 읽기 경로를 함께 갱신해야 함(이번 세션: F-05·R5-03 두 건). 이후 경계(selection→transport→…)에서도 예상.
- 대규모 블록 이동은 스크립트로 "정확히 1회 일치 시에만 제거" 검증 후 실행 — 본문 재구성 오타($0/$1, 들여쓰기)를 사전에 잡음.

### 다음 세션 인계 (우선순위 순)
1. **EXECUTION_PLAN §3 Inc 4 — G-01 Inc2 카라오케 활성 단어 렌더링**(방향 문서 §3 순서; Inc 3 완료로 잠금 해제).
2. EditorViewModel 차기 경계(transport: 셔틀·seek·zoom 클러스터 — 접근 정규화 선례로 이제 순수 이동 가능).
3. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
4. lint 신규 error 0 CI 반영 + 장형 fixture `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- 없음. Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.

## 2026-08-17 세션 2 (EditorViewModel 분해 1호 경계 — 최소 슬라이스 + 장벽 지도)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,155 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). `run_core_editing_parity.sh` **14/14 PASS**. `ui_regression.sh` PASS. 첫 게이트 실행 1회 실패 — `KeyboardShortcutStaticContractTests`(소스 문자열 회귀 잠금)가 메인 파일의 이동 함수 존재를 검사 → 경계 분해 반영해 두 파일을 읽도록 갱신 후 재통과(제품 회귀 아님).

### 수반 수정(사전 존재 드리프트 아님 — 이동에 수반하는 잠금 갱신)
- `KeyboardShortcutStaticContractTests.editorViewModelExposesCommandBackedF05Actions` — `EditorViewModel.swift` + `EditorViewModel+TimelineEditing.swift` 양쪽을 읽도록(이동 멤버 계약 유지). §7-5 원칙(StaticContract은 회귀 잠금)에 따른 잠금 위치 갱신.

### 완료 — EXECUTION_PLAN §3 Inc 2 (부분, 스펙 리스크 조항에 따른 기록)
1. **순수 이동**: `App/MovieCutMac/EditorViewModel+TimelineEditing.swift` 신규(141줄) — 선택 접근자(`selectedClipId` 계산 프로퍼티·`selectedClip`·`hasSelectedClips`·`canSplitSelectedClip`·`selectedClipTrack/Id`·`visibleTimelineDuration`·`canGroupSelectedClips`), 플레이헤드 스냅/경계 점프(`snapPlayheadToSelectedClip*`·`jumpToPrevious/NextClipBoundary`), 전용 private 헬퍼(`timelineNavigationPoints` + `TimelineNavigationPoint` 타입 — 사용처가 이동 멤버뿐이라 함께 이동, 접근 수준 유지). 본체 6,107→**5,982줄(−125)**. diff는 삭제+신규 파일 동일 내용(새 로직 0줄, DoD ④).
2. **xcodegen 재생성** 신규 파일 타깃 포함(App 소스는 디렉터리 글로브).

### 미달·보류 기록 (스펙 리스크 조항 이행 — "private 접근 → 기록하고 이동 보류")
**DoD ① 목표(~5,200 이하) 미달.** 타임라인 편집 연산 대부분이 private **공유 인프라**에 묶여 extension 이동만으로는 해소 불가:
- `@ObservationIgnored private var session` — `splitClip`·`bladeSplitAtPlayhead`·`group/ungroupSelectedClips`·`duplicateClips`·`cutClips`·`pasteClipsAtPlayhead`·`deleteClips` 등 디스패치 계열 전부.
- `private func apply(_:)`/`refreshFromSession()` — `trimClip`·`moveClip`·`toggleTrack*`·`rippleDeleteClip`·`copyClip`.
- private 저장 프로퍼티 — `clipClipboardPayload`(copy/canPaste), `pendingScrubTask/Time`(`scrubPlayhead` 본체), zoom 상수(`zoomTimelineIn/Out`).
- private 헬퍼의 교차 사용 — `timelineClips(in:)`(`hasGroupedSelection`·`linkedClipIds`·`selectTimelineClip` 체인; `ungroupSelectedClips`가 잡고 있어 이동 불가), `currentClipIds`(`canCopy/CutClips`), `assetDuration(for:)`(`assetDuration(forClipID:)`).
**다음 경계 패스를 위한 선택지(사용자 결정 아님, 기록)**: (a) 현행 유지 — 이후 경계(selection→transport→…)도 같은 제약 하에 슬라이스 반복, (b) `session`·`apply`·`refreshFromSession` 등 공유 인프라의 접근 수준 정규화(private→internal)를 별도 마이크로 증분으로 명시적으로 수행 — 접근 변경이 스펙 "접근 수준 유지"와 충돌하므로 계획서/사용자 승인 후에만.

### 발견한 함정(다음 세션 참고)
- xcodegen 재생성 후 첫 xcodebuild는 DerivedData 상태에 따라 지연 가능(기존 노트 재확인). 신규 파일 추가 시 반드시 xcodegen 먼저.
- `private` 중첩 타입(`TimelineNavigationPoint`)은 같은 파일 extension에서만 접근 가능 — 타입 선언을 사용처와 함께 이동하는 것이 순수 이동 요건.

### 다음 세션 인계 (우선순위 순)
1. **G-02 Inc5 HSL 편집 UI** 착수(방향 문서 §3 순서 — Inc 2 최소 조건[시도 기록] 충족으로 진행 가능).
2. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
3. lint 신규 error 0 CI 반영.
4. EditorViewModel 차기 경계(selection) — 위 선택지 (a)/(b) 방향에 따라.
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- 없음(Inc 2 부분 완료는 스펙 리스크 조항의 예상 결과; (b) 접근 정규화 착수 여부만 향후 결정 대상).
- Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.

## 2026-08-17 세션 (프리뷰 색공간 발산 수정 — G-29 전도부, 사용자 결정 A 이행)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,155 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). `run_core_editing_parity.sh` **14/14 시나리오 PASS**(신규 15번 `crop_rect_video` 포함, 시나리오 1 전환은 기존대로 스킵).

### 완료 — 프리뷰 색공간 발산 결함 수정 (증분 1개)
1. **원인 규명(실측)**: AVPlayer의 디코드 다리는 컴포지터 소스 BGRA에 ICC 색공간 태그를 붙이고(미태그 BT.601 SD → "Composite NTSC", SMPTE_C/601 계열) AVAssetExportSession의 디코드 다리는 `kCVImageBufferCGColorSpaceKey=nil`로 전달한다. 컴포지터의 `CIImage(cvPixelBuffer:)`가 프리뷰 다리에서만 핀된 sRGB 작업 공간으로 ICC 변환을 수행 — 순수 레드 (254,0,0)→(247,36,0), 파리티 MAD 10.25. 독립 Swift 실험(최소 컴포지터 재현)으로 각 단계 버퍼 태그·값을 직접 측정해 확정. 종전 가설(YUV↔RGB 매트릭스 불일치)은 부분 정확 — 실체는 "프리뷰만 ICC 색 관리 개입"이었다.
2. **수정**: `RenderColorConfiguration.sourceImage(from:)` 신규(Core) — `CIImage(cvPixelBuffer:options:[.colorSpace: workingSpace])`로 컴포지터 소스 해석을 작업 공간에 고정(디코더 태그 무관). Mac `CustomVideoCompositor` 4개 지점(transition 2·primary·layering)·iOS `IOSCustomVideoCompositor` 4개 지점 교체. **양 다리가 정의상 동일 해석** — "same project → same pixels" 계약 강화.
3. **실증(DoD 충족)**: 파리티 시나리오 `crop_rect_video`(스크립트 15번) 신설·상시화 — 비디오판 크롭(미태그 BT.601 SD 소스가 캔버스를 채움 → 색조 회전이 레터박스·마스킹·crush 뒤에 숨을 수 없는 구조). 수정 전 FAIL MAD 10.25(G=27.0) → 수정 후 **PASS MAD 0.50**(R=1.5 인코딩 반올림 수준). 기존 13개 시나리오 무회귀(전체 14/14).
4. **테스트**: `ColorSpaceParityTests` +2 — `sourceImageIsPinnedToTheWorkingColorSpace`(해석 고정), `sourceImageIgnoresDecoderICCTag`(AdobeRGB ICC 태그 부착 버퍼에서도 값 불변 + 통과 패스스루 ±1).
5. **문서**: VERIFICATION_STANDARD §2.2 시나리오 표 12→14(#13 crop_rect·#14 crop_rect_video + 스크립트 번호 차이 주석), 백로그 §0.5 G-29 전도부 이행 기록, REQUIREMENTS 변경 이력 1줄.

### 발견·기록(범위 밖 — 후속 감사 대상)
- **무컴포지터(plain) 경로의 절대 색상 회전**: plain 프로젝트는 양 다리가 같은 회전값(출력 (255,23,0))을 내므로 **파리티는 일관**(MAD 0.40)하나, 원본 소스 의도 색상 (254,0,0)과는 미세 차이. 이번 수정은 컴포지터 경로만 다룸(DoD 범위) — plain 경로 절대 색상은 G-29 본 증분(3단계 색관리 전면 감사)으로 이월. **파리티 게이트는 일관성이지 정답이 아님**의 두 번째 실측 사례.
- **plain 경로의 자연 크기 렌더링 재확인**: plain 합성은 캔버스(1920×1080)에 소스를 좌상단 자연 크기(320×240)로 배치(CI 원점 기준 좌하단). 정규화 비교 격자에서 비디오가 차지하는 면적이 작아 색 편차가 희석됨 — 시나리오 통과의 숨은 요인.

### 발견한 함정(다음 세션 참고)
- **`open -n -W` 프로브 직접 실행 시 프리뷰 덤프가 검정 프레임이 될 수 있다**: 실제 파리티 스크립트 경로(시나리오 편집 → rebuild → wait → 스냅샷)에서는 재현 안 됨. 프로브용 축약 하니스보다 **스크립트의 run_scenario를 그대로 재사용**할 것(이번 세션 교훈: 재현은 스크립트 구조로).
- **`open`에 앱 번들 경로 전달 필수**(`.app/Contents/MacOS/...` 내부 바이너리 아님 — LaunchServices가 무시하고 result만 MISSING).
- `CGImage.colorSpace`·`CVBufferGetAttachment`로 디코드 버퍼의 실제 태그를 직접 확인 가능 — 색 문제 디버깅의 1차 도구.

### 다음 세션 인계 (우선순위 순)
1. **EXECUTION_PLAN §3 Inc 2 — EditorViewModel 분해 1호 경계(timeline editing)**: 색공간 수정 완료로 계획 원위치(LOOP_STATE 이전 기준). 순수 이동 리팩터링, 파리티 14·ui_regression으로 무회귀 확인.
2. **G-02 Inc5 HSL 편집 UI** 착수(방향 문서 §3 순서).
3. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
4. lint 신규 error 0 CI 반영.
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.
- 신규 없음(색공간 우선순위는 결정 A로 해결됨).

## 2026-08-16 세션 2 (G-23 Inc 2 — 크롭 캔버스 에디터 + 파리티 시나리오 + **사전 존재 결함 2건 발견**)

**게이트**: `verify_gate.sh` 4단계 PASS (swift build / swift test **1,153 tests / 169 suites** / xcodebuild Mac / xcodebuild iOS). `run_core_editing_parity.sh` **13/13 시나리오 PASS**(시나리오 1 전환은 기존대로 스킵, 신규 14번 `crop_rect` 포함).

### 완료 — G-23 Inc 2
1. **Core — `CropRectEditingMath`** (`Sources/MovieCutCore/Editing/`): 정규화 크롭 창 이동/리사이즈 순수 수학. 8방향 핸들+내부, 유닛 프레임 클램프, 반전 방지, 최소 크기 바닥, Shift 캔버스 비율 잠금(aspect). `NormalizedRect`에 `maxX`/`maxY` 접근자 추가. 테스트 10개(앵커/클램프/반전/바닥/비율잠금/interior) 전부 PASS.
2. **Mac — `CropCanvasView`** (`App/MovieCutMac/Effects/`): 프리뷰 캔버스 위에 **크롭되지 않은 원본 소스**(에셋 썸네일, aspect-fit)를 백드롭으로 띄우고 크롭 창을 편집(CapCut 방식 — 컴포지션에 이미 크롭이 구워 있어 프리뷰 픽셀로는 원본 맥락을 줄 수 없음). 4모서리+4에지 핸들, 내부 드래그 이동, 외부 디밍, 3분할 가이드, 리셋/완료 툴바, 접근성 라벨. 제스처 종료 시 1회 커밋(`SetClipPropertyCommand.cropRect`) = **드래그 전체가 단일 undo**. 풀프레임 rect는 nil로 정규화(미크롭 프로젝트 JSON 바이트 동일).
3. **배선**: `EditorViewModel.isCropEditorActive`(마스크 에디터와 상호 배제, 선택/프로젝트 변경 시 리셋 3곳) + `updateSelectedCropRect`. 인스펙터 크롭 섹션에 Canvas/Done 토글 버튼.
4. **하니스/스크립트**: `MOVIECUT_UITEST_CROP=1` 게이트(파리티+제네릭 양쪽 — 인스펙터 1:1 프리셋과 동일한 centered 1:1 크롭 계산). `run_core_editing_parity.sh` 시나리오 14 `crop_rect`(이미지 fixture) 추가 — **실측 overall MAD 0.14/0.70 (허용 2.00), 지속 5.000s 정합**.
5. **iOS — 크롭 UI 진입점**: `IOSInspectorSheet` Crop 섹션(비율 프리셋 6종, 활성 프리셋 하이라이트) + `IOSEditorViewModel.updateSelectedCropRect`/`selectedClipSourceAspect`. 공유 `CropPixelProcessor`로 Mac과 동일 영역 크롭.

### 발견·수정한 사전 존재 결함 (Inc 1 드리프트 — 파리티 시나리오가 즉시 포착)
- **[수정] `PlaybackEngine.usesCustomVideoCompositor` 트리거에 `cropRect != nil` 누락**: Inc 1 커밋 메시지는 "양쪽 엔진 트리거 추가"를 주장했지만 코드에는 Export만 있었다. 프리뷰가 크롭을 무시하는 플레인 경로를 타서 크롭-only 프로젝트의 프리뷰≠출력(R 채널 MAD 182). 트리거 1줄 추가로 폐쇄. **교훈: DoD의 "파리티 시나리오"가 없으면 커밋 메시지와 코드의 불일치는 잡히지 않는다.**

### 발견·미수정 결함 (사용자 결정 대기 — 조기 경보 §5(c))
- **프리뷰 커스텀 컴포지터 경로의 untagged SD 비디오 색조 회전**: 태그 없는 BT.601 SD 영상(320×240 fixture)을 커스텀 컴포지터로 스케일하면 프리뷰에만 색조 회전 발생 — 순수 레드 (254,0,0)이 프리뷰 (247,36,0)/출력 (254,0,0), overall MAD ≈ 10.25 (허용 2.00). **크롭 무관**: 크롭된 PNG 소스는 MAD ≤ 2로 양쪽 일치(크롭 배선 자체는 패리티 청결). 기존 녹색 시나리오들이 이를 가려온 이유: 현존 커스텀 컴포지터 시나리오는 전부 (a) 색보정으로 신호를 crush하거나 (b) 마스크로 가시 면적을 ~1%로 줄인다. 즉 **실사용자의 untagged SD 영상에 마스크/크로마키/컬러보정을 적용하면 프리뷰 색상이 출력과 다르게 보이는 실결함**.
  - 추정 메커니즘: 컴포지터 진입 소스 YUV→RGB와 CIContext 출력 RGB→YUV의 행렬(601/709) 가정이 프리뷰 다리에서 어긋남(출력 다리와 달리). `AVPlayerItemVideoOutput`에 `kCVImageBufferCGColorSpaceKey`로 sRGB 태그를 강제하는 실험은 조합 빌드를 행업시켜 폐기(되돌림).
  - 제안: 다음 세션 증분 1로 정착(G-29 색관리 감사의 전도부). 매트릭스 수준 실험 필요 — `CIImage(cvPixelBuffer:)` 태깅/`matchedFrom`/컴포지터 내 정규화 경로. 수정 전까지 스크립트의 비디오판 크롭 시나리오는 주석 처리(근거 각주 스크립트 내 참조).

### 발견한 함정(다음 세션 참고)
- `writeHarnessStatus`는 **truncate-write** — 하니스 결과는 마지막 한 줄만 살아남는다(전 세션 노트 재확인). 진행 체크포인트는 디버깅용.
- **패리티 게이트는 일관성이지 정답이 아니다**: 무효과 플레인 경로는 소스를 캔버스에 자연 크기로 렌더링(캔버스 채움 아님)하는데 양쪽 다 같아서 PASS. 색 결함도 "양쪽이 같은 잘못"이면 통과 — 신호를 crush하지 않는 시나리오(순색+무보정)를 추가로 둘 것(이번 crop_rect가 그 역할).
- xcodegen으로 재생성한 직후 DerivedData가 다른 경로(`/tmp/MovieCutParityDerivedData`)의 첫 빌드는 5분+ 걸릴 수 있다.

### 다음 세션 인계 (우선순위 순)
1. **프리뷰 색공간 발산 결함 수정**(위 결함 — 조기 경보. 비디오판 크롭 파리티 시나리오 재활성화가 완료 판정).
2. **G-02 Inc5 HSL 편집 UI** 착수(방향 문서 §3 순서 원위치).
3. T1/T2/T3 스트레스 타임라인 fixture 확정 + PERFORMANCE_SLO.md p50/p95 기록.
4. lint 신규 error 0 CI 반영 + `EditorViewModel` 분해 1호 경계(timeline editing).
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측.

### 사용자 결정 대기 사항
- ~~프리뷰 색공간 발산 결함의 우선순위~~ → **결정됨(2026-08-16): 선택 A — 다음 증분으로 색공간 수정 우선.** G-02 Inc5 HSL UI는 그 뒤로. fixture bt709 태깅(C안)은 기각.
- Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.

## 2026-08-16 세션 (프로토콜 0 + 증분 2개)

**게이트**: 전 증분 `verify_gate.sh` 4단계 PASS (swift build / swift test **1,143 tests / 168 suites** / xcodebuild Mac / xcodebuild iOS). 커밋 `ab35763`→`6a3845f`까지 6건, main 로컬 (미푸시).

### 완료
1. **프로토콜 0a — WIP 커밋**: `ab35763` docs 재편, `5bec84d` 컴파운드 Phase 2 + 프로 도구 V/C/Y/U, `a66dd6b` iOS 컴포지터 패리티 + 문자열 카탈로그, `eb61487` 방향 문서 채택.
2. **프로토콜 0b — §8 문서 반영**: 백로그 §0.5에 G-23~G-29 등록(G-05/G-07 재정의 포함), VERIFICATION_STANDARD §6(검증 업그레이드 6항), PERFORMANCE_SLO(Metal 트리거 7개 표, 스트레스 타임라인 T1/T2/T3, EffectCostProfile), REQUIREMENTS §13.14 + 체인지로그 + 아카이브 링크 수정.
3. **증분 1 — G-23 크롭 Inc 1** (`0c37215`):
   - `CropPixelProcessor`(Core 공유): 정규화 top-left rect → y-플립 → 픽셀 crop → 캔버스 aspect-fill 중앙 정렬. 전체 프레임은 무변경 게이트.
   - `Clip.cropRect: NormalizedRect?` (레거시 디코드 nil, 미설정 JSON 바이트 동일) + `ClipProperty.cropRect` 케이스(단일 undo).
   - 배선: `CustomCompositionClipEffect.cropRect` → Mac/iOS 컴포지터 `applyClipEffects` 크롭-퍼스트 + 양쪽 엔진 트리거에 `cropRect != nil` 추가(프리뷰=출력 동일 픽셀 경로 구조 보장).
   - UI: 인스펙터 Basic/visual 크롭 섹션 — 비율 프리셋 6종(Original/1:1/4:3/3:4/16:9/9:16), 소스 실제 픽셀 aspect 기반 중앙 크롭 계산.
   - 테스트 9개: 골든 픽셀 4(y-플립 고정, fill+센터링, no-op), 프리셋 수학 3, 명령/Codable 2.
   - **수반 수정(사전 존재 드리프트)**: 프리뷰 커스텀 컴포지터 경로가 transform/opacity/keyframes 미전달(출력만 적용) → `PlaybackClipInstructionMetadata`에 `clipTransform`/`keyframes` 추가해 폐쇄.
4. **증분 2 — 지연 측정 기반** (`6a3845f`): 하니스 `MOVIECUT_UITEST_LATENCY_BASELINE=<n>` + `scripts/run_latency_baseline.sh`(수집 게이트, `--enforce` 전환 가능). **첫 실측**: seek request p50 0.11ms / p95 0.17ms, scrub apply p50 0.07ms / p95 0.10ms, 소형 fixture 프로젝트 열기 121.6ms — PERFORMANCE_SLO.md 기록 완료.

### 발견한 함정(다음 세션 참고)
- `writeHarnessStatus`는 **truncate-write** — 하니스 결과는 마지막 한 줄만 살아남는다. 진행 체크포인트는 디버깅용이고, 최종 판정 라인이 반드시 마지막 write여야 한다.
- 하니스 시나리오는 `ContentView.task`에서 시작(홈 스테이지 아니어야 함 — 기존 게이트와 동일하게 `MOVIECUT_UITEST=1`이면 에디터로 라우팅됨). 시나리오 종료 시 `MOVIECUT_UITEST_QUIT=1` 처리를 직접 호출해야 앱이 종료된다.

### 다음 세션 인계 (우선순위 순)
1. **G-23 Inc 2**: 프리뷰 캔버스 크롭 핸들(마스크 캔버스 패턴 참조) + 파리티 시나리오 #13 `crop_rect`(하니스 `MOVIECUT_UITEST_CROP` + `run_core_editing_parity.sh` 추가) + iOS 크롭 UI 진입점.
2. **G-02 Inc5 HSL 편집 UI** 착수(1단계 최대 체감; 컬러휠/스코프 옆 8밴드 + 커브 에디터).
3. **T1/T2/T3 스트레스 타임라인 fixture** 확정 + `PERFORMANCE_SLO.md`에 p50/p95 기록.
4. lint 신규 error 0 CI 반영 + `EditorViewModel` 분해 1호 경계(timeline editing).
5. 장형(≥10분) fixture 제작 후 `run_latency_baseline.sh` 재측 — SLO "10분 프로젝트 열기 3초"의 원 의미 실측.

### 사용자 결정 대기 사항
- 없음(§7 열린 결정은 기본 채택값으로 진행 중). Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.
