# Local Beta Diagnostics — 설계 (2026-09-21)

> 원천: 사용자 직접 방향 자문(`AI_REVIEW/FEEDBACK_20260921_DIRECTION.md` P1) — "오프라인 약속을 훼손하지 않고 '쉬운지'를 계측"하는 베타 루프 설계.
> 상태: **설계 완료 — 구현은 승인 대기**(CA-30). 신규 앱 코드 추가이므로 루프 승인 규칙(제품 의미 변경 금지) 적용.
> 전제 계승: CA-25의 `OnboardingMetrics`(첫출력 ≤10분·Quick Tools 발견률, **로컬 전용**) — 본 설계는 그 확장이지 대체가 아니다.

## 1. 원칙 — 무엇을 하지 않는가

1. **네트워크 0 유지**: 어떤 analytics SDK도 부착하지 않는다. CA-01의 실측 계약(차단망 완주·iOS 소켓 캡처 0/36샘플)과 `PrivacyInfo.xcprivacy`(데이터 수집 없음)는 계속 유효해야 한다.
2. **PII·콘텐츠 미기록**: 미디어 파일명·경로·대사 전사·프로젝트 내용 일절 기록하지 않는다. 기록은 이벤트 종류·시각·duration·오류 코드·OS/device class로 한정한다.
3. **반출은 명시적 opt-in만**: 데이터는 사용자가 TestFlight 피드백에 "진단 정보 첨부"를 선택할 때만 나간다. 자동 업로드 경로는 만들지 않는다.
4. **기준값은 사전등록 + 변경 승인제**: 아래 수치는 2026-09-21 사전등록값이며, 변경은 CA-02(허용치 변경 승인제)와 동일 규율을 따른다.

## 2. 이벤트 모델 (로컬 JSON, 앱 컨테이너 내부)

`OnboardingMetrics`의 퍼널을 확장 — 이벤트 5종 + 컨텍스트 필드:

```
import_start → first_clip_on_timeline → first_edit → export_start → export_success/fail
```

- 각 이벤트: `{event, ts, session_id(랜덤 UUID), duration_ms, error_code?(있을 때만), os_version, device_class}` — device_class는 3단(최저 지원급/중간급/최신급, G-27 러너 분류와 동일 체계).
- `first_edit` 정의: 임포트 이후 첫 사용자 발동 편집 커맨드(trim/split/효과/자막/속도 — undo 스택 진입 기준, 자동 배치·자동저장 제외).
- 저장: 단일 append-only JSONL(회전 상한 예: 1MB) — 기존 autosave와 별개 파일, 크래시 복구 대상 아님(진단은 부수물).
- 테스트 하니스 실행 시 기록 스킵(기존 CA-25 UITest 억제 패턴 재사용 — 하니스 노이즈 방지).

## 3. 판정 지표 (베타 목표 — 사전등록)

North Star: **Unaided First Export Rate**(도움 없이 import→edit→export 완료 비율).

| 지표 | 베타 목표 | 산출 근거(이벤트) |
|---|---|---|
| Unaided First Export | ≥80% (안정화 ≥90%) | import_start…export_success 동일 session 완결 |
| 첫 출력 median / P80 | ≤10분 / ≤15분 | import_start→export_success 분포 |
| 첫 import 성공 | ≥95% | import_start→(실패 이벤트 없음) |
| 첫 export 성공 | ≥90% | export_start→export_success |
| 오류 후 자가 복구 | ≥90% | 오류 코드 후 동일 세션 재시도 성공 |
| 7일 내 두 번째 프로젝트 시작 | ≥40% | 신규 session의 import_start 재발 |
| 동일 단계 3회+ 반복/backtrack | <15% sessions | undo 스택 역방향 연쇄(프록시) |

- SEQ(1~7)·"다음에 무엇을 해야 할지 알았다" 같은 주관 지표는 `BETA_GUIDE.md` 정성 시트(기존 §5)로 측정 — 로컬 계측 대상 아님.
- 코호트 4축(자문 채택): 편집 숙련도(처음/CapCut 이용자/FCP·Premiere 이용자) × 입력 소스(iPhone only/미러리스 포함) × 작업 유형(talking head/montage/합성·카드/장편) × 환경(iOS-first/Mac-first/둘 다). 코호트는 진단 반출 시점의 설문(TestFlight 가이드에 4문항)으로만 태깅 — 앱 내 추론 금지.

## 4. Beta Launch Gate (P0 수치 기준 — RELEASE_CHECKLIST §5.1로 이관 등록)

실기기 3종(최저/중간/최신) × 대표 워크플로우 3종 이상에서 Blocker 0이 전제다. 그 위의 출시 판정 수치:

| 게이트 | 기준 |
|---|---|
| Import 성공률 | ≥98% |
| 첫 프로젝트 Export 성공률 | ≥95% |
| 재실행 후 프로젝트 복구 | 100% |
| A/V sync critical defect | 0 |
| 편집 중 crash | <1% session |
| Photos 권한 상태별 dead-end | 0 |
| 20분 편집 후 thermal 사용불가 | 0 |
| P0/P1 UI blocker | 0 |

- 측정 인프라(CA-30) 승인 전까지의 대리 판정: G-27 실기기 3종 러너 시나리오 Blocker 0 + `run_beta_scenarios.sh` 4/4 — 위 수치의 실측은 CA-30 구현 후 베타 세션에서 축적한다.
- **iOS 오디오 preset 최소안 연계**: 자문의 P0 예외(약속-실제 불일치 제거) — EQ/덕킹을 강점으로 내세우면서 iOS 조작이 없다면, ①최소 preset UI(Voice Enhance/Duck Background/Noise Reduce 3종) 또는 ②베타 기간 iOS 차별화 문구에서 제외 중 선택 필요(CA-31, 사용자).

## 5. 구현 범위 (승인 시 — CA-30)

- Core: 이벤트 열거형 + JSONL writer(기존 `OnboardingMetrics` 확장 또는 인접 신규 타입 — 구현 세부는 승인 증분에서 확정).
- 반출: 진단 JSONL을 임시 파일로 복사해 공유 시트(ShareLink)로 첨부 — TestFlight 피드백 흐름과 연동되는 최소 형태. 네트워크 API 부재.
- 검증: 유닛(이벤트 순서·PII 부재 단언 — 파일명/전사 문자열 미포함 스키마 고정)·하니스 스킵 게이트·오프라인 회귀(CA-01 게이트 재통과).
- DoD: 위 유닛 통과 + CA-01 오프라인 게이트 무회귀 + 카탈로그 키(en/ko) + 게이트 5/5.

## 6. 명시적 비목표

- 원격 분석·크래시 리포터 부착, 자동 업로드, 서버 집계 — 전부 안 함.
- 세션 녹화·입력 로깅·스크린샷 캡처 — 안 함.
- 마케팅 지표(DAU·리텐션 등) — 범위 밖. 본 진단은 베타 품질 판정 전용.
