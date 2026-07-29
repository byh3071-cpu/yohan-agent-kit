# goal-cycle — 대조·리서치 메모

## Agentic SDLC ↔ 골 사이클

| Agentic 패턴 (문헌·가이드 공통) | 골 사이클 |
|----------------------------------|-----------|
| Human orchestrates, agents execute | 요한=머지판정·스펙승인, AI=조사~PR |
| Work unit = minutes–hours | **티켓** |
| Builder ≠ Validator | 만들기 ≠ 검수 |
| Plan/quality gate before code | 스펙·설계 승인 전 만들기 금지 |
| Observe after ship | 지켜보기 · 다듬기 |

참고(외부, 2025–26 대조):
- TestQuality Agentic SDLC — builder–validator chain, acceptance 기준 독립 검증
- Port AI Builder — Plan Mode 승인 후 실행 (사람 게이트)
- smarzban/agent-sdlc — idea→AC→arch→atomic plan→gate→test-first build→PR
- richard-devbot/SDLC-rstack — Orchestrator / Builder / Validator 샌드박스 분리
- Cursor Plan Mode — 만들기 전 조사~티켓나누기

## 생태계 매핑

| 요한 도구 | 골 사이클 역할 |
|-----------|----------------|
| dump-gate / thought-to-prompt | 사이클 **전** 생각→지시문 |
| Plan 모드 + goal-cycle | 조사~티켓나누기 |
| /goal + orca conductor | 멀티벤더 만들기·검수 |
| vhk-auto | 만들기(커밋만) |
| overnight-vhk-auto + auto_pr | PR올리기 |
| overnight-autoloop | **사용 금지**(다른 트랙) |
| check-goal / CI | 검증 |
| cavecrew-reviewer / 다른 벤더 | 검수 |
| morning-merge-check | 머지판정 지원 |
| improvement-loop | 다듬기 |
| research-scout | 경쟁사만 — **조사(코드) 아님** |

## 이름 충돌 방지

- Scout(조사) ≠ research-scout  
- Plan(설계·합의 단계) ≠ “아무 계획 문서”  
- Verify(검증=CI) ≠ 검수(Review)  
- handoff(인계 쪽지) ≠ 티켓
