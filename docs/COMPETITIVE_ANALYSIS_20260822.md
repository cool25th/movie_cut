# MovieCut 경쟁 분석·제품 방향 — 통합 문서 (2026-08-22, v3)

> **통합 이력:** 2026-08-22 세션의 4개 문서(갭 분석 / 세부 기능 딥다이브 / Evidence Ledger / Capability Matrix)를 **하나로 통합**(사용자 지시). 외부 피드백 v2 반영분을 승계한다. 경쟁 사실·출처는 §9, 내부 기능 상태는 §10에 원장 형태로 보존.
> **비교 축:** 모바일(iOS 앱) ↔ YouTube Create 0.139.x / **맥 설치 버전**(native Mac 앱) ↔ CapCut 데스크톱 설치판 2026-08 + Final Cut Pro 12.3. 브라우저 편집기·생성 AI는 범위 밖(오프라인 원칙).
> **연계:** 방향의 기반은 `DEVELOPMENT_DIRECTION_20260815.md`(포지셔닝·12개월 순서·W1~W5). 본 문서는 경쟁 관점의 보완이며, 실행 우선순위 충돌 시 방향 문서 §3의 고정 순서가 우선한다(변경은 사용자 승인 필요).

---

# Part 1 — 기준·정의 (모든 표와 주장의 전제)

## 1.1 상태 표기 E/U/P/X/D/S

사용자 관점에서 **UI 미노출 기능은 없는 기능**이고, export 미검증 기능은 출시 기능으로 계산하지 않는다.

| 표기 | 의미 |
|---|---|
| **E** | Engine 구현(코어 로직 존재) |
| **U** | 사용자 UI 노출 |
| **P** | Preview 검증(골든/픽셀 증거) |
| **X** | Export 검증(픽셀·ffprobe·E2E 증거) |
| **D** | 실제 기기 검증(Mac 로컬 E2E / iOS 실기기 G-27) |
| **S** | 출시 지원 범위 포함(Track A 출시 후 확약) |

경쟁표의 "지원" 비교에는 **S만** 사용한다(현재 미출시 → 전항목 S=—가 정상).

## 1.2 프리뷰=출력의 정의 ("같은 픽셀" 주장 철회)

> 프리뷰와 출력은 동일한 타임라인 평가·효과 순서·색관리 규칙을 사용하며, 항목별로 정의된 허용 오차 안에서 일치한다.

| 등급 | 대상 | 기준 |
|---|---|---|
| **Exact** | 시간 계산, 키프레임 평가, transform, 렌더 계획, 무손실 중간 출력 | 수치 동일 |
| **Tolerance** | GPU 색보정, 마스크 경계, 필터 출력 | 허용 오차(**Q7 확정: 현행 골든 파리티 MAD ≤ 2.0 유지** — 등급별 세분은 측정 데이터 확보 후) |
| **Perceptual** | H.264/HEVC 인코딩, 프록시 프리뷰, HDR 디스플레이 | 지각적 일치(블라인드) |

외부 문구는 **"보이는 대로 출력"**. 골든 하니스·null test는 Exact/Tolerance의 내부 증거다.

## 1.3 온디바이스·네트워크 주장의 증명 체계

- **Mac(사실 확인):** App Sandbox + `network.client` 부재(`App/MovieCutMac/MovieCutMac.entitlements`, 의도 주석 명시) → 샌드박스 앱 외부 발신 OS 차단.
- **iOS:** entitlement 개념 없어 별도 증명 — ① 코드 감사(네트워크 API 부재, **2026-08-22 확인**) ② 차단 환경 대표 작업 통과 ③ 트래픽 캡처 0 (②③ 미실행 — P0).
- **STT(사실 확인):** `requiresOnDeviceRecognition = true` + 미지원 시 명시적 실패(서버 폴백 없음, `SpeechTranscriptionProvider.swift`).
- **외부 문구:** "네트워크 권한 0" 대신 **"편집·자막 생성·출력 과정에서 영상과 음성을 외부 서버로 전송하지 않습니다"**(Apple이 처리하는 통신과 범위 구분 명시).
- **자막 언어:** "지원 기기·언어에서 온디바이스 STT, 네트워크 폴백 없음." 언어별 WER/CER·30분 안정성 매트릭스는 미측정(P0).
- **길이:** "MovieCut 자체 길이 제한 없음. 최대 검증 길이 별도 표기"(장문 안정성 미측정).

## 1.4 성능 수치의 정의

- `Export RTF = export 경과 / 출력 길이`(RTF 0.99 = 10분 영상 9분 54초 출력). 모든 비교에 조건 필드 필수: 기기·RAM·OS·앱버전·전원·thermal·cold/warm·저장장치(입·출력)·코덱·해상도·fps·비트레이트·HW인코딩·캐시 상태·반복 횟수·중앙값/p95·peak RSS·앱 전체 vs encode 구간.
- `seek 0.05ms`는 **타임라인 모델 계산 시간**. 외부 공개 값은 "사용자 입력 → 화면 프레임 표시 완료"로 재측정(분해: 모델 계산/디코더 seek/첫 프레임/표시 완료/연속 scrubbing fps/캐시).
- `열기 144ms`·`225MB`는 fixture 규모(10분 프로젝트) 명시 필수.

## 1.5 자동화의 수정가능성 원칙

> MovieCut의 자동화는 항상 **설명 가능하고, 미리 볼 수 있으며, 부분적으로 적용하고, 완전히 되돌릴 수 있어야 한다.**

모든 자동 기능(오토컷·하라이트·무음 제거·N1·N2) 게이트: 변경 미리보기 / 적용 범위 선택 / confidence 표시 / 개별 제외 / 단일 undo / 원본 보존 / 동일 입력 재현성 / 재실행이 사용자 수정을 덮어쓰지 않음.

## 1.6 주장 수위 사다리

| 단계 | 문구 | 해제 조건 |
|---|---|---|
| 지금 | "온디바이스 다국어 자막에 집중" | — |
| 실증 후 | "계정 없이 긴 영상 자막 생성" | 언어 매트릭스·장문 안정성 측정 |
| 블라인드 평가 후 | "주요 언어에서 경쟁 대비 동급 이상" | 언어별 블라인드 WER/CER + 수정 시간 측정 |

"3제품 최강"·"FCP급 오디오"·"코어 열위 없음" 금지. 오디오는 **"EQ·컴프레서·리미터·덕킹·LUFS 포함 내장 음성 마스터링 워크플로"**로 표현(AU 플러그인·roles·서라운드·자동싱크·stem export 등 미보유).

## 1.7 타깃 사용자 (**Q1 확정** — 제안안 채택, `DECISIONS_20260822.md`)

> iPhone 또는 미러리스로 촬영하며, CapCut은 출력·프라이버시가 불안하고 Final Cut Pro는 과도하다고 느끼는 1인 크리에이터.
> 핵심 작업: 30분 촬영본 좋은 구간 찾기 / 무음·실수·필러 제거 / 세로형 쇼츠 / 한국어 자막 생성·스타일링 / 음악에 맞춘 컷 배치 / 정확한 품질 출력.
> 전환 이유: 계정 없음 / 업로드 없는 STT / 빠른 초안 / 수정 가능한 자동화 / 출력 품질·메타데이터 통제 / 일회성 구매.

경쟁표 각 기능은 최소 하나의 핵심 작업과 연결한다. 연결 없는 기능은 우선순위를 낮춘다.

---

# Part 2 — 모바일(iOS) vs YouTube Create

## 2.1 기준

YouTube Create는 서비스 중(2026-08-21 Play 업데이트, iOS 주간 릴리스). 한국 정식 배포. 무료·무워터마크·무광고, Google 계정 필수, 편집 온디바이스, 생성 AI는 클라우드+미국 등 5~6개국 한정.

## 2.2 이미 이기는 축 (단, §1.1 표기로 실증 상태 명시)

| 영역 | YouTube Create | MovieCut iOS |
|---|---|---|
| 키프레임 | **없음** | 7속성·보간 5종 — E·U 확보, P·X 미검증² |
| 레이어/멀티트랙 | 제한적 | 멀티트랙 — E·U 확보 |
| 역재생·정지프레임·램프 | **없음** | **E만 확보(U❌·X 미검증)** — Part 10 iOS `●·○·○·◐·○`와 정합² |
| 마스크 6종·크로마키 | 컷아웃+기본 크로마 | E·U 확보, 배선 후 행동 검증 대기(**iOS preview는 크로마 미표시** — `PLATFORM_PARITY_MATRIX.md`)² |
| 자동 자막 | **60초 초과 불가(공식)**¹ | 온디바이스·폴백 없음 — 언어 실증 미측정 |
| 프라이버시 | 계정 필수·AI 클라우드 | 계정 불필요·외부 전송 없음(§1.3) |
| 실행취소 | 기본 | 무제한 |

¹ 공식 원문: "YouTube Create cannot generate captions for clips longer than 60 seconds." (support.google.com/youtube/answer/13818789, 2026-08-22 확인 — §9 YC-01)
² E 기준 우위 행은 U/X/D 확정 전 대외 홍보 불가(§1.1).

## 2.3 하드 격차 (지는 목록)

| # | 격차 | 내용 | 매핑 |
|---|---|---|---|
| M1 | 전환(two-source) 렌더 부재 | iOS에 `TransitionPixelProcessor` 미배선 — 상대는 전환 40+종(3차 집계) | G-09 Inc3 2순위 |
| M2 | autosave/복구 부재 | iOS 라이프사이클에서 ProjectStore 미연결 — 크래시 시 유실 | G-09 Inc3 3순위 |
| M3 | 출력 옵션 | `.mov` 단일 프리셋 vs 상대 4K(비공식)·화질 선택 | G-09 Inc3 4순위 |
| M4 | 오디오 도구 | 상대 원탭 정리 vs iOS EQ·덕킹·NR 액션 부재 | G-09 Inc3 5순위 |
| M5 | 실기기 성능 데이터 없음 | G-27 3종 대기 — 상대 핵심 자산이 "중저가 폰 매끄러움" | G-27 (P0) |
| M6 | YouTube 직접 업로드 | 상대 시그니처. **Q4에서 비목표 확정** — 오프라인 원칙(외부 전송 없음) 최우선 | F-24 |
| M7 | 검증 부재 | 램프·역재생·정지·배경제거 export 미증명 | G-27 |
| M8~M13 | 중간 격차 | iOS 트림 = 툴바 버튼 존재하나 no-op + 핸들 UI 부재(U❌) / 비트 감지 iOS UI / 템플릿 탐색 / 음악 규모(방향 §2 확정 유지) / 폰트(N5, 라이선스·패키징 동반) / 원클릭 자동화(N2) | 소형·P1~P2 |
| M14 | 컬러 심층 UI iOS defer | 3-way 휠/스코프 심층 UI 미노출 — 렌더 parity는 존재 | 방향 §3 defer 유지 |
| M15 | 생성 AI 비목표 | Gemini Omni·Seedance 등 생성 계열 미채택 — 오프라인 원칙 | §6 비목표 명시 |

**요약:** M1~M4는 G-09 Inc3에 이미 문서화된 순서와 일치(신규 기획 불요, 실행 문제). M5가 모바일 성능 우위 주장의 유일한 차단 항목. M6은 Q4 비목표 확정으로 종결.

---

# Part 3 — 맥 설치 버전 vs CapCut + Final Cut Pro

## 3.1 2026-08에 닫힌 격차 (08-16 분석 대비)

| 격차 | 상태 | 근거 |
|---|---|---|
| C1 자막 완성 외형 | 닫힘(Mac) — 카라오케 UI+스타일 6종(골든) | aefbfa5, 00c97cf |
| F1 HSL/커브 UI | 닫힘(Mac) — HSL 8밴드+파리티 실증 | c142c62 |
| F2 조정 클립 | 닫힘 — 렌더 배선 Mac+iOS | b9d0e58 |
| F3 팬·믹싱·미터·LUFS | 닫힘 — null test·−0.02LU·드리프트 0 | G-25 |
| F5 안정화 | 닫힘(v1) — DoD PASS+warp 통합 | 1dbf49a |
| C2 효과·템플릿 브라우저 | 닫힘(Mac) — G-28 전체 | 836d246 등 |
| F4(일부) 오디오 프로세서 | 닫힘(기본선) — G-26+직렬화+마스터 체인 UI | 075910a, 68a03f7 |
| G-06 보간 UI | 닫힘(Mac) — 베지어 그래프 | aa1ba11 |
| G-23 크롭 | 닫힘 — iOS 진입점 포함 | b4de271 |

## 3.2 세부 기능 매트릭스 (방향 열 포함)

### A. 편집 코어 — 방어

| 기능 | YouTube Create | CapCut | FCP 12.3 | MovieCut (Mac/iOS) | 방향 |
|---|---|---|---|---|---|
| 타임라인 모델 | 순차+오버레이 | 멀티트랙 | 마그네틱 | 마그네틱+멀티트랙 ✅/E·U | 방어 |
| 트림/스플릿/리플/슬립/슬라이드 | 트림·스플릿 | 대부분 | 전부+투업 | Mac 전단계 ✅ / **iOS 트림 = 툴바 버튼 존재하나 no-op + 핸들 UI 부재(U❌)** | iOS 소형 |
| 컴파운드 | ❌ | 있음 | 무제한 | 1레벨 ✅/미노출 | 다단계 3단계 |
| 조정 클립 | ❌ | 있음 | 11.1+ | ✅/렌더 배선 | 방어 |
| 키프레임 | **❌** | 속성별 | 속성별+그래프 | Mac✅/iOS E·U | 실증 후 홍보 |
| 마스크 | ❌ | 있음 | 마그네틱+Auto Mask | 6종 ✅/E·U | F14 후순위 |
| 스피드 | 상수 | **커브** | 램프+광학흐름 | Mac✅/iOS E·U❌ | iOS UI+검증 |
| 역재생·정지 | **❌** | 있음 | 있음 | Mac✅/iOS E만 확보(U❌·X 미검증) | G-27 |
| 멀티캠 | ❌ | 제한 | 64각도 | ❌ | 비목표 |

판정: **"Mac 출시 단위로는 열위 없음, iOS는 U/X/D 미완 다수"** — 남은 일은 전부 iOS UI·검증.

### B. 자막·텍스트·트랜스크립트 — 공격 축 (선언은 §1.6 사다리)

| 기능 | YT Create | CapCut | FCP 12.3 | MovieCut | 방향 |
|---|---|---|---|---|---|
| STT 자막 | 60초 제한(공식)¹ | 다국어·화자(Pro) | 미국영어·실리콘 한정 | 온디바이스 폴백 없음 | 언어 실증 P0 |
| 워드 타이밍·수정 | 워드 수정 | 워드 수정 | 트랜스크립트 편집 | ✅/iOS 확인 필요 | iOS 보강 |
| 스타일 | 기본 | 다수 | 캡션 스타일 | 6종 Mac✅/iOS❌ | iOS 이식 |
| 카라오케 | 비공식 | 있음 | ❌ | Mac✅/iOS❌ | iOS 이식 |
| 폰트 | Google 수백 | 다수+임포트 | 시스템+커스텀 | 시스템만 | N5(라이선스·패키징 동반) |
| TTS | AI 내 한정 | AI 음성 | ❌ | AVSpeech Mac✅ | 유지 |
| 텍스트 기반 편집 | ❌ | ❌ | Transcript Search(12.0) | ❌(인프라 보유) | **N1 — §6.1** |

**자막 경쟁력 평가 항목(전부 미측정):** WER/CER(ko·en)·고유명사·문장부호·숫자·다중 화자·음악/노이즈 환경·워드 타이밍 오차·장문 sync drift·부분 재생성·사용자 사전·줄바꿈·CPS 경고·SRT/VTT/ITT·burn-in vs sidecar·번역·safe area·세로형 회피. → 2026-08-23: sidecar 검증 CA-17, 화자 분리 CA-18 등록 승인.

### C. 오디오 — 표현 축소(§1.6)

FCP급 철회 — 미보유: AU 플러그인·roles·서라운드 패닝·자동싱크·batch normalization·stem export·latency compensation·effect automation. 완결 범위는 **"음성 중심 소셜 영상의 기본 믹싱 체인"**(EQ·컴프·리미터·덕킹·팬·미터·LUFS — Mac 측정 통과). 방향: iOS "최소 팬·프리셋·미터"(2단계 계획), ML 스템 3단계 게이트, 음성효과·음악 수 경쟁 불응(라이선스 검토 전 확대 금지), 비트 감지 iOS UI(P1).

### D. 색·이미지

기본 보정·휠·커브·HSL(8월 닫힘)·LUT Mac✅. 스코프 히스토+웨이브+**벡터스코프(Mac U 확보 — `InspectorEffectsSection.swift:200`, 2026-08-23 확인, P/X 미검증; 구 문서 "P2"는 오류로 정정 — CA_REGISTRATION_PROPOSAL §4)**. **매치컬러: FCP 12.3 + CapCut 모두 보유(공식 문서 — §9 CC-01 정정), MovieCut 없음 → P2.** 안정화 v1 완료(v2는 4단계). **LUT export·RGB 파레이드 부재(2026-08-23 확인) — CA-26·28 등록.** 뷰티 N6 **비목표 확정(Q4)** — 오프라인 원칙·포지셔닝상 제외, 백로그 명시 완료. HDR G-29 3단계 게이트 유지.

### E. 이펙트·콘텐츠

전환 11종 Mac✅/iOS 렌더 미배선(M1) — `TransitionType` 구체 케이스 기준(`.none`·범주 라벨 제외 11개, 2026-08-22 코드 확인). CapCut 템플릿 바이럴 마켓은 복제하지 않음 — 대응은 G-28 탐색 품질(완료)+**N2 오토스타일**. 애니메이션 스티커(N3)는 `.moviecutpack` v0와 세트(3단계). 타임라인 가이드라인+눈자 밀도 감사(CA-19 — 시간 눈자는 이미 존재, 2026-08-23 정정).

### F. AI·자동화 — N1·N2에 집중

오토컷·하이라이트·리프레임·트래킹·배경제거 엔진 보유. Edit Detection(N11) 검토. 생성 AI(Gemini Omni·Seedance) **비목표 명시** — "편집 품질·프라이버시에서 상회, 생성 제외".

### G. 출력·성능

Mac: H.264/HEVC/ProRes 422·4444·1-200Mbps·챕터·소셜 프리셋 5종(ffprobe)·프록시 4단계+thermal. iOS `.mov` 단일(M3). FCP 12.3이 백그라운드 렌더 기본 OFF로 전환한 교훈: 성급한 백그라운드 렌더는 렌더 파일 팽창 부채 — F9는 2~3단계. **성능 우위 주장은 §7 하니스 완료 전 보류.**

### H. 플랫폼·신뢰·가격

계정 없음·외부 전송 없음(§1.3) = 최강 차별화, 마케팅 첫 줄. 가격은 사실만: FCP $299.99 일회성(US) + Creator Studio $12.99/mo·$129/yr(일부 콘텐츠 구독자 전용) / CapCut Pro $19.99/mo(US 정상가, 지역·경로 상이, 영구 없음) / YT Create 무료. 평가 표현 제외, 상세는 §9 가격표. MovieCut 가격 모델 **확정(Q2): 일회성 구매+유료 메이저 업데이트·Universal Purchase** — 구체 가격 미정(CA-07, 사용자 전용). FCP 12.3 요구 macOS 15.6+ vs MovieCut macOS 14+ — macOS 14 지원 **유지 확정(Q3)**, FCP(15.6+)가 못 닿는 시장 차별화.

---

# Part 4 — 제품 기본기 (기능표에 없던 출시 기본기, 대부분 미감사)

> 효과·AI보다 먼저 사용자를 잃게 하는 영역. 감사 전 경쟁표 기입 금지.

## 4.1 가져오기·미디어 관리
대량 임포트(수백~수천) / Photos+iCloud 원본 상태 / 외장 디스크 재연결 / **미디어 재연결** / 중복 감지 / 누락 안내·일괄 재연결 / 메타데이터 / 정렬·검색 / 썸네일 백그라운드 / 긴 오디오 파형 / 프록시 관리 / 캐시 용량·정리 / 사용 미디어 아카이브 / import·proxy 중단 복구. 현황: bookmark persist 확인, 나머지 ❓. **로컬 우선 앱의 차별화 = "파일을 잃지 않게 관리하는 능력" — P0 감사.**

## 4.2 프로젝트 호환성·마이그레이션
과거 schema 전 fixture / 이전 프로젝트 열기 / migration 실패 시 원본 보존 / 도중 종료 복구 / 하위 호환 안내 / 손상 복구 / 사본 / 외장 이동 / 패키징 / 경로·bookmark 만료 / 파일명 충돌 / 재설치 후 접근. 현황: v1~v4+autosave 존재(Mac E2E), 실패 경로 ❓. "몇 년 뒤에도 연다"가 신뢰 자산 — P0.

## 4.3 입력 포맷 호환성
H.264/HEVC 8·10bit / HLG·PQ / Apple Log·Log 2 / ProRes / alpha / **VFR** / 23.976~60fps / rotation / non-square / 인터레이스 / 화면녹화 / 슬로모션 / Cinematic / spatial / MP3·AAC·PCM·ALAC / 44.1·48·96kHz / 채널 / 이미지 orientation·wide gamut. **최우선 회귀: 서로 다른 fps·색공간·sample rate 혼합 시 sync·색 유지** — P0 매트릭스.

## 4.4 실패·복구 UX
디스크 부족 / 쓰기 불가 / 디스크 해제 / 파일 손상 / 미지원 코덱 / 메모리 압박 / thermal / 백그라운드 / 취소 / 강제 종료 / 잠금 / 전화·오디오 세션 / 권한 거부 / STT 모델 부재 / 저장 중 종료. 판정: 무손실·원인 이해·재시도·이어하기·임시 파일 정리. 현황 부분(export 분류·thermal·복구) — 전체 매트릭스 P0.

## 4.5 접근성
VoiceOver / Voice Control / 키보드만 편집 / 대비 / 색만 구분 금지 / Reduce Motion / 포커스 / 타임라인 클립 설명 / 시간 읽기 / 슬라이더 값·미세조정 / 오류 접근성 / 첫실행~구매 완료. 현황 ❓(누락 영역이었음). Apple Accessibility Nutrition Labels 대응 예고 — **커스텀 타임라인 UI는 후조립 어려움, 지금 핵심 경로 게이트**(범위 Q6).

## 4.6 현지화·텍스트 품질
ko·en UI(카탈로그 존재) / CJK fallback / RTL 자막 / emoji·결합문자 / line breaking / 세로 텍스트 / safe area / 숫자·시간 locale / 파일명 유니코드 정규화 / 비라틴 단축키. 다국어 자막 강점의 전제 — P1 감사.

---

# Part 5 — 벤치마크 하니스 설계

1. **비교조건 필드(필수):** §1.4 목록 전부.
2. **품질 지표:** PSNR 단독 금지 — SSIM+지각 지표+프레임별 오차+ΔE+banding+highlight clipping+shadow crush+chroma subsampling+keyframe 간격+실제 bitrate+VFR/CFR+audio sync+loudness·true peak+메타데이터, **사람 블라인드 병행**(방향 문서 4단계 게이트를 상시 하니스로 앞당김).
3. **대표 프로젝트 세트(버전 관리):** ①1080p30 단일 ②4K60 HEVC ③10-bit HDR ④30분 인터뷰+자막 ⑤다중 오버레이 쇼츠 ⑥램프+광학흐름 ⑦마스크+크로마키 ⑧색+LUT ⑨덕킹+마스터체인 ⑩외장 디스크 ⑪VFR 화면녹화 ⑫2시간. fixture마다 checksum·schema 버전·기대 메타데이터·대표 프레임·허용 오차·기준 성능 범위 고정.
4. **측정 정의:** §1.4 준수.

---

# Part 6 — N1·N2 단계 분해

## 6.1 N1 대사 기반 편집
- **N1-A 대사 검색(P1):** 정확·유사 검색 / 결과 목록 / 구간 이동 / 마커
- **N1-B 텍스트 선택(P1):** 문장→range 선택→재생
- **N1-C 텍스트 삭제(P2):** ripple delete / undo / 연결 클립 / 자막 재동기화
- **N1-D 필러 제거(P2):** 후보 표시 / 일괄 미리보기 / 개별 승인 / jump cut 처리

## 6.2 N2 오토스타일 MVP (P1)
후보 생성 → 사용자 선택 → 컷 적용 → 비트 싱크 → 자막 스타일 → BGM 덕킹 → 재생성 → **사용자 수정 보존**. 첫 버전은 "자동 완성"이 아닌 **제안→미리보기→적용→되돌리기**(§1.5).

---

# Part 7 — 우선순위 (P0/P1/P2)

**P0 출시 주장:** ① §9 Evidence Ledger 확정 ② §10 E/U/P/X/D/S 전환 ③ G-27 실기기 검증 ④ G-09 Inc3(iOS 전환·autosave·출력·오디오) ⑤ 미디어 재연결·손상·디스크·복구 테스트(§4.1~4.4) ⑥ 입력 포맷 매트릭스 ⑦ 프리뷰/export 허용 오차 확정(Tolerance 수치) ⑧ 오프라인 차단 테스트(iOS 포함) ⑨ 접근성 핵심 경로 매트릭스 ⑩ 가격·판매 단위 결정.

**P1 차별화:** iOS 자막 스타일·카라오케 / N1-A / N1-B / N2 제안형 MVP / 상시 벤치마크 하니스 / 폰트 패키징 정책 / 비트 감지 iOS UI / 현지화 감사.

**P2 반응 후:** N1-C·N1-D / 매치컬러 / 애니메이션 스티커 / 보이스 체인저 / 업로드 메타데이터 보조 / iOS 프록시 / 배치 export. (벡터스코프는 2026-08-23 구현 확인으로 P2 목록에서 제외 — §3.2.D·CA_REGISTRATION_PROPOSAL §4)

신규 편입(⑤⑥⑨)은 **Q11 승인 완료**(`DECISIONS_20260822.md`) — 방향 문서 §3 반영 후 실행. ⑩(가격·판매 단위)은 모델을 Q2에서 결정, 구체 가격만 CA-07 잔여. ⑦(Tolerance 수치)은 Q7 확정(MAD ≤ 2.0) 이행, ⑧(오프라인 차단 테스트)은 §1.3 MC-02②③ 이행으로 신규 기획 편입이 아니다.

---

# Part 8 — 열린 결정 (질문 목록)

> **(2026-08-22 확정)** Q1~Q12 전항목 결정 완료(권장안 채택) — 결정 원천은 `DECISIONS_20260822.md`, 백로그 §0.5.1 게이팅 갱신·REQUIREMENTS §13.15 반영 완료. 아래는 질문 원문으로 보존한다.

Q1 타깃 페르소나·핵심 작업 확정 / Q2 가격·판매 모델(①일회성+유료업데이트 ②체험+잠금해제 ③일회성+콘텐츠팩 구독)·Universal Purchase / Q3 macOS 14 지원 유지(FCP는 15.6+) / Q4 N6 뷰티·F-24 업로드 보조 최소안 / Q5 자막 언어 범위·WER 목표 / Q6 접근성 게이트 범위·자동화 원칙 적용 범위 / Q7 Tolerance 허용 오차 수치 / Q8 성능 대외 수치 재측정·공개 시점 / Q9 경쟁사 실측 방식 / Q10 분기 갱신 편성 / Q11 P0 신규 편입 승인 / Q12 프로젝트 공식 지원 상한.

---

# Part 9 — 경쟁 사실 증거 원장 (Evidence Ledger)

> 신뢰도: ★★★ 공식 1차(원문 인용) / ★★ 검증된 2차 / ★ 커뮤니티(경향만) / ⏳ 실기기 검증 대기. 공식 문서상 제공 ≠ 설치판·무료 플랜 제공.

## YouTube Create
| ID | 주장 | 신뢰도 | 상태 |
|---|---|---|---|
| YC-01 | 캡션 60초 제한 — 공식 원문 확인 | ★★★ | 2026-08-22 확인(국가·언어별 관찰 기록은 미작성) |
| YC-02 | 캡션 언어 목록 비공개(한국어는 3차 자료) | ★★★/★ | 확인 |
| YC-03 | 키프레임·역재생·정지·램프 없음 | ★★ | ⏳ 표준 양식 1회 실측 권장 |
| YC-04 | 전환 40+ | ★ | ⏳ 개수 실측 |
| YC-05 | 4K60 출력 | ★ | ⏳ "비공식" 취급 유지 |
| YC-06 | 백그라운드 전환 시 export 중단 | ★★★ | 확인 |
| YC-07 | 계정 필수·생성 AI 5~6개국·SynthID | ★★★ | 확인 |
| YC-08 | 로열티프리 수천+Shorts 라이브러리 제약(60s·유튜브 한정) | ★★★ | 확인 |
| YC-09 | 긴 영상 크래시·느린 임포트 불만 | ★ | 경향 관찰만 |

## CapCut 데스크톱 설치판
| ID | 주장 | 신뢰도 | 상태 |
|---|---|---|---|
| CC-01 | **Match Color 존재(공식 Color Matcher 페이지)** | ★★★ | 2026-08-22 확인 — v1 "❌"은 오류(정정). 설치판·플랜·지역 ⏳ |
| CC-02 | Pro $19.99/mo(US), 영구 없음, 4K·AI는 Pro | ★★ | ⏳ 가격표 필드 관리 |
| CC-03 | 강제 로그인화(연령게이트·잠금 사례) | ★★ | 확인 |
| CC-04 | 2025-01 미국 중단 → 2월 복귀 | ★★ | 확인 |
| CC-05 | export 재압축·랙·자가업데이트 지연 불만 | ★ | 경향만 — 정량은 §5 하니스로 |
| CC-06 | 2026-08 pro 물결(눈자·가이드라인·오실로스코프) | ★ | ⏳ 설치판 재확인 |
| CC-07 | Auto-Style·Seedance·아바타·보컬 제거 | ★★★ | 페이지 확인, 플랜 구분 ⏳ |

## Final Cut Pro
| ID | 주장 | 신뢰도 | 상태 |
|---|---|---|---|
| FCP-01 | 12.0: Transcript/Visual Search·Beat Detection | ★★★ | 확인 |
| FCP-02 | 12.3: Generate Captions(실리콘·미국영어)·Auto Mask·Match Color·Edit Detection·HEVC 프록시·백그라운드 렌더 기본 OFF | ★★★ | 확인 |
| FCP-03 | macOS 15.6+ 요구 | ★★★ | 확인(Q3 이슈) |
| FCP-04 | $299.99 일회성 + Creator Studio $12.99/mo·$129/yr(일부 콘텐츠 구독자 전용) | ★★★ | 확인 |
| FCP-05 | 필러 제거·번역·화자ID 없음, 생성 AI·협업 없음 | ★★ | 확인(N1-D 근거) |
| FCP-06 | 대형 라이브러리 열기 지연·렌더 팽창 불만 | ★ | 경향만 |

## 가격표 (국가·플랜·확인일 분리)

| 제품 | 국가/통화 | 플랜 | 가격 | 영구 라이선스 | 확인일 |
|---|---|---|---|---|---|
| FCP | US/USD | 일회성 | $299.99 | **있음** | 2026-08-22 |
| Creator Studio | US/USD | 월/연 | $12.99 / $129 | 없음 | 2026-08-22 |
| CapCut Pro | US/USD | 월/연 | $19.99 / $179.99(앱내 +$1~3) | 없음 | 2026-08-22(KR 등 재확인 ⏳) |
| YouTube Create | — | — | 무료·무광고·무워터마크 | — | 2026-08-22 |
| MovieCut | 미정(CA-07) | 일회성+유료 메이저 업데이트(**Q2 확정**) | **미정** | 있음(일회성) | 2026-08-22 |

## MovieCut 자체 주장 증명 상태

| ID | 주장 | 상태 |
|---|---|---|
| MC-01 | Mac 네트워크 차단(샌드박스) | ✅ 2026-08-22(entitlements 확인) |
| MC-02 | iOS 네트워크 미사용 | ✅ 2026-08-27 — ①코드감사(08-22) ②차단테스트: Mac sandbox-exec 네트워크 전면 거부 하 대표 작업(임포트→프리뷰→출력) 완주·sandboxd 위반 0건 ③캡처: iOS 시뮬레이터 전체 하니스 중 lsof 소켓 0개/36샘플(`run_ca01_offline_gate.sh`) |
| MC-03 | STT 온디바이스 강제·폴백 없음 | ✅ 2026-08-22(코드 확인) |
| MC-04 | 자막 언어·정확도 | **미측정 P0** |
| MC-05 | "보이는 대로 출력" | **확정 완료(2026-08-23, CA-02)** — 3등급 수치 VERIFICATION_STANDARD §2 기재(Exact=수치 동일 / Tolerance=MAD ≤ 2.0+1프레임 / Perceptual=블라인드 비열등) |
| MC-06 | 성능 우위(3제품 대비) | **미실행 P1**(§5 하니스) |
| MC-07 | 프리뷰=출력(Exact/Tolerance) | 내부 증거 있음(전 경로 커버 감사 필요) |

---

# Part 10 — 역량 매트릭스 (Capability Matrix, E·U·P·X·D)

> ● 확보(증거 있음) / ◐ 부분·미감사 / ○ 없음. iOS의 D는 G-27 완료 전 전항목 ○ 원칙. 경쟁 비교에는 S만 사용(현재 미출시).

## 편집 코어

| 기능 | Mac E·U·P·X·D | iOS E·U·P·X·D | 비고 |
|---|---|---|---|
| 트림/스플릿/리플 | ●●●●● | ●·◐·◐·◐·○ | iOS: Split·Ripple은 진입점 실동작(iOSContentView.swift:521·IOSInspectorSheet.swift:124·136 → 커맨드 디스패치)이 U=◐ 근거. 직접 트림은 미노출 — Trim 툴바 no-op(iOSContentView.swift:526) + 핸들 부재(타임라인 드래그=moveClip, IOSTimelineView.swift:173) |
| 슬립/슬라이드+셔틀 | ●●●●·◐ | ○ | Mac J/K/L·V/C/Y/U |
| 컴파운드(1레벨) | ●●●●·◐ | ◐·○·○·○·○ | |
| 조정 레이어 | ●●●●·◐ | ●·○·◐·◐·○ | b9d0e58 |
| 키프레임 | ●●●●·◐ | ●·●·◐·◐·○ | 그래프는 Mac |
| 마스크 6종 | ●●●●·◐ | ●·●·◐·◐·○ | |
| 램프·광학흐름 | ●●●●·◐ | ●·○·○·◐·○ | iOS UI 없음 |
| 역재생·정지 | ●●●●·◐ | ●·○·○·◐·○ | |

## 색·이미지

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| 기본 보정 | ●●●●·◐ | ●·●·◐·◐·○ | |
| 3-way 휠 | ●●●●·◐ | ●·◐·○·○·○ | iOS 심층 defer |
| 커브·HSL | ●●●●·◐ | ●·○·○·○·○ | |
| LUT | ●●●●·◐ | ◐·◐·◐·◐·○ | iOS legacy 병존 |
| 스코프 | ●●—·—·◐ | ○ | |
| 크로마키 | ●●●●·◐ | ●·●·◐·◐·○ | |
| 배경제거 | ●●●●·◐ | ●·◐·○·◐·○ | iOS preview 미표시 |
| 안정화 v1 | ●●●●·◐ | ●·○·◐·◐·○ | |
| 크롭 | ●●●●·◐ | ●·●·◐·◐·○ | |

## 자막·AI

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| STT+워드타이밍 | ●●●●·◐ | ●·●·◐·◐·○ | MC-04 미측정 |
| 스타일 6종+카라오케 | ●●●●·◐ | ◐·○·○·○·○ | |
| 오토컷 | ●●●●·◐ | ◐·◐·○·○·○ | |
| 하이라이트 | ●·◐·◐·◐·◐ | ◐ | UI 감사 필요 |
| 비트 감지 | ●●●●·◐ | ●·○·○·○·○ | |
| 리프레임·트래킹 | ●●●●·◐ | ◐ | |
| TTS | ●●●·◐·◐ | ◐·○·○·○·○ | |

## 오디오

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| 볼륨·페이드·파형 | ●●●●·◐ | ●·●·◐·◐·○ | |
| EQ·덕킹·NR·보컬분리 | ●●●●·◐ | ●·○·○·○·○ | iOS 미배선 |
| G-25 믹싱(팬·미터·LUFS) | ●●●●·◐ | ○ | |
| G-26 프로세서·마스터체인 | ●●●●·◐ | ○ | |
| 보이스오버 | ●●●·●·◐ | ●·●·◐·◐·○ | |
| 음악·SFX 라이브러리 | ●●—·—·◐ | ●·●·—·—·○ | 라이선스 감사 전 확대 금지 |

## 출력·운영

| 기능 | Mac | iOS | 비고 |
|---|---|---|---|
| 코덱·비트레이트·챕터 | ●●●●·◐ | ○ | iOS `.mov` 단일 |
| 소셜 프리셋·GIF·스틸 | ●●●●·◐ | ○ | |
| 프록시+thermal | ●●●·●·◐ | ○ | |
| autosave·복구 | ●●●·●·◐ | ●·○·○·○·○ | |
| schema 마이그레이션 | ●·—·—·—·● | ● | X축 부적용(마이그레이션은 export 경로 아님 — 2026-08-22 정의 정합성 확인). D=● 근거: Mac 재오픈 E2E(10분 fixture 열기 = decode+migrate+session swap, `run_latency_baseline` 게이트) · 실패 경로 감사 필요 |
| .mctemplate | ●●●·●·◐ | ◐ | |
| 브라우저(G-28) | ●●●·●·◐ | ○ | iOS 피커만 |

**미감사 영역(§4 전체):** 미디어 재연결·대량 임포트·외장 디스크·입력 포맷·오류/복구·접근성·현지화 — 감사 전 경쟁표 기입 금지(P0 ⑤⑥⑨).

---

## 출처

- **YouTube Create:** [공식 도움말 — 캡션(60초 제한 원문)](https://support.google.com/youtube/answer/13818789)·[오디오](https://support.google.com/youtube/answer/13521394)·[템플릿](https://support.google.com/youtube/answer/16399142)·[export](https://support.google.com/youtube/answer/13521602)·[Google Play](https://play.google.com/store/apps/details?id=com.google.android.apps.youtube.producer)·[App Store](https://apps.apple.com/us/app/youtube-create/id6476327393), [Primal Video 가이드](https://primalvideo.com/guides/youtube-create-app-complete-beginners-guide-iphone-android/), [AnyMP4 비교](https://www.anymp4.com/video-editing/capcut-vs-youtube-create.html)
- **FCP:** [Apple 릴리즈 노트](https://support.apple.com/en-us/102825)(12.0/12.2/12.3), [Apple FCP 제품 페이지(요구사항·가격)](https://www.apple.com/final-cut-pro/), [Apple Creator Studio 발표](https://www.apple.com/newsroom/2026/01/introducing-apple-creator-studio-an-inspiring-collection-of-creative-apps/), [ProVideo Coalition 12.3](https://www.provideocoalition.com/surprise-its-final-cut-pro-12-3/), [PCMag 리뷰](https://uk.pcmag.com/video-editing/19465/apple-final-cut-pro-x)
- **CapCut:** [공식 Color Matcher](https://www.capcut.com/tools/match-color-with-ai)·[AI Video Generator](https://www.capcut.com/tools/ai-video-generator), [BIGVU 요금제 재편](https://bigvu.tv/blog/capcut-free-vs-pro-what-2026s-restructure-actually-gives-you/), [CapCut Help — export](https://www.capcut.com/help/export-videos-in-capcut), [r/CapCut 품질 불만 스레드](https://www.reddit.com/r/CapCut/comments/1bpj1uv/capcut_export_quality_problem/)
- **Apple 개발자 문서:** [supportsOnDeviceRecognition](https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition), [macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox), [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- **내부:** DEVELOPMENT_DIRECTION_20260815, PLATFORM_PARITY_MATRIX, LOOP_STATE @HEAD, PERFORMANCE_SLO, git log 2026-08. 커뮤니티(★) 항목은 경향 관찰로만 사용(정량 비교 금지 — §5).
