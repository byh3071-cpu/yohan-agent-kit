---
name: goal-cycle
description: >
  골 사이클 — Plan 모드에서 조사→스펙→설계→티켓나누기→(승인 후)만들기→검증→검수→PR올리기→머지판정
  순서로 진행. 트리거: "골 사이클", "개발 플로우", "조사부터 스펙", "혼자돌기", "다른눈돌리기",
  "확인턱", Scout/Spec/DoD를 우리 말로 통일할 때.
  /goal·overnight-autoloop·dump-gate와 역할이 다름 — SoT:
  C:\Users\Public\dev\.agents\DEV_FLOW_GLOSSARY.md.
---

# 골 사이클 (goal-cycle)

용어 SoT: [DEV_FLOW_GLOSSARY.md](file:///C:/Users/Public/dev/.agents/DEV_FLOW_GLOSSARY.md).

```
조사 → 스펙 → 설계 → 티켓나누기 → 만들기 → 검증 → 검수 → PR올리기 → 머지판정 → 지켜보기 → 다듬기
```

## 하드 게이트

1. 스펙·설계 **승인 전 만들기 금지**  
2. **검수 ≠ 만들기** (리뷰라고 하면 검수)  
3. **무인 머지 금지** (OSS 라벨 자동머지는 사람 켠 세션만)  
4. 성공 정의에 **악수 1줄**  
5. 가정 금지  
6. **PR·Plan·사람용 문서 = 한국어** (코드·커밋은 영어)  

## 크기판정 → 혼자 / 서브 / 다른눈

라우팅 선언 1줄 먼저: `라우팅: S|M|L — …`

| 판정 | 패턴 | 동작 |
|------|------|------|
| S | 혼자돌기 | Plan 또는 Agent. orca 금지 |
| M | 서브에이전트 | 탐색 cheap → 계획 → 구현 → 검수 |
| L | 다른눈돌리기 | Plan 승인 후 **`/goal`** + orca 워커 |

확인턱(애매·악수 누락·워커 on/off 불명): 「혼자돌까, 다른눈돌릴까?」

## 세션지휘자 · 한도 2층

- **세션지휘자** = 이 채팅을 연 CLI (sticky). 로스터기본(Claude/fable)은 새 세션·애매 시 권장일 뿐.  
- 층1 모델: fable→opus · sol→terra · grok→composer  
- 층2 CLI: claude→cursor→codex (agy=조사만). 종량 API 금지.  
- 세션 CLI 이전은 자동 불가 → 「X 한도 → Y에서 /goal 이어서」.  
- `% weekly limit` 사용량 표시만으로 우회 금지. 소진 미확정이면 멈춤.  
- 한도우회 자동 = `conductor wait-failover`만 (MaxAttempts≤2). S/M은 확인턱 안내.  
- wait exit 5 = NEED_CLI. 완료 = worker_done 메일만.

## 단계 (Plan = 1~4)

1. **조사** — 사실만. research-scout 금지.  
2. **스펙** — 무엇을/비범위/성공 정의/악수.  
3. **설계** — 구조·경계·리스크.  
4. **티켓나누기** — 파동>목표>티켓 → **승인**.  
5. **만들기** — 티켓 순.  
6. **검증** — CI·테스트 결정론.  
7. **검수** — 깨뜨려라. blocker면 만들기로.  
8. **품질확인** — 작으면 6+7에 흡수.  
9. **PR올리기** — 머지 안 함.  
10. **머지판정** — 사람.  
11–12. **지켜보기** · **다듬기**.

## 보고

```
단계: <우리 말>
상태: DONE | BLOCKED | 승인대기
성공 정의 진행: n/m
악수: 아직 / 증명됨
다음에: <한 줄>
```

## /goal

멀티벤더 워커 = `/goal` + conductor.ps1.  
완료 = worker_done **메일만**. preview = 한도우회 트리거만.
