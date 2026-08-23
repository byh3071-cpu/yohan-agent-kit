---
vhk_format: 1
type: goal
id: 15
title: 범용 세션 감독·재시작 인수인계·런타임 사고 조사
status: IN_PROGRESS
priority: P0
size: L
execution_provider: native-approved
automatic_fallback: false
started: 2026-08-23
---

# Goal 15: 범용 세션 감독·재시작 인수인계·런타임 사고 조사

## 배경

장기 실행 세션에서는 작업 보고서, 런타임 완료 신호, 현재 coordinator, 전달 시도, 실제 수신 확인이 서로 다른 증거다. 이들을 한 상태로 취급하면 중복 writer, 성급한 완료, 원인 없는 장애 결론, 승인 게이트 우회가 생긴다. 디자인 세션에서 확인한 연속성 패턴을 범용 운영 계약으로 분리하되 디자인 고유 승인·취향·시각 영수증은 디자인 도메인에 남긴다.

## 범위

- `supervised-session-conductor`: 단일 대화 소유권, report ledger, 완료 신호 화해, 충돌 기록, 최종 단일 사람 게이트
- `restart-safe-handoff`: 재시작 가능한 최소 번들, attempt ledger, content/delivery 이중 영수증, 중복 writer·takeover 차단
- `runtime-incident-investigator`: App/Runtime/Terminal/Provider/Project 읽기 전용 계층, 시간선, 관측·추론·반증
- 세 스킬의 자동 라우팅 경계와 Codex UI 메타데이터
- 디자인 세션 연속성 계약과 범용 인수인계 계약의 양방향 링크
- 적대 fixture와 결정론 검증, 전체 manifest, registry/catalog 정합

## 비범위

- 특정 런타임 명령·버전·모델·벤더·프로젝트·PC 경로 고정
- 기존 runtime 또는 orchestration 결함 수정
- 사용자 홈 설치, 외부 provider 실호출, release, push, PR, merge, publish
- 디자인 전용 세션 연속성 문구의 복제·삭제

## Completion Check

- [ ] 세 스킬의 책임과 부정 호출 조건이 description과 본문에서 서로 충돌하지 않는다.
- [ ] 보고서와 `worker_done`은 독립 증거이며 어느 하나만으로 최종 완료를 주장하지 않는다.
- [ ] 살아 있는 coordinator는 takeover하지 않고 design-vs-QA 충돌은 한 번의 명시적 최종 사람 게이트로 올린다.
- [ ] handoff attempt는 receipt가 아니며 content와 delivery 영수증이 독립적으로 검증된다.
- [ ] 중복 writer와 불명확한 takeover가 fail-closed되고 단독 설치만으로 최소 handoff 계약을 이해할 수 있다.
- [ ] runtime 조사는 다섯 계층을 읽기 전용으로 분리하고 관측·추론·반증과 시간상 상관·인과를 구분한다.
- [ ] 디자인 세션 연속성 문서는 범용 handoff의 도메인 확장으로 양방향 연결되며 문구를 복제하지 않는다.
- [ ] 적대 fixture 5건, skill validator, manifest, registry/catalog, Goal 11–14 회귀, `git diff --check`가 통과한다.

## 악수

세 스킬이 같은 사건을 다뤄도 live 감독, 재시작 전달, 장애 원인 판단의 소유권과 완료 주장은 서로 대체되지 않는다.

## Forbidden

- 보고서만 있거나 완료 신호만 있는 상태를 최종 완료로 승격
- 살아 있는 coordinator 위에 새 writer를 세우거나 failed send를 근거 없이 반복
- 같은 시각의 두 오류를 공통 원인 증거 없이 인과로 연결
- live guide를 읽지 않고 특정 orchestration·terminal 명령을 추정·복제
- unrelated Goal 5·8·10 상태 변경
