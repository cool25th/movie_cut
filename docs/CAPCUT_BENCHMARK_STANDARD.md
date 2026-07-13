# CapCut 벤치마크 기준서 (Benchmark Standard)

> 버전: 1.3 / 작성일: 2026-07-06 / 기준 대상: **CapCut 데스크톱(Mac/PC) 2026 버전**
> 변경 이력: v1.1 (2026-07-12) — [추정] 8건 웹 검증: 7건 [확인] 승격(F1.4·F2.4·F4.4·F5.3·F5.4·I3·I8), L4 탭명 부분 승격. F1.4는 CapCut 약점으로 판명(능가 기회로 재분류).
> 변경 이력: v1.2 (2026-07-13) — **사용자 보고 기반 격차 등재**: B-I2 타임라인 스크럽 판정 정정(코드 실사로 ❌ 확인), 클립 복사/붙여넣기 §6 신규 후보 추가(B-F2.1 기준 문장 보강).
> 변경 이력: v1.3 (2026-07-13) — 사용자 보고 P0를 스펙 **G-16 타임라인 스크럽 / G-17 클립 복사·잘라내기·붙여넣기**로 정식 등재하고 §6 처리 상태를 갱신.
> **목적: MovieCut 검증의 명시적 잣대.** "CapCut 수준"이라는 말을 관찰 가능한 문장으로 고정해, 모든 감사·검증 세션이 같은 기준으로 판정하게 한다.
> 신뢰도 표기 — **[확인]**: 웹 출처/실사용으로 확인됨. **[추정]**: 훈련 지식 기반, 판정에 사용 전 실제 CapCut 또는 웹으로 확인할 것.
> 무료 티어 기준. Pro 전용은 (Pro) 표시 — MovieCut은 해당 기능을 **무료·오프라인**으로 제공하는 것이 전략(차별화 축).

---

## 0. 사용법 (검증 세션 규약)

1. 각 B-ID에 대해 MovieCut을 4단계로 판정한다: **⬆ 능가 / = 동급 / ⬇ 미달 / ❌ 부재**. 판정에는 증거(E2E 로그·골든·캡처·실기기 녹화) 필수 — 코드 존재는 증거가 아니다.
2. `gap-audit` 세션은 §7 채점 시트를 갱신해 분석 문서(V*)에 첨부한다.
3. `/surpass` 작업의 완료 선언은 해당 G/U-ID가 참조하는 B-ID의 **= 이상** 도달을 의미해야 한다.
4. [추정] 항목으로 ⬇/❌ 판정을 내릴 때는 먼저 웹/실기기로 CapCut 실제 동작을 확인하고 본 문서를 [확인]으로 승격한다(출처 병기).
5. 이 문서의 기준 자체를 바꾸려면(예: CapCut 업데이트) 버전 bump + 변경 이력 1줄.

---

## 1. B-F 기능 수준 (Functions)

### B-F1. 미디어 입출력
| ID | CapCut 수준 (기준 문장) | 신뢰도 | MovieCut 검증 방법 |
|---|---|---|---|
| B-F1.1 | 비디오/사진/오디오/GIF를 드래그 또는 파일 선택으로 import하면 실패 없이 라이브러리에 즉시 나타난다 | [확인] | E2E import + 실기기 드래그 |
| B-F1.2 | **사진을 타임라인에 놓으면 즉시 재생·export 가능한 클립이 된다.** 기본 duration 3~5s, 설정에서 변경 가능, Duration 도구로 정확한 초 입력·일괄 적용 가능 | [확인] | G-15 E2E(프레임 색 실측) + 실기기 |
| B-F1.3 | 사진+비디오+오디오 혼합 타임라인이 제약 없이 재생·export된다 | [확인] | W-스모크 E2E |
| B-F1.4 | Photos 앱 직접 드래그: **CapCut은 불안정** — 비디오를 끌면 JPEG 썸네일로 들어오고, 내장 Photos 브라우저도 비디오 일부만 표시. 신뢰 경로는 파일 export 후 import | [확인] | 실기기 (G-12 #14) — **MovieCut이 제대로 수용하면 ⬆ 지점** |
| B-F1.5 | export: 해상도(≤4K)/fps(≤60)/비트레이트/코덱 선택, GIF export, 진행률+취소 | [확인] | ffprobe E2E |
| B-F1.6 | 플랫폼 규격 프리셋(9:16 등) 원클릭 | [확인] | ffprobe E2E (상환됨) |

### B-F2. 타임라인 편집
| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-F2.1 | split/trim/move/delete/ripple/duplicate + **클립 복사/붙여넣기(Ctrl+C/V, 트랙·시각 이동 가능)** — 프레임 정확, 즉시 반영 | [확인] | 기존 E2E+실기기 — **복사/붙여넣기는 MovieCut ❌**(단축키 미배선, Cmd+D duplicate만 존재. §6 참조) |
| B-F2.2 | 트랙 Hide/Lock/Mute 토글 | [확인] | 실기기 + contract |
| B-F2.3 | 컴파운드 클립(중첩)과 그룹으로 복잡한 타임라인 정리 | [확인] | 그룹=구현됨 / 컴파운드=MovieCut ❌(신규 후보) |
| B-F2.4 | 속도: 일반 배속 0.1x~100x(Keep pitch 옵션) + 커브 프리셋 6종(Bullet/Montage/Jump Cut/Hero Time/Flash In/Flash Out, 일부 프리미엄 커브 Pro) + Customized 커브, Smooth slow-mo(Frame Blending/Optical Flow), 역재생(체크박스), freeze(우클릭) | [확인] | speed E2E+실기기 |
| B-F2.5 | 키프레임: position/scale/opacity/rotation, 타임라인에서 직접 설정 | [확인] | 골든+실기기 |
| B-F2.6 | 단축키 체계(Ctrl+B split, Ctrl+G group 등) + 단축키 목록 제공 | [확인] | F-05 구현됨, 실기기 |

### B-F3. 텍스트·자막
| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-F3.1 | 자동 캡션: 55+ 언어, 정확도 ~92-95%(명료한 음성), 무료 티어 프로젝트당 10분 제한 | [확인] | STT E2E — **MovieCut은 무제한·온디바이스로 능가가 목표** |
| B-F3.2 | 캡션 편집기: 텍스트 수정/타이밍/블록 분할·병합/스타일 일괄, SRT·VTT·ASS export | [확인] | F-13 구현(SRT), VTT/ASS는 ❌ |
| B-F3.3 | **워드 단위 하이라이트(karaoke) 캡션 스타일 프리셋 다수** (고급 스타일 일부 Pro) | [확인] | G-01 — 현재 MovieCut ❌ |
| B-F3.4 | 텍스트 템플릿·타이틀 프리셋 수십 종 + 텍스트 애니메이션(in/out/loop) | [확인] | 14종+13종 E2E 상환됨 — 볼륨은 ⬇ |
| B-F3.5 | TTS 다수 보이스 | [확인] | TTS 구현, 보이스 품질 ⬇ 허용(온디바이스 트레이드) |

### B-F4. 색·효과
| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-F4.1 | 기본 보정(밝기/대비/채도/온도) + HSL + 커브 + LUT import | [확인] | 골든/E2E — 엔진 = 도달, **편집기 UI ⬇(G-02 Inc 5~6)** |
| B-F4.2 | 필터 프리셋 수십~수백 종, 강도 조절 | [확인] | MovieCut 볼륨 ⬇ (G-07) |
| B-F4.3 | 이펙트/전환 라이브러리 수백 종(트렌드 갱신) | [확인] | 전환 12종 = 코어, 볼륨 ⬇ — 전략상 큐레이션 20종+플러그인(G-07) |
| B-F4.4 | 크로마키/마스크/블렌딩 모드 — 블렌딩은 속성 패널 드롭다운, Multiply/Screen/Overlay/Soft Light 등 다수 모드 + 불투명도 병용 | [확인] | 크로마키·마스크 구현, 블렌딩 모드 MovieCut ❌(§6 확정 격차) |
| B-F4.5 | 스코프(파형/벡터/히스토그램) — **CapCut 없음** | [확인] | MovieCut ⬆ 유지 |
| B-F4.6 | ProRes/10-bit HDR export — **CapCut 없음(h264/HEVC 소비자 출력)** | [확인] | MovieCut ⬆ 유지 (E2E 상환) |

### B-F5. 오디오
| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-F5.1 | 상용 음악/SFX 라이브러리 내장(라이선스 주의 고지) | [확인] | MovieCut ⬇ (G-08 스타터 팩) |
| B-F5.2 | 오디오 분리(비디오에서 추출), 노이즈 제거, 보컬 분리, 보이스 체인저 | [확인] | 추출·NR 상환 / 보컬분리·보이스FX ❌(G-05) |
| B-F5.3 | 비트 감지 마커, 볼륨/페이드. 덕킹: 자동 덕킹은 버전에 따라 유무가 갈리고, 표준 경로는 **수동 볼륨 키프레임** | [확인] | 구현+E2E 상환 — MovieCut 자동 덕킹 구현 시 ⬆ 후보 |
| B-F5.4 | 실 EQ — **CapCut 데스크톱은 멀티밴드 EQ 부재**(v4.8 기준). 대신 loudness normalization/voice enhance/noise reduction/vocal isolation 제공 | [확인] | MovieCut 5밴드 DSP ⬆ 확정 |

### B-F6. AI 기능
| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-F6.1 | 배경 제거(2026 개선), auto reframe, **모션 트래킹**(얼굴/손/객체에 텍스트·그래픽 부착) — 클라우드 처리 | [확인] | MovieCut 온디바이스 구현 — 실영상 품질 판정 잔여(#11/#12) |
| B-F6.2 | AI Auto-Edit(2026): 원본 업로드+프롬프트 → 자동 컷/전환/음악 | [확인] | MovieCut = 자동컷+하이라이트+어시스턴트 1단계 — 통합 수준 ⬇, 단 오프라인 ⬆ |
| B-F6.3 | 리터치/뷰티 | [확인] | 전략상 최소 범위(G-13, 합의 대기) |
| B-F6.4 | 처리 방식: 클라우드 업로드 필요, 프라이버시 우려 상존 | [확인] | **MovieCut 온디바이스 = 구조적 ⬆** |

---

## 2. B-L 화면 구성 (Layout)

| ID | CapCut 수준 | 신뢰도 | MovieCut 현재 |
|---|---|---|---|
| B-L1 | **3패널 구조**: 좌상 미디어·에셋 패널(미디어/오디오/텍스트/스티커/필터/전환 탭) · 우상 속성 패널(맥락형) · 하단 멀티트랙 타임라인 | [확인] | = (IA 패스 완료, 잠금) |
| B-L2 | 홈 화면: 프로젝트 목록(썸네일)·새 프로젝트·템플릿 진입 | [확인] | ❌ (U-01) |
| B-L3 | 에셋 패널이 즉시 사용 가능한 **콘텐츠 그리드**(썸네일 카드, 검색, 카테고리) | [확인] | 🟡 부분 (U-07) |
| B-L4 | 속성 패널: 선택 대상에 따라 전환. 비디오 선택 시 Basic/Speed/Cutout(크로마키·마스크)/Audio 탭은 개별 [확인], 전체 탭 목록·순서는 [추정] | [확인](전체 탭 구성만 [추정]) | = 구조 도달, 탭 리듬 폴리시 잔여 |
| B-L5 | 타임라인 툴바: split/delete/마커/스냅/줌 등이 타임라인에 밀착 | [확인] | = (UX-05) |
| B-L6 | Export가 우상단 단일 주 액션 | [확인] | = |
| B-L7 | 클립 표면: 비디오=필름스트립, 오디오=파형, 사진=이미지, 전환=클립 사이 아이콘, 적용 효과 표시 | [확인] | ⬇ 파형만 = (G-04·U-02) |

## 3. B-I 동작·인터랙션 (Interactions)

| ID | CapCut 수준 | 신뢰도 | 검증 |
|---|---|---|---|
| B-I1 | 드래그: 고스트 표시 → 스냅 가이드라인 → 드롭 즉시 배치. 실패는 시각 피드백 | [확인] | 실기기 — 타임라인 스냅=구현, 가이드라인 ⬇ |
| B-I2 | 스크럽: 룰러 클릭/플레이헤드 드래그에 프리뷰가 프레임 단위 즉시 추종 | [확인] | **❌ 판정 (2026-07-13 사용자 보고+코드 실사)**: `TimelineView.swift` 룰러·플레이헤드에 탭/드래그 시킹 제스처 0건. 시킹 수단이 PreviewPanel 슬라이더/마커/스냅 명령/프레임 스텝뿐 — 타임라인에서 직접 스크럽 불가. §6 참조 |
| B-I3 | 텍스트/캡션 더블클릭=즉시 편집(우클릭 → Edit Captions 대체 경로). 우클릭 메뉴 풍부: 설정 복사(변형·텍스트 스타일·조정 전부), Detach Audio, Sync video and audio, Freeze Frame, Select Leftward/Rightward | [확인] | 실기기 |
| B-I4 | 호버: 에셋 카드 호버 프리뷰, 클립 호버 정보 | [확인] | ⬇ (G-04 호버 스크럽) |
| B-I5 | 자동 저장 + 프로젝트 자동 복구 | [확인] | = 이상 (E2E 상환) |
| B-I6 | undo/redo 깊은 히스토리, 모든 편집 동작 커버 | [확인] | = (스냅샷 undo 무결성 검증) |
| B-I7 | Proxy Mode: Settings > Performance에서 활성화+해상도 선택(720p 권장), 생성 완료 시 클립에 Proxy 배지, export는 원본 사용 | [확인] | ⬇ 생성만 됨, 소비 미배선 (G-11) |
| B-I8 | 프리뷰 품질 선택: 프리뷰 우상단 메뉴 → Preview Quality → Performance Priority Mode(성능 우선) 또는 수동 해상도(360p/540p 등), export 품질 무영향 | [확인] | ❌ (G-11) |

## 4. B-U 사용성·성능·신뢰성 (Usability)

| ID | CapCut 수준 (측정 가능 기준) | 신뢰도 | 검증 |
|---|---|---|---|
| B-U1 | 조작→화면 반영 지연 체감 없음 (기준: 슬라이더 드래그 ≤100ms 반영) | [추정](수치는 자체 기준) | signpost 측정 |
| B-U2 | 1080p 타임라인 프리뷰 실시간 재생(≥30fps, 효과 적용 상태) | [추정] | 측정 (베이스라인 5.5ms/frame = 여유) |
| B-U3 | 기본 편집 완주에 튜토리얼 불필요 — trim/속도/자막/전환이 안내 없이 도달 가능 | [확인] | 클릭수 측정(U-08 AC③, 핵심 편집 ≤2클릭) |
| B-U4 | 빈 상태마다 다음 행동 안내(import CTA 등) | [확인] | = (P0/P1 폴리시) |
| B-U5 | 작업 피드백: 완료/실패가 눈에 띄는 알림으로 | [확인] | ⬇ 상태바 1줄 (U-04) |
| B-U6 | 다국어 UI(한국어 포함) | [확인] | ❌ (U-06) |
| B-U7 | 크래시 후 재실행 시 작업 복구 제안 | [확인] | = (E2E 상환) |
| B-U8 | 워터마크 없음·로그인: CapCut은 **로그인 필요+기능별 페이월**(캡션 10분 제한, Pro $7.99/월) | [확인] | **MovieCut ⬆ (로그인 불필요·무제한·오프라인)** |

## 5. 능가 목표선 (MovieCut이 = 가 아니라 ⬆로 가는 지점)

전략(로드맵 §2) 재확인: **B-F4.5/4.6(스코프·Pro출력), B-F6.4(온디바이스), B-U8(무료·오프라인)은 이미 ⬆ — 지킬 것.** B-F5.4(실 EQ)는 v1.1 검증으로 **⬆ 확정**(CapCut 데스크톱 멀티밴드 EQ 부재). 추가 ⬆ 후보: B-F3.1(무제한 온디바이스 캡션), B-F1.4(Photos 직접 드래그 — CapCut 불안정으로 확인, 네이티브 Mac 앱의 구조적 우위 지점), B-F5.3(자동 덕킹 — CapCut은 수동 키프레임이 표준), B-I5/6(신뢰성), FCPXML(G-10, CapCut 부재), 커맨드 팔레트(U-09, CapCut 부재).

## 6. 신규 격차 후보 (이 기준서 작성 중 식별 — 스펙 미등재)

| 항목 | CapCut | MovieCut | 처리 |
|---|---|---|---|
| **타임라인 스크럽(B-I2)** — 룰러 클릭 시킹 + 플레이헤드 드래그 | 있음 [확인] (핵심 편집 인터랙션) | ❌ — `TimelineView.swift` 룰러(§timeRuler)·플레이헤드 Rectangle에 제스처 없음. `seekPlayhead` 호출부는 마커/스냅/프레임스텝뿐 | **G-16 등재됨** — 사용자 보고 P0, 착수 1순위 |
| **클립 복사/붙여넣기(B-F2.1)** — Cmd+C/X/V, 플레이헤드 위치·다른 트랙에 붙여넣기 | 있음 [확인] | ❌ — `MovieCutMacApp.swift` 단축키에 C/X/V 미배선, `EditorViewModel.copyClip`은 드래그 복제 내부용 | **G-17 등재됨** — 사용자 보고 P0, G-16 다음 |
| 클립 필름스트립이 단일 썸네일 타일 반복 | 시간축 실프레임 필름스트립 [확인] | ⬇ — `TimelineView.thumbnailStrip`이 프레임 1장을 반복 타일링 | 기존 G-04 범위 — 사용자 보고로 체감 확인, 우선순위 상향 근거 |
| 컴파운드 클립(중첩 타임라인) | 있음 [확인] | ❌ | 다음 감사에서 G-ID 신설 검토 |
| 블렌딩 모드(screen/multiply 등) | 있음 [확인] (v1.1 웹 검증) | ❌ | **확정 격차 — 다음 감사에서 G-ID 신설** |
| 캡션 VTT/ASS export | 있음 [확인] | SRT만 | F-13 확장 소항목 |

## 7. 채점 시트 (감사 세션이 갱신)

> 최초 스냅샷은 2026-07-06 V12 시점 판정. 다음 gap-audit부터 이 표를 복사·갱신해 V* 문서에 첨부.

| 영역 | ⬆ | = | ⬇ | ❌ | 주요 ❌/⬇ |
|---|---|---|---|---|---|
| B-F1 미디어 | 1 (F1.5 ProRes 포함 시) | 4 | 1 (F1.2 duration 도구/실기기 잔여) | F1.4 | G-15 AC1~AC2 상환: 사진 단독 export + 사진→비디오 mixed export E2E 완료 |
| B-F2 타임라인 | — | 5 | 1 (F2.4 커브 프리셋 UI) | F2.3 컴파운드 | |
| B-F3 텍스트·자막 | 후보 F3.1 | 2 | 2 | **F3.3 워드 캡션** | |
| B-F4 색·효과 | **F4.5/F4.6** | 2 | F4.1(UI)/F4.2/F4.3 | F4.4 블렌딩 | |
| B-F5 오디오 | F5.4 | 2 | F5.1 | F5.2 일부(보컬분리) | |
| B-F6 AI | F6.4 | 1 | F6.2 | F6.3 | |
| B-L 화면 | — | 4 | 2 (L3/L7) | **L2 홈** | |
| B-I 동작 | — | 3 | 3 (I1/I4/I7) | I8 | |
| B-U 사용성 | **U8** | 3 | 2 (U3측정전/U5) | U6 현지화 | |

---

출처: [CapCut PC 공식](https://www.capcut.com/resource/pc-professional-video-editor), [BIGVU 리뷰 2026](https://bigvu.tv/blog/capcut-online-desktop-editor-review/), [Atomi CapCut PC 리뷰 2026](https://atomisystems.com/screencasting/capcut-pc-review-2026-is-free-video-editing-really-worth-your-time/), [캡션 가이드 2026](https://caption-x.com/blog/how-to-add-captions-capcut), [타임라인 가이드](https://filmora.wondershare.com/advanced-video-editing/capcut-timeline.html), [AI 기능 리뷰 2026](https://freeacademy.ai/blog/capcut-ai-features-complete-guide-review-2026), [이미지 duration 설정](https://www.quora.com/How-do-you-set-the-duration-in-Capcut)

v1.1 추가 출처: [속도 커브(Filmora)](https://filmora.wondershare.com/video-editing-tips/speed-ramp-capcut.html), [속도 커브 도구(rezaid)](https://rezaid.co.uk/using-capcut-desktop-video-editors-speed-curve-tool-for-simple-edits/), [블렌드 모드(CapCut 공식)](https://www.capcut.com/create/blend-modes-creative-video-photo-effects), [오버레이/블렌딩(BuddyX)](https://buddyxtheme.com/how-to-overlay-multiple-videos-in-capcut-desktop/), [프리뷰 성능 모드](https://www.nyongesasande.com/performance-priority-mode-in-capcut-a-guide/), [프록시/렉 해결(MiniTool)](https://moviemaker.minitool.com/news/capcut-lagging.html), [export 품질 공식 도움말](https://www.capcut.com/help/video-quality-change-after-exporting), [캡션 편집 공식 도움말](https://www.capcut.com/help/auto-captions-in-capcut), [데스크톱 팁(Kim Klassen)](https://www.kimklassen.com/blog/capcut-desktop-tips), [EQ 부재·오디오 도구(wishwonsystem)](https://wishwonsystem.com/archives/19), [Photos 드래그 문제(Apple Community)](https://discussions.apple.com/thread/255346153), [Photos 브라우저 제한(Apple Community)](https://discussions.apple.com/thread/255740567)
