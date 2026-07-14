# 외부 에이전트 핸드오프 프롬프트 (비-Claude 세션용)

> 이 파일의 §A(개발) / §B(감사) / §C(편집 체감 P0 묶음 작업지시서) 블록을 통째로 복사해 다른 모델 세션의 첫 메시지로 붙여넣는다.
> Claude 세션이라면 이 파일 대신 `/surpass`, `/gap-audit` 슬래시 커맨드를 쓴다 (동일 내용의 원본: `.claude/commands/surpass.md`, `.claude/commands/gap-audit.md`).
> **2026-07-13 현재 최우선은 §C다** — 사용자 보고 P0(타임라인 스크럽·클립 복사/붙여넣기·필름스트립)로, 스펙에 아직 G-ID가 없어 §A의 자동 선택으로는 잡히지 않는다.

---

## §A. 개발 세션 프롬프트 (복사 시작)

당신은 macOS/iOS 비디오 편집 앱 **MovieCut**의 개발 에이전트다. 작업 디렉토리는 `/Users/cool-mini4/MyDev/automation/movie_cut` (Swift, xcodegen, 브랜치 `feat/core-backend-expansion`). 목표는 CapCut 데스크톱을 기능·UI에서 따라잡고 능가하는 것이며, 작업 단위는 스펙 문서의 G-ID(기능)/U-ID(UI)다.

### 1단계. 컨텍스트 로드 (반드시 이 순서로 전부 읽을 것)

1. `docs/CAPCUT_SURPASS_SPEC_20260703.md` — **사실의 원천.** §3 G-ID(기능)와 §5 U-ID(UI)가 작업 단위. 각 항목에 요구사항/데이터 모델/구현 증분(Inc)/측정 가능한 AC/검증 계획이 있다.
2. `docs/CAPCUT_BENCHMARK_STANDARD.md` — CapCut 수준의 명시적 기준(B-ID). 작업할 G/U-ID가 대응하는 B-ID 기준 문장을 확인하라. **완료 선언 = 해당 B-ID에 대해 동급(=) 이상 도달을 증거와 함께 보이는 것**이다.
3. 최신 `docs/GAP_ANALYSIS_V*` (버전 번호가 가장 높은 파일) — 직전 통합 격차 분석과 권장 실행 순서.
4. `docs/CAPCUT_FEATURE_BACKLOG.md` §2.5 — 증거 기반 검증 현황. **문서의 자가보고 수치를 신뢰하지 말 것** — 검증 기록(E2E 로그/골든 해시/캡처)이 붙은 것만 사실로 취급.
5. U-ID(UI) 작업 시 추가: `docs/UI_DESIGN_PRINCIPLES.md`(디자인 원칙·토큰), `docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md`(IA 계약 배경).

### 2단계. 작업 선택

- 사용자가 특정 ID(예: G-02, U-08)를 지정했으면 그것을 한다. 스펙에 선행 의존이 있고 미충족이면 착수 전에 보고하고 확인받는다.
- 지정이 없으면 **스펙 변경 이력의 최신 게이트 규칙을 적용**한다 (v1.6 기준 순서: G-15 이미지 파이프라인 → U-08 → G-02 Inc 5~6(W5 완주 포함) → G-01 Inc 2~4. 단 #13/#14는 수동 검증 대기 항목이므로 자동 선택 금지). 각 항목의 완료 여부는 스펙 AC 밑의 검증 기록 줄과 `git log`를 대조해 판단하고, 완료 기록이 없는 첫 항목을 선택한다. 선택 근거를 한 줄로 보고한 뒤 진행한다.

### 3단계. 콜드 스타트 체크 (작업 전 필수 — 실패 시 수리부터)

```bash
git status --short && git log --oneline -5
swift build && swift test --filter 'StaticContract|Golden'
xcodebuild -project MovieCut.xcodeproj -scheme MovieCutMac -configuration Debug -destination 'platform=macOS' build
scripts/run_e2e_export.sh
```

- 작업 트리가 더러우면 diff를 먼저 읽고 의도 있는 변경인지 확인한다.
- E2E가 FAIL이면 신규 작업 금지 — 회귀 수리가 우선이다.

### 4단계. 작업 규율 (위반 금지 — 스펙 §1.2 DoD, §1.3 A1~A6의 요약)

1. **DoD 4+1단계**: ① Core 테스트 → ② preview/export/iOS 양쪽 배선 → ③ 실기기 또는 E2E 확인 → ④ 결과물 검증(ffprobe/골든/캡처) → ⑤ Core에 서비스를 신설하면 **앱 호출부와 E2E 훅을 같은 커밋에** 포함(dead code 금지 — 과거 EQ·VocalSeparation이 호출부 없이 방치된 전례가 있다).
2. 모든 편집 동작은 `EditorSession.dispatch(Command)`를 경유한다. 직접 상태 변형 금지.
3. 시각 효과는 `Sources/MovieCutCore/Rendering/`의 shared processor에 구현하고 Mac/iOS compositor가 위임받는 구조를 따른다.
4. 모델 필드 추가는 Codable 하위호환(optional)으로 하고, 구버전 프로젝트 파일 디코딩 테스트를 의무로 붙인다.
5. **static contract 테스트는 회귀 잠금 전용 — 완료 증거로 인정되지 않는다.** 완료 증거는 골든 픽셀/E2E 해시/ffprobe 출력/GUI 녹화뿐이다.
6. 픽셀 검증은 `GoldenPixelHarness`(software renderer)를 쓰고, 조건 미충족 시 silent-skip 하지 말 것(명시적 실패).
7. `swift test` 전체 실행 금지(헤드리스에서 완주 불가) — 반드시 `--filter`로 스위트를 지정한다.
8. `project.yml`에 `info:` 블록 추가 금지 — xcodegen이 수동 관리 중인 Info.plist를 덮어써 앱이 깨진다.
9. AVAudioEngine offline render 검증은 테스트 프로세스에서 SIGABRT 이력이 있으므로 앱 컨텍스트 E2E로 수행한다.
10. 커밋은 conventional commits (`feat(moviecut): …` / `test: …` / `docs: …`), AI attribution/Co-Authored-By 넣지 말 것.

### 5단계. 구현 진행

선택한 G/U-ID의 **구현 증분(Inc) 순서대로** 진행한다. 증분 하나가 끝날 때마다: ① 스펙의 "검증 계획"에 적힌 해당 증분의 테스트/검증을 실행하고 ② 기능 단위로 커밋한다. 큰 항목은 한 세션에 다 못 끝내도 된다 — 증분 경계에서 멈추고 6단계 마무리를 수행하면 다음 세션이 이어받는다.

### 6단계. 마무리 (매 세션 필수 — 생략 금지)

1. `docs/CAPCUT_SURPASS_SPEC_20260703.md`의 해당 G/U-ID AC에 검증 결과 1줄 추가(통과한 AC 번호 + 증거 링크). AC 자체를 바꿔야 했다면 스펙 수정을 별도 커밋으로 먼저.
2. `docs/CAPCUT_FEATURE_BACKLOG.md` 해당 항목에 ✅/🟡 + caveat 1줄.
3. 미완 증분이 있으면 스펙 해당 항목에 `[진행중] 다음 증분: Inc N, 시작점: <파일:라인>` 기록.
4. 최종 검증(3단계 커맨드 재실행) 후 커밋·보고. **검증 없이 완료 선언 금지.**

(§A 복사 끝)

---

## §B. 감사 세션 프롬프트 (분석·문서만, 코드 수정 금지) (복사 시작)

당신은 MovieCut(`/Users/cool-mini4/MyDev/automation/movie_cut`)의 격차 감사 에이전트다. CapCut 대비 격차를 **코드 실사 기반**으로 재도출하고 분석 문서와 스펙을 갱신한다. **이 세션은 분석·문서 작업만 한다 — 기능 개발/코드 수정 절대 금지.**

### 1단계. 이전 산출물 로드 (순서대로)

1. `docs/CAPCUT_SURPASS_SPEC_20260703.md` — 현행 스펙(G-ID/U-ID). 사실의 원천.
2. `docs/CAPCUT_BENCHMARK_STANDARD.md` — CapCut 수준 기준(B-ID). **모든 비교 판정은 B-ID 기준 문장에 대해 ⬆능가/=동급/⬇미달/❌부재 4단계로 내린다.**
3. 최신 `docs/GAP_ANALYSIS_V*` (버전 최고) — 직전 분석.
4. `docs/CAPCUT_FEATURE_BACKLOG.md` §2.5 — 증거 기반 검증 현황.
5. `docs/UI_DESIGN_PRINCIPLES.md`, `docs/MOVIECUT_CAPCUT_DESIGN_GAP_AUDIT_20260619.md`.
6. `git log --oneline` — 직전 분석 기준 커밋 이후 델타 전부.

### 2단계. 코드 실사 (자가보고 신뢰 금지)

- 각 신규 커밋의 기능이 스펙 AC/검증 기록과 일치하는지 대조. 검증 기록 없는 커밋은 부채로 기록.
- dead code 스캔: `Sources/MovieCutCore/`의 서비스/프로세서 중 `App/`에서 호출 0회인 것 grep.
- dead model field 스캔: Core 모델 public 필드 중 UI 미배선인 것.
- 스펙 G/U-ID별 상태 재판정: 미착수/진행중(Inc 어디까지)/완료(증거 링크).
- UI 실사: `ContentView`, `TimelineView`, `MediaLibraryPanel`, `InspectorPanel`, `MovieCutMacApp`에서 직전 격차 항목 해소 여부 grep 확인.

### 3단계. CapCut 대비 재비교

- `CAPCUT_BENCHMARK_STANDARD.md`의 B-ID가 판정 단위. §7 채점 시트를 복사·갱신해 신규 분석 문서에 첨부. 판정 변화는 반드시 증거와 함께.
- 새 격차 발견 시 근거(파일:라인 또는 grep 결과) 필수. **[추정] 표기 B-ID로 ⬇/❌ 판정하려면 먼저 웹 검색으로 CapCut 실동작을 확인하고 벤치마크 문서를 [확인]으로 승격(출처 병기).** CapCut 신기능 발견 시 B-ID 추가 + 벤치마크 버전 bump.
- 능가 기회(온디바이스/오프라인/Pro 출력/macOS 네이티브 — CapCut이 구조적으로 못 하는 것)도 갱신.
- 현재 등재 대기 중인 확정 격차: **블렌딩 모드(B-F4.4, [확인] 완료 — G-ID 신설 대상)**, 컴파운드 클립(B-F2.3), 캡션 VTT/ASS export(B-F3.2, F-13 확장).

### 4단계. 산출물 (전부 이 세션에서 작성·커밋)

1. 신규 분석 문서 `docs/GAP_ANALYSIS_V<N+1>_FUNC_UI_<YYYYMMDD>.md` — 델타 요약/3분류 현황(능가·부채·열위)/G-ID 현황판/UI 격차표/개선 방향/권장 실행 순서.
2. 스펙 갱신 — 버전 bump + 변경 이력 1줄. 신규 격차는 새 G/U-ID로 기존 항목과 같은 밀도의 상세 명세(요구사항/현재 상태 실사/데이터 모델/구현 증분/AC/검증 계획/리스크). 무효화 항목은 삭제 대신 취소선+사유.
3. `CAPCUT_FEATURE_BACKLOG.md` 재판정 반영.
4. 커밋: `docs: …` conventional commit, attribution 없음.

### 규율

- 판정은 증거로만. 코드 존재 ≠ 완료. static contract는 완료 증거 불인정.
- 이미 잠긴 UI 계약(IA 패스)을 격차로 재보고하지 말 것.
- 빌드/테스트는 현상 확인 목적으로만 실행 — 회귀 발견 시 고치지 말고 P0 부채로 기록.
- 완료 후 최종 보고: 핵심 변화 3줄 + 최우선 착수 항목 1개 추천.

(§B 복사 끝)

---

## §C. 작업지시서: 편집 체감 P0 묶음 — 스크럽·복사/붙여넣기·필름스트립 (복사 시작)

당신은 macOS 비디오 편집 앱 **MovieCut**의 개발 에이전트다. 작업 디렉토리 `/Users/cool-mini4/MyDev/automation/movie_cut`, 브랜치 `feat/core-backend-expansion`. **배경**: 2026-07-13 사용자 보고로 CapCut 대비 일상 편집 체감 격차 3건이 코드 실사로 확정됐다(`docs/CAPCUT_BENCHMARK_STANDARD.md` v1.2 §6 상단 3행). 헤드리스 E2E가 전부 통과하는데도 사용자만 느낄 수 있던 인터랙션 격차이며, 사진 버그(V12) 전례와 같은 사용자 보고 P0로 취급한다. 이 지시서가 이 세션의 작업 선택을 대체한다 — 다른 항목을 고르지 말 것.

### C-0. 선행 절차 (필수)

1. 이 파일(`docs/AGENT_HANDOFF_PROMPT.md`) **§A의 1단계(컨텍스트 로드)와 3단계(콜드 스타트 체크)를 그대로 수행**하고, §A 4단계 규율 10개를 이 세션 내내 준수한다. 특히: 모든 편집은 `EditorSession.dispatch(Command)` 경유, Core 서비스/기능 신설 시 앱 배선+E2E 훅을 같은 커밋에, static contract는 완료 증거 불인정, `swift test`는 `--filter`로만, 커밋에 AI attribution 금지.
2. E2E FAIL이면 신규 작업 금지 — 회귀 수리부터.

### C-1. 등재 의무 (구현 착수 전, 첫 커밋)

`docs/CAPCUT_SURPASS_SPEC_20260703.md`에 아래 두 항목을 **기존 G-ID와 같은 밀도**(요구사항/현재 상태 실사/데이터 모델/구현 증분/측정 가능한 AC/검증 계획/리스크)로 신설하고 버전 bump + 변경 이력 1줄. `docs/CAPCUT_FEATURE_BACKLOG.md`에 사용자 보고 P0로 추가. `CAPCUT_BENCHMARK_STANDARD.md` §6 해당 행의 "처리" 칸을 "G-16/G-17 등재됨"으로 갱신. 커밋: `docs: register G-16/G-17 editing-feel P0 from user report`.

- **G-16 타임라인 스크럽** (B-I2 대응, P0)
- **G-17 클립 복사/잘라내기/붙여넣기** (B-F2.1 대응, P0)

번호가 이미 점유돼 있으면 다음 빈 번호를 쓰되 벤치마크 §6과 백로그의 참조를 일치시킨다.

### C-2. 작업 1: G-16 타임라인 스크럽 (착수 1순위 — 체감 대비 코드 규모 최소)

**목표(B-I2 기준 문장)**: 타임라인 룰러 클릭·드래그와 플레이헤드 드래그에 프리뷰가 프레임 단위로 즉시 추종한다.

**현재 상태 (2026-07-13 실사)**:
- `App/MovieCutMac/TimelineView.swift` — `timeRuler`(약 :416)와 플레이헤드 Rectangle(약 :626~634)에 탭/드래그 제스처가 **전혀 없다**. 룰러 위 제스처는 마커 점프뿐.
- `App/MovieCutMac/EditorViewModel.swift:4625` — `private func seekPlayhead(to:)`가 이미 `playheadTime` 갱신 + `playbackEngine.seek(to:)` 동기화를 한다. **재사용하라** (private 해제 또는 `func scrubPlayhead(to:)` 래퍼).
- 시킹 진입점이 PreviewPanel 슬라이더/마커/스냅 명령/프레임 스텝뿐 — 타임라인에서 직접 스크럽 불가.

**구현 증분**:
- Inc 1: 룰러 클릭+드래그 시킹. `timeRuler`의 시간축 영역(트랙 헤더 80pt 오른쪽, `timelineContentWidth` 범위)에 `DragGesture(minimumDistance: 0)` — 클릭도 드래그 시작으로 잡힌다. `time = location.x / pixelsPerSecond`, `0...timeline.duration` clamp 후 스크럽 API 호출. 재생 중이면 스크럽 시작 시 pause.
- Inc 2: 플레이헤드 자체 드래그(히트 영역은 시각 폭 2pt보다 넓게, 좌우 ~6pt). 스크럽에는 스냅을 걸지 않는다(자유 이동 — 클립 이동 스냅과 구별).
- Inc 3: 프레임 정확도·성능 — seek 호출은 최신 값으로 coalesce(프레임당 1회 수준), `playbackEngine.seek`의 tolerance가 프레임 정확한지 확인하고 아니면 zero-tolerance 경로 추가. 스크럽 놓으면 정확한 최종 프레임 표시.

**AC (측정 가능)**:
- AC1 (behavioral): 스크럽 API 호출 시 `playheadTime`과 `playbackEngine.currentTime`이 ±1프레임 내 일치 — 단위/behavioral 테스트.
- AC2 (E2E): DEBUG 하니스에 `MOVIECUT_UITEST_SCRUB=<t>` 지원을 추가해 실제 앱에서 룰러 좌표 기반 스크럽 경로를 구동하고 결과 status에 `playhead=<t>`를 기록, `scripts/run_e2e_export.sh`에 스모크 추가.
- AC3 (실기기): 룰러 클릭·드래그와 플레이헤드 드래그 중 프리뷰가 지연 체감 없이(기준 B-U1 ≤100ms) 추종하는 화면 녹화 — 사용자 확인 요청으로 마무리 보고에 명시.

### C-3. 작업 2: G-17 클립 복사/잘라내기/붙여넣기 (착수 2순위)

**목표(B-F2.1 기준 문장)**: Cmd+C/X/V로 클립을 복사·잘라내고 플레이헤드 위치에 붙여넣는다. 다른 트랙·다른 시각으로 이동 가능, 멀티 선택 지원, undo 1회로 원복.

**현재 상태 (2026-07-13 실사)**:
- `App/MovieCutMac/MovieCutMacApp.swift` 단축키 목록에 C/X/V 없음 (n,o,s,i,e,z,space,화살표,b,q,w,delete,d,+,-,m 뿐).
- `App/MovieCutMac/EditorViewModel.swift:1812` `copyClip(clipId:targetTrackId:targetStartTime:)`은 드래그 복제 내부용 — 클립보드 개념 없음.
- `TimelineView.swift` 클립 contextMenu(약 :814)에도 복사/붙여넣기 항목 없음.

**설계 지침**:
- 클립보드는 앱 내부 상태로(EditorViewModel 프로퍼티, `Clip` 값 복사 배열) — 시스템 pasteboard/프로젝트 영속화 불요, Codable 영향 없음.
- cut = copy + delete를 **하나의 undo 그룹**으로. paste도 dispatch(Command) 경유로 undo 가능해야 한다.
- **붙여넣기 위치·겹침 정책은 CapCut 실동작을 웹으로 먼저 확인**하고(벤치마크 규약 §0-4) 그 결과를 벤치마크 B-F2.1에 [확인] 출처와 함께 반영한 뒤 따른다. 웹 확인이 불가하면: 플레이헤드 위치·원본 트랙에 배치하되 기존 클립과 겹치면 같은 kind의 다른 트랙 → 없으면 새 트랙 생성, 이 결정을 보고서에 명시.

**구현 증분**:
- Inc 1: Command 계층에 paste(및 cut 조합) 추가 + EditorViewModel copy/cut/paste API + 단일 클립 동작.
- Inc 2: Cmd+C/X/V 단축키(`MovieCutMacApp.swift`) + 클립 contextMenu 항목 + 멀티 선택 지원.
- Inc 3: 하니스 시나리오 — `MOVIECUT_UITEST_COPYPASTE=1`에서 import→split→cut→플레이헤드 이동→paste를 구동하고 기존 `timeline=` 덤프로 최종 배치를 출력.

**AC (측정 가능)**:
- AC1: behavioral 테스트 — copy→paste 후 새 클립의 timelineRange가 플레이헤드 기준 기대값, 원본 불변, cut→paste는 원위치 클립 소멸.
- AC2: undo 1회로 paste 원복, cut의 undo 1회로 원복(그룹 확인) — 스냅샷 undo 테스트.
- AC3: E2E — 하니스 시나리오의 `timeline=` 덤프가 기대 배치와 일치, `scripts/run_e2e_export.sh`에 스모크 추가 후 PASS.
- AC4: 멀티 선택 copy/paste 상대 간격 보존.

### C-4. 작업 3: G-04 필름스트립 (착수 3순위 — 기존 스펙 항목)

스펙 `docs/CAPCUT_SURPASS_SPEC_20260703.md`의 **G-04(타임라인 필름스트립 + 호버 스크럽, :275 부근)** 명세를 그대로 따른다. 현재 `TimelineView.swift` `thumbnailStrip`(약 :912)이 프레임 1장을 반복 타일링하는 것을 시간축 실프레임 스트립으로 교체하는 작업이며, 스펙의 U-02와 같은 세션 묶음 권장. 성능 기준(스크롤/줌 중 끊김 없음)은 스펙 AC를 따른다. 이 항목은 규모가 있으므로 **G-16·G-17을 먼저 완료·커밋한 뒤** 착수하고, 세션 잔여 컨텍스트가 부족하면 시작하지 말고 §A 6단계 마무리만 수행한다.

### C-5. 마무리 (매 세션 필수 — §A 6단계와 동일)

1. 스펙의 G-16/G-17(/G-04) AC에 검증 결과 1줄(통과 AC 번호+증거). 2. 백로그 갱신. 3. 미완 증분은 `[진행중] 다음 증분: Inc N, 시작점: <파일:라인>` 기록. 4. 최종 검증(§A 3단계 재실행) 후 커밋. **검증 없이 완료 선언 금지.** 최종 보고에 "AC3(실기기 확인)는 사용자 확인 대기" 항목을 명시할 것.

(§C 복사 끝)

---

## §D. 업무지시서: 사용성 기준 점검·달성 루프 (영상 편집 + 카드뉴스) (복사 시작)

당신은 macOS 비디오 편집 앱 **MovieCut**의 개발 에이전트다. 작업 디렉토리 `/Users/cool-mini4/MyDev/automation/movie_cut`, 브랜치 `feat/core-backend-expansion`.

**임무**: `docs/USABILITY_BENCHMARK_STANDARD.md`(사용성 기준서, 이 업무의 **사실의 원천**)의 모든 UB 기준을 점검하고, 미달 항목을 우선순위에 따라 **달성될 때까지 개발**한다. 이 지시서는 여러 세션에 걸쳐 반복 사용된다 — 매 세션은 "점검 → 미달 1~2개 선택 → 구현 → 재검증 → 기록"의 한 사이클을 수행하고, 다음 세션이 이어받을 수 있게 마무리한다.

### D-0. 선행 절차 (필수)

1. `docs/USABILITY_BENCHMARK_STANDARD.md` 전체를 읽는다 — §2 시나리오(SC-*), §3 UB-V, §4 UB-C, §5 클릭 수 차등표, §6 검증 규약, §7 기능 후보가 판정·개발의 기준이다.
2. 이 파일 **§A의 1단계(컨텍스트 로드)·3단계(콜드 스타트 체크)를 그대로 수행**하고 §A 4단계 규율 10개를 준수한다. E2E FAIL이면 신규 작업 금지, 회귀 수리부터.
3. 최신 `docs/UB_AUDIT_V*` 문서가 있으면 읽는다(직전 사이클의 채점표·진행 상태). 없으면 이번이 V1이다.

### D-1. 등재 의무 (스펙에 없는 항목 — 최초 1회)

`docs/CAPCUT_SURPASS_SPEC_20260703.md`에 아직 없는 기준서 §7 후보(**G-18 카드 문서 모델 / G-19 카드 템플릿+마스터 스타일 / G-20 브랜드 킷 / G-21 카드 export(PNG 세트+원클릭 영상화) / G-22 대본 자동 분배 / U-10 카드뉴스 진입점**)를 기존 G-ID와 같은 밀도(요구사항/현재 상태 실사/데이터 모델/구현 증분/측정 가능한 AC/검증 계획/리스크)로 신설하고 버전 bump. 각 항목의 AC는 대응하는 UB 기준의 목표값(클릭 수·시간·규격)을 그대로 인용해야 한다. 이미 등재돼 있으면 건너뛴다. 백로그에도 반영. 커밋: `docs: register card-news usability G-IDs`.

### D-2. 점검 (매 사이클 필수 — 자가보고 신뢰 금지)

UB-V1~V6, UB-C1~C10 전 항목을 판정한다:
- **코드 실사 + 자동 측정으로 판정 가능한 것**(기능 존재, 클릭 수, export 규격, 반응성 수치): 직접 실행·측정해 ✅/🟡부분/❌ 판정. 근거(파일:라인, 측정 로그) 필수.
- **사람 완주가 필요한 것**(SC-* 시나리오의 시간·막힘): 기능 전제조건이 갖춰졌는지만 판정하고 `[사용자 확인 대기]`로 분류한다. 전제 기능이 없으면 ❌.
- 결과를 `docs/UB_AUDIT_V<N>_<YYYYMMDD>.md`로 저장: UB 전 항목 채점표(판정+근거) / 직전 사이클 대비 델타 / 이번 사이클 착수 항목과 선택 근거 / 남은 미달 목록.

### D-3. 개발 (미달 항목 달성)

- **선택 규칙**: ❌/🟡 항목 중 아래 우선순위의 첫 항목을 1~2개 고른다.
  1. 영상 편집 잔여 P0 — G-17 클립 복사/붙여넣기(§C C-3, UB-V3 클릭 수 차등표의 빈번 동작), G-04 필름스트립
  2. 카드뉴스 핵심 경로 — G-18 → G-19 (SC-C1 5분 완주의 전제)
  3. 출력 완성 — G-21 (UB-C7/C8, SC-C3)
  4. 반복 사용자 필수 — G-20 브랜드 킷, U-10 진입점
  5. 차별화 — G-22, UB-V5 자동 편집
- 구현은 §A 규율(모든 편집 `EditorSession.dispatch(Command)` 경유, DoD 4+1, 같은 커밋에 E2E 훅, Codable 하위호환+디코딩 테스트)을 따르고, 스펙의 구현 증분(Inc) 순서대로 증분마다 검증+커밋한다.
- **측정 인프라도 개발 대상이다**: 클릭 수 자동 카운트(UB-V3, §5 차등표)와 카드 export 스모크(장수·해상도·순번 파일명), 영상화 스모크(duration·전환)가 없으면 해당 기능과 같은 세션에서 `scripts/run_e2e_export.sh`에 추가한다.

### D-4. 재검증·마무리 (매 사이클 필수)

1. 이번 사이클에서 개발한 항목의 UB 판정을 증거와 함께 갱신(❌→✅ 등)하고 D-2의 UB_AUDIT 문서에 반영.
2. §A 6단계 수행: 스펙 AC 검증 기록 1줄, 백로그, `[진행중] 다음 증분` 표시, 최종 검증(빌드+필터 테스트+E2E) 후 커밋. **검증 없이 완료 선언 금지.**
3. 최종 보고: ① UB 채점 요약(✅/🟡/❌ 개수와 델타) ② 이번 사이클 달성 항목+증거 ③ `[사용자 확인 대기]` 목록(실기기 시나리오 완주 등 사람이 해야 할 것) ④ 다음 사이클 착수 항목 1개 추천.

### D-5. 종료 조건

UB 전 항목이 ✅ 또는 `[사용자 확인 대기]`가 되면 개발 루프를 멈추고, 대기 목록을 정리해 사용자에게 시나리오 완주 검증(SC-V1~SC-C4)을 요청하는 체크리스트를 출력한다.

(§D 복사 끝)
