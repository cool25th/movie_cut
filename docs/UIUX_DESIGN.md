# MovieCut UI/UX 디자인 시스템 및 인터랙션 규격 (UI/UX Specification)

> **버전:** 1.0 (2026-08-15)  
> **정체성:** Pro 다크 에디터 (Pro-grade Dark Creative NLE)  
> **디자인 원칙:** "CapCut의 빠른 직관성과 발견성 위에 전문가급 정보 밀도와 정밀 제어를 결합"

---

## 1. 4대 UI/UX 설계 원칙

| 원칙 | 정의 | 목표 기준 |
|---|---|---|
| **반응성 (Responsiveness)** | 사용자 입력 및 드래그 조작에 대한 즉각적 화면 반영 | 프리뷰 60fps 유지 (프레임 렌더 5.5ms), 슬라이더/트림 지연 체감 0 |
| **정보 밀도 (Density)** | 전문가가 필요로 하는 수치, 스코프, 컨트롤의 동시 가시성 | 주요 제어값 상시 노출, 다크 톤 계층으로 시각 피로 억제 |
| **발견성 (Discoverability)** | 기능 진입까지의 마우스 클릭 수 최소화 | 핵심 편집 도구 ≤ 2클릭 진입, 카드/레일 상시 가시화 |
| **접근성 (Accessibility)** | VoiceOver, 키보드 내비게이션, 색상 대비 | 모든 컨트롤에 영문 Key 기반 접근성 Label/Hint 완비, WCAG AA 충족 |

---

## 2. 정보 구조 (IA - Information Architecture)

```text
┌────────────────────────────────────────────────────────────────────────────┐
│ Top Chrome: [Home] [Undo/Redo]  Project Title  [Preview Qual] [Export (S5)]│
├─────────────────────┬───────────────────────────┬──────────────────────────┤
│ Media Library Panel │ Canvas & Player Area      │ Inspector Panel          │
│                     │                           │                          │
│ • Project Media     │ • 16:9 / 9:16 Canvas      │ • [Basic] Transform/Blend│
│ • Text Presets      │ • Safe Zone Guides        │ • [Effects] Mask/Chroma  │
│ • Audio / SFX       │ • Luma / RGB Scopes       │ • [Audio] Volume/Fade    │
│ • Transitions       │ • Timecode Transport      │ • [Vocal] Separate/Split │
│ • Cards / Filters   │                           │ • [Text] Font/Style/Sub  │
├─────────────────────┴───────────────────────────┴──────────────────────────┤
│ Multi-track Magnetic Timeline                                              │
│                                                                            │
│ [Tools: Select, Razor, Slip, Slide] [Snapping: On] [Zoom: ──●──] [Timecode] │
│ ────────────────────────────────────────────────────────────────────────── │
│ [Video 2 (Overlay / PIP)]                                                  │
│ [Video 1 (Main Magnetic Track)] [Transition Glyphs]                        │
│ [Audio 1 (Voiceover / Primary Sound)]                                      │
│ [Audio 2 (BGM / Sound Effects)]                                            │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. 디자인 토큰 시스템 (`MovieCutTheme`)

### 3.1 배경 및 표면 명도 (Dark Base Palette)
MovieCut은 깊이감을 과도한 보더 대신 **배경 명도차**로 표현합니다.
* **Canvas / Editor Base**: `#0F0F10` (최심부 배경)
* **Panel Surface**: `#17181A` (사이드바, 인스펙터, 라이브러리)
* **Raised Container**: `#202124` (카드, 툴바, 타임라인 레인)
* **Border Token**: `rgba(255, 255, 255, 0.08)` (최소한의 구조선, 보더 남발 금지)

### 3.2 액센트 & 상태 컬러
* **Primary Accent**: `#36D7FF` (시안 - 선택 영역, 플레이헤드, 주요 활성 상태)
* **Success / Ready**: `#30D158` (녹색 - Export 완료, 렌더 준비)
* **Warning / Degraded**: `#FFD60A` (노란색 - 열 강등 알림, 프록시 권장)
* **Danger / Delete**: `#FF453A` (빨간색 - 트랙 잠금 해제 필요, 삭제 경고)

### 3.3 타임라인 클립 타입별 색상
가독성을 높이고 시각적 피로를 줄이기 위해 **채도가 억제된 차분한 톤**을 사용합니다:
* **Video Clip**: `#1D3038` (다크 틸-그레이)
* **Audio Clip**: `#223329` (다크 올리브-그린)
* **Text / Subtitle Clip**: `#3A2B1F` (다크 앰버-브라운)
* **Sticker / Shape Clip**: `#382535` (다크 퍼플-그레이)
* **Compound Container**: `#2C2D35` (중첩 컨테이너 인디고-그레이)

---

## 4. 핵심 인터랙션 & 단축키 규격

### 4.1 타임라인 마우스 / 트랙패드 제스처
* **클립 선택**: 단일 클릭 (다중 선택: `Shift` + 클릭)
* **Slip 편집 (내용물 이동)**: `Option` + 클립 드래그 (타임라인 위치와 길이는 고정, 내부 소스 구간만 이동)
* **Slide 편집 (클립 이동 및 인접 조정)**: `Command` + 클립 드래그 (내부 소스는 고정, 타임라인 위치 이동 및 인접 클립 경계 자동 흡수)
* **타임라인 확대/축소**: `Command` + 트랙패드/마우스 휠 스크롤 또는 하단 줌 슬라이더
* **매그네틱 스냅**: 기본 활성화 (클립 경계, 플레이헤드, 비트 마커에 자석 정렬)

### 4.2 필수 키보드 단축키 맵
| 기능 | 단축키 | 설명 |
|---|---|---|
| **재생 / 일시정지** | `Space` | 플레이헤드 토글 |
| **클립 자르기 (Split)** | `Cmd + B` | 플레이헤드 위치에서 현재 선택 클립 분할 |
| **플레이헤드 기준 앞쪽 자르기** | `Q` | 클립 시작점부터 플레이헤드까지 즉시 트림 (Ripple Trim In) |
| **플레이헤드 기준 뒤쪽 자르기** | `W` | 플레이헤드부터 클립 끝점까지 즉시 트림 (Ripple Trim Out) |
| **일반 삭제 (Normal Delete)** | `Delete` | 선택 클립 삭제 및 빈 공간(Gap) 유지 |
| **밀어내기 삭제 (Ripple Delete)** | `Shift + Delete` | 선택 클립 삭제 및 후속 클립 당김 |
| **클립 복제 (Duplicate)** | `Cmd + D` | 선택 클립 복제 및 뒤에 삽입 |
| **실행 취소 / 다시 실행** | `Cmd + Z` / `Shift + Cmd + Z` | Undo / Redo |
| **마커 추가** | `M` | 타임라인 현재 위치에 마커 생성 |
| **1초 앞/뒤 이동** | `Shift + Left/Right` | 타임라인 정밀 탐색 |
| **클립 경계로 이동** | `Up / Down` | 이전/다음 클립 시작점으로 플레이헤드 점프 |
| **맨 앞 / 맨 뒤로 이동** | `Home / End` | 타임라인 시작 / 끝 이동 |
