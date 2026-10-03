# Genspark(Claude Opus 5.5) 외부 리뷰 — 2026-10-04

> **출처**: Genspark AI Chat · 모델 **Claude Opus 5.5** (사용자 요청 "지금 현재 개발된 내용들을 genspark opus 5.5 에게 문의해서, 개선사항 도출해줄래?" → "개선사항 넣어줘")
> **방법**: ZCode 브라우저 자동화(bsk)로 사용자 로그인 세션에서 문의 — 입력 패키지는 구조 실측(Core 227파일/32k줄·Mac 79파일/44k줄·EditorViewModel 5,412줄·테스트 1,509/231·게이트 5/5)+주요 기능(액션 DSL·오디오 그래프·비디오 기능·CLI/MCP·벤치마크)+출시 상태+기술 부채.
> **수집 주의**: 응답은 접근성 트리 관측으로 수집(전문 대화는 Genspark 계정 AI Chat 히스트리 보존). 모델은 **코드를 직접 보지 않고 요약만으로 판단**했다고 명시함 — 아래 항목의 사실 관계는 본문 처분 표(`ACTIONS_20261004_GENSPARK.md`)에서 코드베이스 실상과 대조했음.
> **처분**: 신규 실행 항목은 `CAPCUT_FEATURE_BACKLOG.md` **CA-34~CA-40**으로 등록.

---

## 요청한 5관점

1. 아키텍처/리팩터링 — 특히 EditorViewModel 5,412줄 분할 전략(경계·순서·안전장치)
2. AI 편집 축 확장 — 플래너/MCP 인터페이스 도입 판단, 장애 모드 관리
3. 테스트/품질 전략 — 승격 측정·semantic contract·e2e 운영의 허점
4. 출시 체크리스트 리스크
5. 벤치마크/경쟁 대응

## 모델 요약 판정 (상위 5개)

1. **[P0]** Universal Purchase용 번들 ID와 App Store Connect 앱 레코드 구조를 먼저 확정 — 첫 업로드 이후에는 되돌릴 수 없음.
2. **[P0]** 모든 타임라인 변경이 `EditingActionApplier`를 거치는지 확인 — UI 수동 편집과 AI 편집의 변경 경로가 하나인지가 EditorViewModel 분할보다 먼저.
3. **[P0]** 프로젝트 파일 포맷에 스키마 버전과 마이그레이션 테스트를 1.0 전에 넣으라. *(→ 이미 QAUTO-02로 충족돼 있음 — 처분 표 참조)*
4. **[P1]** EditorViewModel 분할은 출시 전에 "동작 변경 없는 추출"까지만 하고, 출시 동결 2주 전에는 중단.
5. **[P1]** 승격 측정이 이미 만점이라 변별력이 없음 — held-out·적대적 시나리오 추가.

---

## 1. 아키텍처 / 리팩터링

### [P0] 변경 경로를 하나로 만들기 (분할의 전제조건)
- 근거: Action DSL은 10개 액션뿐인데 EditorViewModel은 5,412줄. 수동 편집(드래그 트림, 인스펙터 슬라이더 등) 상당수가 Action DSL을 거치지 않고 모델을 직접 바꿀 가능성(확인 필요). 그렇다면 undo 스택이 두 갈래가 되고, "AI가 한 편집과 손으로 한 편집이 섞인 상태에서 undo"가 가장 버그 나기 쉬운 지점이며 AI 편집 차별화 축의 신뢰성과 직결.
- 조치: EditorViewModel 안에서 모델을 직접 바꾸는 지점을 grep 등으로 전수 조사해 목록화. 각 지점을 typed action으로 승격하거나, 최소한 `EditingTransaction`으로 감싸 같은 undo 매니저를 쓰게 하기. 슬라이더처럼 연속으로 바뀌는 입력은 "begin/update/commit" 트랜잭션으로 묶어 undo 1회. 이 작업이 끝나면 VM 분할 경계가 "액션을 만드는 쪽"과 "상태를 관찰하는 쪽"으로 자연스럽게 갈림.

### [P1] EditorViewModel 분할 전략
- 경계: 기능이 아니라 **상태 소유권 기준**으로 자르기. 후보: `ProjectDocumentStore`(타임라인 모델·리비전·저장) / `SelectionState`(선택·포커스·플레이헤드) / `TransportController`(재생·스크럽·PlaybackEngine 연결) / `InspectorCoordinator`(선택 객체→파라미터 바인딩→액션 생성) / `MediaImportCoordinator` / `ExportCoordinator` / `AgentSession`(프롬프트·플랜·미리보기·적용).
- 순서(위험 낮은 것부터): Stage 0 특성화 테스트+성능 기준선 → Stage 1 순수 계산 로직(시간 변환·레이아웃·포맷팅) Core 이동(timelineMapping 중복 동시 정리) → Stage 2 의존 적은 말단 기능(Export·MediaImport·AgentSession) → Stage 3 Transport/Playback 분리 → Stage 4 Selection/Timeline(가장 얽혀서 마지막).
- 방식: 전 과정에서 EditorViewModel은 하위 객체로 위임만 하는 파사드로 남기는 **strangler** 방식. `ObservableObject`를 하위로 쪼개면 중첩 객체의 `objectWillChange`가 상위로 전파되지 않아 UI 갱신 회귀가 흔하니, 최소 OS가 macOS 14/iOS 17 이상이면 `@Observable`로 옮기면서 쪼개는 것 권장(프로퍼티 단위 추적으로 2k줄 PreviewPanel·TimelineView의 불필요한 body 재평가도 감소).
- 안전장치: VM 공개 상태를 스냅샷 직렬화해 특성화 테스트. PR당 diff ~500줄 이하, 이동과 수정 분리. 단계마다 e2e 5종+UI 골든+스크럽 fps·body 호출 횟수(signpost) 회귀 확인. Swift 6 strict concurrency 경고 수가 늘지 않게 하는 것도 게이트로.
- 출시 전에는 "동작 변경 없는 추출"까지만, 출시 동결 2주 전 중단.

### [P1] 엔진 계층을 앱에서 Core로 이동
- 근거: Mac App(44k줄)이 Core(32k줄)보다 큼. ExportEngine·PlaybackEngine은 UI가 아닌데 앱 계층. 이 상태로 iOS(24파일)를 키우면 덕킹/NR 125줄 중복이 엔진 규모로 반복됨.
- 조치: 엔진을 Core(별도 모듈)로 이동, 플랫폼별 차이는 프로토콜(디스플레이 링크·오디오 세션)로 주입.

### 매직 넘버 0.01×3 — 정수 tick 통일
- 근거: Double 초 단위 비교 정황이면 23.976/29.97fps·VFR 폰 영상에서 프레임 경계 오차가 누적돼 컷 위치가 1프레임 어긋날 수 있음.
- 조치: 정수 tick(예: 1/600 등 공배수 timescale) 통일. 파라미터 기본값(-40/0.35)은 Core에 `AudioProcessingDefaults` 같은 단일 정의로 두고 iOS/Mac 동일 값을 테스트로 고정.

### [P2] 영상 프리뷰↔출력 일치 검증
- 근거: 오디오는 null-test로 비트 단위 동일을 보장하는데, 영상은 ffmpeg 대비 PSNR만 확인.
- 조치: 프리뷰 렌더 경로와 익스포트 경로의 같은 프레임을 SSIM 임계값으로 비교하는 계약 테스트 추가(색공간·HDR 톤매핑·조정 레이어 합성 순서가 차이 나기 쉬움).

---

## 2. AI 편집 축

### [P0] 장애 모드 분류와 계약 정의 (현재 fail-closed 처리)
1. **리비전 불일치**: 플랜 생성 시점 리비전 N ≠ 적용 시점 N+1 — 플랜에 타임라인 리비전 해시를 넣고 불일치 시 거부/재계획하는 낙관적 동시성 제어.
2. **부분 실패**: 다중 액션 플랜 중 3번째 실패 — 전체 롤백 원자적 트랜잭션, undo도 1회.
3. **환각 ID**(LLM 도입 시): 액션 검증 단계에서 ID 실존 확인.
4. **파괴적 플랜**: 타임라인 30%+ 삭제·클립 N개+ 영향 플랜은 미리보기 diff+사용자 확인 강제.

### 온디바이스 LLM 후보 — Apple Foundation Models
- guided generation이 typed action 스키마와 잘 맞고, 오프라인·프라이버시 포지션과 일치. 단 Apple Intelligence 지원 기기에서만 동작하므로 미지원 기기용 대체 경로 필수. 클라우드 LLM을 쓰면 출시 체크리스트 4절의 개인정보 고지 항목 해당.
- 규칙 기반 로컬 플래너는 (환각이 없어) 현재 구조에서 유지 적합.

### [P2] MCP 도입 판단 — 1.0 제외, 1.1 스파이크
- 근거: 스토어 전용 배포의 샌드박스 제약. 외부 MCP 클라이언트가 stdio로 앱 번들 내 헬퍼 실행/로컬 소켓 접속 구조가 Mac App Store 샌드박스·심사 정책 안에서 성립하는지 미검증. iOS는 사실상 불가.
- 조치: 먼저 **App Intents**(Shortcuts·Spotlight·Apple Intelligence 연동)로 같은 typed action을 노출 — Apple 공식 경로, iOS/Mac 공통. MCP는 샌드박스에서 2~3일 스파이크로 확인 후 결정. 도입해도 첫 단계는 읽기+dry-run(플랜 반환만) 전용, 실제 적용은 앱 UI에서 사용자 확인 경유. 헤드리스 CLI는 스토어 전용 판매 모델과 충돌 가능성 — 배포 형태 명확화.
- 운영 지표 제안: opt-in 로컬 텔레메트리로 의도 분류 실패율·되묻기 비율·적용 후 60초 내 undo 비율.

---

## 3. 테스트 / 품질 전략

### [P0] 승격 측정의 천장 효과
- 근거: 80/80·100/100 만점은 변별력 없음. rule of three(n=80, 실패 0)로 95% 신뢰 실패율 상한은 ~3.7%. 시나리오를 개발팀이 직접 작성했다면 과적합 위험.
- 조치: 개발 중 열어보지 않는 **held-out 세트**. 같은 의도의 다른 표현(패러프레이즈)·한영 혼용 등 적대적 시나리오. 지표를 이분법에서 (부분 점수/등급으로) 확장.

### [P1] semantic contract를 속성 기반 테스트로 확장
- 무작위 액션 시퀀스 생성 → 불변식 검증: applyⁿ 후 undoⁿ = 원래 상태 / undo 후 redo = apply 직후 상태. 실패 시 최소 재현 시퀀스로 축소(shrinking)해 보고. 수동 시나리오 100개보다 엣지 케이스를 훨씬 많이 찾음.

### [P1] 앱 계층 커버리지 공백
- 1,509 테스트는 Core 대상. 44k줄 Mac App·특히 EditorViewModel은 e2e 5종과 UI 골든에만 의존할 가능성. 1절 Stage 0 특성화 테스트가 이 공백을 겸해서 메움.

### [P1] 현실적인 미디어 및 환경 매트릭스 (e2e 추가)
- 미디어: 4K HEVC 10bit HDR, iPhone VFR, 120/240fps, 회전 메타데이터 영상, 오디오 트랙 없는 영상.
- 규모: 60분 이상·클립 500개 이상 장편 프로젝트.
- 환경: 익스포트 중 디스크 가득 참, iCloud에 플레이스홀더만 있는 파일, 앱 재시작 후 security-scoped bookmark 미디어 재연결, 백그라운드 전환·전화 수신 오디오 인터럽션, 발열 성능 저하(thermal throttling).

### [P2] 결정성과 골든 테스트 운영
- 오디오 비트 단위 일치는 같은 기기·OS 기준일 가능성 — 기기 간/OS 간 비교에서 Accelerate 구현 차이로 깨질 수 있으니 주의. UI 골든은 CI 머신 OS·Xcode 버전 고정, OS 변경 시 일괄 재승인 절차.
- 성능 기준선 CI 고정: 첫 프레임까지 시간·스크럽 지연·익스포트 속도(실시간 대비 배수)·최대 메모리(XCTest metrics·signpost 활용).

---

## 4. 출시 체크리스트 리스크

### [P0] Universal Purchase 구조
- iOS와 Mac 앱이 같은 번들 ID로 하나의 앱 레코드로 묶여야 함. Mac 타깃이 별도 번들 ID로 개발됐다면 첫 업로드 전에 반드시 정리(이후 되돌릴 수 없음).
- Team ID 확정 시 App Group·iCloud 컨테이너·키체인 그룹 등 Team ID 접두사 entitlement 일괄 교체가 몰림 — 지금 미리 매개변수화.

### [P0] 프로젝트 파일 포워드 호환성
- 1.0 출시 후 포맷을 깨면 데이터 손실 사고. 스키마 버전 필드·버전별 마이그레이션 테스트(v1 픽스처→현재)·모르는 필드 보존 정책을 지금 정의.

### [P1] 계약·심사 리드타임
- Paid Applications 계약은 세금·은행 검증에 시간 — Team ID 나오는 즉시 착수. 외부 TestFlight에는 베타 심사 필요. 최신 Xcode/SDK 빌드 요구 확인.

### [P1] 개인정보·AI 심사 항목
- `PrivacyInfo.xcprivacy`: 디스크 여유 공간·파일 타임스탬프·UserDefaults 같은 항목 정리. 음성 전사 Speech 프레임워크 권한 문구(자체 모델이면 앱 용량·Background Assets 분리 다운로드 검토). 클라우드 LLM으로 사용자 데이터 전송 시 심사 가이드라인 5.1.2의 명시적 고지+동의. `ITSAppUsesNonExemptEncryption`. 번들 폰트·음원·이미지(템플릿·카드뉴스·카라오케) 상업적 재배포 라이선스 증빙 — 앱 리젝보다 출시 후 분쟁이 더 큰 리스크.

### 비즈니스 (사업 판단 영역 — 팀에 위임)
- 유료 선구매($29.99)는 체험판 제공 불가 구조. 무료 CapCut과 비교되는 상황에서 전환에 불리 — 대안 검토 가치.

### [P2] 실기기 검증 3종 구체화
- 지원하는 가장 오래된(메모리 최소) iPhone·iPad·최저 사양 Apple Silicon Mac(Intel 지원 시 +1). 각 기기 10분 4K 익스포트의 발열·메모리·소요 시간 기록. 크래시 수집은 Xcode Organizer+MetricKit 출시 첫날부터 준비.

---

## 5. 벤치마크 / 경쟁 대응

### [P1] 기술 지표에서 작업 지표로 전환
- 대표 작업 완료 시간(예: "이 트랜스크립션으로 쇼츠 자르기")을 정해 CapCut·FCP와 비교 — AI 에이전트 편집의 가치가 드러나는 지표.
- fixture 4개는 적음: 어두운 장면·빠른 움직임·그레인·HDR 추가. 사람 체감 화질과 상관 높은 **VMAF** 병용.
- 경쟁 제품은 업데이트가 잦으니 버전 고정(CapCut 8.9.0처럼)+분기 재측정 주기. 측정 결과가 받쳐주는 범위 안에서만 대외 메시지 고정.
