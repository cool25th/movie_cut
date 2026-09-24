# MovieCut vs Palmier Pro — 상세 비교 (2026-09-24)

> 방법론: CapCut 비교(`CAPCUT_DETAILED_COMPARISON_20260923.md`)와 동일 규율
> (⬆/=/⬇/❌ + 근거). 차이: Palmier는 **소스가 공개돼 있어 코드 수준 조사**가 가능했다
> (GitHub API 트리·raw 파일 인출 — 2026-09-24). 단, **앱을 실행하지 않았으므로 런타임
> 검증 아님** — 정적 근거(파일명·도구 정의·README)와 실행 확인이 필요한 항목을 구분한다.
> 출처: [palmier-io/palmier-pro](https://github.com/palmier-io/palmier-pro)·
> [HN 런치(2026-07)](https://news.ycombinator.com)·저장소 내 LICENSE/BINARY_LICENSE/appcast.

## 1. Palmier Pro 현재 상태 (2026-09-24 확정 사실)

| 항목 | 사실 | 근거 |
|---|---|---|
| 정체 | YC 백킹·Swift 네이티브 macOS 편집기, "north star는 Premiere Pro" | README |
| **라이선스 전환** | v0.7.6·`last-gpl-source` 브랜치까지 **GPLv3** — 이후 바이너리는 **독점(소스 미공개)**·코드 기여 중단("no longer accepts code contributions") | README 원문 |
| 요구사항 | **macOS 26(Tahoe)·Apple Silicon 전용** | README FAQ |
| 활동 | 14.4k stars·1.1k forks·마지막 push 2026-09-23·appcast로 **근일 단위 릴리스**(2026-04~09 지속) | GitHub API·appcast.xml |
| MCP | 앱 실행 중 로컬 HTTP `127.0.0.1:19789/mcp` — Claude Code/Codex/Cursor/Claude Desktop 연결 + 인앱 에이전트 | README·`Agent/MCP/` |
| AI 생성 | Seedance·Kling·Nano Banana Pro를 타임라인 내 생성(클라우드) | README |
| 온디바이스 ML | `beat_this`(비트 감지)·`siglip2`(시맨틱 미디어 검색) 번들 | `models/` |
| 테스트 | **테스트 파일 219개 존재** — 품질 문화 인정(규모·커버리지 미검증) | GitHub 트리 |

**첫 번째 정정(2026-09-20 판정 갱신)**: 종전 "오픈소스 Mac AI 편집기" 서술은
현재 tense로 틀렸다 — 오픈소스는 **역사적 상태**(v0.7.6까지)이고 현재는 독점
바이너리 배포다. 경쟁 분석·메모리에 정정 반영.

## 2. 핵심 대결 축: 에이전트 편집 — Palmier ⬆ (구조적 선점, 판정 유지·강화)

`ToolDefinitions.swift`(1,436줄)에서 추출한 MCP 도구면 **~53종** — 카테고리:

- **타임라인 CRUD**: add/remove/move/split/insert_clips·set_clip_properties·
  set_keyframes·copy_clip_settings·manage_tracks·manage_markers·create_timeline
- **미디어**: import_media·get_media·search_media(**시맨틱 검색** — siglip2)·
  organize_media·inspect_media/timeline/color·capture_frame
- **텍스트·전사**: add_captions·add_texts·get_transcript(**전사 provider =
  cloud ∨ local — local는 언어 제한, cloud는 크레딧 소모** `captionCloudCreditCost`)·
  **remove_words**(대사 기반 삭제)·remove_silence·ripple_delete_ranges
- **색·효과**: apply_color(exposure/contrast/saturation/shadows/highlights/blacks·
  LUT)·apply_effect·apply_layout·**denoise_audio**
- **멀티캠**: manage_multicam·get_multicam·change_cam — **MovieCut은 명시적 비목표**
- **생성**: generate_video/image/audio(클라우드)·list_models
- **출력**: export_project — 모드 video/xml/**fcpxml(fcpxmlTarget: 'fcp'∨'resolve')**/
  palmier·코덱 파라미터(h264 기본)·manage_exports
- 메타: manage_skills/read_skill(에이전트 스킬)·send_feedback

**MovieCut 측 현황**: P3-01 `EditingActionDSL` 커널 v1(10액션·타입거부·validate —
**UI 노출 없음·적용기/플래너 바인딩 잔여**) + `AIEditingProvider`/`ClaudeEditingProvider`
368줄 미배선(2026-08 감사). **판정: 이 축은 Palmier 완승** — 도구 수(53 vs 커널 10)보다
본질적인 차이는 **실행 계층의 존재**(로컬 MCP 서버·인앱 에이전트·연결 레시피)다.
MovieCut의 유효 대응은 (a) N1(직접 UI 텍스트 편집 — 아래 §3) (b) P3 승격
(사전등록 기준: 플랜 유효성 ≥95%·의도 일치 ≥90%·파괴-복구불가 0·undo 100%).

## 3. 도메인별 상세

| 도메인 | Palmier (코드 기반) | MovieCut (실측/검증 기반) | 판정 |
|---|---|---|---|
| **에이전트/MCP** | MCP 53도구·인앱 에이전트·스킬 | P3 커널 v1 미노출·프로바이더 미배선 | **⬇ (선점당함 — 방어 불가 축)** |
| **텍스트 기반 편집** | remove_words·ripple_delete_ranges(에이전트 경유) | **N1 완결(2026-09-22)** — 코퍼스 검색 p95 4.78ms·문장/범위 삭제·keep-only·온디맨드 STT(직접 UI) | = (양측 보유 — 형태 상이: 에이전트 경유 vs 직접 UI·오프라인) |
| **자막/STT** | cloud∨local 전사·사이드카 파서(SubtitleFileParser)·클라우드 크레딧 | 온디바이스 강제·폴백 없음·무제한(로케일 조건)·스타일 6종+카라오케 | 프라이버시 ⬆ / 언어 범위·정확도는 양측 미측정(MC-04) |
| **AI 생성** | Seedance·Kling·Nano Banana(타임라인 내) | 명시적 비목표(오프라인 원칙) | ⬇ (범위 불응) |
| **색·이미지** | apply_color+LUT·ColorScopes·effect/layout | 3-way·커브·HSL 8밴드·LUT·스코프 3종·안정화 v1(골든/E2E) | =~⬆ (Palmier 런타임 미검증 — 보류 표기) |
| **오디오** | WaveformExtractor·denoise_audio·detect_beats — **EQ/덕킹/LUFS/보컬분리 파일 부재 관측**(파일명 grep 한계) | EQ 5밴드·컴프/리미터·LUFS(−0.02LU·드리프트 0)·자동 덕킹 램프·NR(G-25/26 E2E) | **⬆ (마스터링 체인 — 실행 확인 시 유효)** |
| **출력·교환** | export(h264 기반·codec 파라미터)·**FCPXML(fcp/resolve)**·XML | ProRes 422/4444·10bit HDR·1~200Mbps·챕터·소셜 프리셋(G-12 ffprobe) — **FCPXML 0건(G-10 미구현)** | 교환 ⬇(FCPXML) / 프로 출력 ⬆ |
| **멀티캠** | manage_multicam 3도구 | ❌ 비목표 확정 | ⬇ (양방향 인지 — MovieCut 포지션과 상충 없음) |
| **시맨틱 검색** | siglip2 임베딩 search_media | 키워드·자막 검색(N1·CA-20 인덱스) | ⬇ (기술 축 — 우선순위 낮음) |
| **플랫폼 도달** | macOS 26+·Apple Silicon 단일 | macOS 14+·**Mac+iOS 동시(Q14)**·Universal Purchase | **⬆** |
| **프라이버시·신뢰** | 클라우드 전사(크레딧)·클라우드 생성 상시 | 네트워크 entitlement 부재(실증 3종 MC-01/02/03)·계정 없음 | **⬆** |
| **라이선스·지속성** | 독점 바이너리 전환·기여 폐쇄·가격 미공개 | 일회성 구매·1.x 무료(Q17④)·로컬 파일 워크플로우 | ⬆ (구조 — 단 MovieCut 미출시) |
| **검증 문화** | 테스트 219파일(규모 인정) | verify_gate 5/5·골든 파리티 MAD≤2.0·19시나리오 상시 스윕·E2E | ⬆ (증명 체계 — 자기평가 한계 명시) |

## 4. 측정 축 — Palmier는 CapCut과 달리 **자동 측정 가능**

- 이 기기 호환: 측정 환경 = macOS 26.6.2·Apple M4(CA-12 conditions) — 요구사항 충족.
- **Palmier 자신의 MCP가 측정 하니스가 된다**: 앱 기동 → 로컬 HTTP MCP에
  JSON-RPC로 `import_media`→`add_clips`→`export_project`(h264·해상도 지정) →
  출력을 후보 규약에 적치. GUI 자동화·수동 키트 불필요(CapCut 대비 구조적 이점).
- 등록: `run_benchmark_candidates.sh --register palmier-pro` — 출력 규약
  `artifacts/ab_benchmark/candidates/palmier-pro/<fixture>.mp4`·동일 소스 참조
  pair 계약으로 MovieCut/ffmpeg-reference/CapCut과 같은 표에 슬롯인.
- 주의: 독점 바이너리 다운로드 필요·첫 실행 권한/로그인 상태 미확인·클라우드
  크레딧 불필요(패스스루 출력). 측정 시 라이선스는 로컬 평가 목적 사용 범위.

## 5. 정리

**Palmier가 이기는 축**: 에이전트 편집(MCP 53도구·구조적 선점 — 재논쟁 여지 없음) ·
FCPXML 교환(fcp/resolve) · 멀티캠 · AI 생성 통합 · 시맨틱 검색 · 릴리스 속도·커뮤니티(14.4k).

**MovieCut가 이기는 축(실증)**: 완전 오프라인(네트워크 부재 실증 vs 클라우드 전사·생성) ·
오디오 마스터링 체인(EQ/LUFS/덕킹 — 상대 부재 관측) · 플랫폼 도달(macOS 14+·iOS 동시) ·
프로 출력(ProRes/10bit) · 직접 UI 텍스트 편집(N1 — 에이전트 없이도 동작) ·
검증 문화(상시 파리티 스윕) · 일회성 라이선스 구조.

**보류**: Palmier 런타임 품질(출력 pair·RTF — §4 경로로 측정 시 확정) · 색·효과 실사용
품질·EQ 부재 관측의 실행 확인 · 양측 자막 정확도(MC-04) · 가격 정책 미공개.

**전략적 해석**: 두 제품은 같은 시장의 다른 변을 잡고 있다 — Palmier는
"에이전트가 편집하는 프레미어" , MovieCut는 "아무것도 올라가지 않는 정확한 편집기".
정면 충돌 축은 에이전트 편집 하나뿐이고, 그 축의 MovieCut 대응은 P3 승격(사전등록
기준 충족) 여부로 판정한다 — **선점을 뒤집으려 하지 않고, 검증된 서브셋+N1 직접
편집으로 응수**하는 것이 방향 문서(§1.6 사다리)와 정합적이다. CapCut과는 달리
Palmier는 측정 가능한 상대이므로, 품질 우위 주장은 §4 측정 후로 유보한다.
