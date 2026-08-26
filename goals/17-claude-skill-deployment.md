---
vhk_format: 1
type: goal
id: 17
title: Claude Code personal skill discovery 복구
status: IN_PROGRESS
priority: P0
size: L
execution_provider: orca-ready
automatic_fallback: false
started: 2026-08-26
---

# Goal 17: Claude Code personal skill discovery 복구

## 배경

Agent Kit `origin/main@e8717e2c2e55cf43b530db584a0f2b9d06f3d82a`의 manager는 Claude personal skill을 Windows Junction으로 배포한다. MOVA dogfood evidence `ea1a0422b93fc1115b82f677b1b33e320e153a3d`에서 Claude Code `2.1.246` fresh `--bare`는 설치된 `/agent-team-operations`를 발견하지 못했다. 기존 [Goal 8](8-two-machine-four-vendor-validation.md)의 교훈대로 filesystem `Healthy`와 vendor discovery receipt는 별도다.

관련 결정은 [Claude Code personal skill materialization ADR](../docs/decisions/2026-08-26-claude-personal-skill-materialization.md)이며 현재 `Accepted`다. repo-local 구현·fixture 회귀가 승인됐고, 실제 HomeRoot·Git delivery·유료 smoke는 후속 사람 게이트다.

## 현재 승인 범위

- 공식 Claude discovery 계약, manager·test·Goal 8·기존 audit 영향면 조사
- Proposed ADR과 구현 계획 작성
- 문서 링크, Goal schema, whitespace 정적 검증

## ADR 승인 뒤의 구현 범위

- Claude role을 봉인된 physical adapter로 materialize하는 manager contract 5
- transaction schema 3·4 Restore 호환성과 새 schema 5 migration·rollback
- matching canonical Junction의 identity-preserving migration
- deterministic provenance metadata, source/adapter drift fail-closed, PlanDigest 결합
- fixture HomeRoot의 Check→Install→Healthy→Restore와 전체 배포 회귀
- 실제 홈의 새 read-only Check·PlanDigest 승인 뒤 `agent-team-operations` canary migration
- repo/plugin shadow가 없는 fresh Claude `--bare` explicit discovery smoke

## 비범위

- Git 정본 또는 distribution manifest의 skill bytes 변경
- Agents·Codex·Cursor·Antigravity 배포 방식 변경
- Claude plugin namespace로 범용 skill 복제
- 승인 범위 밖 manager·test 구현
- 승인되지 않은 실제 홈 쓰기, 전역 설치·복원, 유료 smoke
- commit·push·PR Ready·merge·tag·publish·worktree 삭제

## Tasks

- [x] HARD_STOP·nearest rules·배포 계약·Goal 8·MOVA dogfood evidence를 read-only로 재실측한다.
- [x] 실제 대안과 transaction 호환성을 비교한 Proposed ADR을 작성한다.
- [x] red test부터 fresh smoke까지의 구현 계획을 작성한다.
- [x] 사람이 ADR을 `Accepted`로 승인한다.
- [x] failing regression을 먼저 추가하고 Claude materialization 최소 구현을 수행한다.
- [ ] 전체 회귀와 schema 3·4·5 Restore 호환성을 통과한다.
- [x] 격리 HomeRoot에서 install·rollback·restore를 검증한다.
- [ ] clean primary ref에서 실제 홈 migration의 새 Check와 PlanDigest를 만들고 사람이 승인한다.
- [ ] 승인된 canary Install 뒤 fresh Claude `--bare` smoke를 통과한다.
- [ ] 감사 영수증과 남은 rollout 위험을 기록하고 사람의 완료 판정을 기다린다.

## Completion Check

- [ ] `~/.claude/skills/agent-team-operations/SKILL.md`가 ordinary physical directory 아래에 있고 deterministic provenance·payload digest가 current canonical source와 일치한다.
- [ ] Agents와 AgyStandard canonical Junction은 변경되지 않는다.
- [ ] Check가 missing·matching Junction·healthy adapter·drifted adapter·unrelated reparse point를 각각 결정론적으로 판정한다.
- [ ] Install·Restore가 승인된 PlanDigest 없이는 HomeRoot를 변경하지 않는다.
- [ ] schema 3·4 BackupId가 기존 의미로 복원되고 schema 5가 보존 Junction의 target·NTFS identity를 rollback한다.
- [ ] stale source, metadata/payload drift, recreated Junction, interrupted activation이 fail-closed한다.
- [ ] manager full regression, Goal 1·8·15·17 gate, PowerShell parser, `git diff --check`가 통과한다.
- [ ] repo 밖 작업 디렉터리의 Claude Code fresh `--bare`에서 `/agent-team-operations`가 plugin·project shadow 없이 명시 호출된다.
- [ ] 실제 홈 변경의 Check JSON, approved PlanDigest, exact BackupId, post-Check, smoke transcript가 안정된 audit에 연결된다.

## 악수

입력은 clean tracked canonical source와 승인된 current PlanDigest이고, 출력은 그 source bytes를 봉인한 Claude personal physical adapter와 fresh-session discovery receipt다.

## Forbidden

- Proposed ADR을 구현 승인으로 간주
- schema 4의 Claude target 의미를 in-place로 바꾸어 과거 BackupId를 무효화
- existing Junction이나 physical directory를 recursive delete 또는 무조건 overwrite
- current Check와 다른 PlanDigest 재사용
- repo-local `.claude/skills`, `--add-dir`, `--plugin-dir`로 fresh personal discovery를 가짜 통과
- smoke 실패 뒤 유료 호출 반복 또는 무승인 Restore

## 사람 게이트

1. ADR Accepted
2. 구현 Plan 승인
3. Git 통합·merge
4. 실제 HomeRoot Check diff·새 PlanDigest와 Install 승인
5. 유료 fresh Claude smoke
6. smoke 실패 시 exact BackupId Restore 승인
7. PR Ready·배포·publish·Goal 완료 판정

## 구현 계획

[Goal 17 — Claude skill deployment 구현 계획](../docs/plans/goal-17-claude-skill-deployment.md)
