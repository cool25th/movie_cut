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

## 3단계 증분 B (2026-09-02) — e2e HDR 프로브·writer 결함 수정·**flag 플립**

- **배선**: 하니스 `MOVIECUT_UITEST_EXPORT_PROFILE=<profile>` env → VM 신규 공용 마스터링 루트 `exportMaster(to:profile:)`(ProRes/HDR/하니스 노브가 같은 메서드로 수렴 — 기존 2경로 중복 제거) → `exportVideoWithExplicitBitrate(profileOverride:)`. flag 독립 설계 — 프로브가 플립 전에 실행 가능해야 함.
- **증분 A 결함 포착·수정(프로브 첫 수확)**: writer `outputSettings`의 `kCVPixelBufferPixelFormatTypeKey`가 `AVVideoCodecKey`와 공존하면 `AVAssetWriterInput`이 `NSInvalidArgumentException`으로 거부 — 예외가 Swift 비동기 태스크를 조용히 죽여 하니스가 무출력 파킹(3/3 결정적). 유닛은 딕셔너리 내용만 pin해 writer-input 실검증을 안 거쳤음. 격리 스위프트 프로브로 키 조합 특정(Rec.2020/HLG·Main10 무죄·픽셀포맷 키만 범인). **수정**: writer에서 픽셀포맷 키 제거 — 10-bit 서페이스는 reader(ExportEngine이 HDR에 420YpCbCr10BiPlanarVideoRange)의 책임으로 계약 문서화 + 유닛에 **실 AVAssetWriterInput 생성 트립와이어** 추가.
- **e2e 프로브 강화**(`run_e2e_export.sh`): ①명시적 오버라이드 HDR 프로브(codec/profile/pix_fmt/primaries/transfer/matrix + mid-frame 콘텐츠) ②SDR 명시적 회귀(8-bit Rec.709 핀) ③flag-gated HDR 섹션을 "거부 기대"에서 "실출력 기대"로 전환.
- **실측(격리+e2e 양쪽)**: 명시적 hevcHDR → **hevc / Main 10 / yuv420p10le / bt2020 / arib-std-b67 / bt2020nc**(1.5s, error=none, mid-frame rgb=112,97,99)·SDR hevc → **yuv420p / bt709×3** 무변경·flag 경로 동일.
- **FeatureFlag.hdrMaster 플립(OFF→ON)** — 플랜의 조건(실출력 10-bit/Rec.2020/HLG 확인 + SDR 무변경) 충족 후. preview는 여전히 SDR(BUG-CA12-02/G-29 범위)을 flag 문서에 명시. flag 의존 테스트 2종(HDRProfileGating·ExportPlanner) ON 계약으로 갱신 + 정적 계약(ExportOptionsUIStaticContract) exportMaster 라우팅으로 갱신.
- **검증**: swift test **1,467/218 PASS**(실패 1건=정적 계약 낡은 문자열 — 갱신으로 해결)·verify_gate **5/5 GATE_PASS**·run_e2e_export — **HDR 3섹션(명시적·SDR 회귀·flag 게이트) 전부 PASS**.
- **e2e 완주 부대낌(정직 기록 → 백로그 등록)**: ①**BUG-ACC-07**: G-25 §8 meter run M "measurement nil" — stash A/B로 **선결함 판정**(이번 증분 무관, 4/4 재현) — 전 섹션 외 유일 FAIL로 스크립트는 종료 코드 실패. ②**BUG-ACC-08**: 하니스 앱 간헐 비종료(산출물 완결 후 terminate 불이행 + ShareKit 루프) — 3회 관찰, 사이드카 와치독으로 회수하며 완주(소유 미판정·변경 경로 무관).

## 4단계 증분 1 (2026-09-02) — iOS preview 전용 source policy + thermal observer

- **범위**: 계획 4-2항 중 proxy/thermal 의미만 재구현(구형 IOSPlaybackEngine 복원 없음). ducking/EQ placed-span은 다음 증분.
- **구현**: ①`IOSExportEngine`에 `IOSSourcePolicy`(`.originalOnly`=export/하니스 명시 모드·`.proxyWhenAvailable`=프리뷰) 추가 — 플랜이 설정/ProcessInfo를 직접 읽지 않게 **호출자가 정책을 해석**해 전달(Mac `PlaybackEngine.playbackURL` 패리티). 비디오 삽입·오디오 삽입 양쪽이 같은 해석기 경유(프록시는 풀 트랜스코드라 A/V 동기 유지). ②`exportProject`는 `.originalOnly` **명시 전달** — 프록시로 마스터 만들면 다운스케일 아티팩트가 배이므로. ③프리뷰(PreviewView)는 `useProxyPlayback || ProxyDowngradePolicy.shouldAutoDowngrade(ThermalState.current, autoProxyOnThermalPressure)`로 정책 해석 + `thermalStateDidChangeNotification` onReceive 재구축 트리거(S7 사다리·Mac ThermalStateObserver와 동일 Core 정책 재사용 — 관찰자 클래스 복제 없음).
- **테스트**: 신규 `IOSSourcePolicyTests` 4종 — ①proxyWhenAvailable 플랜의 비디오 세그먼트가 프록시 URL 참조(구조 단언) ②기본(export/하니스) 플랜이 프록시 존재에도 원본 참조 ③**행동 증명**: 프록시(단색 청색 스탠드인·실 AVAssetWriter 생성)가 있어도 export 출력의 mid-frame이 적색 지배(원본 판독) ④정책 판정표(Core 패리티). 부수: `IOSPhase1SurfacesTests` 트랙 관리 테스트를 CODEX-20 잠금 계약으로 갱신(잠긴 트랙 삭제 거부 → 해제 후 삭제 — CODEX-20 세션이 iOS 전체 스위트를 안 돌려 방치된 낡은 기대치).
- **정적 계약 갱신 2건**: IOSParityMatrix·IOSColorCorrectionParity(플랜 호출 시그니처에 sourcePolicy 추가 반영 — 위임 의도 불변).
- **검증**: iOS 시뮬 전체 **75테스트/18스위트 PASS**(신규 4 포함)·Core swift test 1,467/218·verify_gate **GATE_PASS 5/5**.
- **thermal 측정 항목(4-1)은 환경 차단 기록**: serious 상태 장편 완주율 측정이 선행 조건이나 이 Mac mini에서 열 상태를 결정적으로 강제할 방법이 없음(공식 오버라이드 부재·지속 부하 방식은 사용자 voiceagent 활성 중 비현실적) — 조용한/부하 상태에서 측정 창구 확보 시 재개.

## 4단계 증분 2 (2026-09-02) — ducking/EQ placed-span — **4단계 구현 항목 완결**

- **덕킹**: `AudioMixEntry`에 ducking 창(클립-로컬 모델 초)·레벨·모델 시간축 추가 → `makeAudioMix`가 **Mac `PlaybackEngine.applyDuckingRamps` 계약 그대로**(ducked=base×level·attack 0.12s/release 0.25s·램프 사이 감쇠 유지·fade 창 회피·`mergeOverlapping`) 램프 적용. **placed-span 매핑**: 모든 오프셋·램프 길이가 placedDuration/timelineDuration 배율로 환산 — 1x에서 Mac과 동일, 2x에서 모델 시간 절반 위치에 덕 착지(원시 시간 버그 판별기로 실측 고착).
- **EQ 파생 유효 미디어**: EQ'd 클립의 오디오를 **공유 Core `AudioEqualizerService.apply`**(Mac 그래프 §0 유효 미디어와 동일 DSP — G-25 2C-2 어댑터로 비디오 컨테이너 포함)로 오프라인 렌더해 temp 파일에서 삽입 — 구형 EQ tap 복원 없음, 렌더가 원본 시간 배치 보존으로 sourceRange 1:1 매핑, 프리뷰·export가 같은 플랜 소비로 파리티 자동. 임시 파일은 imageRenderURLs 수명 주기와 동일 관리(eqRenderURLs).
- **테스트**: 신규 `IOSAudioDuckingEQTests` 5종 — ①덕 감쇠 ≥6dB(Mac e2e 임계값·through-mix Goertzel) ②**placed-span 판별기**(2x — 매핑 창 감쇠 + 원시 시간 창은 그대로 큼) ③무메타데이터 nil mix ④EQ 파생 미디어 구조(세그먼트 소스) ⑤bassBoost export 스펙트럼 행동(저/고 비 ≥2배).
- **검증**: iOS 시뮬 전체 **80테스트/19스위트 PASS**·Core 1,467/218·verify_gate **GATE_PASS 5/5**.
- **4단계 상태**: 구현 항목 전부 완결(proxy/thermal source policy + ducking/EQ). thermal 측정(6a58b16 이식 판단)만 환경 대기(serious 강제 불가 — 위 증분 1 기록).

## 리뷰 후속 (2026-09-03) — 코드리뷰 P2~P4 수정

- **P2 EQ 파생 미디어 캐시**: iOS 엔진에 `eqDerivations` 캐시 추가 — Mac `equalizedPreviewAudio` 패리티(설정+입력URL 키, "관련 없는 편집마다 재렌더 금지" 주석 동일). 프리뷰가 모든 커밋마다 플랜을 다시 만들어 긴 소스의 EQ 클립에서 전체 PCM 재렌더가 반복되던 성능 결함 수습. evict 시 이전 temp 즉시 삭제·EQ 해제 클립의 캐시 항목 회수(수명=엔진). 테스트: 재사용(동일 파일)·설정 변경 시 재파생 단언.
- **P3 quit 헬퍼 통일**: 하니스 내 12곳 `NSApp.terminate` 사이트가 전부 `terminateHarnessProcess()`(terminate 반환 시 exit(0) 폴백)로 통일 — 메인 플로우만 경화돼 있던 커버리지 공백(파리티 흐름 등 export 생산 시나리오가 같은 파크 클래스에 노출).
- **P3 thermal 스킵 가드**: PreviewView가 정책 불변 thermal 알림(nominal↔fair 등)에서 재구축 스킵 — Mac 옵저버의 중복 스킵 패리티(EQ 파생 비용과 곱해지던 낭비).
- **P4**: e2e flag-gated HDR 출력 파일명 `.mov`→`.mp4`(컨테이너 정합).
- **검증**: iOS 시뮬 **81테스트/19스위트 PASS**(캐시 테스트 포함)·verify_gate **GATE_PASS 5/5**·**e2e 전체 클린 패스(12분 22초 완주, `E2E check OK` — BUG-ACC-07/08 수정 반영 후 첫 풀 그린, HDR 3섹션·G-25 미터 포함)**.
- **정직 기록**: e2e 클린 패스까지 4회 실패 — 전부 **병렬 루프 세션 증분 버스트가 이 세션의 앱 인스턴스를 SIGTERM**하는 경합(광학흐름 섹션 ~21초 만에 사망·단독 실행은 항상 통과·시스템 로그에 킬 근거 없음·루프 셸/테스트 시작 시각과 상관 관계). 재시도 래퍼로 깨끗한 창 확보. 크로스세션 검증 직렬 규율의 실효 사례.

## 감사 잔여 항목 처분 (2026-09-03, 항목 3·5·6)

- **5 — 스크립트 처분**: `run_preview_export_parity.sh`(계승: run_core_editing_parity가 같은 비교기로 19시나리오 커버)·`capture_capcut_parity.sh`+`capcut_parity_metrics.py`(UI 스크린샷 패리티 도구 — MACUI-01 AX 차단·아카이브 문서 전용; 인코딩 B측 도구는 아님) → **docs/archive/scripts/ 이동 보존**. `verify_preview_export_parity.py`는 현행 게이트·nightly가 사용 중이라 **원위치 유지**·ab_benchmark 주석의 이동된 경로 참조 정리.
- **3 — 카드뉴스 은닉 명시화**: `isCardEditorMode`에 dormant-by-design 문서화 — 제품 UI는 cardDocument를 만들지 않고 진입은 cardDocument 보유 프로젝트 열기 + 하니스/e2e(G-18/G-19)뿐. Core 모델·명령은 후속 오서링 기능용 유지(삭제 아님 — 제품 결정 대기 유지하되 상태가 코드에 보임).
- **6 — UITestHarness 분할**: **이연(근거 기록)** — 확장 멤버 114개 중 private 59개·공유 헬퍼 다수로 분할 시 internal 승격이 광범위하고, 병렬 루프 세션의 STAB-02 취소 E2E가 같은 파일에 시나리오를 추가할 가능성이 높아 지금 분할은 충돌 위험이 이득보다 큼. 병렬 세션 종료 후 단독 증분 권장.
- 게이트: verify_gate **GATE_PASS 5/5**.

## 다음 작업

1. ~~3단계 증분 B·4단계 구현 항목~~ **완료**.
2. 남은 4단계: thermal 측정(환경 대기 — 조용한/부하 기기에서 serious 상태 장편 완주율).
3. BUG-ACC-08 조사·CODEX-04(실기기 대기).
4. 통합 브랜치 병합 결정(사용자).
