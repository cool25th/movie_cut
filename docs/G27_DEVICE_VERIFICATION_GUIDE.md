# G-27 실기기 검증 가이드 (1단계 마지막 게이트)

> 1단계의 마지막 미충족 조건은 **iOS 실기기 3종 통과**입니다(개발 계획 §4).
> 시뮬레이터 E2E·모든 자율 측정 창구는 이미 녹색입니다. 아래 절차대로 진행해 주세요.

## 무엇이 필요한가

3종(최소/중간/최신) 실제 iPhone. 현재 파악된 것:

| 세대 | 예시 | 상태 |
|---|---|---|
| 중간 | iPhone 13 Pro (페어링 이력 있음) | 연결 필요 |
| 최소 | 예: iPhone SE 2/3세대 | 확보 필요 |
| 최신 | 최신 세대 iPhone | 확보 필요 |

3종을 다 확보하기 어렵다면 **가진 것부터** 진행해 주세요 — 1종씩 결과가 쌓입니다.

## 사전 준비 (한 번만)

1. **Xcode 서명 계정**: Xcode → Settings → Accounts에서 Apple ID 추가(무료 Personal Team도 가능). 팀 ID를 확인합니다(Accounts에서 팀 선택 시 오른쪽에 표시, `XXXXXXXXXX` 형식).
2. **iPhone 개발자 모드**: 설정 → 개인정보 보호 및 보안 → 개발자 모드 켜기(기기 재시작 필요).
3. **신뢰**: 기기 연결 시 "이 컴퓨터를 신뢰" 승인.

## 실행 (기기마다 1회)

```bash
cd /Users/cool-mini4/MyDev/automation/movie_cut
xcrun devicectl list devices        # State가 'available'인지 확인
TEAM_ID=<위에서 확인한 팀 ID> bash scripts/run_g27_device_e2e.sh
```

- 기기 식별자를 명시하려면 마지막에 인자로 추가 (`...run_g27_device_e2e.sh <identifier>`).
- 스크립트가 하는 일: 앱 빌드·설치(서명) → 픽스처 업로드 → 1단계(임포트→프리뷰→출력→오디오 라우팅→저장) → 2단계(신규 프로세스 재오픈) → 시뮬레이터 게이트와 동일한 단언.
- 기대 출력 마지막 줄: `G-27 DEVICE E2E PASS (<identifier>)`

## 결과 보고

기기마다 위 스크립트 출력 전체를 그대로 알려주시면 됩니다(루프가 아티팩트로 정리·§4 표를 갱신합니다). 3종 PASS가 확인되면 **1단계(DONE_PHASE1) 선언**으로 이어집니다.

## 문제가 생기면

- `no CONNECTED device found` → 기기 연결·잠금 해제 후 `devicectl list devices`에서 available 확인.
- 서명/프로비저닝 오류 → Xcode에서 한 번 빌드(Cmd+R)해 보고 기기 신뢰 프롬프트 승인 후 재시도.
- 그 외 실패 → 출력 전체를 알려주세요 (결함으로 기록되고 수습 증분이 잡힙니다).
