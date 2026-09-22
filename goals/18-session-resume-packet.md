---
vhk_format: 1
type: goal
id: 18
title: P2 Session Resume packet과 교차 클라이언트 복구
status: IN_PROGRESS
priority: P0
size: L
execution_provider: native-approved
automatic_fallback: false
started: 2026-09-22
---

# Goal 18: P2 Session Resume packet과 교차 클라이언트 복구

## 배경

P1 task-scoped `get_context`는 yohan-mcp PR #84 merge `81ea431ccba4ee93c8836e882537506ec6bb82f1`과 실제 stdio MCP smoke로 완료됐다. 다음 단계는 세션·클라이언트·기기가 바뀌어도 대화 기억에 의존하지 않고 같은 저장소·Goal·SHA·근거·blocker·next action에서 안전하게 재개하는 것이다.

관련 실행 계약은 yohan-agent-kit #1과 Brain #227이다. 기존 `workflow:handoff`, `restart-safe-handoff`, Goal 15의 content/delivery receipt와 writer ownership 계약을 재사용한다.

## 범위

- `session-resume-packet/v1` schema와 정본 계약
- P1 `task-context/v1` 및 live Git/VHK 읽기 전용 상태에서 packet을 만드는 prepare 경로
- SHA·evidence hash·freshness·dirty state·active writer/epoch을 검증하는 verify 경로
- receiver·source ref·current gate·next action을 고정하는 acknowledge 경로
- workflow handoff full 절차와 packet CLI 연결
- stale/corrupt/conflict/secret/absolute-path 적대 fixture
- Claude 준비 경로에서 Codex 검증·ACK으로 이어지는 실제 로컬 교차 클라이언트 receipt
- 두 번째 기기가 없으면 `REAL_MACHINE_UNVERIFIED`를 명시하는 멀티머신 경계

## 비범위

- 새 MCP 서버 또는 Graph/Graphiti
- MOVA 자동 전달·재전송·재접속(P4 소유)
- Notion/Qdrant write, 사용자 홈 설치, 시크릿 저장
- 자동 writer takeover 또는 timeout만으로 ownership 변경
- 기존 Goal 5·8·10·17 상태 변경
- PR Ready·merge·tag·publish·배포

## Tasks

- [x] P1 완료 ref와 canonical runtime receipt를 고정한다.
- [x] 기존 handoff·restart-safe-handoff·Goal 15/16 계약과 열린 PR 중복을 조사한다.
- [x] packet schema·상태 전이·digest canonicalization을 구현한다.
- [x] prepare/verify/ack CLI와 결정론 fixture를 구현한다.
- [x] workflow handoff가 새 packet 경로와 fail-closed 규칙을 사용하게 연결한다.
- [x] P1 실제 Muse envelope를 packet으로 변환하고 새 프로세스에서 검증·ACK한다.
- [x] 전체 회귀·시크릿 검사·독립 검토를 통과한다.
- [x] 완료 receipt와 남은 실기기 한계를 기록하고 Draft PR을 만든다.

## Completion Check

- [x] 필수 필드 `repo + goal + SHA + evidence + blocker + next_action`과 schema version이 검증된다.
- [x] repo identity와 상대경로만 저장하고 대화 원문·시크릿·기기별 절대경로를 거부한다.
- [x] content receipt와 delivery receipt가 독립 상태이며 `sent`가 `acknowledged`로 자동 승격되지 않는다.
- [x] source SHA, evidence hash, dirty state, writer/epoch, freshness 불일치가 fail-closed한다.
- [x] stale·손상·중복 key·미등록 repo·active writer 충돌 fixture가 통과한다.
- [x] 실제 `Muse 이어서 해` packet이 `products/muse`와 P1 runtime/index/catalog lineage를 보존한다.
- [x] receiver가 owner scope, source ref, current gate, exact next action을 ACK한다.
- [x] 단일 기기 검증과 실제 멀티머신 검증 여부를 섞지 않는다.
- [x] Goal 15·16 회귀, Goal 18 gate, `git diff --check`, secret gate가 통과한다.

## 악수

입력은 정확한 P1 `task-context/v1` envelope와 같은 시점의 live repository state이고, 출력은 동일 source SHA·evidence hash·writer epoch·next gate를 새 프로세스가 검증하고 ACK한 `session-resume-packet/v1` receipt다.

## Forbidden

- 채팅 요약이나 전달 시도를 content/delivery ACK로 간주
- stale packet과 live state를 임의 병합
- absolute path·raw prompt·raw answer·token·credential 저장
- 살아 있는 writer 위에 새 writer 생성
- timeout·프로세스 종료·send 실패만으로 takeover
- 한 기기 fixture를 노트북→PC 실증으로 주장
- P2에 P4 자동 전달 또는 Graph 신규 구현 포함

## 사람 게이트

1. 신규 Goal 및 구현 Plan 승인 — 2026-09-22 사용자 승인 완료
2. Draft PR 이후 Ready·merge
3. 실제 사용자 홈 설치·두 번째 기기 검증이 필요할 경우 별도 승인
4. Goal 완료 판정

## 구현 계획

[P2 Session Resume 구현 계획](../docs/plans/p2-session-resume-implementation.md)
