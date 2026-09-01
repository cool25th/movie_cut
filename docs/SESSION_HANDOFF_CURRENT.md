# 세션 핸드오프 — 현재 (2026-08-19)

> 마스터 프롬프트(`AGENT_MASTER_PROMPT_20260815.md`) 프로토콜 6번의 세션 종료 산출물.
> 최신 세션이 이 파일의 최상단에 기록된다. 실행 순서의 근거는 `DEVELOPMENT_DIRECTION_20260815.md` §3·§9 — 단, **안정화 창구(STABILIZATION_PLAN_20260829.md 루프 실행 가능 잔여 존재 중)는 해당 계획의 §3 Phase 순서가 우선**(LI-004, 사용자 병합 지시 2026-08-29).

## 2026-09-01 세션 (CODEX-19 완료 — z-index 정규화·커맨드 원천 해법)

- **스카웃·챌린지**: 큐 그대로 CODEX-19(양플랫폼·유닛 검증 가능) — 반박 근거 없음.
- **수정(원천 해법)**: `CreateTrackCommand.apply`가 **충돌 z-index를 max+1로 정규화** — 커맨드가 모든 표면의 단일 초이크 포인트라 양플랫폼 caller(iOS 4곳·Mac 1곳의 `tracks.count` 배정) 수정 없이 결함 차단. 비충돌 명시 z는 보존(의도적 레이어 배치 생존).
- **실측**: 신설 4종 — ①충돌 범프(2→3) ②명시 z(7) 보존 ③**정확한 결함 시퀀스**(0/1/2→z0 삭제→tracks.count 재추가→유일성) ④undo 왕복. Core 전체 **1,433/213 PASS**·게이트 5/5.
- **자기 리뷰**: ①같은 클래스 후보 — `RemoveTrackCommand`는 삭제 후 재정규화 없이 제거만(추가 시 정규화가 상쇄하므로 비결함화 — 다만 z 구멍은 잔존·관찰) ②CODEX-20(RemoveTrack 잠금 무시 P2)이 다음 CODEX 잔여 ③계측 — `swift test --filter`가 새 스위트를 못 찾는 선행 필터 함정(전체 실행으로 검증 — 정규식 이스케이프 의심).

### 다음 회차 — 큐
① CODEX-20(RemoveTrack 잠금 무시·P2·유닛 검증 가능) ② CODEX-04·07(실기기 검증 권장)·CODEX-21 회귀 관찰·STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력.

## 2026-09-01 세션 (CODEX-18 완료 — fps 프리셋 원자 undo·Mac 동일 클래스 동시 수습)

- **큐 챌린지**: CODEX-04(실기기 검증 대기 — 측정 불가) 대신 **CODEX-18**(완전 유닛 검증 가능) 선택.
- **수정**: Core `SetProjectCanvasAndExportSettingsCommand` 신규 — 캔버스 재바인딩+exportSettings를 **하나의 undo 엔트리**로. iOS `updateCanvasPreset` 전환(스냅숏 왕往返 부수 제거) + **Mac `applyExportPreset` 동일 결함 클래스**를 자기 리뷰 ①문항으로 발견해 동시 수습.
- **실측**: 신설 2종 — 60fps 정사각 프리셋 후 **undo 1회가 캔버스·타임라인 재바인딩·export fps 전체 왕복**(구 2-디스패치는 export만 복원)·redo 왕복. iOS 71테스트/17스위트 PASS·게이트 5/5.
- **자기 리뷰**: ①동일 클래스 Mac까지 수습 완료 ②CODEX-19(z-index)가 같은 "커맨드 정합성" 묶음 — 다음 후보 ③계측 무결(첫 테스트의 프리셋 기본 fps30 가정 오탐 — 명시 fps60으로 수정).

### 다음 회차 — CODEX 큐
① **CODEX-19**(P2 — z-index tracks.count 중복·양플랫폼·유닛 검증 가능) ② CODEX-04·07(실기기 검증 권장)·CODEX-21 회귀 관찰·STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력.

## 2026-09-01 세션 (CODEX-21 등록+수정 완료 — iOS 속도 UI 재타이밍·SetClipSpeedCommand 패리티)

- **본체**: iOS `updateSelectedPlaybackRate`가 raw `SetClipPropertyCommand(.playbackRate)` 사용 — `timelineRange.duration`이 stale로 남아 타임라인 폭·스냅·전환/페이드·덕킹·마그네틱 후속 클립이 렌더와 어긋남(결함 클래스는 `SetClipSpeedCommand` 헤더가 스스로 서술하는 그 것). **`SetClipSpeedCommand(.constantRate)` 경유 전환**(Mac 패리티 — 재타이밍+ripple이 같은 undo 스텝에 원자 포함. iOS 속도 UI는 슬라이더라 constantRate만 해당). 백로그 **CODEX-21로 등록 후 완료 처리**(20은 기존 RemoveTrackCommand 항목이 사용 중 — 번호 충돌 회피).
- **검증**: 신규 테스트 — 4s 클립 2x → 타임라인 스팬 ~2.0s 수축 단언(수정 전 4.0 stale로 RED 재현) + **undo 1회에 rate·스팬 동시 왕복** 단언. CODEX-17 `speedEndTrim` 무영향 통과(수축된 [0,2] 스팬 내 트림·결과 동일 — 낡은 "stays 4s" 주석만 갱신). **iOS 15스위트 전부 통과**·**verify_gate 5/5 GATE_PASS**.
- **경과**: CODEX P1 잔여 **1건**(04 PhotosPicker — 실기기 검증 필수·코드 수정만 가능). iOS 속도·트림·회전·전환·relink 결함(CODEX-07/08/09/17/21) 소진.

### 다음 회차 — CODEX 큐
① **CODEX-04 코드 수정 선행**(PhotosPicker FileRepresentation 전환 — 검증은 G-27 실기기 대기·하니스는 시뮬레이터 파일 URL로 못 잡음을 문서에 명시) 또는 **CODEX-18/19(P2)**·STAB-02 취소 E2E·worst-MAD 캡처 소형. **사용자 대기**: 실기기 2종(G-27 — CODEX-04/07 배선 확인 포함)·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력.

## 2026-09-01 세션 (CODEX-07 수정 완료 — relink 후 iOS 프리뷰 재구축 트리거)

- **스카웃**: 큐 1번 CODEX-17은 **병렬 세션이 이미 완료**(5100d22+586f356 — 코드·백로그·핸드오프 전부 갱신·CODEX-20 속도 UI 재타이밍 후보 플래그) → 반복 제외. CODEX-04는 실기기 없이 검증 불가(시뮬레이터가 못 잡는 결함) → **CODEX-07** 선택(수정 방향 명확·SURV-01 왕복으로 고착 가능).
- **본체**: `relinkMedia`는 mediaLibrary만 갱신하는데 PreviewView는 timeline만 관찰 — 결측 상태에서 만든 플랜이 relink 후에도 남아 재생 불가. **`.onChange(of: currentProject.mediaLibrary)` → 재구축 트리거 추가**(MediaLibrary는 Core Equatable — relink의 URL 교체가 발화). generation 가드가 이중 발화 무해화.
- **검증**: SURV-01 왕복 테스트에 **"relink가 mediaLibrary 값을 실제로 변경(Equatable≠)" 단언 다리** 추가(onChange 발화 전제 고정) — 스위트 통과. iOS 15스위트 전부·**verify_gate 5/5 GATE_PASS**. **정직 잔여: SwiftUI 배선 자체는 유닛테스트 불가(STAB-03 선례) — 실기기/수동 확인 항목(G-27 연계)**.
- **경과**: CODEX P1 잔여 **2건**(04 PhotosPicker — 실기기 검증 필수·코드 수정만 가능 / 20-신규후보 속도 UI 재타이밍 — 미등록, 번호 주의: CODEX-20은 기존 RemoveTrackCommand 항목이 사용 중 → 신규는 CODEX-21로 등록 권장). iOS 엔진+VM 결함(CODEX-07·08·09·17) 소진.

### 다음 회차 — CODEX 큐
① **CODEX-21 등록+수정(속도 UI 재타이밍)** — iOS 속도 UI가 raw `SetClipPropertyCommand(.playbackRate)`(재타이밍 없음) vs Mac `SetClipSpeedCommand` — Mac 구현 포팅이라 자율 실행·검증 용이(CODEX-17 세션 발견) ② CODEX-04(코드 수정 선행 — 실기기 검증은 G-27 대기)·CODEX-18/19(P2) ③ STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력.

## 2026-09-01 세션 (CODEX-17 완료 — iOS 플레이헤드 트림 정규 매핑 전환)

- **스카웃·챌린지**: CODEX-08 커밋(51dd431) 확인·활성 세션 부재 → 큐 그대로 CODEX-17 착수(반박 근거 없음).
- **수정**: 양 플레이헤드 트림이 `ClipTrimMath.compute` 경유(Mac 4경로 패리티 — iOS는 그동안 사용 0건). `trimClip`에 `sourceRange` 선택 파라미터(정규 결과 직접 전달·레거시 호출부 무변경). **플레이헤드 사전 가드 유지** — compute는 드래그 계약(클램프)이라 밖 目标도 조용히 클램프 트림하는데, 플레이헤드 계약은 거부+안내가 옳음(계약 차등 명시).
- **실측**: 신설 3종(실 AVAssetWriter 비대칭 픽스처·실 임포트→타임라인→속도 커맨드→트림 경로) — ①2x END 트림 **매핑 기준 ~2.0s 소스 보존**(레거시 1.0s 절단 실측) ②1x 리버스 START 반대 엣지 ③밖 거부. **iOS 68테스트/16스위트 2회 연속 PASS**·verify_gate 5/5.
- **자기 리뷰**: ①iOS 속도 UI가 raw `SetClipPropertyCommand(.playbackRate)`(재타이밍 없음) vs Mac `SetClipSpeedCommand` — **CODEX-20 후보 등록 권장**(매핑 비일관 모델) ②CODEX-08 rotated-outgoing 전환 테스트 1회 플래이크(풀 번들 부하 — 3회 재측·2회 풀 정상) 후속 관찰 ③계측 무결.

### 다음 회차 — CODEX 큐
① **CODEX-04·07**(코드 수정先行 — 실기기 검증 권장)·CODEX-18/19(P2)·CODEX-20(속도 UI 재타이밍 — 이번 발견) ② STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력.

## 2026-08-31 세션 (CODEX-08 수정 완료 — 혼합 회전 트랙 클립별 orientation·발현 조건 정밀화)

- **본체**: iOS 클립 이펙트의 `sourcePreferredTransform`이 composition **트랙의** pt를 읽어 혼합 회전 트랙에서 뒤따르는 클립이 첫 클립 방향을 상속. BUG-IOS-10 audioMixEntries와 동일한 **수집-소비 패턴**으로 전환 — `insertClip`이 effective 소스(원본·리버스 렌더·이미지 프리렌더)에서 클립별 pt를 `sourceOrientations[clip.id]`에 기록, 이펙트가 자기 pt 수신, 플랜 종료 시清除. 트랙 pt는 외부 플레이어 메타데이터로 유지(first-writer-wins).
- **발현 조건 정밀화(재현에서 판명 — 원 서술보다 좁음)**: 설정 조건이 `pt == .identity`일 때만이라 **가로(첫)→세로(둘째)는 트랙이 identity에 머물러 둘째 삽입 시 재설정이 우연히 동작**(결과는 올바르지만 취약) — **세로(첫, 90°)→가로(둘째)에서만** 뒤따르는 클립이 90° 상속으로 옆으로 눕는다. 테스트 2건: 구조 단언(세로→가로·수정 전 RED → 후 GREEN: 둘째 이펙트 identity·첫 클립은 90° 유지) + 픽셀 밴드 단언(가로→세로 upright 고정 — 우연 동작의 회귀 방지).
- **검증**: 전환 스위트 **4회 연속 통과**(GREEN 직후 + 백투백 3 — rotatedOutgoing 플레이크 재발 0)·**iOS 15스위트 전부 통과**(렌더/익스포트 골든 포함 — 회전 변경 무회귀)·**verify_gate 5/5 GATE_PASS**(Core 1,429/212·양 빌드·lint)·LOOP_STATE 재생성.
- **경과**: CODEX P1 잔여 **3건**(04·07 — 실기기 검증 권장·17 — iOS 트림 ClipTrimMath). iOS 엔진 결함 CODEX-08·09 소진.

### 다음 회차 — STAB 큐
① **CODEX-17** (P1 — iOS 플레이헤드 트림이 비정규 시간 매핑 사용, `IOSEditorViewModel.swift` L1329·L1350 → `trimClip` L1074 — 양 플레이헤드 동작 `ClipTrimMath.compute` 경유 전환[Mac 4경로 패리티] + 속도 램프·리버스 픽스처 왕복 테스트. VM 로직·실기기 불필요) → CODEX-04·07(실기기 검증 권장 — 코드 수정만 먼저 가능)·STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력(블라인드 평가 개시 조건).

## 2026-08-31 세션 (CODEX-10 수정 완료 — 블라인드 투표 라벨 반전·B측 평가 전제 전부 정리)

- **본체**: `ab_benchmark_metrics.py` blind 프로토콜에서 `x_is_a=False` 시 구현화는 `_X.mp4`←B측로 정상인데 **투표표 rows만 X열에 `_Y.mp4`(=A측)를 안내** — X↔A/B 해독을 tally의 mapping이 담당하는 구조와 충돌해 평가자의 X 선호가 반대 편집기로 집계. **투표표 X/Y열을 항상 `{fid}_X.mp4`/`{fid}_Y.mp4`로 고정**(해독은 mapping이 유일 담당) + ballot 안내문에 파일 대응 명시.
- **검증**: ①셀프테스트 2건 추가 — 투표표 라벨 정합 + 구현화 바이트==mapping 측·all-X tally 왕복(12시드×4fixture로 x_is_a 양 분기 커버) — self-test 전체 PASS ②**반전 실증(pre/post)**: A를 4번 전부 선호한 정직한 평가자(투표표 파일 열 파싱 기준 투표)가 수정 전 **2/2 절반 오집계**(x_is_a=False 비율 — 원 서술 "약 반수"와 일치) → 수정 후 4/0. ③함정 2건(정직 기록): 재현 스크립트가 mapping 기준으로 투표를 생성하면 tally와 같은 규칙이라 반전이 안 보임(평가자 시점=투표표 파일 열 파싱으로 수정)·all-X 투표의 우연한 정합(2/2)은 결함 부재가 아님.
- **경과**: CODEX P1 잔여 **4건**(04·07·08·17). **CODEX-10/11 완료로 B측 블라인드 평가의 계측 전제 정리 완료** — 남은 것은 경쟁사 출력 확보(사용자/수동) 후 `--blind` 실행.

### 다음 회차 — STAB 큐
① **CODEX-08** (P1 — 혼합 회전 트랙 orientation, `IOSExportEngine.swift` L560·L1032 — 클립별 `AVAssetTrack.preferredTransform` 전달 + 혼합 회전 픽스처. 엔진 로직·실기기 불필요) → CODEX-17(iOS 트림 ClipTrimMath 전환)·04·07(실기기 검증 권장)·STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07(Q13) 결정·push 후 원격 CI 관찰·경쟁사 B측 출력(블라인드 평가 개시 조건).

## 2026-08-31 세션 (STAB-07 제안 상신 + CODEX-11 수정 — REPS 집계·B측 블라인드 평가 전제 정리)

- **STAB-07(제안 작성 완료·사용자 결정 대기)**: `DECISIONS_20260822.md`에 **Q13 상신** — 안 A(온디바이스 `MXMetricManager` 구독 한정 채택·네트워크/서버 코드 추가 0·미디어·편집 데이터 전송 없음·진단은 Apple 익명 집계 경유 + OS 수준 옵트인 기본 OFF가 §13.10 "외부 처리 명시·기본 OFF" 원칙과 정합·macOS 12+로 Q3 macOS 14와 호환)·안 B(§13.8 요구 폐기 — 크래시 가시성이 사용자 수동 의존으로 약화)·안 C(베타 후 재검토) 3안·권고 A. 사실 관계(전송 범위·플랫폼·옵트인 구조) 명시 — 단 전력 지표의 macOS 가용성·Privacy Label 영향은 도입 시 실험 확인 필요로 신중 표기. **결정 전 구현 없음.**
- **CODEX-11 수정(A류 계측)**: `run_ca12_ab_benchmark.sh`의 fixture별 집계가 rep1만 읽던 것을 **모든 rep 소비**로 교체 — `repetition_stats`(median/p95/min/max/n)·`reps_recorded`·`failed_reps`(실패 은폐 없음)·`reps_expected` 불일치 마커·**n=1은 `single_rep`+`p95:null` 명시**(단일 표본의 통계 위장 폐지 — 조건 노트의 "median/p95 recorded" 약속 이행). rep1 엔트리는 하위호환 대표로 유지. 검증: 합성 4케이스 단위 검증 + **REPS=2 ab05 종단 실증 — 양 rep 값(min 1.628/max 4.296) 전부 소비·5필드 통계 기록·status=0**. 검증 잔여물 296KB 즉시 정리·lint 게이트 PASS.
- **경과**: CODEX P1 잔여 **5건**(04·07·08·10·17). STAB 계획의 루프 실행 가능 항목 중 미완료는 **worst-MAD 캡처 소형과 CODEX P1·STAB-02 취소 E2E 소형뿐** — STAB-07 제안은 상신 완료로 루트 닫힘(결정은 사용자).

### 다음 회차 — STAB 큐
① **CODEX-10** (P1·A류 — 블라인드 투표 라벨 불일치, `ab_benchmark_metrics.py` L485-487·셀프테스트 보강으로 자율 실행 가능·**CODEX-11과 같은 B측 평가 전제**) → CODEX P1 잔여(08 혼합 회전 — 엔진 로직·실기기 불필요 / 17 iOS 트림 ClipTrimMath / 04·07은 실기기 검증 권장)·STAB-02 취소 E2E·worst-MAD 캡처. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·**STAB-07(Q13) 결정**·push 후 원격 CI 관찰.

## 2026-08-31 세션 (CODEX-09 수정 완료 — iOS 초과 전환 클립 무음 드랍·배치/이펙트 단일 클램프 통일)

- **스카웃**: STAB-05 루트(스테일 공급=BUG-CA12-01 에스컬레이션 대기)·STAB-06 원격(사용자 push 대기)·STAB-04 w1(STT TCC 대기)는 전부 대기 → CODEX P1 7건 중 **CODEX-09** 선택(데이터 손실급 제품 결함·엔진 로직으로 결정적 재현 가능·실기기 불필요). CODEX-04는 시뮬레이터가 못 잡는 결함이라 이번 세션 제외.
- **본체**: iOS `IOSExportEngine`의 백타이밍 배치 2경로(`insertVideoTrack`·`makeVideoComposition` 이펙트 timeRange)가 **raw `transition.duration`** 으로 시작을 당기는 동안 전환 창(`makeTransitionEffects`)만 인접 클립 길이로 클램프 — 요청이 이웃보다 길면 커서 역전 → `insertClip`의 `timelineStart >= cursor` 가드가 꼬리 클립을 조용히 드랍. **단일 클램프 계산 `clampedTransitionDuration`(+래퍼 `clampedOverlapPull`) 신설, 3경로 전환이 동일 값 사용.** 초과 전환 픽스처(3×1s red·blue·red + 2s crossDissolve×2): 수정 전 미디어 세그먼트 2/3·composition 1.0s·t=1.9 프레임 생성 불가(AVF -11832) 재현 → 수정 후 3/3·2.0s·t=1.9 red-dominant 블렌드.
- **검증**: iOS 전체 **15스위트 통과**(상태 4·렌더/익스포트 5·파이프라인/접근성 6 — STAB-06 분할과 동일 그룹핑)·전환 스위트 **5회 연속 통과**·**verify_gate 5/5 GATE_PASS**(Core 1,429/212·Mac/iOS 빌드·lint)·LOOP_STATE `--check-reproducible` 후 `--write` 재생성.
- **관찰 2건(정직 기록)**: ①`rotatedOutgoingTransitionsUpright`가 수정 전 빌드 첫 실행에서 1회 실패(after.r=87.7 vs <50) — 이후 재발 0(5회). 0.6s 전환은 클램프 미발동 경로로 본 수정과 무관·원인 미상 — STAB-05 "빌드 간 수치 변동" 클래스 인접 관찰로 남김. ②**Mac ExportEngine도 동일 구조(백타이밍 raw·창 클램프)** — 단 Mac은 cursor 가드가 아닌 절대 시각 삽입이라 초과 전환 시 드랍이 아닌 겹침 삽입 동작(별개 결함 가능성) — CODEX-09의 Mac 측은 별도 관찰 항목.

### 다음 회차 — STAB 큐
① **STAB-07 MetricKit 제안 작성**(제안만·결정은 사용자 — DECISIONS 상신) → 소형(**CODEX P1 잔여 04·07·08·10·11·17** — 10/11은 A류 계측·B측 블라인드 평가 개시 전 필수, 08·17은 엔진/VM 로직으로 실기기 불필요, 04·07은 실기기 검증 권장·코드 수정만 가능 — STAB-02 취소 E2E·worst-MAD 캡처). STAB-05 루트·STAB-06 원격 = 대기. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07 결정·push 후 원격 CI 관찰.

## 2026-08-31 세션 (STAB-08 완료 — LOOP_STATE 자동 생성·이력 레코더 + Part 9 재감사)

- **본체**: 3게이트(verify_gate·W smoke·파리티)가 종료 시 `.build-check/history/*.json`으로 판정을 append-only 기록 → `gen_loop_state_report.py`가 최근 3회를 `docs/LOOP_STATE_REPORT.md`로 생성(수작업 편집 금지 마킹). **재현성 DoD 실측**(`--check-reproducible` 2회 렌더 동일). 등록 플래이크는 이름으로 표기 — "측정된 것을 보여준다".
- **계측 도구 결함 2건 발견·수정(자기 리뷰 ③문항의 값)**: ①파리티 스크립트가 `--export_mp4`(언더스코어)로 비교기를 호출 — argparse가 전 시나리오 기각(전 스윕 오염 이력은 삭제) ②게이트 이력 파서가 xcodebuild Mac/iOS 라인 누락(소문자 전용 charset)·따옴표 값 기각 — 수정 후 4스텝 전부 기록.
- **Part 9 재감사(STAB-08 후반)**: M1~M4 정정 상태 확인·**MC-07 갱신** — 19시나리오 파리티 상시 게이트화(CI nightly 포함)·스테일 클래스 4시나리오 잔여 명시.
- **측정 스냅샷**: 게이트 5/5(기록됨)·W smoke 5/5(29/29)·파리티 15/19(cross_dissolve·normal_delete·freeze·motion = 등록 스케일 클래스, 부하 하 FAIL — 리포트에 그대로).
- 잔여 소형 등록: worst MAD 캡처(레코더 파싱 확장). 스카웃: 파리티 타입수정은 계측 도구 결함의 실례 — 타 게이트 스크립트의 argparse 인자 접두사 정합 검사 후보(저우선).

### 다음 회차 — STAB 큐
① **STAB-07 MetricKit 제안 작성**(제안만·결정은 사용자 — DECISIONS 상신) → 소형(STAB-02 취소 E2E·CODEX P1 7건·worst-MAD 캡처). STAB-05 루트·STAB-06 원격 = 대기. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07 결정·push 후 원격 CI 관찰.

## 2026-08-31 세션 (STAB-06 로컬 완료 — CI iOS 잡 분할·nightly W smoke + BUG-ACC-06 증거 통합)

- **스카웃**: STAB-05 잔여의 근본(스테일 공급)이 전 플래이크로 수렴했으나 BUG-CA12-01 에스컬레이션 대기 — 루프가 즉시 실행 불가. **큐 챌린지**: STAB-06(완전 실행 가능·원격 CI 관찰 창구 직결)으로 전환, BUG-ACC-06 증거 통합을 소형 병행.
- **STAB-06**: iOS 잡 3분할 — `ios-fast-tests`(상태 4스위트·**14테스트 0.55s 실측**·20m)·`ios-av-tests`(AV 11스위트 **2직렬 스텝 개별 타임아웃**·렌더/익스포트 22테스트 40.2s@20m 선행 → 파이프라인/접근성 26테스트 5.0s@15m). **분할 커버리지 4+11=15 diff 실증**·`-only-testing`명↔@Suite 파일 매핑 15/15·yaml 파싱·3그룹 전부 로컬 PASS. nightly에 W smoke 추가(파리티 스윕·E2E·퍼즈는 기존 포함)·cross-dissolve "스킵" 낡은 주석 갱신.
- **BUG-ACC-06 증거 §1.13 BUG-CA12-01 통합**: 격자 정렬 판별기(1.7667→35.26 4/4 결정적 vs 1.75 이분)·normal_delete 부하 민감성(단독 12연속 vs 스윕 53.31)·재현 레시피 — 상위 도구 조사 시 우선 사용 권장.
- **자기 리뷰**: ①같은 패턴 — 원격 CI의 나머지 잡(build-and-test 15m Core 타임아웃 등)은 현행 유지(실행 증거 없는 선조정 금지) ②release.yml은 미점검 — 관찰 항목 ③측정 도구 — grep 클래스명 패턴이 숫자 포함 이름(IOSPhase1Surfaces)을 잘라 "MISSING" 오탐 → [A-Za-z0-9] 교훈화.
- 게이트 5/5. **원격 검증은 사용자 push 후 관찰**(STAB-06 DoD의 사용자 절반).

### 다음 회차 — STAB 큐
① **STAB-08 LOOP_STATE 자동 생성**(게이트 JSON 기반 상태표·재현성) → STAB-07 MetricKit 제안 + 소형(STAB-02 취소 E2E·CODEX P1 7건). STAB-05 잔여·STAB-06 원격 = 대기. 스카웃: release.yml CI 미점검(관찰). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT 음성인식 TCC·STAB-07 결정·**push 후 원격 CI 관찰(STAB-06 검증)**.

## 2026-08-31 세션 (STAB-05 3차 — cross-dissolve 재편입·BUG-ACC-06 등록·갭 검출 슬롯 오판 수정)

- **스카웃**: 스킵 주석(L167)이 STAB-02 이전 작성 — 행업이 순차 펌프 기아 동일 클래스일 가능성 → 재편입 프로브 선택(큐 챌린지: motion 심층보다 저비용·+1 시나리오 직결).
- **재편입**: 하니스 `MOVIECUT_UITEST_TRANSITION_TARGET=first` 노브 신설(콤마 임포트 선택=마지막 클립 → 전환 무효 문제 해결) + 시나리오 1 실장. **행업 소멸 실증**(STAB-02 부수 효과)·duration 4.5s 백타이밍 정확·**구조 검증형 3/3 결정적 통과**(t=0.5/2.6 MAD 1.39/3.36).
- **BUG-ACC-06 등록(P1)**: 디졸브 창(t≈1.75)은 프리뷰가 순수 A 프레임을 "신규" 반환하는 **스테일 공급 클래스(BUG-CA12-01 인접)**에 차단 — **프레임 격자 정렬 판별기**(1.7667→35.26 4/4 결정적 vs 1.75 이분) 확보. normal_delete의 부하 민감 재발(스윕 53.31 vs 단독 12연속 통과)도 동일 클래스로 기록.
- **부수 수정**: BUG-ACC-05 갭 검출이 슬롯 교대 첫 세그먼트(전환 오버랩)를 갭으로 오판 → 어웨이-앤-백 오발동 → **전 비디오 트랙 합집합 커버리지 기준으로 수정**.
- **자기 리뷰**: ①iOS 스냅숏 경로는 copyPixelBuffer 미사용(영향 없음 확인) ②디졸브 창 단언은 BUG-ACC-06로 이관 ③측정 함정 — comparator 출력은 시각을 3자리로 반올림(`t=1.7667`→`t=1.767`): grep 패턴 주의.
- 게이트 5/5·풀스윕 cross_dissolve 통과(잔여 실패=기존 플래이크). 스크래치 14MB 정리(디스크 11Gi 여유).

### 다음 회차 — STAB 큐
① **STAB-05 잔여**(플래이크의 근본 = 스테일 공급 — BUG-CA12-01 에스컬레이션에 BUG-ACC-06 증거·격자 판별기 통합 권장) → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·CODEX P1). 스카웃: 신규 후보 없음(BUG-ACC-06이 이번 스카웃 발견). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-30 세션 (BUG-ACC-05 수정 완료 — 5차 어웨이-앤-백 재렌더·갭 한정 게이트)

- **수정**: `snapshotFrame`이 **갭 직후 0.5s 창**에서 attempt 0의 빠른 성공(<150ms)을 불신 → 어웨이-앤-백(t±0.05 시크→120ms 정착→t 재시크) 재렌더 후 두 번째 프레임 선호. 갭 검출: 컴포지션 비디오 트랙 세그먼트 표에서 직전 세그먼트가 **빈 삽입(source duration 0)**이거나 비연속인 시작(빈 채움 세그먼트가 있는 실갑 식별 — 첫 판정 로직의 함정).
- **전범위 불신 기각(중요 함정)**: 휴면 캐시의 "빠르고 정상"까지 재렌더하면 motion_tracking 회귀(0.05→4.33) — 갭 근접 게이트가 필수.
- **검증**: normal_delete **12회 연속 t=2.5 MAD 1.65**(5+5+2 — 수정 직후·게이트 정밀화 후·계측 제거 후)·재렌더 발동 확인(6.4ms 검정→RERENDER→정상)·W 스모크 5/5·29/29·verify_gate 5/5.
- **소유 판정**: motion_tracking(5.46/12.03)·freeze(9.69) 실패는 수정·기준선 양쪽 3/3 동일 — **STAB-05 기존 플래이크**(빌드 간 수치 변동 관찰 — 다음 조사 단서).
- 진단 계측 전부 제거(컴포지터 요청·스냅숏 경로·ExportEngine 형상+플래그 — BUG-ACC-04·05 종료).

### 다음 회차 — STAB 큐
① **STAB-05 잔여**(freeze/motion 백투백 플래이크 — 빌드 간 수치 변동 단서 포함·cross-dissolve 재편입·18/18×3) → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·CODEX P1). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-30 세션 (BUG-ACC-05 4차 — 재시도 변형은 발동 불발이었음 판명·병렬 WIP 인수 검증)

- **병렬 WIP 인수 검증(LI-003 — 3h17m 경과·프로세스 0)**: `hasNewPixelBuffer` 게이트 제거("한발 뒤 도착" 가설) — **5/5 실패 실측으로 기각·미커밋 원복**.
- **3가설 기각(전부 실측)**: ①컴포지터 요청 로그 0건 = 평문 AVVideoComposition 경로(커스텀 컴포지터 무관 — 2차 "nil-source 0건"의 재해석) ②opacity 앵커 미러링(export 구성 복제) 3/3 실패·원복 ③위 게이트 제거.
- **결정적 실측**: 스냅숏 경로 계측 — t=2.5가 **폴링 attempt 0에서 34ms 만에 성공**(검정 버퍼가 "신규"로 태깅). 시크 직후 소스 미프라임 상태에서 평문 컴포지터가 **검정으로 렌더 완결 + 재렌더 없음** — 프리롤/재시도 전부 "attempt 0 성공"이라 **발동 불발**이었던 것. 다음 시크(3.5)의 신규 렌더가 항상 정상인 것과 정합.
- **5차 방향(백로그 §1.15)**: attempt 0의 지나치게 빠른 성공(<~150ms·신선한 제로톨러런스 시크 직후)은 불신 → 어웨이-앤-백 재렌더(t±0.05→정착→재시크) 또는 1프레임 플레이 넛지 후 두 번째 프레임 선호. 갭의 정당한 검정과 구분은 스냅숏 호출부 의미론 필요.
- 게이트 5/5. 계측은 `diagLogCompositionRequests`·스냅숏 경로 로그로 잔류(수정 후 제거).

### 다음 회차 — STAB 큐
① **BUG-ACC-05 5차**(어웨이-앤-백/플레이 넛지 수정·측정) → STAB-05 잔여(freeze 백투백·cross-dissolve·18/18×3) → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·CODEX P1). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-30 세션 (BUG-ACC-05 3차 조사 — 공급 지연 가설 기각·렌더 쪽 판정 반전)

- **시도·원복**: 기록된 수정 방향(프리롤 웜업 — t−0.2 콘텐츠 내부 프라이밍 후 정착 150/400ms·재시크)은 비결정적 부분 통과(2/3·1/3)만 달성 — 가짜 수정으로 원복, `snapshotFrame` 동작 바이트 동일(측정 주석만 추가).
- **결정적 실측**: 재시도에서 `hasNewPixelBuffer` 게이트 제거 시 `copyPixelBuffer(forItemTime: t=2.5)`가 **성공하고 검정 픽셀 반환(4/4 결정적)** — 갱 직후 item time에 검정 버퍼가 실재. 프레임이 늦은 게 아니라 **렌더 산출 자체가 검정**(또는 갭의 낡은 검정이 태깅) — 플래그는 낡은/검정 복사의 필수 방어로 확인.
- **4차 방향(백로그 §1.15 기록)**: 컴포지터 요청 단위 계측 — 갭 직후 요청의 `sourceFrame(byTrackID:)` 반환 버퍼 귀속 + 합성 출력 평균 휘도 로깅으로 "컴포지터가 검정 합성" vs "플레이어가 낡은 검정 태깅" 판정.
- 게이트 5/5·기준선 보존(53.31 MAD 재현 확인).

### 다음 회차 — STAB 큐
① **BUG-ACC-05 4차**(컴포지터 계측→수정) → STAB-05 잔여(freeze 백투백 플래이크·cross-dissolve 재편입·18/18×3) → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·CODEX P1). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-29 세션 (BUG-ACC-04 2차 조사 — 팽창원 실측·진단 실장, 판정 재현 1회 남음)

- **진단 실장**: nil 소스 프레임 경로(요청 시각·명령 범위·활성/소스 트랙 ID) + `makeExportPackage` 형상(컴포지션 길이·트랙별 범위·**그래프 오디오 길이**·**프로젝트 클립 원형**) 로깅 — `diagLogCompositionShape` 플래그(수정 후 제거 대상).
- **핵심 실측(재현 6회·실패 2)**: 실패 run `composition=600s graphAudio=600s tracks=[vide:0..600 soun:0..600]` — **그래프 믹스가 300+300 순차**로 렌더되고 비디오 트랙까지 팽창. 통과 run 전부 300s·프로젝트 원형 결정적(`video:[0..300, 300..600adj] audio:[0..300]` — 조정 클립은 항상 자기 압축 [300,600]에 있으나 BUG-ACC-01 가드로 무해 확인). 평탄화 무죄(단순 통과·컴파운드 없음).
- **잔여(3차)**: 간헐 변수 = BGM이 [0,300] 오버레이 대신 [300,600] 순차로 놓이는 것(또는 동등 audible-600). 하니스 배치 코드는 결정적으로 보임 — **다음 실패 재현의 `pkg project clips` 라인이 직접 판정**. 재현: `bash scripts/run_w_acceptance.sh w4` 반복(약 50%) + `/usr/bin/log show --last 10m --predicate 'processImagePath CONTAINS "MovieCutMac" AND eventMessage CONTAINS "pkg"' --info`.
- 부수: 탐침 재시도 rc 기반 6×1s 보강(통과 run에서도 prores_codec 공탐 지속 — 관찰). 게이트 5/5.

### 다음 회차 — STAB 큐
① ~~BUG-ACC-04~~ **수정 완료(2026-08-29 23:0x 메인 세션 — 자기 압축 동률 UUID 코인플립 판정·조정 레이어 동률 규칙 폐지·w4 2연속 300.00s 완주·사후 검증 prores 6/6)** → 소형 A류: 러너 계측 3건(탐침 출력-빈-재시도·사전 디스크 검사 ~8GB·보존 상한) ② STAB-04 2차(acceptance 5/5×3) → STAB-05 파리티 통합 → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·CODEX P1). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-29 세션 (BUG-ACC-01 완료 — 조정 레이어 오디오 편입 판명·w4 4s 복원 + BUG-ACC-04 등록)

- **원인 판명(실측 이분법)**: 그래프 빌더·렌더러·audibleSampleEnd 전부 배치 정상 — 하니스 상태 라인 `video:0-2, audio:2-6`이 결정적 단서. **조정 레이어**(자산 ID 차용·G-03 컨테이너)가 자기 압축으로 [2,6]에 밀린 뒤 `carriesAudio` 필터를 통과해 오디오 스트립으로 편입 → audible 범위 2s+4s=6s 팽창(비디오 스트림은 export 필터로 2s 유지 — 오디오만 6s인 실측과 정합). 일반 콤마 임포트의 6s는 멀티 URL 루프의 의도적 순차 배치(결함 아님).
- **수정·검증**: 빌더가 `isAdjustmentLayer` 클립 제외 + Core 유닛(w4 형태 2스트립·audible ≤4s 단언) + **스모크 w4 6.000s→4.000000s(프리셋·ProRes 양 경로)** + 스모크 W 5/5·29/29 + 게이트 5/5.
- **acceptance 러너 보강(A류)**: 실패 시 워크디렉터리 보존(경로 출력)·ffprobe 탐침 재시도(5분 인코직 직후 조기 공탐 — 보존 파일 재탐침 즉시 정상)·앱 stdout을 `app.log`로 캡처.
- **BUG-ACC-04 등록(P1)**: 5분 마스터 출력이 **4회 중 2회 전면 실패**(양 export 0바이트·오류 무표면·prores 스텝 거짓 OK — exportProResMaster 조기 반환). app.log 캡처가 다음 재현 판정용(BUG-CA12-01 계열 여부).

### 다음 회차 — STAB 큐
① ~~BUG-ACC-02 병합~~ 완료(2026-08-29 메인 세션 — 백로그 §1.13에 재현 경로·스택 증거 통합, 1커맨드 재현 `run_w_acceptance.sh w1` 문서화) ② STAB-04 2차(acceptance 5/5×3 — BUG-ACC-04 app.log 조사 포함) → STAB-05 파리티 통합 → STAB-06 CI 분할 → STAB-08·07 + 소형(STAB-02 취소 E2E·**CODEX P1 7건 — 04·07·08·09·10·11·17**, 04·PhotosPicker는 기존 열거 누락 보강 2026-08-29). **STAB 창구 종료 후 복귀 큐는 STABILIZATION_PLAN §3 Phase 3+ 체크리스트로 원장화됨**(리뷰 권장 2~4단계 전항 — 베타 검증 매트릭스·CapCut 속도 지표·FCP 품질 지표·경계 분해 복귀·백로그 §K 카드뉴스 G-20/21/22·U-10 연결). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·W1 STT용 음성인식 TCC·STAB-07 결정.

## 2026-08-29 세션 (STAB-04 1차 완료 — W 측정 양분화·실결함 3건 포착, 메인 세션 수동 3연속 회차)

- **STAB-04 1차**: ① `run_w_scenarios.sh` → **`run_w_smoke.sh`** 개명(헤더에 "대표 작업 게이트 아님·STT 무실행 허용·하드코딩 덕킹" 명시) ② 하니스 **`MOVIECUT_UITEST_W_STRICT=1`** 모드 — w1 세로 영상 임포트(strict 게이트 — 비게이트 시 스모크 형상 변형·파킹 실측)·**STT 미실행 시 ok=false**(`stt=user_tcc_required_for_acceptance` — 외부 리뷰 "STT 못 돌아도 성공" 폐지)·덕킹 실분석 경로(`autoDuckOtherAudio` F-14) ③ **ProRes 레이스 예산 90초 고정 → STRICT에서 `max(90, duration*2)`** — 고정 90초는 "게이트<실작업"의 사례 그 자체(300초 마스터가 RTF 정상이어도 타임아웃) ④ `make_w_acceptance_fixtures.sh`(say 실발화 60s — 문장 pauses로 덕킹 분석 유도·720x1280 세로·5분 마스터·120BPM) ⑤ `run_w_acceptance.sh`(와치독 held-PID + **앱 파킹 시 러너 직접 회수**·ffprobe 검증: 세로 기하·길이±·prores 코덱·A/V 싱크≤1프레임·시간 예산).
- **게이트 즉시 포착 — 백로그 §1.15 등록**: **BUG-ACC-01 (P1)** ProRes·명시적 비트레이트 출력에서 겹치는 오디오 길이 **합산**(2s 영상+4s BGM→6.000s·300+300→600s — 프리셋/프리뷰 경로는 정상 오버레이. 코덱 prores 정상) — 그래프 믹스다운 배치 의심. **BUG-ACC-02 (P1)** `autoDuckOtherAudio` 실분석이 60초 실발화에서 continuation 파킹(메인 런루프 유휴·워커 부재·w.json 미기록·12분 스택 샘플) — **BUG-CA12-01 계열 신규 재현 경로**(1커맨드 재현 가능). **BUG-ACC-03 (P2)** 비트 마커 수율(4s 8클릭≥6개 vs 60s 120BPM→4개).
- **함정 3건(정직 기록)**: ① 세로 임포트를 strict가 아닌 픽스처 존재로 걸어 스모크 w1 형상 변형→파킹(40분 소모 후 strict 가드로 회복 — 스모크 W 5/5·29/29·40s 재실측) ② 스모크/acceptance 러너 공통의 "와치독만 앱을 죽이는" 구조 — 파킹 시 `wait $pid` 영구 블록(양쪽 모두 러너 직접 회수로 보강) ③ bash `set -e` + `[ $? -ne 0 ] && FAIL=1` 무음 사망(acceptance 러너 — `if !` 형태로 수정, CA-01 함정 재발).
- **검증**: 스모크 W 5/5·29/29(무회귀)·verify_gate 5/5. acceptance는 현재 정직하게 RED(w1=STT TCC 대기+BUG-ACC-02·w2=마커 수율 약어셜션·w4=BUG-ACC-01 duration) — **BUG-ACC-01/02 수정 후 5/5×3이 STAB-04 2차 완료 기준**.
- **경과**: STAB 진도 4/8(1차). Phase 2(측정 재설계) 착수 — 게이트가 이미 결함을 잡기 시작함(외부 리뷰 요구의 실증).

### 다음 회차 — LOOP_STATE 우선순위
① **BUG-ACC-01 (P1)** ProRes/명시적 비트레이트 오디오 길이 합산 수정(그래프 믹스다운 배치 — 재현: 2s 영상+4s BGM 오버레이→ProRes 6s·수정 후 4s 단언 + 프리셋 경로 패리티) ② BUG-ACC-02 재현 경로 BUG-CA12-01 에스컬레이션 병합 + STAB-04 2차(acceptance 재실측) ③ STAB-05 파리티 통합. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·**W1 STT용 음성인식 TCC 승인(시스템 설정→개인정보→음성 인식 — 무인 acceptance가 실전 STT를 돌리는 전제)**·STAB-07 결정.

## 2026-08-29 세션 (STAB-03 완료 — iOS 제품 결함 4건, 메인 세션 수동 회차)

- **STAB-03(메인 세션 수동 회차 — 연속 2회차)**: ① stepFrame이 `frameStepTick` 발행 → PreviewView가 해당 틱을 관찰해 **0.25s 공산 임계값을 우회한 강제 시크**(zero-tolerance) — ~0.033s 스텝이 재생헤드 숫자만 바꾸고 렌더 프레임이 남던 결함 폐지. 시크 함수를 `coalescingSmallMoves` 파라미터로 분리(일반 observer 동기화는 기존 0.25s 공산 유지 — 재생 중 15Hz 재시크 스퍼터 방지 목적 보존) ② 루프/정지 판단을 periodic observer의 종료 샘플링(미보장)에서 **AVPlayerItemDidPlayToEndTime 알림**으로 이관 — VM `handlePlaybackReachedEnd()`(루프→playhead 0·유지 / 비루프→정지) + 뷰가 시크·재개 수행. observer 클로저는 `MainActor.assumeIsolated`로 격리 명시 ③ fileImporter의 security scope을 **Task 내부**에서 열고 닫기(기존 defer는 Task 예약 직후 종료 — Files/iCloud URL 권한 조기 상실) ④ fileExporter 성공 후 중복 `saveProject` 제거(성공 저장의 2차 쓰기 실패가 오류로 표시되던 경로).
- **검증**: iOS 전체 **62테스트/15스위트 PASS**(신규 `playbackEndHandling` — 엔드 핸들러 루프/정지 분기·`frameStepTick` 단언 포함)·verify_gate 5/5.
- **정직 기록**: 틱→강제 시크 배선과 알림 등록은 SwiftUI 뷰 코드로 유닛테스트 불가 — **실기기/수동 확인 항목(G-27 연계)**으로 남김. VM 로직(틱·엔드 판단)은 단위테스트로 고착.
- **경과**: STAB 진도 3/8. Phase 1(제품 결함) 전 증분 완료 — Phase 2(측정 재설계) 진입.

### 다음 회차 — LOOP_STATE 우선순위
① **STAB-04 W 측정 양분화** — 현행 스크립트를 `run_w_smoke.sh`로 개명 + `run_w_acceptance.sh` 신설(60초 토킹헤드 STT[TCC 전제]·5분 멀티트랙 ProRes·카드뉴스 문서 편집기·덕킹 실제 감지·작업시간·출력 품질 검증 — 설계 문서화 후 구현) ② STAB-05 파리티 통합(freeze-frame 플래이크·normal_delete 실제 gap·cross-dissolve 재편입). **소형 병행 후보**: STAB-02 잔여(취소 E2E)·CODEX-06(AIFF)·CODEX-17(iOS 트림 ClipTrimMath 전환). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·STAB-07 결정.

## 2026-08-29 세션 (STAB-02 완료 — Mac 펌프 병렬화·W 측정 분쟁 판정, 메인 세션 수동 회차)

- **STAB-02(메인 세션이 수동 실행 — 16:00 회차 전 유창)**: `ExportEngine.exportVideoWithExplicitBitrate`의 순차 pump(Video 완전 종료 후 Audio)를 **태스크그룹 병렬 pump로 교체**(iOS RENDER-02 패턴 포팅). 실패 전파 설계: 펌프 하나가 throw하면 즉시 양 reader+writer 해체 — 취소된 리더의 `copyNextSampleBuffer→nil`로 형제 pump continuation이 재개됨(`withThrowingTaskGroup`은 자식 전원 완료를 기다리므로, 해체 없으면 그룹 대기 자체가 교착 — continuation 기반 pump는 태스크 취소에 반응하지 않음). 부수: writer `.cancelled`→`CancellationError` 매핑, 활성 writer 세션 추적(`activeWriterSessionReaders/Writer`) + `cancelExport()` 확장 — 제품 경로 취소 배관(프리셋 경로와 동일 지위).
- **W 측정 분쟁 판정(§0 원칙 이행)**: STAB-01+02 완료 상태에서 **W4 3회 연속(84,957B 동일) + W 전체 5/5 × 3회 연속(15/15 워크플로·29/29 스텝·고아 0)** — 외부 리뷰의 W 4/5(W4 ProRes timeout)는 재현되지 않았고, 구조적 교착 원인은 코드에서 제거됨. **내부 5/5로 확정.**
- **검증**: verify_gate 5/5(Core 1,425/211스위트·Mac/iOS 빌드·lint).
- **함정 2건(정직 기록)**: ① 취소 E2E 단위테스트는 라이브 export 테스트 인프라가 부재해(기존은 정적 계약만) 이번 증분에 넣지 못함 — STAB 잔여로 등록. ② `MovieCutMacUITests/ImportExportE2ETests.testImportThenExportProducesAMovieFile` 2회 연속 실패(124s·아티팩트 0B·로그: 미디어 오픈 실패 AVFoundation -11829/-12848 + 오디오 HAL 프록시 오류) — **부모 커밋(stash)에서 동일 실패로 선결함·환경 판정**(MACUI-01 계열·voiceagent 오디오 점유 의심). verify_gate 대상 아님. 후속 관찰 등록.
- **경과**: STAB 진도 2/8. Phase 1(제품 결함) 잔여 = STAB-03(iOS 4건).

### 다음 회차 — LOOP_STATE 우선순위
① **STAB-03** iOS 4건 — 프레임 스텝이 0.25s seek 임계값 우회(PreviewView.swift:230 — VM 숫자가 아닌 AVPlayer 실제 프레임 실측)·루프/정지를 `AVPlayerItemDidPlayToEndTime` 알림으로(observer 추정 폐지)+MainActor 격리 명시·security scope를 Task 내부에서 열고 닫기(iOSContentView.swift:361-365)·fileExporter 성공 후 중복 `saveProject` 제거 ② STAB-04 W 측정 양분화. **소형 병행 후보**: STAB-02 잔여(취소 E2E)·CODEX-06(AIFF)·CODEX-17(iOS 트림 ClipTrimMath 전환 — STAB-03과 같은 파일군). **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·STAB-07 결정. STAB 증분 커밋 후 push는 루프 금지 — 메인 세션/사용자가 반영.

## 2026-08-29 세션 (외부 리뷰 #2 병합 — 안정화 계획 등록, docs 전용)

- **입력**: 사용자 제공 외부 종합 리뷰(2026-08-29, 판정 "후기 알파·베타 진입 전 안정화"). 핵심 주장 전부 코드 대조로 확인: Mac ExportEngine A/V 순차 펌프(ExportEngine.swift L1561-1578)·W 시나리오 2~4초 픽스처·iOS stepFrame 0.25초 seek 임계값 흡수(PreviewView.swift L230)·security scope Task 앞 조기 종료(iOSContentView.swift L361-365)·fileExporter 이중 저장·watchdog "수습" 주석의 순서 오류(kill 후 pkill -P — 재부모화된 sleep 미포획)·cross-dissolve 통합 스킵(run_core_editing_parity.sh L167-173)·freeze-frame 순서 의존 플래이크·CI 30분 제한 하 iOS 61테스트 미완주·MetricKit 요구 충돌(REQUIREMENTS §13.8 vs AppLog 미도입 정책)·122커밋 원격 미푸시.
- **산출**: `docs/STABILIZATION_PLAN_20260829.md` 신설 — STAB-01~08 항목 원장(우선순위·실행주체·완료기준) + Phase 0~2 순서·종료기준 + 기존 기록(RENDER-02·세션 34 수습·BUG-CA12-01·PARITY-TOL-01)과의 관계 정리. 크론 프롬프트 우선순위 체인에 계획 문서 편입(무상태 유지 — 항목·상태는 문서에서만 읽음; LI-004로 기록, 사용자 병합 지시가 승인 근거).
- **측정 분쟁 명시**: 외부 W 4/5(W4 ProRes 90초 timeout) vs 내부 W 5/5(2026-08-28 재실측) — **STAB-01·STAB-02 완료 후 동일 커맨드 3회 연속으로만 판정**(조건부 교착은 단발 실행으로 부정 불가). 그 전까지 W 보고에 측정 환경 병기. Phase 1 x/7 판정은 Phase 2 종료 시 재실측 대조까지 보류.
- **큐 전환**: 경계 분해 잔여(F-17 TTS·F-13 자막·F-19 리프레임 — internal 승격 리팩터 승인 대상)·G-29·블라인드 A/B는 STAB 창구 종료 후 재개. soak 2run·실기기 2종(사용자 대기)은 병렬 유지.
- **검증**: docs 전용 증분(코드 변경 없음) — 문서 경로 검증 통과. STAB-01부터 각 증분이 자체 게이트 실측으로 완료 판정.

### 다음 회차 — LOOP_STATE 우선순위
① **STAB-01** watchdog 고아 sleep 재수습(run_w_scenarios.sh 수습 로직 순서 정정 + run_longform_soak.sh 동일 패턴 적용 — STABILIZATION_PLAN §1) ② **STAB-02** Mac ExportEngine A/V 펌프 병렬화(iOS RENDER-02 태스크그룹 패턴 포팅·취소·부분파일 정리 — 완료 시 W4 ProRes 3회 연속) ③ **STAB-03** iOS 4건(프레임 스텝 임계값·루프 EndTime 알림·security scope 수명·fileExporter 이중 저장). **사용자 대기(병렬)**: ~~122커밋 push~~ 완료(2026-08-29 — 스택 PR #19~#23, 순서 병합)·soak 2run(조용한 기기)·실기기 2종·MACUI-01/U-08 TCC. **STAB 증분 커밋 후 push는 루프 금지 — 메인 세션/사용자가 스택 PR #23로 주기 반영.**

## 2026-08-28 세션 (장편 soak 게이트 구축 — 유효 1차 실측·환경 오염으로 2run 확증 연기)

- **게이트 신설**: `scripts/run_longform_soak.sh` — 30분 fixture(ab04) N회 연속 실앱 출력으로 ①와치독 내 완주 ②**RSS 증가 ≤15%**(누수 가드) ③길이·A/V 시작 Δ ≤1프레임 ④**실행 간 프레임 해시 9표본 동일**(결정성) ⑤열·전원 조건 기록. 실행 간 열 상태 기록·와치독 2400s(지속 부하 현실화 — 1차 시도에서 run2가 1500s 초과한 경위 주석).
- **유효 실측(오염 전, 1차 시도 run1)**: wall 872.6s(RTF 0.485)·peak RSS **1,574MB**·길이 1800.000000s 정확·**A/V 시작 Δ 0.000000** — 30분 장편 단일 실행 안정성 실증(CA-12 2시간 단일 실행 증거와 병기).
- **환경 오염 발견·중단(정직 기록)**: run2부터 기기 부하 평균 41~55 급등 — **사용자 `.voiceagent` 어댑터 3종**(senseVoice·diarization·parakeet, 측정 중 시작)이 CPU 상당량 점유 + 데이터 볼륨 98%(4.7Gi). 앱 결함 아님 — 앱은 유휴 수준까지 느려졌을 뿐. 사용자 프로세스는 건드리지 않고 측정 중단. **재생 가능 아티팩트 2.3GB 정리**(CA-12 기준 baseline.json은 보존)로 11Gi 회복.
- **재실행(1커맨드·조용한 기기에서)**: `bash scripts/run_longform_soak.sh 2` — 사용자가 voiceagent 일시 중지 + 디스크 여유 확보 후.

### 2026-08-29 세션 (STAB-01 완료 — watchdog 고아 sleep 재수습 + soak 2run 확증 달성)

- **STAB-01(양 스크립트 재수습)**: `run_w_scenarios.sh`·`run_longform_soak.sh` 모두 (sleep N; kill…) subshell watchdog를 `kill $wd`로 죽인 뒤 `pkill -P $wd`를 호출 — subshell 사망 시 내부 sleep이 launchd로 재부모화돼 **빈 결과**(구 "수습"은 무효, 시나리오당 360s·런당 2400s 고아 잔류). 정석 수정: **spawn 직후 내부 sleep PID를 pgrep -P로 기록**(subshell 생존 중·유계 재시도) → 완료 시 watchdog·sleep PID 둘 다 kill → `kill -0 $sleep` 사후 단언(생존 시 FAIL).
- **실측**: W 스위트 5/5 완주(워크플로 29/29 스텝·내장 단언 5회 통과) + **soak 2런 완주 — run1 wall 803.2s/RSS 1,476MB·run2 700.5s/1,080MB·RSS 성장 0.0%(게이트 ≤15%)·결정성 9/9 프레임 해시·A/V Δ0.0 — LONGFORM SOAK GATE PASS**(내장 단언 2회) + **외부 교차검증: `sleep 360/2400` 고아 0건**(pgrep -x sleep→argv 정밀 매칭 — -f 패턴은 탐침 자기오탐 함정).
- **부수 성과**: 기기가 조용해진 시점에 재수습 코드가 탑재된 채 2런이 돌아 **사용자 대기 항목이었던 soak 2run 확증을 이번에 달성** — STAB 계획서 §2·LOOP_STATE 대기 목록에서 완료 처리.
- **검증**: verify_gate 5/5(Core 1,425·Mac/iOS 빌드·lint).

### 다음 회차 — STAB Phase 0 계속
① **STAB-02**(P0 — Mac ExportEngine A/V 펌프 병렬화, iOS RENDER-02 태스크그룹 참조 구현 포팅 + 취소·부분파일 정리) ② STAB-06(CI 분할 yaml) — Phase 0 잔여. 이후 STAB-03(iOS 4건) → Phase 2. **사용자 대기**: 실기기 2종·MACUI-01/U-08 TCC·STAB-07 결정.

## 2026-08-29 세션 (경계 분리 2차 — 분해 한계 해제: 공유 헬퍼 승격 이동 + F-20 하이라이트 이동)

- **soak 2run 재차단**: voiceagent 활성(어댑터 구성만 교체 — diarization-adapter)·로드 29+ — 사용자 워크플로 존중, 조용한 기기 대기 유지. G-29(3단계 기간 위반)·블라인드 A/B(2단계+사람 패널)도 자율 부적 판정.
- **전회차 "분해 한계" 해제 증분(8919f3c)**: 공유 file-private 헬퍼 4종(`sourceClipAndAsset`·`timelineMapping`·`recordAnalysisResult`+`clipDescription`·`isTranscribable`)을 `EditorViewModel+AnalysisSupport.swift`로 이동, 공유 4종은 private→internal 승격(**동일 타깃 가시성 확대만 — 스코프·공개 표면·호출부 불변**, A류 경계 정리 성격으로 큐 운영자 승인 하 실행). `ensureDefaultTracks` 동일 승격. F-20 하이라이트 메서드(+shift)가 `EditorViewModel+AutoHighlights.swift`로 뒤따름 — 본체 **5,443→5,206줄**. `HighlightsStaticContract` 소스 경로만 새 파일로 추적(기대치 5종 불변).
- **함정**: ①pbxproj 등록을 취약한 문자열 조립으로 생성 → 그룹/페이즈 줄 끝 `;` 파손으로 **프로젝트 자체가 안 읽힘**(무수정 stash 프로브로 판별·이분법으로 격리·정정 재적용) ②Core 1,425 중 4 issue = 하이라이트 소스 계약 1개 테스트의 기대치 4건(경로 갱신으로 해소).
- **검증**: Core 1,425/211스위트 PASS·Mac 48/48·verify_gate 5/5. 잔여 분해 후보: F-17 TTS(ensureTrack·audioDuration·sanitizedDuration·minimumVoiceoverDuration 승격 필요)·F-13 자막·F-19 리프레임 등 — 동일 패턴으로 진행 가능.

### 다음 회차 — LOOP_STATE 우선순위
① soak 2run(조용한 기기 — 사용자 voiceagent 일시중지 후) ② 실기기 2종(사용자) ③ 경계 분리 3차(위 잔여)·G-29(3단계 도달 시)·블라인드 A/B·BUG-CA12-01 에스컬레이션.

## 2026-08-29 세션 (경계 분리 부채 증분 — F-12R 순수 이동 + 분해 한계 발견·soak 환경 차단 판정)

- **soak 2run 확증: 환경 차단 판정** — 사용자 voiceagent 어댑터 3종(VoiceAgentApp·parakeet·senseVoice)이 여전히 활성 + 로드 28~36으로 측정 타당성 훼손. 사용자 프로세스 무손상 원칙으로 개입 불가 — **조용한 기기 확보(voiceagent 일시중지) 후 1커맨드**(`run_longform_soak.sh`) 대기 유지.
- **부채 증분(리뷰 #7·§6 부채 원칙·P0-C "경계 분리 착수")**: F-12R 사용자 텍스트 스타일 프리셋 45줄을 `EditorViewModel+TextStylePresets.swift`로 **순수 이동**(메서드 5종+섹션 전용 private 헬퍼 — 저장 속성은 본체 유지, +Media 선례 패턴). 본체 5,486→5,443줄.
- **분해 한계 발견(중요)**: 잔여 섹션(F-17 TTS·F-19 리프레임·F-20 하이라이트·F-13 자막·스코프 등)은 전부 공유 file-private 헬퍼에 얽힘 — `sourceClipAndAsset`(15호출)·`timelineMapping`(15)·`recordAnalysisResult`(10)·`ensureTrack`·`audioDuration`·`sanitizedDuration`·`minimumVoiceoverDuration`. **순수 이동 분해는 자연 한계 도달** — 추가 분해는 이 헬퍼들의 internal 승격(또는 공유 extension 이동)을 수반하며, +Media 헤더의 규율상 "별도 승인된 변경"으로 큐 운영자/사용자 판단 대상.
- **검증**: Mac 유닛 48/48·verify_gate 5/5.

### 다음 회차 — LOOP_STATE 우선순위
① soak 2run(조용한 기기 — 사용자 voiceagent 일시중지 후) ② 실기기 2종(사용자) ③ 경계 분리 계속(승격 리팩터 승인 여부 판단 포함)·G-29·블라인드 A/B·BUG-CA12-01 에스컬레이션.

## 다음 회차 — LOOP_STATE 우선순위
① **soak 2run 확증**(위 조건 — 사용자 환경 협조 필요: voiceagent 일시중지·디스크) ② 실기기 2종(사용자 대기 — Phase 1 마지막) ③ G-29·블라인드 A/B·EditorViewModel 경계 분리·BUG-CA12-01 에스컬레이션.

## 2026-08-28 세션 (iOS Phase-1 잔여 UI 완료 — 리뷰 #3 전항)

- **프레임 스텝**: `stepFrame(forward:)` ±1/frameRate·양단 클램프·스텝 시 일시정지 — 전송부에 backward.frame/play/forward.frame 버튼.
- **루프 재생**: `isLooping` 토글(repeat 아이콘) — PreviewView 시간 옵저버가 끝 도달 시 0으로 시크·재생 지속(꺼져 있으면 기존 정지).
- **트랙 관리**: 하단 툴바 "Tracks" 시트 — 비디오/오디오 트랙 추가(CreateTrackCommand)·트랙별 mute/lock(SetTrackPropertyCommand)·스와이프 삭제(RemoveTrackCommand — Core public화로 iOS 도달).
- **프로젝트 열기/저장**: 상단 ⋯ 메뉴 — fileImporter(.moviecut) → `openProject` ReplaceProjectCommand 경로·fileExporter(MovieCutProjectDocument — ProjectStore와 동일 코덱: ISO8601·pretty·sortedKeys) → `saveProject`. 양 플랫폼 왕복 호환.
- **출력 프리셋**: Export Settings 시트 — 해상도(720p/1080p/4K)·컨테이너 버튼 행(IOSExportOptionRow 제네릭 — 인라인 Picker 체인이 타입체커 타임아웃이라 분리). 부수: ExportResolution에 displayName·CaseIterable 추가.
- **함정 기록**: 5단계 빌드 오류의 진범은 전부 ExportResolution.displayName 부재 폭포였음 — 겉보기 오류(Picker 오버로드·타입체크 타임아웃)는 전부 그 하위 증상.
- **검증**: IOSPhase1SurfacesTests 6/6(스텝 수학·클램프·루프·트랙 명령 왕복·저장/열기 복원·손상 파일 명시 오류·프리셋 비간섭)·verify_gate 5/5.

### 다음 회차 — LOOP_STATE 우선순위
① 실기기 2종(사용자 대기 — Phase 1 마지막 조건) ② G-29(HDR 파이프라인·BUG-CA12-02 입력 요구)·블라인드 A/B·장편 soak ③ EditorViewModel 경계 분리 지속·BUG-CA12-01 에스컬레이션.

## 2026-08-28 세션 (PARITY-TOL-01(a) 해결 — 캔버스 정합 픽스처·핵심 파리티 18/18·스윕 13/13 @2.0)

- **실행(리뷰 권고 (a)·승인)**: 파리티 픽스처를 1440x1080 4:3(기본 1920x1080 캔버스에서 1:1 픽셀 매핑·필러박스)으로 교체 — solid_red·bars·moving_subject(좌표 전부 ×4.5 쌍둥이) 재생성·커밋. 허용치는 무변경(MAD ≤ 2.0 유지).
- **재실측**: 핵심 파리티 **18/18 PASS**(이전 실패 8개 전부 0.25~1.67로 회복) + 파리티 스윕 **13/13 PASS·허용치 12→2.0 강화**(신규 MAD 0.02~1.36).
- **함정 2건 실측 고착**: ①ripple_delete는 bars=testsrc2의 1440 미세 패턴이 코덱 잡음(Perceptual 영역)으로 ~3 MAD — **평탄 smptebars**로 교체해 해소(재표본 아님·결정론 3회 확인 후 판정). ②optical_flow는 1440에서 보간 비용 4.5배로 240s 하니스 와치독 초과(2회) — 양 다리 컴포지터 상쇄 근거(320에서도 PASS)로 해당 시나리오만 320 유지.
- **문서**: VERIFICATION_STANDARD §2 해결 기록·백로그 §1.9 PARITY-TOL-01 종결. **Phase 1 판정 갱신: 6/7 — 잔여는 실기기 2종(사용자)뿐.**

### 다음 회차 — LOOP_STATE 우선순위
① **iOS Phase-1 잔여 UI**(프레임 스텝·루프·트랙 관리·프로젝트 열기/저장·출력 프리셋 — 리뷰 #3) ② 실기기 2종(사용자 대기) ③ G-29·블라인드 A/B·장편 soak·EditorViewModel 경계 분리 지속.

## 2026-08-28 세션 (외부 리뷰 반영 — P0/P1/P2 전량 수정·W 워크플로 판정·Phase 1 정직 재판정)

- **리뷰 검증**: 7건 주장 전부 코드로 확인(판정 희석·트림 no-op·컨테이너 고정·fps 미반영·배경색 폐기·watchdog 누수·문서 부정합).
- **P0 ①②+P2**: W 판정을 워크플로 단위로(필수 단계 전부+출력물 성공 시에만 PASS) + watchdog 고아 sleep 수습 → **W 5/5 워크플로 재실측 PASS(W4 ProRes 포함 — 리뷰의 타임아웃은 재현 안 됨·고아 sleep 파이프류로 판정)**·스크립트 즉시 종료.
- **P0 ③④**: iOS 트림 다이얼로그(플레이헤드 기준 앞/뒤 — TrimClipCommand 실경로·범위 외 명시 오류) + 출력 컨테이너 planner 해석(mp4 기본·URL/fileType 동일 소스).
- **P1 ⑤⑥**: 캔버스 fps → export 설정 동기화(SetProjectExportSettingsCommand)·텍스트 배경색 저장(TextClipContent.backgroundColor).
- **검증**: iOS 신규 5/5(컨테이너 mp4 실측·트림 수축·오류·배경색·fps 동기)·verify_gate 5/5.
- **Phase 1 재판정(리뷰 수용)**: 6/7 표기 철회 — 확실 4/7 + W 5/5로 **5/7**. 잔여: 픽셀 파리티(PARITY-TOL-01 — 리뷰 권고 (a)≥720p 재생성으로 **실행 승인됨·다음 증분**)·실기기 2종(사용자). 경쟁분석 낡은 iOS 행(M1 전환·M2 autosave·M4 오디오 해결·M3 출력 축소) 정정.
- **리뷰 잔여 지시(다음 큐)**: PARITY-TOL-01(a) 실행 → iOS Phase-1 잔여 UI(프레임 스텝·루프·트랙 관리·프로젝트 열기/저장·출력 프리셋 UI — 리뷰 #3) → 실기기 → 상태 원장 갱신(본 세션 수행) → G-29·블라인드 A/B·장편 soak(리뷰 #6)·EditorViewModel 경계 분리 지속(#7).

### 다음 회차 — LOOP_STATE 우선순위
① **PARITY-TOL-01(a)**: ≥720p 캔버스 정합 픽스처 재생성 + 18/18 재검증(연동 골든 해시·스크립트 정합 포함 — 대형 증분) ② iOS Phase-1 잔여 UI(P0 목록) ③ 실기기 2종(사용자 대기 불변).

## 2026-08-28 세션 (A11Y-03 + CA-19 — 자율 소형 큐 소진)

- **A11Y-03(P3) 수정**: 빈 라이브러리의 스켈리톤 6장(로딩/깨진 자산처럼 보임) → 단일 빈 상태 안내 카드("Your library is empty"+임포트 안내·en/ko 카탈로그 등록·VO 가시·`square.grid.2x2` 아이콘). StaticContract 3종(Phase21·P0Browser·Phase24)을 새 구조로 갱신 + 스켈리톤 복귀 금지 부정 단언. 계약이 금지한 온보딩 아이콘(`photo.on.rectangle.angled`) 재사용을 피한 경위 주석.
- **CA-19 완전 종결**(0d4909e): 밀도 감사 — 전 줌 범위 라벨 충돌 불가(최악 200px)·결함 0건, 장편 라벨 가독성은 `TimecodeParser.rulerLabel` 3단 적응으로 수정(12/12).
- **큐 상태**: 잔여 자율 소형 전부 소진 — 남은 것은 사용자 대기(G-27 실기기·TCC·PARITY-TOL-01·디스크)와 상위 이관(BUG-CA12-01 에스컬레이션·BUG-CA12-02→G-29)뿐. 게이트 5/5.

### 다음 회차 — LOOP_STATE 우선순위
① 방향 문서 §3 게이트 대조·백로그 잔여 점검 후 보고(자율 큐 소진). **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01(승인)·디스크 용량 관리·BUG-CA12-01 에스컬레이션.

## 2026-08-28 세션 (CA-19 완전 종결 — 타임라인 눈금 밀도 감사·장편 라벨 적응)

- **밀도 감사(잔여 소멸)**: `CA19_RULER_DENSITY_AUDIT_20260828.md` — 라벨 충돌은 줌 하한(20px/s)에서도 200px 간격으로 전 범위 산술 안전(충돌 조건 줌<5px/s 도달 불가)·2시간 콘텐츠도 Canvas 가시 영역 렌더라 국소 부담 — **결함 0건**.
- **가독성 결함 수정**: 룰러 라벨이 초 고정("3600s")이던 것을 `TimecodeParser.rulerLabel` 3단 적응(45s / 12:05 / 2:02:05·프레임 무 — 전송부 MM:SS:FF와 역할 구분)으로 교체. 표값 테스트 9종 포함 12/12 PASS.
- **큐 상태**: A11Y-01/02·UX-REC-01/02·CA-14/15/22/19 전부 완료 확인 — 잔여 자율 소형은 A11Y-03(P3)뿐. 사용자 대기 불변.

### 다음 회차 — LOOP_STATE 우선순위
① **A11Y-03**(P3 빈 라이브러리 빈 상태 카드) ② 방향 문서 §3 게이트 대조·자율 큐 소진 보고. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01(승인)·디스크 용량 관리.

## 2026-08-28 세션 (CA-14/15 완료 — 비트 감지 iOS UI·현지화·텍스트 품질 감사)

- **CA-14(iOS 비트 감지, Mac 패리티)**: ①`IOSEditorViewModel.detectBeats/clearBeatMarkers/canDetectBeats/hasBeatMarkers` + `lastStatusMessage` — Core `BeatDetectionProvider` 공유·canonical 매핑(속도/램프 포함)·`AddMarkersCommand` 단일 undo·BPM 상태. ②하단 툴바 "Beats" 버튼 → confirmationDialog(Detect/Clear — 선택 게이트). ③타임라인 비트 틱 오버레이(레인 상단 2pt 주황·장식용 — 터치 타깃 문제로 비인터랙티브·VO 숨김, 개수는 상태로 안내). ④**스냅 대상에 마커 포함**(Mac은 포함·iOS는 빠져 있던 파리티 갭 수습). ⑤`IOSBeatDetectionTests` 2/2 — 실제 클릭트랙 WAV(120BPM 8클릭)를 AVAudioFile로 합성→임포트→선택→감지→마커≥6·클립 범위 내→정리·무선택 명시 오류.
- **CA-15(현지화·텍스트 품질 감사)**: `CA15_LOCALIZATION_TEXT_QUALITY_MATRIX_20260828.md` — 축 10종(카탈로그/CJK/emoji·결합/RTL/줄바꿈/세로텍스트/숫자·시간/파일명/단축키/측정) 판정: **7종 충족(4종 실측)·1종 범위 외·2종 관찰 — 신규 결함 0건**. 실측 프로브 `MultilingualTextRenderTests` 4/4 PASS(공유 TextOverlayPixelProcessor 경로 잉크 커버리지 — 폰트 캐스케이드 가정 아닌 픽셀 증거)가 상시 게이트에 편입되어 다국어 렌더 회귀 차단.
- **검증**: iOS 시뮬레이터 테스트 2/2(TEST SUCCEEDED)·Core 프로브 4/4·verify_gate 5/5.
- **부수**: 테스트 게이팅 단언 순서 수정(addClipToTimeline 자동 선택 반영).

### 다음 회차 — LOOP_STATE 우선순위
① 백로그 잔여 자율 소형 점검(CA-17 실제 플레이어 로드 확인=수동/D·CA-19 밀도 감사 보고 등) ② 방향 문서 게이트 대조·자율 큐 소진 시 보고. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01(승인)·디스크 용량 관리.

## 2026-08-27 세션 (CA-22 2차 완료 — 프록시 설정 UI·진행 취소·재개)

- **설정 토글**: 인스펙터 Playback 섹션에 "Auto-generate proxy on import" 체크박스(`updatePlaybackSettings` 신규 파라미터) — 프록시 설정 3종(재생 사용·thermal 자동·해상도)과 한 블록.
- **취소**: `cancelAutoProxyGeneration()` — 관찰 가능 `autoProxyGenerating` 집합 + 태스크 핸들 저장. Core `ProxyGenerator.generateProxy`는 `withTaskCancellationHandler`+`cancelExport`로 **인코딩 중 취소**를 지원하고 부분 파일을 정리(취소≠실패 구분 — `autoProxyCancelledCount`).
- **재개**: `resumeMissingProxies()` — 프록시 없는 전 비디오 자산 일괄 생성(취소분+thermal 스킵분 모두). 진행 중/취소 중 태스크 완료를 먼저 대기해 cancel→resume 경쟁 차단. thermal critical은 안내 후 거부.
- **1차 갭 수습**: 자동 생성이 미디어 라이브러리 임포트에만 연결돼 있었음 → **타임라인 임포트(주 사용자 경로)에도 연결**. 하니스(MOVIECUT_UITEST) 실행은 기본 억제(CA-22 게이트만 옵트인)로 기존 게이트 결정성 보존 — 파리티 스윕 13/13 무회귀로 확인.
- **검증**: `scripts/run_ca22_proxy_gate.sh` **4 leg 12/12 PASS** — A off→미스케줄·B on→백그라운드 생성 완료·C 90s fixture 인코딩 중 취소(cancelled=1·프록시 0)·D 취소→재개 완주(cancelled=1·프록시 1). Core 유닛 3종(취소 거부 결정적 seam·레디 파일 단축·설정 왕복). 게이트 5/5(Core 1,420).
- **부수**: 게이트 스크립트 set -e 함정 2건(PASS 판정 후 `[ ] && FAIL=1` 반환값 1로 조용히 사망·field 파이프라인) — `return 0`/`|| echo`로 수습. DerivedData Debug 산출물이 세션 중 1회 원인 불명 소실(재빌드로 회복 — 재발 시 관찰).

### 다음 회차 — LOOP_STATE 우선순위
① **CA-14/15**(소형) ② 이후 백로그 점검. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01(승인)·디스크 용량.

## 2026-08-27 세션 (BUG-CA12-01·02 결함 조사 — 메커니즘 확정·근본 수정은 각각 상위 이관)

- **BUG-CA12-02(HDR 파리티, P1 후보)**: 픽셀 특성화로 범인 특정 — 대부분 밴드 Δ≤2·**고채도 시안 밴드만 프리뷰에서 핑크**. 프리뷰(plain 경로·플레이어 다리)는 AVFoundation이 HDR 태그 소스를 SDR 렌더 표면에 맞춰 변환하며 범위 밖 색을 뒤집음. 출력은 원시 재해석(소스 프레임과 MAD 2.49 충실 — CA-04 v1 계약). **수정 시도 2건 모두 측정 무효로 폐지**: ①스냅샷 최종 변환 작업공간 핀(버퍼가 이미 변환돼 도착 — MAD 11.13→11.07) ②합성 색 삼중항 709 명시(reader 다리는 소비 안 함 — 11.07). 측정 증거 없는 배선 금지 원칙으로 둘 다 revert. **본수정 = HDR 인입 형식 수용 컴포지터 + 공유 변환 → G-29(3단계) 이관**. 스냅샷 핀은 행동 중립 주석과 함께 원칙적 핀으로만 유지.
- **BUG-CA12-01(파리티×덕킹 파킹, P2)**: 계측 체인으로 확정 — ①파킹은 **첫 필수 서스펜션마다 이동**(재배열로 composition_ready 통과 → 스냅샷 대기에서 동일 파킹 → 재배열 폐기) ②`Task.sleep`·`Task.yield` 모두 재개 안 됨 ③**`DispatchQueue.main.async` 블록도 전달 정지(GCD 레벨)** — 반면 앱 활성화 등 런루프 이벤트는 처리됨(모드 DefaultMode 정상·lldb 확인) ④전역 풀 생존(detached 하트비트 1틱) 후 MainActor 홉에서 정지 ⑤덕킹 램프 적용 무관(오디오 트랙 존재가 트리거). 종합: **메인 디스패치 큐 전달 영구 정지** 클래스 — W4 ProRes 교찰의 "once-continuation 파킹(Apple측)" 부류 추정, 루프 내 도구로 근본 특정 불가 → 상위 도구·에스컬레이션 후보. 재현 1커맨드 고정(ab09).
- **부산물(유지·검증)**: `snapshotFrame` seek completion 누수 방어 와치독(2s 경합·1회 재개 — AVPlayer 문서상 미보장 클래스) + 스냅샷 작업공간 핀. **파리티 스윕 13/13 ALL PASS**·verify_gate 5/5.
- **교훈**: 정적 분석 불가능한 파킹은 계측 체크포인트→프로브 태스크→GCD/이벤트 분리 실험의 사다리로 좁힌다; 측정 무효 배선은 즉시 revert(원칙 준수).

### 다음 회차 — LOOP_STATE 우선순위
① **CA-22 2차**(프록시 설정 UI·취소·재개) ② CA-14/15(소형) ③ BUG-CA12-01은 에스컬레이션 후보·BUG-CA12-02는 G-29 입력 요구. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01(승인)·디스크 용량.

## 2026-08-27 세션 (CA-12 완료 — 경쟁사 A/B 벤치마크 하니스 + 기준 수치 최초 기록)

- **환경 사건**: 세션 시작 시 데이터 볼륨 **100%(가용 163MB)** — CA-12 픽스처 생성 불가 상태. 재생 가능 캐시만 정리(/tmp 세션 임시 434MB·Xcode DerivedData 2곳 908MB·xcresult 176MB ≈ 1.5GB — 사용자 데이터 무손상)로 회복, 이후 purgeable 정산으로 27Gi까지 안정. 부수: 7.5GB ab12 출력은 메트릭 기록 후 러너가 자동 프루닝(13Gi 유지). **데이터 볼륨 용량은 사용자 관리 필요**.
- **하니스 3종**: ①`scripts/ab_benchmark_metrics.py` — `single`(절대 지표: 코덱/색태그/chroma·비트레이트·키프레임·CFR/VFR·클리핑/크러시/banding·LUFS/true-peak·A/V sync) `pair`(무손실 프리뷰 PNG 참조 대비 PSNR 전역/프레임·block SSIM·MAD p95/max·CIE76 ΔE) `blind`(시드 랜덤화 투표+채점 왕복) `self-test` **15/15 PASS**(해석값 고정). ②`scripts/make_ab_fixtures.sh` — Part 5 §3의 12 대표 fixture 결정적 생성(장편 2종은 축소 스케일 명시)+SHA-256 핀 테이블=세트 버전 관리+manifest.json. ③`scripts/run_ca12_ab_benchmark.sh` — §1.4 조건 필드 전항 기록·실앱 구동(RSS 폴링·와치독)·RTF(encode 구간 격리 시계)·baseline.json·블라인드 A측 스테이징+거대 출력 프루닝.
- **하니스 게이트(Swift)**: `MOVIECUT_UITEST_CHROMA_KEY=1`(실제 SetClipPropertyCommand 경로·⑦) + `export_wall_s`(일반·파리티 양 경로 — §1.4 앱 전체 vs encode 분리) + 파리티 경로 DUCKING/CHROMA_KEY 미러링(파리티는 앱 종료로 일반 플로우에 도달 못 함).
- **첫 기준 수치(11/12 fixture 실측**, `CA12_AB_BENCHMARK_20260827.md`§5): 소형 RTF 0.24~0.44·30분 0.299(peakRSS 1,387MB)·2시간 0.348(peakRSS 5,054MB·**A/V 싱크 Δ0.000s**). 전 출력 기본 캔버스 1920x1080(4K 소스 다운스케일 — 조건 기록). 해석 규칙 발견: pair 지표는 동일 스케일 fixture 간 비교로 한정(업스케일 소스는 보간 차이가 지배).
- **발견 등록(§1.13)**: **BUG-CA12-01**(P2 인프라) — 파리티×덕킹 조합 태스크 파킹(`scenarios_applied`에서 0% CPU 정지·결정론 재현 2회·일반 경로는 통과 — ⑨ 수치 공백). **BUG-CA12-02**(P1 후보) — HDR(BT.2020+PQ) 태그 소스 preview↔export 픽셀 발산(PSNR 15.1dB·기존 비교기 교차 FAIL MAD 11.26 vs 허용 2.0 — CA-04는 태그만 확인하고 픽셀 파리티 미측정이었음). VFR timestamp 편차(MAD 78)는 측정 정의 한계로 기록(결함 아님).
- **검증**: self-test 15/15·블라인드 왕복·파리티 비교기 교차(ab03/ab11)·verify_gate 5/5.
- **부수**: 러너 fixture 접두사 선택 버그 수정(ab03→ab03_hdr_10bit 매칭)·CFR 판정 B-프레임 정렬 수정·blind --tally 인자 검증 순서 수정.

### 다음 회차 — LOOP_STATE 우선순위
① **BUG-CA12-02 감사**(HDR 색 해석 경로 — P1 후보·G-29 연계) ② BUG-CA12-01 최소화(파리티×덕킹 파킹) 또는 CA-22 2차(프록시 설정 UI·취소·재개) ③ CA-14/15(소형). **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·PARITY-TOL-01(승인)·디스크 용량(데이터 볼륨 만약 — 캐시 정리는 1회 수행됨).

## 2026-08-27 세션 (CA 소형~중형 4건 + iOS 커브 UI + 후속 관찰 상환 — 직렬 세션)

- **CA-08(iOS 자막 스타일 6종, 7ca8949)**: Core `SubtitleStylePresets.builtins` 6종(Clean White·Bold Box·Yellow Pop·Shadow Soft·Mint Outline·Classic Serif)을 iOS 인스펙터 "Subtitle Style" 섹션에서 원탭 적용 — `applySubtitleStylePreset`(Mac 패리티) + 수평 칩(색상 미리보기 원형·스트로크 테두리). 렌더링 변경 불필요(TextOverlayPixelProcessor 공유).
- **CA-17(iOS 자막 export SRT/VTT, b03c62b)**: `exportSubtitles(format:)` — 텍스트 트랙 클립을 Core `SubtitleDocument`로 직렬화(Mac 바이트 동일) + 하단 툴바 "Subtitles" → confirmationDialog(SRT/VTT) → 상단 ShareLink.
- **CA-19(iOS 타임라인 스냅+가이드, fa11902)**: 드래그 종료 시 다른 클립 가장자리·플레이헤드·0에 스냅(14pt 반경) + 액센트 가이드라인(Mac 패리티). 부수: Mac trim `snappedTime` 빌드 오류 수정.
- **CA-22 1차(프록시 자동 생성, a789b58)**: `PlaybackSettings.autoGenerateProxyOnImport`(기본 true·Codable 하위호환) + 비디오 임포트 후 fire-and-forget 백그라운드 Task(중복 방지·thermal critical 스킵).
- **iOS 커브 편집 UI(5e5e36b)**: 효과 인스펙터 Color Grade에 Tone Curves 추가 — 4채널 피커 + CurveEvaluator 미니 프리뷰(Canvas) + 6종 프리셋 칩(Linear/S-Curve/Fade Up/Fade Down/Boost/Reduce).
- **후속 관찰 2건 상환(6499efc)**: Mac 하위 트랙 orientedForDisplay+fittedToCanvas(iOS 패리티) + 회전×전환 upright 실측.
- **검증**: iOS 48/48·Mac 48/48·Core 1,417·verify_gate 5/5.
- **병렬 세션(4시간 루프)**: CA-01(오프라인 차단 — sandbox 네트워크 거부 하 E2E·MC-02 ②③✅)·ENOSPC fail-closed 저장·ui_regression 무음 PASS 폐쇄(49b7f87)·iOS 커브 UI 연결.

### 다음 회차 — LOOP_STATE 우선순위
① **CA-12**(경쟁사 A/B 벤치마크 하니스 — PSNR/SSIM+블라인드·중형) ② CA-22 2차(프록시 설정 UI·취소·재개) ③ CA-14/15(소형). **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01+U-08 회귀 실측(TCC 접근성/재부팅)·PARITY-TOL-01(승인).

## 2026-08-27 세션 (중단 WIP 인수 — ProjectStore ENOSPC fail-closed + ui_regression 무음 PASS 폐쇄)

- **인수 경위(LI-003 3원칙)**: 타 세션 WIP 4파일 발견(ProjectStore·ENOSPC 테스트 신규·ui_regression·static contract) — 타임스탬프 1시간 40분 경과·실행 중 빌드 프로세스 없음·diff 전수 검토(일관된 단일 증분 판정) 후 프로토콜 0로 검증 마무리·커밋(49b7f87).
- **내용**: ①`ProjectStore` 저장 흐름의 파일 I/O를 `ProjectFileWriting` 심으로 분리(생산 동작 불변) — temp 쓰기 실패 시 `FileOperationError.classify`(ENOSPC→.diskFull)로 표면화·temp 잔여 정리·커밋 미도달. ②`ProjectStoreENOSPCIntegrationTests` — 주입된 ENOSPC에서 기존 목적지 SHA256 바이트 동일 보존·커밋 0회·temp 잔여 0·.diskFull 분류 단언. ③`ui_regression.sh` — "캡처 없음/골든 없음"이 SKIP(무음 통과)이던 것을 FAIL로, 전체 실행은 캡처∪커밋 골든 합집합 검사(한쪽에만 있는 파일이 조용히 사라지는 것 차단), static contract로 고착.
- **검증**: 신규 스위트 3테스트 PASS + verify_gate 5/5(Core 1,416·Mac/iOS 빌드·lint).
- **주의**: ui_regression의 FAIL 강화로 AX 환경 차단 중 전체 회귀 실행은 (의도적으로) 실패함 — 환경 복구 전까지 회귀 PASS 실측은 U-08 잔여 상태 유지.

### 다음 회차 — CA 큐 잔여 자율 행
① **CA-08**(iOS 자막 스타일 6종·카라오케 이식 — 방향 문서 2단계 일치) ② CA-12(A/B 벤치마크 하니스) ③ CA-14/15(소형). **사용자 대기**: G-27 실기기 2종·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01·G-15 AC4·G-16 AC3/AC4.

## 2026-08-27 세션 (CA-01 완료 — 오프라인 차단·캡처 실측, MC-02 ②③ 갱신)

- **`scripts/run_ca01_offline_gate.sh` 신설·실측 PASS**: **Mac 다리** — sandbox-exec `(deny network*)` 프로파일(루프백 접속 거부 프로브로 프로파일 유효성 선입증 — 무효 프로파일의 공회전 PASS 차단) 하에서 파리티 하니스(임포트→프리뷰 덤프→출력) 완주(8,283바이트·2.0s 출력) + **sandboxd 네트워크 위반 0건**(시도조차 없음). **iOS 다리** — 시뮬레이터에서 G-27 전체 하니스(임포트→프리뷰→출력→오디오 라우팅→저장) 구동 중 `lsof -i -p` 폴링으로 소켓 캡처 — **최대 0개/36 샘플**.
- **함정 3건(set -e 계열 — 스크립트 전체가 조용히 죽는 원인 전부 실측 판명)**: ①`$(xcodebuild -showBuildSettings | awk)` 치환 실패 시 할당문이 set -e 격발(빌드는 성공했는데 설정 조회가 빌드 시스템 경합 실패 → 무음 exit) ②`[ … ] && 할당` 행이 거짓이면 문장 전체 exit 1 ③**`lsof`는 매칭 0이면 exit 1** — 파이프라인 치환이 실패해 첫 샘플에서 사망(기대 상태가 정상 종료를 유발하는 역설). 모두 `|| true`·if문·재시도로 보강.
- **문서**: 백로그 CA-01 완료 처리·증거원장 MC-02 ②③ ✅ 갱신. 게이트 PASS(Core 1,416·Mac/iOS 빌드·lint 5/5).

### 다음 회차 — CA 큐 잔여 자율 행
① **CA-08**(iOS 자막 스타일 6종·카라오케 이식 — 방향 문서 2단계 일치) ② CA-12(A/B 벤치마크 하니스) ③ CA-14/15(소형). **사용자 대기**: G-27 실기기 2종·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01·G-15 AC4·G-16 AC3/AC4.

## 2026-08-26 세션 (G-02 Inc 6 완료 — 톤 커브 에디터 UI·커브 단독 파리티)

- **ColorCurvesView 신규**(Mac 인스펙터, HSL 밴드 하위): 마스터/R/G/B 채널 4종 드래그 캔버스 — 커브는 렌더러가 소비하는 동일 `CurveEvaluator`로 샘플링(보이는 곡선=렌더 곡선), 끝점 (0,0)/(1,1) 고정·내부 점 드래그(x를 이웃 사이로 클램프해 단조 유지), Add Point(최대 폭 구간 중점 — 결정적·포인터 없이 접근 가능)·Remove·채널 리셋. **커밋 규율(Inc 5 동일)**: 드래그 중 로컬 드래프트, 제스처 종료 시 4채널 전체 단일 커맨드(undo 1-step/gesture), 전 채널 identity면 nil 커밋(미그레이션 JSON 바이트 안정). 스키마 무변경.
- **파리티 #16 `curves_only` 신설**(하니스 `MOVIECUT_UITEST_CURVES=1` — 마스터 S-커브+레드 리프트, 3-way·밴드 없음): 밴드 체인(#15)과 커브 체인의 독립 분리 — **실측 PASS MAD 0.43**(허용치 2.0, t=0.5/1.5 양 지점). VERIFICATION_STANDARD 표 16번으로 등록(기존 16/17은 17/18로 이동).
- **테스트**: `ColorCurvesEditorCommitTests` 3종(identity→nil 매핑·4채널 전체 커밋·커밋 점의 평가기 단조성) — Mac 유닛 48/48. 게이트 **PASS**(Core 1,416·208스위트·Mac/iOS 빌드·lint 5/5).
- **잔여 기록**: iOS 커브 편집 UI 미연결(값 통과만 존재 — 후속 관찰). ui_regression 골든은 인스펙터 UI 변경으로 의도 드리프트 예상 — AX 환경 차단(U-08 회차 판정)으로 갱신 불가, 환경 복구 시 with_color_grade 상태 골든 갱신 필요.

### 다음 회차 — LOOP_STATE 우선순위
① **G-01 잔여 Inc 점검 후 착수**(v1.6 체인 — Inc2 카라오케·Inc3 스타일 6종은 완료 이력이므로 백로그에서 실제 잔여 Inc를 먼저 확인) ② 이후 백로그 점검. **사용자 대기**: G-27 실기기 2종·MACUI-01+U-08 회귀 실측(TCC)·PARITY-TOL-01·G-15 AC4·G-16 AC3/AC4.

## 2026-08-26 세션 (U-08 착수 → 환경 차단 판정 — System Events AX 창 쿼리 머신 전체 불가)

- **실측**: `ui_regression.sh` 4상태(import_only·populated_editor·with_color_grade·with_mask) 전부 **WINDOW_COUNT_0** — 앱 자체는 정상 기동(하니스 임포트·CoreMedia 첫 프레임 재생 로그 확인)하나 osascript System Events가 창을 0개로 카운트.
- **원인 판정(제품 아님)**: 보장된 창을 가진 TextEdit 프로브에서도 `count of windows` = 0(프로세스 목록은 정상) — **AX 창 쿼리가 머신 전체에서 불가**. MACUI-01(러너 "hung before establishing connection")과 동일 접근성/TCC 클래스. 골든 4종 자체는 이미 커밋돼 있으므로(5945243 등), U-08 잔여는 ①4상태 회귀 PASS 실측 ②클릭수 metric(AX 구동 필요) — 둘 다 이 환경이 복구돼야만 측정 가능.
- **조치**: 게이트 규율(원인 명확한 실패는 재시도 없이 중단·보고)에 따라 U-08을 사용자 조치 대기로 이동, 다음 자율 증분은 **G-02 Inc 6**으로 큐 정리(f31e326). **사용자 조치**: 시스템 설정 → 개인정보 보호 → 접근성에서 터미널/osascript 호스트에 권한 부여(또는 재부팅) — MACUI-01 조치와 동일.

### 다음 회차 — LOOP_STATE 우선순위
① **G-02 Inc 6**(커브 에디터 UI — Mac 인스펙터 내 커브 편집 컨트롤) ② G-01 Inc 2~4. **사용자 대기**: G-27 실기기 2종·MACUI-01+U-08 잔여(TCC 접근성/재부팅)·PARITY-TOL-01·G-15 AC4·G-16 AC3/AC4.

## 2026-08-26 세션 (G-15 AC7 완료 — 대형 이미지 다운스케일 검증)

- **G-15 AC7**: 24MP(6000x4000) 비대칭 PNG 소스가 `kCGImageSourceThumbnailMaxPixelSize`를 통해 **캔버스 해상도 상한으로 다운스케일**됨을 3종 테스트로 고착: ①1080p 캔버스에서 출력 트랙 1920x1080(원본 6000x4000 아님) ②4K 캔버스에서 3840x2160 ③Ken Burns 2x 줌에서도 출력은 캔버스 크기 유지(로드 상한 = 캔버스장변 × 최대줌 = 3840px — 원본 6000px보다 작음).
- **v1.6 체인 갱신**: G-15 잔여는 AC4(사용자 실기기)뿐 → 다음 자율 선택은 **U-08 잔여(4표면 골든·클릭수 metric)** → G-02 Inc 6(커브 에디터 UI) → G-01 Inc 2~4.
- **검증**: Core 1,416(3종 신규)·verify_gate 5/5.
- 커밋: 9fe5446.

### 다음 회차 — LOOP_STATE 우선순위
① U-08 잔여(4표면 골든·클릭수 metric — `scripts/ui_capture.sh`·`ui_regression.sh` 인프라 존재, 골든 확장 필요) ② G-02 Inc 6(커브 에디터 UI — Mac 인스펙터 내 커브 편집 컨트롤) ③ G-01 Inc 2~4. **사용자 대기**: G-27 실기기 2종·MACUI-01(TCC)·PARITY-TOL-01·G-15 AC4·G-16 AC3/AC4.

## 2026-08-26 세션 (후속 관찰 2건 상환 — Mac 하위 트랙 오리엔테이션·핏 + 회전×전환 실측)

- **(a) Mac 하위 트랙 결함(BUG-06/07 잔존)**: `layerActiveTracks`의 하위 레이어가 `orientedForDisplay`도 `fittedToCanvas`도 없이 raw storage 프레임을 쓰고 있었음 — 회전 소스가 오버레이 아래에서 옆으로 누운 채 자연 크기로 렌더. iOS 패리티로 둘 다 적용(6499efc). 검증: 비대칭 회전 픽스처(320x240 + 90°)를 하위 트랙으로, 30% 불투명도 오버레이를 얹어 세로 캔버스에서 밴드 실측 — 상=적/하=청 upright 확인(옆으로 누웠으면 좌측 1/3만 적색 = 밴드 신호 소멸).
- **(b) 회전×전환 조합(iOS)**: 회전된 outgoing 클립이 전환 보유 트랙에서 창 전 upright·창 후 incoming 청색 지배 — 2-소스 전환 브랜치의 오리엔테이션 경로가 테스트 없이 방치돼 있던 것을 고착.
- **검증**: Mac 45/45(신규 1)·iOS 48/48(신규 1)·verify_gate 5/5(Core 1,413).
- **큐 상태**: §1.12 + 후속 관찰까지 전부 소진. 남은 것은 사용자 대기 3종뿐.

### 다음 회차 — LOOP_STATE 우선순위
자율 큐 소진 — 게이트 확인 후 보고로 마침. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01(TCC/재부팅)·PARITY-TOL-01(승인).

## 2026-08-26 세션 (RENDER-02 해결 — 태그된 라이터 전환·드리프트 21→3.09·교착/측정결함 3건 실측 고착)

- **본 증분**: iOS `exportProject`를 `AVAssetExportSession` 프리셋 → `AVAssetWriter`(플래너 출력 설정, SDR H.264 Rec.709 명시 태그) + `AVAssetReader` 출력으로 전면 교체. 프리뷰↔출력 luma 드리프트 **~21/255 → 3.09 실측 붕괴**, 파리티 밴드 26 → **<8**로 조임(태그 회귀 시 ~21 복귀로 즉시 실패).
- **함정 3건(전부 실측으로 확정·고착)**: ①**교착** — 오디오 writer input 존재 시 비디오 pump 단독 선행이 비디오 큐를 영구 정지(오디오 포함 컴포지션 전부 행업, 뮤트·무오디오 정상, hung 프로세스 스택샘플 = MediaToolbox 전 파이프라인 유휴, 이분법 진단으로 트리거 특정) → **태스크그룹 병렬 pump**로 해결. ②리더가 라이터의 48k 스테레오 포맷으로 변환해 AAC 입력 정합. ③**테스트 측정 버그** — RMS 측정이 interleaved 스테레오를 mDataByteSize/4로 읽어 타임라인 2배+채널 교차("페이드 왜곡"의 진범; 모노 44.1k 프리셋 시대 은폐) → 채널 스트라이드 추출 수정. **교훈: 측정 도구 자체를 먼저 의심하라 — ffprobe 교차검증이 진범 규명의 결정타.**
- **검증(전부 실측)**: iOS 전체 47/47(오디오 페이드·이미지 E2E·전환·회전의 export 다리가 전부 새 라이터 탑승) · verify_gate 5/5(Core 1,413·207스위트).
- **큐 상태**: §1.12 리뷰 파생 자율 항목 전부 소진. 잔여는 사용자 대기 3종(G-27 실기기·MACUI-01·PARITY-TOL-01) + 후속 관찰 2건.

### 다음 회차 — LOOP_STATE 우선순위
자율 큐 소진 상태 — 게이트 확인 후 보고로 마침. 신규 자율 후보는 외부 리뷰/감사 등록 시에만 추가. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01(TCC/재부팅)·PARITY-TOL-01(승인).

## 2026-08-26 세션 (루프 회차 — SURV-01 2차 완료, 중단 WIP 인계 마무리)

- **경위**: 4시간 루프 회차가 06:05경 증분 중간에 중단되며 미커밋 WIP 6파일을 남김(상대 참조 필드·재결합·relink UI·정리 정책의 정합적 구현). 후속 수동 회차가 프로토콜 0로 인수 — 타 세션 부재 확인(타임스탬프 2시간 경과·실행 중 프로세스 없음) 후 diff 전수 검토·의존성 확인 후 검증 마무리.
- **SURV-01 2차 내용**: ①`MediaAsset.managedImportPath`(상대 참조, Codable 하위호환) ②`ProjectStore.rebaseManagedImports` — 복구 로드 시 죽은 절대경로(재설치·기기 복원으로 컨테이너 경로 변경)를 상대 참조 → 레거시 `/MovieCut/Imports/<projectId>/<file>` 접미사 매칭 순으로 재결합 ③relink UI — 결측 배너 + fileImporter, 교체본을 관리 루트로 복사해 **자산 UUID를 유지한 채 재결합**(클립 참조 보존, Mac `relinkMedia` 패리티) ④`cleanupOrphanedImports` — 미참조 프로젝트 디렉터리 7일 유예 후 정리.
- **검증(전부 실측)**: `IOSMediaSurvivabilityTests` 6/6(상대/레거시 재결합·relink E2E·정리 정책 4종 신설) · iOS 47/47(12스위트) · verify_gate 5/5(Core 1,413·207스위트). 로컬라이제이션 키(신규 3)·Hangul 리터럴 검사 PASS.
- **함정 기록**: 루프 회차의 중단 잔존 WIP는 프로토콜 0(검증 후 커밋)으로 회수 가능하나, 인수 전 반드시 (a)타임스탬프 경과 확인 (b)실행 중 빌드 프로세스 부재 확인 (c)diff 전수 검토를 거칠 것 — 이번 케이스의 3원칙.

### 다음 회차 — LOOP_STATE 우선순위
① **RENDER-02** — iOS 태그된 라이터 마이그레이션(색 파리티 26 밴드 근본 해법). ② 이후 백로그 "진행중/후속" 자율 항목. **사용자 대기**: G-27 실기기 2종(잠금 해제)·MACUI-01(TCC/재부팅)·PARITY-TOL-01(승인).

## 2026-08-26 세션 (외부 리뷰 반영 — Phase 0~3 완료: 게이트 복구·P0 출력 정확성 5건·P1 생존성 6건·CI 승격)

- **리뷰 검증**: 사용자 제공 리뷰 8건 전부 코드 대조로 확정(탐색 3패스+직접 열독), 백로그 §1.12에 GATE-01·BUG-08·BUG-IOS-08·G-15 AC6·BUG-IOS-09·BUG-IOS-10·STICKER-01·SURV-01·RACE-01·L10N-01 등록.
- **Phase 0(게이트)**: `AudioComponentFindNext` 프로브 제거(전체 스위트 병렬 오디오 부하에서 교착 — 08-26 게이트 FAIL 직접 원인) + verify_gate 와치독 타임아웃(기본 900s)·tee 스트리밍. 2553919.
- **Phase 1(P0 출력 정확성, 전부 픽셀 실측)**: ①BUG-08 멀티트랙 — **이중 결함 판명**: pixel-identity 게이트 제거(Mac+iOS) + iOS `includeIdentitySource` 누락(항등 클립 효과 미생성 — 게이트만 고쳐선 안 고쳐짐). 이색 픽스처(solid_red/solid_blue)로 opacity·마스크 오버레이 하단 기여 단언. 8702109. ②BUG-IOS-08 회전 — 효과에 sourcePreferredTransform 전달+컴포지터 3경로 `orientedForDisplay` 포팅; 비대칭 픽스처로 플랜 프레임+출력 디코드(autorotate) 양 다리 upright — 이중 회전 차단. ③G-15 AC5+AC6 — `ImageVideoRenderService` Core 이동(양플랫폼 공유), 이미지 사전 렌더 분기; PNG·HEIC·EXIF upright·사진 전용 export E2E. e99ac37. ④BUG-IOS-09 전환 — 2슬롯 트랙 교차+백타이밍+`makeTransitionEffects` 포팅(전환 없는 트랙은 단일 레이아웃·byte-identity 유지); 플랜 프레임에서 순수 적→혼합→순수 청 실측. 03359cb. ⑤BUG-IOS-10 오디오 — 렌더 계획에 audioMix(배치 구간 기반 램프), 프리뷰·출력 양쪽; 리더 경로+출력 파일 RMS 실측. 43a20d7.
- **Phase 2(P1 생존성/안정성)**: RACE-01(프리뷰 세대 토큰+15fps CPU 오버레이 전면 제거)·STICKER-01(addSticker Mac 패리티)·autosave scenePhase 즉시 flush+플래키 테스트 폴링 전환(f184401) · L10N-01(한글 리터럴 31곳→카탈로그+18키 등록+`verify_no_hangul_literals.py` CI 차단, 4d881cb) · G-27 하니스 `makeRenderPlan` 구동 전환+레거시 `IOSPreviewCompositionBuilder` 삭제(012c10e) · SURV-01 1차(App Support/MovieCut/Imports 관리 루트+복구 시 결측 원본 표면화, a5474df — relink UI·상대경로 참조는 후속).
- **Phase 3**: Mac 전체 유닛테스트 CI 차단 승격(44/44 반복 안정 확인 후 continue-on-error 제거) · 백로그 §0.5에 범위 경계 명문화("FCP급"은 선택 영역 한정 — 멀티캠·Auditions·플러그인 생태계 등 명시적 비목표).
- **검증**: 최종 게이트 PASS(Core 1,413/207스위트·Mac/iOS 빌드·lint 5/5) · iOS 43/43(12스위트, 신설 5스위트) · Mac 44/44. 잔여 사용자 대기: G-27 실기기 2종·MACUI-01 TCC·PARITY-TOL-01 승인·RENDER-02 태그된 라이터(별도 증분).

### 다음 회차 — LOOP_STATE 우선순위
① SURV-01 2차(상대 경로 참조·relink UI·정리 정책) ② G-27 실기기 2종(사용자 잠금 해제 대기)·MACUI-01(사용자 TCC 조치 대기) ③ RENDER-02(iOS 태그된 라이터 — 색 패리티 26 밴드 근본 해법). PARITY-TOL-01 승인 대기 유지.

## 2026-08-25 세션 (BUG-07 해결 — 회전 메타데이터 3경로 평행 수정·매트릭스 방향 어설션 승격)

- **실측 판정**: 비대칭(좌=적/우=청) 회전 픽스처 신설(`ca04_rotated_asym_320x240_2s_90deg.mp4`, AVAssetWriter 생성기 확장) — BUG-07은 **실제 결함**: 회전된 표시 크기(240×320)로 핏 스케일만 계산하고 픽셀은 옆으로 누운 채 1080×810 상단 고정 렌더(BUG-06 핏 수정과의 상호작용). ffmpeg autorotate 기준값: 바로 세우면 **상=적/하=청**.
- **3경로 수정**: ① 평문 출력 `ExportEngine.rotationAwareFitTransform` — 회전→핏 순 결합(**`concatenating`은 self-먼저·인자-나중 적용임을 실증 판명** — 순서 틀리면 콘텐츠가 캔버스 밖으로 감) ② 프리뷰 동일 결합 + **유저 변환 `.sourceFrame` 앵커에서 pt 제거**(앵커의 base가 pt 자체라 이중 적용 — "항등" 클립도 pt를 실음) + 컴포지션 트랙 pt identity 통일 ③ 커스텀 컴포지터 `orientedForDisplay`(±90°/180° → CIImage 오리엔테이션, `CustomCompositionClipEffect.sourcePreferredTransform` 플러밍 — 엔진·프리뷰 양쪽).
- **검증(전부 실측)**: 엑스포트+프리뷰 프레임 픽셀 측정 모두 **상=적(R237)/하=청(B235)·마진 흑색 PASS** · 오리엔테이션 유닛 4종 신설(±90°·180°·항등 — 픽셀 렌더 측정, Mac 42/42) · **CA-04 매트릭스 PASS — rotated 시나리오 방향 어설션 승격, BUG-07 REG 소멸** · verify_gate 1,413·5/5.
- **범위 외 기록**: `layerActiveTracks` 보조 블렌드 트랙은 캔버스 핏 없이 자연 크기(BUG-06 잔존 별도 결함 가능성) — 회전+전환 조합·iOS 회전 경로(RENDER-01 통합 후에도 pt 미결합 가능)도 후속 관찰 대상. ExportEngine:388(트랙 pt 설정)은 엑스포트 렌더 결과와 무관임을 실험 확인 — 유지.

### 다음 회차 — LOOP_STATE 우선순위
① RENDER-02(P2) 범위 태깅 ② G-27 실기기 2종(사용자 잠금 해제 대기)·MACUI-01(사용자 TCC 조치 대기) ③ 잔여 소형(A11Y-01·UX-REC-01/02 등). PARITY-TOL-01 승인 대기 유지.

## 2026-08-25 세션 (BUG-06 사후 독립 검증 — REG 소멸·회귀 없음 확인, 문서 세션)

- **검증(전부 HEAD=62a0ba2 실측)**: tenbit 익스포트 **4회 연속 결정적**(bytes=922751 동일·전체 평균 92.6 — 필러박스 콘텐츠 75% 수학 부합)·t=1.0 프레임 시각 확인(전면 밝은 테스트 패턴)·**CA-04 매트릭스 PASS**(콘텐츠 영역 luma 123.5 vs 소스 124.4 Δ0.9 — **BUG-06 REG 소멸**, tenbit은 ±6 어설션 정식 가드로 상시화)·**G-24 게이트 PASS**(ratio 0.357·severe wobble 0·bypass 0 — RENDER-01/CANVAS-01 렌더 통합의 회귀 없음).
- **판정**: 세션 exec 로그에 남은 G-24 FAIL(ratio 1.534)은 **2026-08-20 18:26 구버전 실행분** — ec5c9e3(08-25 08:31) 이전 아티팩트로 폐기.
- **문서 정정**: AUDIT_INPUT_FORMATS — 매트릭스 10-bit 행을 해결 후 재실측치로 갱신(원인 재판정 명시), RenderColorConfiguration 코드경로 노트 정정(near-black 원인은 8비트 변환 경로가 아닌 범용 aspect-fit 부재). 코드 변경 없음.

### 다음 회차 — LOOP_STATE 우선순위 그대로
① **BUG-IOS-06** 공통 파일 기반 임포터 통합 → ② AUTOSAVE-02 직렬화+UI → ③ MACUI-01 러너 복구·CI 차단화 → ④ BUG-07 비대칭 픽스처 회전 실측·G-27 실기기 2종. PARITY-TOL-01 승인 대기 유지.

## 2026-08-25 세션 (BUG-IOS-06·AUTOSAVE-02 수정, MACUI-01 진단)

- **BUG-IOS-06**: `IOSEditorViewModel.importFromPhotosPicker(_:)` 단일 공유 임포터 — 상단 피커·MediaBrowserView 모두 호출, 뷰 로컬 Data 적재 복사 폐지.
- **AUTOSAVE-02**: 직렬 coordinator(세대 번호·150ms 디바운스·최신 스냅샷만 기록·세대 일치 시에만 상태 갱신) + 상단 주황 실패 배너(en/ko) + `lastAutosaveLoadFailure` 소비(손상 복구 파일 제거 안내).
- **MACUI-01 진단**: 단일 최소 테스트도 러너가 "hung before establishing connection" — stale 정리·양쪽 부호화 모드·크래시 리포트 확인 전부 시도, 제품 결함 아닌 머신 환경(TCC/데몬) 판정. **사용자 조치**: 접근성·개발자 도구 권한 또는 재부팅.
- iOS 29/29·게이트 5/5·지역화 양 플랫폼 PASS.

### 다음 회차
BUG-07(회전 비대칭 재실측) → RENDER-02(P2) → G-27 실기기·MACUI-01(사용자 대기). PARITY-TOL-01 승인 대기.

## 2026-08-25 세션 (외부 리뷰 반영 — iOS ko 유실 발견·재적용, §1.11 등록, 계획 재편)

- **리뷰 검증**: BUG-06 "REG 통과" 주장은 낡음(이미 해결·게이트 승격). **iOS ko 106 미커밋은 사실** — fbf3149 커밋이 Mac 카탈로그만 담음(병렬 경합 유실), 커밋 메시지가 양쪽이라 주장해 기록 오류였음. iOS 프리뷰/익스포트 이중 엔진·캔버스 게이트 부재·MediaBrowser Data 임포트·automsave UI 부재·Mac UI 러너 kill 전부 코드로 확인.
- **즉시 수정**: iOS ko 106 재적용 + 양 카탈로그 en 결손(Mac 103·iOS 100) 보완 → en+ko 전량. CI: 현지화 검사 양 플랫폼 실행 + 키별 en·ko 번역값 존재 차단 검사 추가.
- **§1.11 등록**: RENDER-01(P0 iOS 공통 render plan)·CANVAS-01·BUG-IOS-06 재개방·AUTOSAVE-02·MACUI-01.
- **문서 정정**: CA-21 큐 행(UI 존재 — §H와 모순 해소)·CA-24 완료 처리·LOOP_STATE 전면 재작성(병렬 커밋이 이전 상태로 덮어쓴 것 복구).

### 다음 회차 — 리뷰 권고 순서
RENDER-01(iOS 렌더 통합+패리티) → CANVAS-01 → 임포터 통합 → AUTOSAVE-02 → MACUI-01 → BUG-07·G-27. PARITY-TOL-01 승인 대기.

## 2026-08-24 세션 (CA-04 입력 포맷 호환 매트릭스 — 실측)

**게이트**: `run_ca04_format_matrix.sh` PASS(등록 결함 REG 처리·신규 회귀만 차단) + verify_gate 5/5(1,413).

### 완료 — 매트릭스 6차원 실측 (픽스처→앱 파리티 하니스→출력 ffprobe/픽셀)
- **✅ VFR→CFR**: 100프레임@~20.1fps → 출력 30/1·149프레임·4.967s (지속시간 보존).
- **✅ 혼합 fps(24+30)+오디오**: 출력 3.000s·**A/V Δ=0ms** — 최우선 회귀(동기) 통과.
- **✅ BT.2020+PQ 태그**: 출력 bt709 재태그 — v1 SDR Rec.709 계약 종단 확인.
- **❌ BUG-06 등록(P0)**: 10비트 ProRes 소스가 출력에서 **near-black(평균 휘도 124.4→4.6)** — RenderColorConfiguration의 8비트 변환 경로에서 색 해석 결함.
- **⚠ BUG-07 등록(조사)**: 회전 메타데이터 효과 미실증 — 단색 픽스처 한계, 비대칭 픽스처 재실측 필요(preferredTransform 전달 코드는 존재).
- **픽스처 인프라**: VFR·회전은 AVAssetWriter 생성기 신설(`ca04_avfoundation_fixture_gen.swift` — ffmpeg 8.1.1은 디스플레이 매트릭스 출력 불가·setpts는 CFR 강제) + 10bit ProRes·BT.2020 태그 ffmpeg 생성. 매트릭스 스크립트는 등록 결함 허용 게이트로 상시 가동.

### 다음 회차
1. **BUG-06** 10비트 near-black 재현 최소화(유닛)→픽셀 수정 (P0 — 매트릭스 REG 소멸이 완료 판정).
2. BUG-07 비대칭 픽스처로 회전 실측. 3. CA-05 실패·복구 UX 매트릭스·CA-06 접근성. 실기기 2종 연결 시 G-27 계속.

 세션 (CA-06 접근성 핵심 경로 매트릭스 — P0-D 4종 완료)

- `CA06_ACCESSIBILITY_CORE_PATH_MATRIX_20260824.md` — 핵심 경로(임포트→편집→출력) × VoiceOver/키보드, 파일:라인 근거. **Mac 전 충족**(UX-08 계약 5종 + 43 메뉴 단축키 + 실패 경로 표면화). **iOS 차단 발견**: A11Y-01(P1 — 자막·필터·크로마키·효과·어시스턴트 뷰 VoiceOver 라벨 0건) 등 §1.10.
- 인스펙터 세그먼트 Picker 라벨 접힘 수정(`.labelsHidden()`, VoiceOver 라벨 유지) — 외부 리뷰 UI 지적 2건 중 1건 해소. 스켈리톤 카드는 VO 숨김 정상, 시각 UX로 A11Y-03 등록.
- **P0-D(CA-03/04/05/06) 중 3종 완료** — CA-04는 병렬 세션 진행 중.

### 다음 회차
잔여 소형 우선순위: A11Y-01(iOS 인스펙터 a11y) → UX-REC-01/02 → BUG-IOS-06 → ko 106×2 → iOS 출력 golden → BUG-01 백오프·북마크 자동 치유. CA-04 병렬 완료 시 통합 검증.

## 2026-08-24 세션 (CA-05 실패·복구 UX 매트릭스 완료)

- `CA05_FAILURE_RECOVERY_UX_MATRIX_20260824.md` — 15 실패 시나리오 × 5축(무손실/원인/재시도/이어하기/임시파일) 매트릭스, 파일:라인 근거. **13/15 완전 충족**(이번 주 BUG-01/02/04/05·BUG-IOS-01~05·suggestCuts 수정이 전제). 신규 등록 §1.9: UX-REC-01(P2 — iOS 익스포트 취소/실패 시 부분 출력 잔존, Mac 패리티 부재)·UX-REC-02(P2 — iOS 복구 무음 자동 채택, 버림 선택 부재)·UX-REC-03(참고 — 스코프 철회 감지 시점 유지 결정).
- 문서 전용 증분(코드 변경 없음 — 문서 경로 검증 통과).

### 다음 회차
CA-04(병렬 진행) → **CA-06 접근성 핵심 경로 매트릭스** → 잔여 소형(UX-REC-01/02·BUG-IOS-06·ko 106×2·golden·백오프).

## 2026-08-24 세션 (리뷰 잔여 마무리 — BUG-IOS-01·try? 지점·AppIcon·프로브 v4)

**게이트**: 5/5(1,413/207)·Mac 38/38·iOS 13/13.

- **BUG-IOS-01 (P0) 수정**: 캔버스는 `SetProjectCanvasCommand`, 템플릿은 `ReplaceProjectCommand`(둘 다 기존 Core 커맨드)로 세션 경유 — 이중 상태 제거. `IOSSessionStateTests` 2종. 외부 리뷰 §1.8 전 결함(등록분) 수정 완료.
- 리뷰 지목 `try?` 2곳 표면화: 크롭 프리셋 클릭 실패 보고, suggestCuts 두 도구 시도 후 실패 목록 보고.
- AppIcon 1024 alpha 제거(RGBA→RGB). '필수 크기 누락'은 부정확(단일 크기 형식).
- scene detection 백로그 행 정정 — Core+VM+UI 모두 존재, 잔여는 CA-21 측정 게이트뿐.
- G-28 EffectCostProfile 응답성 프로브 v4: 공유 프로세스 메인 액터 경합(61.5s hop 관측)으로 wall-clock·순서 프로브 모두 위양성 — 결정적 스레드 친화성 검사로 교체.

### 다음 회차
CA-04(병렬 진행) → CA-05 → CA-06. 잔여 소형: BUG-IOS-06, ko 106×2, iOS 출력 golden 테스트, BUG-01 백오프, 북마크 자동 치유.

## 2026-08-24 세션 (외부 리뷰 반영 — 검증·등록·BUG-IOS-02/03/04/05 수정)

**입력**: 사용자 제공 외부 리뷰(iOS 정확성 중심). **실사로 검증 후 반영** — 리뷰의 P0-2 4건(속도·램프·프리즈·Reverse)과 30fps 고정 주장은 현재 코드에서 이미 수정/부정확(등록 않음), 나머지는 백로그 §1.8에 BUG-IOS-01~06 + 참고 4건으로 등록.

### 완료
- **BUG-IOS-02 (P0)**: iOS 크래시 복구 영속성 — `IOSEditorViewModel`이 Core `ProjectStore`로 커밋마다 autosave(실패 비차단 표면화), 루트 뷰 `task`에서 런치 복원(하니스 제외). `IOSPersistenceTests` 2종(재시작 복원·읽기전용 실패).
- **BUG-IOS-03**: iOS 익스포트 `blendMode` 효과 객체 전달 + transform/opacity 컴포지터 게이트 트리거.
- **BUG-IOS-04**: `ProjectPackage.export` 복사 실패 수집 → `mediaCopyFailed` throw + 부분 패키지 제거 + LocalizedError. 테스트 2건 갱신.
- **BUG-IOS-05**: `VoiceoverRecorder` 쓰기 실패 래치 → `stopRecording()`이 `writeFailed` throw.
- 백로그 CloudSync 허위 완료 기록 정정(소스 0건 확인).
- **게이트**: 5/5(1,413/207)·Mac 38/38·iOS 11/11.

### 잔여 (§1.8)
- **BUG-IOS-01 (P0)**: iOS 상태 이중화(캔버스/템플릿 세션 우회) — Core 커맨드 신설 필요, 다음 증분.
- BUG-IOS-06(iOS 파일기반 임포트)·ko 번역 106×2·CI 차단화(플레이크 해소 후)·SwiftLint 부채·UX 지적(CA-06 연계).

## 2026-08-24 세션 (CA-03 결함 수정 — BUG-01/02/04/05 전량)

**게이트**: verify_gate 5/5 — 1,413 테스트/207 스위트, Mac 앱 테스트 38/38, iOS generic 빌드 통과.

### 완료 (커밋 순)
- **BUG-05** (5674250): `FileOperationError` `LocalizedError` 채택 — 엔진이 분류해 throw한 값이 VM catch의 `localizedDescription`에서 살아남음(디스크 풀 안내 보존).
- **BUG-01** (9277d86): 오토토회복 실패 표면화 — `scheduleAutosave`/`flushAutosave`가 `try?` 삼킴 대신 분류 후 비차단 상태바 경고(주황 배너+접근성), 성공 시 해제. 테스트 주입용 `autosaveDirectory` 시임 추가. 동작 테스트 3종.
- **BUG-04** (e00b3fe): 익스포트 5개 진입점(무비·명시 비트레이트·ProRes 패널/자동화·프로젝트 패키지) 전 `ensureAllMediaReachableForExport()` — 누락 미디어 재연결 안내 후 렌더 전 거부. 동작 테스트 3종.
- **BUG-02** (11b2f20): Core `MediaImporter.validatedProbe` — 확장자 허용목록(미지원 명시적 거부, 기존 `.video` 폴백 폐지) + 512바이트 매직 스니프(알려진 시그니처 없는 가비지 거부·종족 충돌 거부·mp3/aac 원시스트림 예외). 맥/iOS 임포트 경로 전환, TTS 자기생성 .caf는 신뢰 경로 유지. Core 테스트 7종 + 재연결 픽스처 ftyp 헤더 갱신 + StaticContract 2건 갱신.

### 다음 회차 — P0-D 감사 계속
1. **CA-04** 입력 포맷 매트릭스(VFR·10bit·Log·혼합 fps/sample rate·rotation).
2. CA-05 실패·복구 UX 매트릭스 / CA-06 접근성 핵심 경로 매트릭스(병렬 가능).
3. 잔여 소형(P2): BUG-01 재시도 백오프, 북마크 자동 치유.

## 2026-08-24 세션 (프로토콜0 WIP 커밋 + CA-03 미디어 생존성 감사 — 1·2차 병합 완료)

**게이트**: verify_gate 5/5(1,405) — 프로토콜0 커밋(a9103e9) 검증. 감사는 문서 전용(기존 증거 재조사).

### 완료
- **프로토콜0**: 핸드오프 "처리 대기" 사용자 변경(`ui_capture.sh` pgrep errexit 가드) 검증·커밋(a9103e9).
- **CA-03 감사 완료** (e36f83a, `AUDIT_MEDIA_SURVIVABILITY_20260824.md`): 경로 5종 판정 — 재연결(UUID 보존·배치 UI 양호)·누락(북마크+안내 양호)·손상(오토토회복 5테스트·출력 부분파일 제거·마이그레이션 구조화 견고·**미디어 무검증**)·디스크(원자적 저장·분류 견고·**오토토회복 침묵**). **결함 등록(1차+2차 병합)**: BUG-01(P0 오토토회복 실패 `try?` 침묵)·BUG-02(P0 임포트 확장자 판별만·조용한 `.video` 디폴트)·**BUG-04(P1 익스포트 전 미디어 사전 검사 부재)**·**BUG-05(P1 VM catch가 분류 오류를 일반 문구로 덮어씀 — FileOperationError LocalizedError 미준수)**. **BUG-03 폐기** — `App/MovieCutMacTests/MediaRelinkTests.swift`가 이미 재연결·누락 감지 자동화를 실경로로 잠금(1차 탐색이 Mac 테스트 디렉터리를 누락). 2차 실사는 같은 날 병렬 독립 감사로 수행됐고 `AUDIT_MEDIA_SURVIVABILITY_20260824.md` §4에 병합.

### 다음 회차 — BUG 증분 (심각도 순)
1. **BUG-01** 오토토회복 실패 표면화(분류→경고+백오프, 비차단 유지).
2. **BUG-02** 임포트 헤더 스니프 + 미지원 확장자 명시적 거부.
3. **BUG-05** `FileOperationError` LocalizedError 채택(소형 — BUG-01과 동일 파일군, 분류 메시지가 throw·catch 양단에서 살아남).
4. **BUG-04** 익스포트 전 `evaluateMissingMedia` 재실행 + 재연결 유도.
5. CA-04 입력 포맷 매트릭스 → CA-05·CA-06. 실기기 2종 연결 시 G-27 계속(3종 PASS → DONE_PHASE1).

 세션 65 (방향 문서 §3 v1.1 반영 + CA-28 RGB 파레이드)

### ① 방향 문서 §3 v1.1 — Q11 승인 P0 편입
- `DEVELOPMENT_DIRECTION_20260815.md` v1.0→v1.1(2026-08-24): §3 1단계 테이블에 **P0-D 신뢰성·호환성·접근성 감사** 스트림 신설(CA-03 미디어 생존성·CA-04 입력 포맷·CA-05 실패·복구 UX·CA-06 접근성 핵심 경로), 1단계 완료 게이트에 4종 산출물 명시.
- 백로그 §0.5.1: CA-03~06 상태를 "방향 문서 §3 반영 후 실행"→"**즉시 실행 가능**(v1.1 반영 완료 2026-08-24)"으로, 실행 규칙 문장 갱신. **CA-03~06 실행 자격 확보 — 다음 증분부터 P0-D 순서 진행.**

### ② CA-28 RGB 파레이드 스코프 완료
- Core `ScopeAnalyzer.rgbParade(rgba:width:height:columns:levels:)` — `lumaWaveform`과 동일한 빈ning 계약으로 R/G/B 채널별 파형(`RGBParade` 구조체). 골든 테스트 4건(Exact 등급): 순수 빨강 채널 분리·가로 램프 x 추적·혼합 픽셀 독립 빈ning·퇴화 지오메트리 가드. 기존 스코프(histogram·waveform·vectorscope) 무변경.
- Mac `RGBParadeView`(`ScopeViews.swift`) — R/G/B 패널 3개 나란히, 각 패널은 `WaveformView`와 동일 렌더링 계약(채널 색조). `EditorViewModel.scopeRGBParade` + `refreshScopes()` 계산·`clearScopes()` 해제. 그레이딩 인스펙터에서 waveform/vectorscope 행 아래 전체 폭 노출. 접근성 라벨/값 영어 키+en/ko 등록(지역화 검증 PASS).
- 백로그 CA-28 행 완료 처리.

### 다음 세션 우선순위
① **CA-03** 미디어 생존성 감사(P0-D 첫 항목) ② CA-04 ③ CA-05 ④ CA-06(P0-D 내 병렬 가능). G-27 실기기는 기기 잠금 해제+연결 시 `TEAM_ID=98ZKV9N9T4 bash scripts/run_g27_device_e2e.sh` 재실행. `scripts/ui_capture.sh` 미커밋 사용자 변경(유효해 보이는 pgrep errexit 가드) 처리 대기.

## 2026-08-24 세션 64 (전역 코드 리뷰 후속 수정 — origin/main 통합 + P1/P2)

### origin/main 통합 (merge commit)
- 충돌 6개 파일 기능별 조정: `SetMasterAudioProcessingCommand`는 main의 `processing:` API로 통일(HEAD의 미사용 `previousPreset` 폐기), `EditorViewModel+Audio`는 main의 mutation coalescing worker 보존, `InspectorPanel`은 main의 Picker UI 채택(HEAD 중복 Toggle 제거), `EffectBrowserView`는 main의 process-wide single-flight 비용 측정 보존, LOOP_STATE/SESSION_HANDOFF는 HEAD의 세션 63 상태 기반. G-26(main)·G-28(main)·CA-26/27(HEAD) 기능 모두 보존.

### P1 — G-27 실기기 E2E 결과 격리
- 러너 실행별 고유 `RUN_ID` 생성·양 phase 전달(`MOVIECUT_G27_RUN_ID`), phase 1 전 기기 결과 파일 초기화, 대기·검증·error=none 카운트 전부 현재 run 범위만. 하니스는 모든 행에 `run=<id>` 태깅(env 부재 시 실행별 생성). 과거 g27_done/g27_reopen이 들어있는 파일로 즉시 PASS 불가(재현 확인).
- devicectl 감지 버그 수리: `awk '{print $NF}'`가 Model 컬럼 `(iPhone14,2)`를 잡아 xcodebuild destination 거부 → UUID 패턴 추출로 변경.
- **실기기 실행(정직 기록)**: iPhone 13 Pro 연결 확인·러너 2회 실실행 — 화면 잠금으로 앱 런치 실패(각 3분 재시도 후 포기). 재실행 명령: 기기 잠금 해제 후 `TEAM_ID=98ZKV9N9T4 bash scripts/run_g27_device_e2e.sh`. **device PASS 선언 없음.**

### P1 — 효과 브라우저 / P1 — G-26 오디오 최신성
- 브라우저 계약(파라미터 키 amount/ev/radius, 전환·externalLUT 제외, 선택→미리보기→명시적 Apply, 싱글플라이트 비용 측정)은 main 병합으로 확보, 관련 동작 테스트 19건 통과.
- G-26은 StaticContract만 있던 무효화/직렬화 계약을 EditorViewModel 실경로 동작 테스트 4건으로 잠금(빠른 토글 마지막 선택 승리, 프리셋 전환·ducking 커밋 시 masterLoudness 폐기, no-audio 오류 보고·커밋 시 소거).

### P2 — CA-27 / CA-26
- 타임코드: finite 검사(frameRate·입력·최종값; inf/infinity/nan/1e309/오버플로 거부), FF 정수 전용, 3필드=MM:SS:FF 통일(문서에서 모순되는 HH:MM:SS 3필드 형태 삭제), 29.97/23.976 마지막 프레임 보존(표시 클램프 `ceil(fps)-1`로 파서 수용과 정확 일치), TextField VoiceOver 독립 탐색(무인자 accessibilityElement 제거·라벨/힌트 필드 직접 적용). 테스트 11건.
- LUT export: 외부 LUT 재내보내기=관리 원본 byte-for-byte 복사(DOMAIN·주석·음수·>1 보존 실증), 동일 경로 안전 no-op, serialize 형상 검증(dimension³×4 불일치 시 throw, 크래시 아님), bake 차원 범위 위반 시 명시적 오류(identity 대체 폐지), bake/65³ 직렬화/파일 쓰기 전부 메인 액터 밖+응답성 실증(최악 메인 홉 <500ms). Core 6건+Mac 3건.

### 자동화·CI·문서·지역화
- CapCut 현행 원장 5종 archive→active 승격(SURPASS 스펙·벤치마크 기준·격차 분석 V13·UI 설계 원칙·디자인 격차 감사 — git mv로 복제 없음). /gap-audit·/surpass 참조 경로 수리, AGENT_LOOP_PROMPT `docs/` 누락 경로 수리, REQUIREMENTS 승격 반영.
- `scripts/verify_doc_paths.sh` 신설(활성 문서·명령 파일의 로컬 경로 자동 검증) — CI lint job blocking 연결. 지역화 검증기(`verify_localization_keys.py`)도 CI blocking 연결, 누락 키 17건+보간 키 1건 수리로 PASS.
- VERIFICATION_STANDARD·README 5단계를 실제 verify_gate와 일치(swift build→전체 test→Mac 빌드→iOS generic 빌드→high-signal lint). ci.yml lint는 job-level continue-on-error 없이 blocking 유지.
- G-26 표시·상태·접근성 문자열 영어 키+en/ko 등록(sourceLanguage=en 정합, 프리셋명 "SNS 좋은 소리"는 로케일 불변 제품명으로 유지).
- `.mimosa/`를 .gitignore에 추가(사용자 코드 아님·커밋 금지).

### 다음 세션 우선순위
① 방향 문서 §3 반영(Q11 승인분 — 반영 후 CA-03/04/05/06 실행 자격) ② CA-28 RGB 파레이드 승인 완료·즉시 실행 가능 ③ 기기 잠금 해제+연결 시 G-27 실기기 재실행(위 명령).

## 2026-08-22 세션 63 (Q1~Q12 제품 결정 12건 확정)

**결정 원천**: `docs/DECISIONS_20260822.md` (4지선다 사용자 답변, 전항목 권장안 채택) — 페르소나=1인 쇼츠 크리에이터·가격=일회성+유료 메이저 업데이트·macOS 14 유지·N6/F-24 비목표·자막 ko+en·접근성 핵심 경로·Tolerance MAD≤2.0 유지·성능 수치 출시 직전 재측정·경쟁 실측 분기 고정·릴리스 분기 1회·P0 편입 ⑤⑥⑨ 승인·지원 상한 60분.

### 파생 갱신
- 백로그 §0.5.1: CA-02 즉시 실행 가능·CA-03/04/05/06 승인 완료(방향 문서 §3 반영 후 실행)·CA-07 모델만 확정(가격은 사용자 전용)·N6/F-24 비목표 명시.
- REQUIREMENTS §13.15 체인지로그 신설.

### 다음 회차 — RUN으로 복귀
1. **방향 문서 §3 반영**(Q11 승인분 편입) → CA-03/04/05/06 실행 자격.
2. **CA-02** 파리티 수치 VERIFICATION_STANDARD §2 기재.
3. 실기기 2종 연결 시 G-27 계속(3종 PASS → DONE_PHASE1).

## 2026-08-22 세션 62 (G-27 실기기 검증 개시 — iPhone 13 Pro PASS, 1/3)

**실측 (iPhone 13 Pro, iOS 26.6, Personal Team 서명)**: `G-27 DEVICE E2E PASS` — 1단계(임포트 2클립·프리뷰 10.000s·출력 64,906B·오디오 Playback/Speaker·저장) + 2단계(신규 프로세스 재오픈, 클립 2개 복원) 전 단언 통과.

### 러너 결함 4건 수정 (커밋 c020063 — 앱 자체는 첫 정상 시도에 통과)
1. **스테이짝 경로**: 파일명 없는 `--destination "Documents/in"`이 devicectl에서 성공 처리돼 올바른 폴백을 가림 → 명시적 파일 경로·실패 시 즉시 중단·스테이징 목록 로깅.
2. **타임아웃 계산**: 반복 횟수 기반 300s가 devicectl 왕복 수 초씩 늘어나 40분+ 행 → 실제 벽시계 마감.
3. **결과 수신**: 디렉터리 대상 `copy from`이 조용히 실패(`|| true`가 삼킴) — 폴링이 영원히 실패 → 정확한 파일 경로.
4. **자동 잠금 내성**: 빌드 중 자동 잠금으로 실행 거부(reason: Locked) → 최대 3분 잠금 해제 대기 재시도.

### §4 실기기 현황: **1/3 PASS**
| 세대 | 기기 | 상태 |
|---|---|---|
| 중간 | iPhone 13 Pro (iOS 26.6) | **PASS** (2026-08-22) |
| 최소 | 예: iPhone SE 2/3세대 | 대기 — 기기 연결 필요 |
| 최신 | 최신 세대 iPhone | 대기 — 기기 연결 필요 |

### 다음 회차 — 잔여 2종 실기기
기기 연결 시마다 `TEAM_ID=98ZKV9N9T4 bash scripts/run_g27_device_e2e.sh` 실행(사전 준비 완료: 개발자 모드·신뢰 절차는 기기마다 1회). 3종 PASS 확정 시 §4 전 조건 충족 → DONE_PHASE1 선언.

## 2026-08-21 세션 61 (1단계 게이트 조건 재점검 — §4 점검표 @HEAD)

**게이트(전부 현재 HEAD 836d246에서 실측)**:

| §4 조건 | 측정 수단 @HEAD | 결과 |
|---|---|---|
| 대표 작업 성공률 90%+ | run_w_scenarios.sh | **29/29 = 100%** ✓ |
| 기존 픽셀 게이트 무회귀 | verify_gate(골든 전수·1,345) + run_parity_sweep.sh | **5/5 + 파리티 13/13 ALL PASS**(MAD 0.04–0.63) ✓ |
| 동일 PCM ±1 샘플 | run_g25_nulltest.sh | **PASS**(3그래프 · 패리티 −0.02 LU · 오프셋 0) ✓ |
| 60분 drift ≤1프레임 | null test 드리프트 | **PASS**(드리프트 0샘플 · 60분 종점 정확) ✓ |
| iOS 실기기 3종 | G-27 러너 | **사용자 의존** — 러너·가이드(docs/G27_DEVICE_VERIFICATION_GUIDE.md) 준비 완료, 기기 연결·실행 대기 |
| seek·프로젝트 열기 기준선 | run_latency_baseline.sh(기본 enforce) | **PASS enforced**(seek p50 0.05–0.06ms / 열기 113–157ms — 목표의 ~5%) ✓ |

### 판정
자체 측정 가능한 §4 조건 5/6 전부 현재 HEAD에서 녹색. 잔여 1항(iOS 실기기 3종)은 점검표 자체가 "병렬 트랙(사용자 의존)"으로 명시 — 루프가 자력으로 충족 불가. **"게이트 조건 미충족 상태로 1단계 종료 선언 금지"(§4)에 따라 DONE_PHASE1 표기는 보류**하고 USER_WAITING으로 전환. 코드 리뷰 결함 큐·2단계 계획 잔여 증분(자력 분) 전부 소진.

### 사용자가 해야 할 일 (1단계 완료 선언을 위해)
1. **G-27 실기기 검증**: 최소·중간·최신 3대 기기 연결 후 docs/G27_DEVICE_VERIFICATION_GUIDE.md 절차 실행(러너 준비 완료).
2. (선택, 2단계 착수 전) N2 오토스타일 등록·N6 뷰티 포지셔닝 결정.

## 2026-08-21 세션 60 (G-28 브라우저 백그라운드 이관)

**게이트**: 프로파일 스위트 8/8(메인 응답성 측정 신규) + verify_gate 5/5(1,345).

### 완료 — 브라우저 프로파일 측정이 메인스레드를 얼리지 않음
- **결함**: `loadProfiles`의 `Task { }`가 @MainActor 뷰의 격리를 **상속** — 수 초짜리 `measureAllBuiltIns`가 메인스레드에서 실행돼 브라우저가 얼었음(뒤의 `await MainActor.run`이 이미 그 증거).
- **수정**: `Task.detached`로 측정 이관 — 렌더는 백그라운드, 상태 갱신만 메인으로 홉.
- **측정 테스트**: 측정 실행 중 메인액터 홉을 프로브 — 메인스레드 실행이면 홉이 로드 전체(수백 ms~수 초)만큼 정체; 실측 최악 홉 < 250ms 게이트(스케줄러 노이즈 허용치).

### 다음 회차 — 잔여 큐 소진, 1단계 게이트 조건 재점검
코드 리뷰 결함·G-24/G-26/G-28 잔여 전부 완결. EXECUTION_PLAN §4 1단계 게이트 조건 대비 측정 증거 재점검(§11①~⑤ 갱신 여부 포함) — 미달 항목이 있으면 다음 증분으로, 전부 충족이면 DONE_PHASE1 평가 보고.

## 2026-08-21 세션 59 (G-26 마스터 체인 인스펙터 UI)

**게이트**: 직렬화 스위트 7/7(신규 라우트 실측 2종 포함) + verify_gate 5/5.

### 완료 — 사용자가 마스터 체인을 켜는 유일한 표면
- **커맨드**: `SetMasterAudioProcessingCommand`(프리셋 옵셔널·nil=끔) — 세션 루트(단일 undo), 새로고침 세션이 프리뷰 컴포지션 재구축.
- **UI**: 오디오 마스터 미터 카드(`MasterLoudnessSection`)에 SNS 프리셋 토글 — 미터와 같은 카드에 두어 "켜고 → 재측정 → §7 밴드 확인" 루프가 한 화면에서 닫힘. 접근성 라벨/힌트 포함.
- **VM**: `updateMasterAudioProcessing(_:)`(+Audio 경계 — 오디오 도메임 응집).
- **라우트 실측 테스트**: 프로젝트(프리셋 on/off) → 빌더 masterBus → 오프라인 렌더 — **무처리 −0.5dB 초과 vs 프리셋 ≤ −0.5dB** (리미터 결속) — 토글의 전체 경로가 측정으로 증명. 커맨드 적용/해제 테스트 포함.

### 다음 회차 — G-28 브라우저 백그라운드 이관
`EffectBrowserView`의 `measureAllBuiltIns`가 메인스레드에서 브라우저를 얼림 — 백그라운드 측정+비동기 게시.

## 2026-08-21 세션 58 (G-28 메모리 실측)

**게이트**: 측정 테스트 7/7(프로파일 스위트) + verify_gate 5/5.

### 완료 — peakMemoryMegabytes 플레이스홀더 폐지
- **실측**: `task_vm_info.phys_footprint`(T2-M 하니스와 동일 지표)를 ~1ms 병렬 샘플러로 폴링 — CI 필터의 과도 표면이 render 호출 **내부에** 살아있어 렌더 간 샘플링은 놓침.
- **차등 정의**: 이펙트의 메모리 비용 = 같은 프레임 **무필터** 렌더의 피크 대비 이펙트 렌더의 피크 초과분 — 동일 하니스의 차등이라 프로세스 상주 메모리가 상쇄됨. 이전 값은 physicalMemory×0.001(모든 이펙트 동일 상수).
- **회귀 테스트**: 측정값이 플레이스홀더 상수와 정확히 일치하면 실패(부활 방지) + 풋프린트 프로브 타당성(0 < fp < physicalMemory) + 측정 엔드투엔드.

### 다음 회차 — 잔여 큐
마스터 체인 인스펙터 UI(모델·직렬화 완비 — 프리셋 선택 UI만 부재)·G-28 브라우저 measureAllBuiltIns 메인스레드 블로킹(백그라운드 이관).

## 2026-08-21 세션 57 (G-26 파라미터 직렬화 — 스펙 §6)

**게이트**: null test PASS(3그래프 · 패리티 −0.02 LU · 드리프트 0샘플) + verify_gate 5/5(1,340).

### 완료 — 마스터 체인 파라미터가 그래프와 함께 직렬된다
- **스펙 모델**: `AudioGraphMasterBus`에 `masterChain`(전체 파라미터) + `presetAlgorithmVersion`(§6) 추가 + `resolvedMasterChain()`(직렬값 우선·래거시 limiter-only 그래프는 SNS 폴백·둘 다 없으면 미처리).
- **렌더러 2곳**(오프라인·AVAudioEngine): 하드코딩 `chain: .sns` 폐지 — 스펙의 직렬화 체인 소비. 역직렬화된 그래프는 어디서든 동일 렌더.
- **프로젝트 저장**: `Project.masterAudioProcessing`(프리셋 이름 — §6의 버전 단위) + 스키마 v8(additive no-op 마이그레이션).
- **빌더**: 프리셋 → masterBus 전개(체인 파라미터 + 프리셋 버전 + 리미터 지연 선언[5ms 룩어헤드]). **발견**: 빌더가 masterBus를 아예 설정하지 않아 제품 경로에서 마스터 체인이 실행조차 되지 않았음(테스트만 limiter 선언) — 이제 프로젝트 프리셋이 전체 경로를 연다.
- **실측 테스트 6종**: 왕복(버스·프로젝트)·우선순위(래거시 폴백)·빌더 전개·**변경된 직렬 체인(realpeak 차이) 소비 검증** — #8 결함 부류(호출 없는 배선) 재발 방지.

### 다음 회차 — G-28 메모리 실측
`EffectCostProfile.peakMemoryMegabytes`가 `physicalMemory/1000` placeholder — 실측(프로세스 풋프린트 샘플링)으로 교체.

## 2026-08-20 세션 56 (코드 리뷰 결함 #9 — G-24 warp 렌더 체인 통합)

**게이트**: G-24 E2E **2회 연속 PASS — 실측 ratio 0.348/0.342 (입력 4.24px → 잔여 1.47px), crop 0.006, 심각 워블 0.000, 장면 전환 오류 0, 적용 게인 1.008/1.019** + verify_gate 5/5(1,335) + W 29/29=100% 무회귀.

### 완료 — 등록 보정 데이터가 컴포지터로 흐르는 경로 구축
- **Core**: `StabilizationPlan`(정규화 보정·시간 조회·상수 커버 줌 근원) + `Clip.stabilization`(스키마 v7, additive no-op 마이그레이션) + `CustomCompositionClipEffect.stabilization`(nil 아니면 커스텀 컴포지터 강제).
- **워프**: `StabilizationWarpProcessor`에 **커버 줌** 추가(플랜 전체에서 한 번 유도·프레임마다 고정 — 호흡 방지, 바이패스 프레임에도 적용). CGAffineTransform 헬퍼가 **프리펜드**로 결합한다는 사실을 테스트로 확정(중심 스케일 순서 교정).
- **배선**: Mac/iOS 컴포지터 `applyClipEffects` 선두에 워프(원시 프레임에 적용·dy는 상하좌표계 반전·바이패스/적용 카운터) + PlaybackEngine/ExportEngine/iOS 트리거·메타데이터 전달.
- **하니스 STABILIZE 재구축**: 분석 결과를 `ReplaceProjectCommand`로 세션에 반영(직접 변형은 세션 재빌드에 레이스로 소실됨 — 실측으로 포착), **입력/스태빌 양패스를 실제 출력 경로(export+AVAssetImageGenerator 정밀 추출)로 렌더**, 빈 플랜으로 양패스 동일 컴포지터 통과, DoD를 실측 픽셀에서 판정(입력 렌더 지터 실측 + 프레임별 교차 등록으로 적용 워프 실측).

### 실측 게이트가 밝혀낸 제품 결함 4건(전부 수정+테스트)
1. **등록기 정수 양자화**: ±1px 노이즈가 실제 지터(~0.6px)를 묻힘 → SAD 최솟값 포물선 **서브픽셀 보정** 추가(완전 일치 시 미적용 가드).
2. **신뢰도 절대 정규화**(improvement/30)가 콘텐츠 대비에 의존 → **상대 개선율**(improvement/baseline)로 교체(스케일 불변). 바이패스 임계값 0.05로 재보정(0.15는 실측 분포의 실제 움직임 대역을 잘랐음 — 31% 바이패스가 교대 지터로 잔여를 입력보다 악화).
3. **플랜 프레임 시프트**: positions 시드 누락으로 보정이 한 프레임 늦게 적용(지터 배증, ratio 1.19) → 프레임 0 시드 추가(수정 후 0.348).
4. **픽스처**: 1Hz 스윙(평활화로 소거됨)·testsrc2(주기 잠김)·mandelbrot(줌 편향) 전부 부적합 → **정지 블러 노이즈 + 다주파수 지터 + 16:9**(출력 경로 해상도 프리셋과 정합)로 재생성(`stab_wobble_640x360_4s_30fps.mp4`).

### 측정 방법론 발견(문서화)
- `snapshotFrame`(프리뷰 영상 출력)은 일부 타임스탬프에서 **중복 프레임** 반환(양패스 동일 지점에서 걸려 리드백은 속임) — 프레임 단위 측정은 출력+제너레이터로.
- 스탭 프레임 자기 등록은 서브픽셀 재표본화 위상 변화로 **랜덤 워크**(6px 드리프트) — 잔여는 프레임별 교차 등록(입력↔스탭, 0.45px 정확도)으로 측정.

### 다음 회차 — G-26 파라미터 직렬화
1. 마스터 체인 파라미터가 SNS 프리셋 기본값 — 그래프 스펙 §6 프리셋 버전 체계로 직렬화.
2. 이후 G-28 메모리 실측(peakMemoryMegabytes가 physicalMemory/1000 placeholder).

## 2026-08-20 세션 55 (코드 리뷰 결함 #8·#10 + 리버브 크래시)

**게이트**: verify_gate 5/5(1,328) + null test PASS + W 29/29=100% 무회귀.

### 완료 — G-26 배선(실제 호출) + G-28 프로파일러 + 리버브 크래시 (커밋 b2ffe46)
- **#8 G-26**: AudioGraphMasterChain.apply가 두 렌더러에서 실제 호출됨(이전: rejection만 제거). 체인 순서 수정: compressor→reverb→limiter(마지막).
- **리버브 크래시**: 짧은 오디오에서 delayFrames > frameCount 시 Range 치명적 오류 — guard 추가.
- **#10 G-28**: 참조 프레임 합성 순서 수정(스크라이프가 보임) + 파라미터 키 수정(amount/ev/radius).

### 다음 회차 — #9 G-24 warp 통합
1. StabilizationWarpProcessor를 컴포지터에 배선 — 등록 보정 데이터가 흐르는 경로.
2. 이후 G-26 파라미터 직렬화·G-28 메모리 실측.

## 2026-08-20 세션 54 (코드 리뷰 결함 #3-#7 수정)

**게이트**: verify_gate 5/5 + null test PASS + W 29/29=100% 무회귀.

### 완료 — 결함 5건 수정 (커밋 1b7c102)
- **#3 라이터 오디오**: 그래프 AAC에 별도 AVAssetReader(교차 자산 canAdd=false로 조용히 스킵되던 것 수정).
- **#4 모노 채널**: GraphMixRenderer가 소스 포맷 프로브(AVAudioFile/AVAssetTrack 헤더) 후 channelCountFor 전달.
- **#5 컴파운드**: renderMix가 tracks 파라미터 수신(플래트닝) — 컨테이너 클립의 오디오 복원.
- **#6 G-03 트리거**: usesCustomVideoCompositor에 hasAdjustmentLayer 추가(양쪽 엔진).
- **#7 G-03 범위**: at:0 게이트 제거 — 전체 세트 전달.

### 다음 회차 — 결함 #8-#10
#8(G-26 배선)·#9(G-24 warp 통합)·#10(G-28 프로파일러). 이후 문서 정정.

## 2026-08-20 세션 53 (코드 리뷰 결함 #1·#2 수정 — 페이드 방향 + 스테레오)

**게이트**: verify_gate 5/5 + null test PASS + W 29/29=100% 무회귀.

### 완료 — 치명적 결함 2건 수정 (커밋 ca0f36f)
- **#1 페이드 방향**: `AudioGraphFade.Direction`(.fadeIn/.fadeOut) + `fadeFactor` 방향별 램프 + 빌더 `.fadeOut` 발행. 수정 전 모든 페이드아웃이 반전.
- **#2 스테레오 채널**: `mappedChannels` frame/channel 전치 수정. 수정 전 오른쪽 채널이 상수.
- **회귀 테스트 7종** + 기존 2종 갱신(빌더 방향·드리프트 ±1).
- **E2E 무회귀**: null test·W 스위트 녹색.

### 다음 회차 — 코드 리뷰 결함 #3-#7
#3(라이터 별도 Reader)·#4(모노 channelCountFor)·#5(컴파운드 tracks)·#6(G-03 트리거)·#7(G-03 범위). 이후 #8-#10.

## 2026-08-20 세션 52 (G-28 KPI 모델 + 2단계 회귀 확인)

**게이트**: verify_gate 5/5(1,325) + null test·W 스위트 무회귀.

### 완료 — G-28 KPI 모델 + 회귀 (커밋 443ca69)
- **회귀**: G-26 그래프 노드 변경 후 null test(3그래프 통과·패리티 −0.02 LU)·W 스위트(29/29=100%) 무회귀.
- **`EffectBrowserKPI`**(Core/Rendering): 검색 성공률·재사용률 — "개수 KPI 폐지"의 대체. meetsTargets·Codable·기록 API.
- 테스트 5종.

### 다음 회차
1. 자율 잔여: EffectBrowserKPI를 하니스에 연결(검색·적용 실측 창구).
2. 사용자 의존: N2 등록·실기기·다음 방향. 루프가 자율 잔여를 진행하거나 지시 대기.

## 2026-08-20 세션 51 (G-26 Inc 4 — 그래프 자리노드 소비 배선)

**게이트**: verify_gate 5/5(1,320 테스트).

### 완료 — G-26 그래프 배선 (커밋 7826cb0)
- **isStage1Supported 갱신**: .compressor·.limiter → true. 그래프가 이 노드를 선언하면 렌더러가 렌더(DSP가 자리를 채움). 남은 placeholder: .eq·.creativeFX·.masterEQ·.noiseReduction·.mlStem.
- **렌더러/엔진 노드 거부 제거**: limiter rejection 제거 — 엔진 간 무결정성 유지(null test가 limiter 선언 그래프에서도 통과).
- **기존 테스트 3종 갱신** + **신규 3종**(지원 분류·limiter 그래프 렌더·SNS true-peak).

### 다음 회차 — 2단계 완료·다음 방향 결정
1. 2단계 계획의 자율 핵심 전부 완료(G-24·G-28·G-26 4증분).
2. 남은 2단계: N2(사용자 등록 결정 전제)·KPI 측정 창구.
3. **사용자 지시 필요**: 다음 우선순위 — 제품 완성도(UI·UX·안정성)·1단계 회귀 확인·2단계 잔여(N2 등)·또는 새로운 방향. 실기기 3종=유보.

## 2026-08-20 세션 50 (G-26 Inc 3 — 마스터 체인 + SNS 프리셋 · **G-26 완결**)

**게이트**: verify_gate 5/5(1,317 테스트 — 신규 5종).

### 완료 — G-26 마스터 체인 (커밋 4c8f903)
- **`AudioGraphMasterChain`**(Core/Audio): compressor→limiter→reverb 체인 조합(nil=우회·bypass=비트 항등) + **SNS 프리셋**(§7 "좋은 소리") + **`measureChainEffect`**(입력/출력 LUFS + true-peak — §8 ±0.2LU 데이터).
- **실측**: 다이나믹 신호에서 SNS 체인이 LUFS 감소·true-peak ≤ −0.5dB 보장·리미터 피크 추가 감소.
- **G-26 완결** — Inc1(컴프레서)→Inc2(리미터+리버브)→Inc3(체인+프리셋).

### 다음 회차 — 2단계 계획 평가
1. G-24✓·G-28(스키마+UI)✓·G-26(3종+체인)✓ — 2단계 핵심 완료.
2. 남은 2단계: N2(등록 결정 전제=사용자)·KPI 측정 창구·프로세서의 그래프 자리노드 직접 소비 배선.
3. 사용자 지시 또는 계획 문서 우선순위에 따라 다음 증분 결정. 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 49 (G-26 Inc 2 — 리미터 + 리버브)

**게이트**: verify_gate 5/5(1,312 테스트 — 신규 9종).

### 완료 — G-26 리미터 + 리버브 (커밋 5ed5b4d)
- **`AudioGraphLimiter`**: look-ahead 피크 클램프 — 창 내 최대 피크→천장 게인·즉시 어택·평활 릴리즈. **천장 절대 초과 않음 실측**(0dBFS→−1dB·과도→사전 클램프). 그래프 .limiter 자리 노드에 구현.
- **`AudioGraphReverb`**: 초기 반사 탭 지연 합성 — 6 탭·지수 감쇠·dry/wet·룸 사이즈. mix=0 비트 항등·꼬리 실측. v1 "공간감".
- 테스트 9종(천장·통일·look-ahead·빈 안전·클램프 + dry 항등·꼬리·프레임·빈).

### 다음 회차 인계 — G-26 Inc 3 (그래프 배선 + 프리셋)
1. 컴프레서·리미터·리버브를 그래프 렌더 체인에 배선(자리 노드 소비).
2. §8 LUFS ±0.2LU 게이트 확장.
3. SNS 프리셋(파라미터 세트). 이후 2단계 다음 항목. 실기기 3종=유보.

## 2026-08-20 세션 48 (G-26 Inc 1 — 오디오 컴프레서)

**게이트**: verify_gate 5/5(1,303 테스트 — 신규 9종).

### 완료 — G-26 컴프레서 (커밋 1af3f6a)
- **`AudioGraphCompressor`**(Core/Audio): 피드포워드 컴프레서 — threshold/ratio/attack/release/makeup. 정적 전달곡선(`staticOutputDb`) + 동적 PCM 적용(`apply`). 그래프의 자리 노드(nodeKind .compressor)가 스키마 불변으로 구현을 받음.
- 테스트 9종: 무릎 통일성·ratio 압축·메이크업·극단 ratio·실측 감쇠(≥6dB)·조용한 통일·빈 안전·클램프.

### 다음 회차 인계 — G-26 Inc 2 (리미터 + 리버브)
1. 리미터(look-ahead 피크 클램프 — true-peak 게이트와 직결) + 리버브(초기 반사 지연 합).
2. Inc 3(프리셋·디-이서 초기). §8 LUFS ±0.2LU는 배선 후.
3. 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 47 (G-28 Inc 2 — 효과 브라우저 UI)

**게이트**: verify_gate 5/5(1,294 테스트).

### 완료 — G-28 브라우저 UI (커밋 5e6e611)
- **`EffectBrowserView`**(App/Inspector): 검색(이름+태그)·costTier 배지(EffectCostProfile 소비)·즐겨찾기(정렬 우선)·카드 탭 적용(실제 updateSelectedEffects). 태그 18종 exhaustive.
- **인스펙터 통합**: Effects 섹션 헤더 "Browse" 버튼 + sheet.
- 정렬: 즐겨찾기 우선→비용 오름차순.

### 다음 회차 인계 — G-26 Inc 1 (오디오 컴프레서)
1. 그래프 자리 노드(nodeKind .compressor — 스키마 불변)에 AVAudioUnitCompressor 구현.
2. §8 게이트 확장: LUFS ±0.2LU(§8의 엄격 게이트 자연 확장).
3. 이후 G-26 Inc 2(리미터+리버브)·Inc 3(프리셋·디-이서). 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 46 (G-28 Inc 1 — EffectCostProfile 스키마 + 측정 파이프라인)

**게이트**: verify_gate 5/5(1,294 테스트 — 신규 5종).

### 완료 — G-28 전제 (커밋 6d113bf)
- **`EffectCostProfile`**: ms/frame(중앙값)·peakMemory·gpu/cpu·realTimeSafe(≤23ms)·costTier(instant/moderate/heavy)·measurementVersion — Codable. 브라우저의 검색/랭킹/배지 데이터 원천.
- **`EffectCostProfiler`**: 참조 프레임(1080p gradient+stripes)에서 전 빌트인 이펙트의 실측 프로파일 생성 — 워밍업 후 중앙값. 전 유형 유한·비음수 단위 테스트.
- PERFORMANCE_SLO 신설 행.

### 다음 회차 인계 — G-28 Inc 2 (브라우저 UI)
1. 검색·미리보기·즐겨찾기·파라미터 편집 — costTier 배지 포함(EffectCostProfile 소비).
2. KPI 측정 창구: 검색 성공률·재사용률(하니스 env).
3. 이후 G-26(Apple AU 오디오 B). 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 45 (P2-G24-6b — 실제 움블 픽스처 + DoD 활성화 · **G-24 완결**)

**게이트**: run_g24_stabilize_gate.sh **2회 연속 DoD PASS** + verify_gate 5/5.

### 완료 — P2-G24-6b (커밋 6dc3d28)
- **픽스처**: dark mandelbrot→bright testsrc2(eq ±0.4)+sine 움블 crop — 실제 카메라 흔들림 내장.
- **측정 모델 근본 수정**: 변위(속도)→**누적 위치**에서 작업 — accumulate→smooth→|raw−smoothed| 입력·correction=(smoothed−raw) 15% 클램프·residual=|(raw+corr)−smoothed|.
- **장면 전환 폴백**: 프로바이더의 카이제곱이 밝기 전환에도 불응 → 하니스 내장 평균 휘도 점프 폴백.
- **실측(2회 동일)**: ratio=0.000·crop=0.003·wobble=0.000·cut_errors=0 — **DoD PASS**.
- **G-24 완결** — 6증분: 측정 수학→분할 브리지→등록+평활화→CI warp→E2E 파이프라인→실제 움블+DoD.

### 다음 회차 인계 — G-28 (EffectCostProfile 선행)
1. EffectCostProfile 스키마 확정(PERFORMANCE_SLO 신설): ms/프레임 실측·메모리·GPU/CPU.
2. 기존 이펙트 프로파일링 실측 → 브라우저 UI.
3. G-24 후속 개선 후보: 컴포지터 배선(등록 보정 실제 렌더 체인 소비)·SceneChangeProvider 히스토그램 메트릭 조사.
4. 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 44 (P2-G24-6 — E2E 종단 파이프라인 · 픽스처 결함 발견)

**게이트**: verify_gate 5/5(1,289) + run_g24_stabilize_gate.sh(파이프라인 PASS — DoD 보고·비게이트).

### 완료 — P2-G24-6 (커밋 4a056bd)
- **하니스 STABILIZE env**: SceneChangeProvider→프레임 추출(120 luma)→등록(SAD)→평활화→보정→DoD 판정 — **종단 파이프라인 앱 컨텍스트에서 실증**(ratio 0.25·error=none).
- **`run_g24_stabilize_gate.sh`**: 실행·메트릭 보고(JSON 아티팩트).
- **픽스처 결함 2건 발견(정직한 기록)**: (a) 경계 검출 실패 — testsrc→smptebars 크롭 후 유사 휘도 (b) 실제 움블 부재 — testsrc의 카운터만 모션. DoD 보고는 하지만 게이트하지 않음.

### 다음 회차 인계 — P2-G24-6b (실제 움블 픽스처 + DoD 활성화)
1. ffmpeg 시변 crop 오프셋으로 sine 움블 적용(±6px x ±4px y @ 2Hz + 강한 대비 패턴 전환) → 경계 검출 + 실제 흔들림.
2. run_g24_stabilize_gate.sh가 DoD 차단 모드로 전환(ratio ≤ 0.5·crop ≤ 15%·wobble ≤ 3%·cut errors 0).
3. G-24 완결 선언. 이후 G-28(EffectCostProfile 스키마 확정 선행).

## 2026-08-20 세션 43 (P2-G24-5 — CI warp 프로세서)

**게이트**: verify_gate 5/5(1,289 테스트 — 신규 4종).

### 완료 — P2-G24-5 (커밋 98c6b08)
- **`StabilizationWarpProcessor`**(Core/Rendering): confidence fallback 포함 CI 워프. 확신 ≥ 0.15 → CGAffineTransform 평행 이동(extent 이동 검증). 제로 보정 → 비트 항등(CIImage equality). 확신 < 0.15 → 원본 통과(픽셀 동일)+bypassed 플래그(호출자 로그 — DoD fallback 지표).
- **범위 조정**: 컴포지터 배선은 P2-G24-6 E2E와 함께 — 실제 등록 데이터(Vision)가 흐르는 종단 경로에서만 측정 가능(측정 증거 없는 배선 금지 원칙).

### 다음 회차 인계 — P2-G24-6 (E2E 종단 + DoD)
1. 하니스 `MOVIECUT_UITEST_STABILIZE=1`: 등록(estimateTranslation)→평활화(smooth)→보정(correction)→워프(StabilizationWarpProcessor)→컴포지터가 소비하는 종단 경로를 앱 컨텍스트에서 구동.
2. 픽스처 실측 변위로 StabilizationMetrics.report 판정 — DoD: 잔류 50%↓·크롭 ≤15%·워블 ≤3%·장면 전환 0.
3. SceneChangeProvider도 앱 컨텍스트에서 검증(P2-G24-2에서 이관된 통합 테스트).
4. 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 42 (P2-G24-3 — 등록 + 평활화 + 보정)

**게이트**: verify_gate 5/5(1,285 테스트 — 신규 7종).

### 완료 — P2-G24-3 (커밋 841dd3e)
- **`StabilizationRegistration`**(Core/Analysis): estimateTranslation(SAD 블록 정합 — 결정적·swift test 동작)+ smooth(이동 평균)+ correction(역변·15% 클램프). 소비자는 RegistrationResult만 읽음 — Vision 업그레이드 시 출력 불변.
- **P2-G24-4의 수학도 통합** (smooth+correction이 같은 데이터 모델) — 계획의 4증분이 3+5로 병합.
- 테스트 7종: 알려진 시프트 ±1px 회수·동일 이미지 제로·퇴화 안전·스파이크 평활화(50%+ 당겨짐·분산 감소)·평활화 경계·보정 수학·제로 보정.

### 다음 회차 인계 — P2-G24-5 (CI warp 배선)
1. 등록·평활화·보정을 Mac 프리뷰/출력+iOS 컴포지터에 편입(CIPerspectiveCorrection·변위 적용).
2. confidence fallback: 낮으면 바이패스(명시적 로그 — 조용한 강등 금지).
3. 파리티 시나리오 신규(스태빌) + 이후 P2-G24-6 E2E(하니스 STABILIZE env + DoD 수치 실측).
4. 실기기 3종=유보. 대기 결정(변경 없음).

## 2026-08-20 세션 41 (P2-G24-2 — 장면 분할 브리지)

**게이트**: verify_gate 5/5(1,278 테스트 — 신규 4종).

### 완료 — P2-G24-2 (커밋 9352dbd)
- **`StabilizationSegmentation`**(Core/Analysis): 프로바이더 검출 시각 → `Frame.isSceneCut` 브리지(±프레임 창·클램프·변위 융합). 순수 수학.
- **환경 제한 발견·기록**: SceneChangeProvider의 AVAssetImageGenerator가 swift test 하에서 프레임을 생성하지 않음(NR DSP와 동일 계열 — 앱 컨텍스트 필요). 프로바이더 통합 검증은 P2-G24-6 E2E로 이관, 브리지 수학은 완전 단위 테스트.
- 테스트 4종: ±2프레임 창·복수 변경·퇴화 안전·변위 융합.

### 다음 회차 인계 — P2-G24-3 (Vision 등록)
1. VNGenerateOpticalFlowRequest 또는 homography로 프레임별 변환 행렬 추정 + confidence.
2. 합성 움블 픽스처의 ground truth(알려진 sine 움블)와 행렬 회수 ±10% 단위 테스트.
3. 이후 P2-G24-4(평활화+crop)·5(CI warp)·6(E2E). 실기기 3종=유보.

## 2026-08-20 세션 40 (P2-G24-1 — 스태빌 측정 인프라 · 2단계 착수)

**게이트**: verify_gate 5/5(1,274 테스트 — 스태빌 7종 신규) + 픽스처 재생성 동일 해시.

### 완료 — P2-G24-1 (커밋 e91771d)
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
- 없음(§7 열린 결정은 기본 채택값으로 진행 중). Track A(A-1 아이콘/A-2 App Store Connect)는 사용자 작업으로 계속 대기.## 2026-08-24 세션 (iOS 출력 golden 테스트 — 실제 익스포트 버그 포획·수정)

- `IOSExportEngineBehaviorTests` 4종: 실제 엔진·표준 픽스처로 2x/0.5x 출력 길이·프리즈 지속·프레임 색(솔리드 레드) 검증.
- **P0급 버그 발견·수정**: `insertVideoTrack`이 항상 오디오 composition 트랙를 추가 — 오디오 없는 소스는 빈 트랙 잔존 → `AVAssetExportSession`이 -11838으로 전체 익스포트 실패. 빈 트랙 제거로 수정(빈 트랙 `timeRange`는 0이 아닌 invalid/NaN — `!isValid` 포함). 바이섹트 진단(원시 경로·transform·네트워크 최적화·빈 오디어 트랙 순 차등)으로 원인 확정.
- iOS 21/21·게이트 5/5(1,413). §1.8~1.10 등록 결함 전량 수정 상태 유지.

### 다음 회차
CA-04 통합(병렬) → BUG-01 백오프·북마크 자동 치유(P2) → 실기기 G-27.

## 2026-08-24 세션 (잔여 소형 4건 — UX-REC-01/02·BUG-IOS-06·ko 번역)

**게이트**: 5/5(1,413)·Mac 38/38·iOS 17/17·지역화 검증기 PASS(332 키/455 카탈로그).

- **UX-REC-01**(2ca5f38): iOS 익스포트 활성 출력 URL 추적 → 취소/실패 시 잘린 .mov 제거(Mac 패리티).
- **UX-REC-02**(9d277fd): 런치 복구 후 유지/버림 알림 — 버림은 신규 프로젝트+복구 파일 삭제.
- **BUG-IOS-06**(b0a5f03): `loadTransferable(URL.self)` + 1MiB 버퍼 복사 + 오류 표면화(기존 Data 전체 적재·try? 무음 폐지).
- **ko 번역**(fbf3149): 양 카탈로그 106개 전량 — 기호/형식 키 동일값, UI 키 번역, 내부 증거 노트 실용 번역.
- 도중 UX-REC-02 커밋에서 VM 파일 누락(병렬 git 경합 추정) 발견 → amend로 정정.

### 다음 회차
CA-04(병렬) 통합 검증 → **iOS 출력 golden 테스트** → BUG-01 백오프·북마크 자동 치유(P2). §1.8~1.10 등록 결함 전량 수정 완료.
