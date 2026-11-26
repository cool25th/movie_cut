# AI 피드백 — 개발 방향 자문 (2026-09-21, 사용자 직접 질문 · 일회성)

> 원천: 사용자 지시로 `DIRECTION_PROMPT_20260921.md` 프롬프트를 ChatGPT(Pro 세션)에 전송해 수신한 응답 전문.
> 매일 새벽 4시 루프의 회차 산출물이 아님(FEEDBACK_20260921.md와 별개) — 문서화 규약은 동일하게 적용.
> 대화: chatgpt.com/c/6ab05386-6180-83ee-a152-e58cabad7d37

---

## 응답 전문

현재 상태라면 향후 3~6개월의 목표는 기능 경쟁이 아니라 "실사용자가 실제로 끝까지 편집을 완료한다"는 증명이어야 합니다. 기능·검증 인프라는 이미 베타에 충분히 가깝고, 지금 가장 큰 불확실성은 코드가 아니라 실기기 UX와 실제 사용자 행동입니다.

2026년 9월 기준으로 CapCut은 Desktop에서도 beat/speech/script 기반 Auto Cut을 제공하고 있고, Palmier Pro는 인앱 에이전트와 로컬 MCP로 타임라인 조작을 전면에 내세우고 있습니다. 따라서 AI 편집을 완전히 무시하는 것도 위험하지만, 이들과 같은 형태의 범용 AI 편집기를 지금 따라가는 것은 더 위험합니다.

### 권장 우선순위

| 우선순위 | 기간 | 핵심 목표 | 판단 |
|---|---|---|---|
| P0 | 지금~4주 | 실기기 베타 출시 가능 상태 | 반드시 |
| P1 | 1~2개월 | "쉽다"를 계측하는 베타 루프 | 반드시 |
| P2 | 2~3개월 | 대사 기반 편집 + iOS 기능 표면화 | 선택적 확장 1순위 |
| P3 | 3~5개월 | 제한된 Offline Editing Agent | 대응하되 작게 |
| P4 | 3~6개월 | 소수의 workflow preset 확장 | CapCut과 선택적 경쟁 |
| P5 | 베타 안정 후 | 경쟁사 블라인드 성능 비교 | 외부 주장 준비 |

### 1. P0 — 베타 전에는 실기기 위험만 닫고 출시

여기서 기능 동결을 풀지 않는 것이 중요합니다.

반드시 닫아야 하는 것은 사진/영상 임포트 실기기 결함 후보, 권한 상태별 Photos/Files import, 터치 편집 체감, 실제 오디오 라우팅, 발열·메모리 압박 상태의 5~20분 프로젝트, background→foreground 복귀, autosave/crash recovery, 최종 export/share입니다.

현재 1/3 실기기 검증이라면 베타 게이트를 이렇게 정의하는 것을 권합니다.

최저 지원급 / 중간급 / 최신급 3개 실기기 × 대표 workflow 3개 이상 = Blocker 0

특히 아래 기준을 넘으면 출시합니다.

| Beta Launch Gate | 기준 |
|---|---|
| Import 성공률 | ≥ 98% |
| 첫 프로젝트 Export 성공률 | ≥ 95% |
| 재실행 후 프로젝트 복구 | 100% |
| A/V sync critical defect | 0 |
| 편집 중 crash | < 1% session |
| Photos permission 상태별 dead-end | 0 |
| 20분 편집 후 thermal로 사용불가 | 0 |
| P0/P1 UI blocker | 0 |

반대로 EQ 전체 UI, 세밀한 덕킹 UI, noise-reduction 고급 UI, MP4 등 추가 container, 템플릿 확대, AI 기능은 모두 베타 후여도 됩니다.

다만 한 가지 예외가 있습니다. 현재 MovieCut의 장점으로 EQ/덕킹을 홍보하면서 iOS에서는 조작할 수 없다면 둘 중 하나를 해야 합니다. 전체 EQ 화면을 만들 필요는 없고, iOS에 Voice Enhance / Duck Background / Noise Reduce 정도의 단순 preset UI만 제공하거나, 베타 기간에는 해당 기능을 iOS 차별화 문구에서 제외하는 편이 낫습니다.

즉 P0의 원칙은 **"기능 추가가 아니라 약속과 실제 동작의 불일치 제거"**입니다.

### 2. P1 — 첫 출력 10분보다 중요한 것은 "도움 없이 끝냈는가"

첫 출력 ≤10분은 좋은 activation metric이지만 이것만 보면 사용자가 헤매면서도 9분 만에 겨우 끝낸 경우를 구분하지 못합니다.

MovieCut에서는 성공률 + 시간 + 마찰 + 주관적 난이도 네 축으로 보는 게 좋습니다.

가장 중요한 North Star 후보는:

**Unaided First Export Rate** — 처음 쓰는 사용자가 문서·개발자 도움 없이 import → edit → export를 완료한 비율. 초기 목표를 ≥80%, 안정화 목표를 ≥90% 정도로 잡겠습니다.

그리고 첫 출력은 평균보다 분포가 중요합니다. Median ≤ 10분과 함께 P80 ≤ 15분을 보세요. 10명 중 2~3명이 30분씩 헤매는데 평균만 좋아지는 상황을 막을 수 있습니다.

추가로 다음 정도면 충분합니다.

| Ease metric | 베타 목표 |
|---|---|
| Unaided First Export | ≥80%, 이후 ≥90% |
| First export median | ≤10분 |
| First export P80 | ≤15분 |
| 첫 import 성공 | ≥95% |
| 첫 export 성공 | ≥90% |
| Task SEQ(1~7) | ≥5.5 |
| "다음에 무엇을 해야 할지 알았다" | ≥80% |
| 동일 단계 3회 이상 반복/backtrack | <15% sessions |
| 오류 후 스스로 복구 | ≥90% |
| 7일 내 두 번째 프로젝트 시작 | ≥40% |

특히 마지막 지표가 중요합니다. 한 번 만들 수 있었다보다 다시 MovieCut을 선택했다가 훨씬 강한 신호입니다.

코호트는 너무 잘게 나누지 말고 네 축이면 충분합니다. 편집 숙련도는 처음 편집 / CapCut 사용자 / FCP·Premiere 사용자, 입력 소스는 iPhone only / 미러리스 포함, 작업 유형은 talking head / montage / composite·card / long-form, 사용 환경은 iOS-first / Mac-first / 둘 다로 나눕니다.

여기서 아주 중요한 점이 하나 있습니다. MovieCut의 완전 오프라인을 훼손하면서 analytics SDK를 넣을 필요가 없습니다. 제가 권하는 것은 **Local Beta Diagnostics**입니다.

앱은 네트워크를 계속 0으로 유지하고, media·파일명·대사 내용 없이 다음만 로컬 JSON로 기록합니다.

import_start → first_clip_on_timeline → first_edit → export_start → export_success

여기에 duration, error code, OS/device class만 붙입니다. 사용자가 TestFlight feedback 시 "진단 정보 첨부"를 선택하면 내보내도록 하면 됩니다. 그러면 기존의 socket capture 0이라는 제품 약속도 그대로 유지할 수 있습니다.

### 3. P2 — CapCut 격차에서 가장 먼저 닫을 것은 대사 기반 편집

승인 대기 목록 중에서는 이것이 압도적으로 먼저입니다. 이유는 MovieCut의 기존 자산과 가장 잘 맞기 때문입니다. 이미 온디바이스 STT와 caption이 있으므로 음성 인식 → 대사 검색 → 해당 구간 선택 → 삭제/유지를 연결하면 됩니다.

예를 들어: "이 부분 찾아줘", "여기부터 여기까지 삭제", "침묵 1초 이상 제거", "이 문장이 나오는 부분만 모아줘".

이것은 거대한 AI 기능처럼 보이지만 실제 제품 가치는 timeline navigation cost를 줄이는 것입니다. 측정 기준도 아주 명확합니다. 기존 timeline 방식 대비 talking-head 10분 소스를 편집할 때 목표: rough-cut 소요시간 30% 이상 감소. 그리고 transcript→timeline jump 정확도 ≥95%, edit 이후 undo/recovery 100%를 목표로 잡으면 됩니다.

이 기능은 다음 P3의 Agent 기반도 됩니다.

### 4. P3 — Palmier 대응은 해야 하지만 "Agent 제품"을 만들지는 마세요

Palmier Pro는 현재 앱 자체가 로컬 MCP를 노출하고 Claude/Codex/Cursor 또는 인앱 agent가 같은 프로젝트를 조작하도록 설계돼 있습니다. 최신 Palmier는 macOS 26/Apple Silicon을 요구하고, 생성형 AI 영역은 로그인/구독이 필요한 구조입니다.

따라서 MovieCut이 이를 그대로 따라갈 필요는 없습니다. 오히려 MovieCut에는 다음 형태가 더 적합합니다.

**Offline Editing Actions → Planner → Preview → Apply → Undo**

예를 들어 사용자가 "말 없는 부분을 줄이고 대사 사이 간격을 자연스럽게 만들어줘."라고 입력하면 AI가 직접 timeline을 자유롭게 조작하는 것이 아니라, DetectSilence → propose 17 cuts → preview → Apply 형태로 동작하게 합니다.

처음 허용할 action은 10~15개 정도면 충분합니다. findTranscript, selectRange, trim, delete, reorder, removeSilence, addCaption, applyAudioPreset, applyTransition, createRoughCut 등입니다.

핵심 설계는 **LLM이 타임라인을 직접 수정하지 않고 typed Action DSL을 생성하게 하는 것**입니다. 그러면 같은 Action DSL을 나중에 인앱 자연어 → Local Model 또는 Claude/Codex → Local MCP 둘 다에서 사용할 수 있습니다. 즉 Palmier에 대한 가장 좋은 대응은 MCP 기능 복제가 아니라 "agent-ready editing kernel" 구축입니다.

MVP 승격 조건은 다음 정도면 적절합니다. scripted command 100개 기준 action plan 유효성 ≥95%, 최종 timeline 의도 일치 ≥90%, destructive unrecoverable action 0, undo recovery 100%. 이 기준을 못 넘으면 UI에 Agent 버튼을 노출하지 않는 것이 좋습니다.

그리고 3~6개월 안에는 Generative Video, AI avatar, voice cloning 같은 AI 생성 영역은 들어가지 않는 것을 권합니다.

### 5. P4 — CapCut과 닫아야 하는 격차 / 닫지 말아야 하는 격차

CapCut은 2026년 현재 Auto Cut에서 beat sync, speech detection, script 기반 편집까지 이미 Desktop/Mobile에 제공하고 있습니다. 따라서 "AI 자동화가 전혀 없는 편집기"는 시간이 갈수록 불리합니다.

하지만 수백 개 template vs 수십 개 template 경쟁은 하지 않는 것이 맞습니다. MovieCut이 닫아야 할 것은 콘텐츠 수가 아니라 작업 완료까지의 단계 수입니다.

닫아야 함: 대사 기반 편집 → 3~5개 workflow preset → iOS audio preset UI → social export/share preset → 제한적 Auto Style.

예를 들어 템플릿을 300개 만드는 대신: Talking Head Clean / Product Reel / Beat Montage / Interview / Short Explainer — 이 5개를 정말 잘 만드는 쪽입니다.

반대로 영구 또는 장기 경쟁 불응으로 둬도 좋은 것은 대규모 필터/transition/template catalog, 상용 음악 marketplace, voice changer, cloud collaboration, social network, plugin ecosystem, multicam/Auditions/FCPXML/stem·surround 등입니다. 이것들은 MovieCut의 구매 이유를 강화하기보다 제품의 복잡도를 증가시킵니다.

Final Cut Pro는 현재 최소 macOS 15.6을 요구하므로, MovieCut의 macOS 14 지원 역시 실제 차별화 요소로 유지할 가치가 있습니다.

### 6. P5 — 경쟁사 블라인드 성능 비교는 베타 후가 맞습니다

단, 두 단계로 나눠야 합니다. 베타 전에는 내부 benchmark를 계속 돌립니다. 지금의 RTF, A/V sync, pixel parity, provenance harness는 regression gate로 유지합니다. 하지만 대외 비교용 CapCut/FCP blind benchmark는 베타 이후가 낫습니다.

왜냐하면 지금 가장 중요한 질문은 "MovieCut이 CapCut보다 12% 빠른가?"가 아니라 "사람이 MovieCut으로 영상을 실제로 완성할 수 있는가?"이기 때문입니다.

베타에서 실제 workflow가 나오면 어떤 benchmark를 해야 할지도 훨씬 명확해집니다. 예를 들어 베타 프로젝트의 70%가 talking-head + 4K iPhone source라면 그것을 primary corpus로 삼아야 합니다.

권장 시점은 베타 사용자 20~30명이 실제 export를 완료하고, 상위 3 workflow가 전체 usage의 60~70% 이상을 설명하는 시점입니다. 그때 CapCut/FCP/MovieCut을 동일 source와 가능한 한 동일 export 조건에서 비교하세요.

측정 대상은 export RTF, A/V sync, frame drop, output size, visual quality, color deviation, audio loudness/true peak, crash/failure rate 정도면 충분합니다. 그리고 지금 구축한 provenance 철학을 그대로 적용해서 competitor version + machine + settings + source hash + output hash를 고정하면 됩니다. 공개 성능 문구는 같은 조건에서 3회 이상 반복되어 재현된 결과만 사용하는 것을 권합니다.

### 로드맵 압축 + 제품 원칙

3~6개월을 한 줄 로드맵으로 압축하면:

1개월차: 실기기 3/3 + TestFlight → 2개월차: 첫 사용자 행동 계측·마찰 제거 → 3개월차: 대사 기반 편집 + iOS 기존 기능 표면화 → 4개월차: Offline Editing Actions/Agent MVP → 5개월차: workflow preset 3~5개 → 6개월차: 실제 베타 workflow 기반 CapCut/FCP 블라인드 벤치마크.

여기서 가장 중요한 제품 원칙 하나를 정한다면 저는 이것을 추천합니다.

MovieCut은 "기능이 많은 편집기"가 아니라, **"내 영상이 밖으로 나가지 않으면서 빠르고 정확하게 완성되는 편집기"**가 되어야 합니다.

그러면 CapCut의 콘텐츠 볼륨, FCP의 전문 기능, Palmier의 범용 Agent 어느 쪽도 정면으로 따라갈 필요가 없고, 오프라인 + 쉬운 완료 + 검증 가능한 출력이라는 세 축이 하나의 제품 전략으로 연결됩니다.

---

## 처분 요약 (세션 종합 — 등록 대기)

- **즉시 반영 가치(기존 문서와 무충돌)**: ①P0 실기기 게이트 수치화(Import ≥98%·첫 Export ≥95%·복구 100% 등 — G-27/QAUTO-05와 동일 방향, 수치 명시는 신규) ②Unaided First Export Rate + P80 분포 + "7일 내 두 번째 프로젝트" 지표(온보딩 메트릭 확장) ③Local Beta Diagnostics(오프라인 원칙 유지 계측 — 신규 제안)
- **사용자 승인 필요**: ④N1 대사 기반 편집 승인(P2 최우선 — 현재 '승인 대기(Q11)') ⑤iOS 오디오 preset UI 최소안(P0 예외) ⑥Offline Editing Actions/Action DSL(P3 — 신규 축)
- **기존 방향과 일치(변경 불요)**: 웹 비목표 유지, 콘텐츠 볼륨 경쟁 불응 유지, FCP 비목표 유지, 성능 대외 주장은 실측 후 보류 유지
