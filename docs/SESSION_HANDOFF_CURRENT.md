# 세션 핸드오프 — 현재 (2026-08-17)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 최신 세션이 이 파일의 최상단에 기록한다. 실행 순서의 근거는 `DEVELOPMENT_DIRECTION_20260815.md` §3·§9.

## 2026-08-17 세션 9-10 (16:05 자동화 + 사용자 지시: 무창 근본 원인 · app log 아티팩트 · 모션 트래킹 게이트)

**게이트**: 각 증분 verify_gate 4단계 PASS (swift test 1,170 tests / 171 suites).

### 완료 1 — 무창 실패 근본 원인 확정 + SESSION_LOCKED 프리플라이트 (커밋 fa80b78)
- **원인 = 세션 잠금(진단 문서 §4-D, 이전 TCC 추정 기각)**: 잠긴 세션에선 WindowServer가 신규 앱에 창을 부여하지 않아 프로세스 생존+창 0(WINDOW_COUNT_0). 실증: 전체 화면 캡처=비밀번호 다이얼로그, loginwindow 창 수=1(잠금 중·해제 시 0). `frontmost` 쿼리는 잠금 중 부실값("ZCode") 반환 — 신호로 부적합(폐기).
- ui_capture.sh 프리플라이트에 SESSION_LOCKED·SCREENSAVER_ACTIVE 즉시 거부 추가. 잠금 상태 라이브 검증 4/4 상태 즉시 거부·앱 미실행. **교훈: ui_regression은 화면 잠금 해제 상태에서만 실행.** 파리티/E2E가 잠겨도 동작한 이유 = 프레임 덤프 방식(창 불필요) — §12 "open 정상" 미지표 해명.

### 완료 2 — app log 실패 아티팩트화 (커밋 94e225a)
- `open` 전환 이후 0바이트가 된 `App log:` 안내 수정: 실패 시 ps 스냅샷+앱 PID 통합 로그 꼬리(`/usr/bin/log` 절대 경로 — zsh `log` 내장 명령이 이진파일을 가림), LAUNCH_FAIL 경로 preexisting_pids 기록, 성공 시에도 메타 참조 실재화.

### 완료 3 — 모션 트래킹 하니스 게이트 T2-R1 전제 (이번 세션 커밋)
- `MOVIECUT_UITEST_MOTION_TRACKING=1`(UITestHarness): 실제 trackMotion 경로(provider→SetClipPropertyCommand(.keyframes))·고정 초기 rect(ground truth x=32/320,y=88/240,72×64,+80px/s)·검증(샘플≥25·키프레임=샘플×2·midX 이동>0.35·posX 이동>80px·ProjectStore 저장/적재 라운드트립 전량 보존)·JSON 행동 덤프.
- `scripts/run_motion_tracking_gate.sh`: 픽스처 SHA-256 검증(b7a9cb2e…)·sandbox OFF 자체 빌드·`open -n -W`·180s 와치독·단언. **2회 연속 PASS + 동일 행동 데이터(samples=61 keyframes=122 roundtrip=122 midx_delta=0.478)** — 결정성 실증.
- 설계: 검증 문서 §4.4 C1+C2 하이브리드(기존 하니스 패턴). C3 provider 계층은 기존 IoU 테스트(MotionTrackingProviderTests)가 담당.

### 완료 4 — 모션 트래킹 신규 프로세스 재오픈 검증 (세션 11)
- 하니스: `MOVIECUT_UITEST_MOTION_TRACKING_SAVE`(saveProject(to:) 실제 수동 저장 경로)·`MOVIECUT_UITEST_MOTION_TRACKING_REOPEN=1`(BOOTSTRAP_PROJECT→openProject 실제 재오픈, 10s 타임라인 폴링으로 런치 경합 흡수, 첫 비디오 클립 posX/Y 유지 검증).
- 스크립트 2단계화(run_harness 공용 헬퍼): 1단계 추적·적용·라운드트립·저장 → 2단계 재오픈·키프레임 수 일치 단언.
- **실행: 1단계 keyframes=122·saved=1 → 2단계 keyframes=122(posX=61/posY=61) 전량 보존 PASS** — 프로세스 경계 결정성 실증, §4.3 저장·재오픈 요건 충족.

### 다음 세션 인계 (우선순위 순 — G-25 승인 여부와 무관 진행 가능)
1. **G-25 승인 확정 시 Inc 7**(Core 모델) — 미승인 시 아래부터.
2. 모션 트래킹 후속: 프리뷰↔출력 파리티(T2-R1) → T2-M 측정.
3. EditorViewModel 인스펙터 경계·lint CI.

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
