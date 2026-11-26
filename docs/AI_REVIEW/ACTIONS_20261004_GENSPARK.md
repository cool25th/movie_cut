# ACTIONS — 2026-10-04 (Genspark Claude Opus 5.5 외부 리뷰 처분)

사용자 요청으로 Genspark(Claude Opus 5.5)에 개발 상태 패키지(구조 실측·기능·출시·부채)를 문의 → 응답 5관점 수집(`GENSPARK_OPUS_REVIEW_20261004.md`). 모델은 코드 미열람·요약만 판단했음을 명시 — 아래 처분은 코드베이스 실상과 대조한 결과. 신규 실행 항목은 **CA-34~CA-40** 등록.

| # | 피드백 | 처분 | 비고 |
|---|--------|------|------|
| 1 | [P0] 모든 타임라인 변경이 EditingActionApplier 단일 경로인지 확인 — 수동 편집 직접 mutation이면 undo 스택 두 갈래 | **ACCEPTED — CA-34 등록(감사 선행)** | EditorViewModel 분할(차기 리팩터 1순위)의 Stage 0 겸함. 실제로는 Command 패턴+`EditingActionBatchCommand` 존재 — "두 갈래 여부"는 미실증이므로 전수 감사로 판정 |
| 2 | [P1] EditorViewModel 분할 — 상태 소유권 경계 7종·Stage 0~4 순서·strangler·@Observable·PR 500줄·동결 2주 전 중단 | **ACCEPTED — 리뷰 문서에 전략 기록 + CA-34가 Stage 0 선행** | 2026-08-17 Inc2(타임라인 편집 클러스터 420줄 순수 이동·본체 −572줄)가 같은 방식의 선례 — private 공유 인프라 장벽 지도 존재 |
| 3 | [P1] 엔진 계층(ExportEngine·PlaybackEngine) Core 이동 — 플랫폼 차이 프로토콜 주입 | **근거 보강 — 기존 백로그(A4~A6·B3·B4 리팩터 잔분)와 동일 축** | iOS 24파일 확장 전 정착 필요성에 외부 의견 일치 |
| 4 | 매직 넘버 0.01×3 → 정수 tick(공배수 timescale) 통일·기본값(-40/0.35) Core 단일 정의 | **근거 보강 — OC-01(정수 틱/합리수 검토 — 1차 완료·핫패스 확장 잔여)+코드품질 2026-09 항목과 직접 연결** | Opus의 "프레임 경계 오차 누적" 근거가 OC-01 핫패스 확장의 우선순위 근거로 추가됨 |
| 5 | [P0] P3 장애 모드 계약 — 리비전 해시 낙관적 동시성·다중 액션 원자성·환각 ID 실존 검증·파괴적 플랜 diff 승인 | **ACCEPTED — CA-35 등록** | 원자성은 `EditingActionBatchCommand` all-or-nothing 기존 계약과 정합 확인 포함. 파괴적 플랜 게이트는 신규 |
| 6 | 온디바이스 후보 Apple Foundation Models(guided generation)·미지원 폴백 | **ACCEPTED — CA-36에 후보 등록** | 클라우드 LLM 시 5.1.2 고지는 CA-37에 연계 |
| 7 | [P2] MCP는 1.0 제외·1.1 스파이크(샌드박스 성립 미검증·iOS 사실상 불가) — App Intents를 먼저 | **ACCEPTED — CA-36 등록(정책)** | P3 증분 4 "MCP 우선 패스(사용자 결정 대기)"에 대한 외부 의견 입장 — 최종 결정은 사용자. App Intents 노출이 신규 실행 축 |
| 8 | [P0] 승격 측정 천장 효과 — held-out 세트·패러프레이즈/한영혼용·rule of three(3/80→상한 3.7%) | **ACCEPTED — CA-37 등록** | 2026-09-24 승격 측정(유효성 80/80·의도 100/100)의 통계적 변별력 한계 지적 — 타당 |
| 9 | [P1] semantic contract 속성 기반 확장(applyⁿ/undoⁿ 불변식·shrink) | **ACCEPTED — CA-37에 포함 등록** | QAUTO-06 seed torture(10시드×120스텝·C1~C3)가 부분 선행 — 불변식 명문화+shrinking이 증분 |
| 10 | [P1] 앱 계층 커버리지 공백(Core 1,509 테스트 vs Mac App 44k줄) | **CA-34 Stage 0 특성화 테스트와 동일 축 — 통합 처분** | |
| 11 | [P1] 미디어/환경 e2e 매트릭스(HDR·VFR·120/240fps·회전·장편 500클립·디스크 만료·iCloud placeholder·bookmark 재연결·인터럽션·thermal) | **ACCEPTED — CA-38 등록** | QAUTO-06 코퍼스(6종 호환)·잔여(ENOSPC 확대·active soak)와 연계·확장 형태 |
| 12 | [P2] 영상 프리뷰↔출력 동일 프레임 SSIM 계약(색공간·HDR 톤매핑·조정 레이어 순서) | **ACCEPTED — CA-38에 포함 등록** | 기존 MAD 파리티 시나리오(Mac↔iOS 축)와 축이 다름(프리뷰↔출력) — 상호보완 |
| 13 | [P2] 결정성·골든 운영(기기 간 Accelerate 차이 주의·CI OS 고정·재승인 절차)·성능 기준선 4종 CI 고정 | **부분 충족 — 지연 기준선 enforce는 verify_gate에 이미 통합. 첫 프레임·메모리·export 배속 확장은 CA-38 연계** | 기기 간 비트 동일성은 "동일 기기" 한정 주의타당 — 벤치마크 축과 함께 관리 |
| 14 | [P0] Universal Purchase 번들 ID 단일 레코드 확정(첫 업로드 후 불가역)·Team ID entitlement 매개변수화 | **ACCEPTED — CA-39 등록** | QAUTO-05 G5(Team ID 사용자 대기) 해제 직후 몰림 방지 선제 정리 |
| 15 | [P0] 프로젝트 파일 스키마 버전+마이그레이션 테스트 | **이미 충족 — QAUTO-02 완료(v1~v8→v9 round-trip·idempotent·truncate fail-closed·미래 버전 거부)** | 잔여 확인 1건: "모르는 필드 보존 정책"(unknown-field passthrough) — CA-39 아닌 QAUTO-02 후속 확인 사항으로 기록 |
| 16 | [P1] 심사 리드타임(계약·베타 심사·최신 SDK)·PrivacyInfo.xcprivacy·5.1.2 AI 고지·번들 에셋 라이선스 증빙·ITSAppUsesNonExemptEncryption | **ACCEPTED — CA-39 등록** | RELEASE_CHECKLIST와 연계 |
| 17 | 유료 선구매는 체험판 불가 — 무료 CapCut 대비 전환 불리 | **ACCEPTED — CA-07(지불의향→가격 확정)에 반영 노트** | 사업 판단 영역(모델도 팀 위임 명시) — 잠정 $29.99 회수 프로세스와 병행 검토 |
| 18 | [P2] 실기기 3종 구체화(최저사양 iPhone·iPad·Apple Silicon Mac+4K 발열·메모리·MetricKit) | **근거 보강 — G-27(QAUTO-05 G4)와 동일 축** | 발열·메모리 기록 항목 구체화 가치 |
| 19 | [P1] 벤치마크 — VMAF 병용·fixture 확장(어두운 장면·그레인 등)·작업 지표(대표 작업 완료 시간) 전환·분기 재측정 | **ACCEPTED — CA-40 등록** | OC-03·CA-12/32/33 후속. "작업 지표"는 W1~W5 대표 작업 축과 자연 정합 |
| 20 | 측정 범위 내 대외 메시지 고정 | **이미 정책 존재 — 경쟁 위치 판정 §1.6("3제품 최강" 금지·성능 대외 주장 보류)** | 외부 의견과 기존 계약 일치 확인 |

**등록 요약**: 신규 CA-34~CA-40(7건 — 변경 경로 감사·P3 장애 모드·AI 노출 정책·승격 변별력·e2e 매트릭스+SSIM·출시 심사 구조·벤치마크 축). 근거 보강 4건(엔진 Core 이동·정수 tick·실기기 구체화·대외 메시지). 이미 충족 3건(스키마 마이그레이션·지연 기준선·대외 메시지 정책). 사업 반영 1건(CA-07 노트).
