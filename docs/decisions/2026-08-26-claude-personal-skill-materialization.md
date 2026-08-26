---
type: adr
title: Claude Code personal skill을 봉인된 physical copy로 배포
status: Accepted
date: 2026-08-26
owners:
  - Yohan Agent Kit
related_goal: ../../goals/17-claude-skill-deployment.md
---

# Claude Code personal skill materialization

- 상태: **Accepted**
- 결정 질문: Windows의 Claude Code personal skill을 Git 정본과 연결하면서도 fresh session에서 신뢰성 있게 발견되도록 어떤 형태로 배포할 것인가?
- 권고: Claude Code 대상은 정본 Junction 대신 provenance가 봉인된 ordinary physical directory로 materialize한다.
- 승인 경계: 사람은 대안 A와 transaction schema 5 구현 계획을 승인했다. 이 승인은 repo-local 구현·fixture 회귀에만 적용하며 실제 HomeRoot·Git delivery·유료 smoke는 각각의 후속 사람 게이트를 유지한다.

## 범위

이 결정은 [멀티벤더 배포 도구](../../scripts/Manage-MultivendorSkills.ps1)가 관리하는 `~/.claude/skills/<name>/` leaf의 materialization 방식, Check·Install·Restore transaction, PlanDigest, 이전 transaction 호환성, fresh Claude smoke에만 적용한다. Git 정본 `skills/<name>/`과 전체 파일 manifest, Agents·Codex·Cursor·Antigravity 경로, Claude plugin namespace는 바꾸지 않는다.

manager의 Claude 기본 정책은 모든 canonical skill에 동일하게 적용하되, 실제 사용자 홈 migration은 `-Skill` 선택 단위의 별도 Check·PlanDigest 승인으로 canary rollout할 수 있다. 첫 canary는 재현 결함의 대상인 `agent-team-operations`다.

## 확인된 사실

1. Agent Kit `origin/main@e8717e2c2e55cf43b530db584a0f2b9d06f3d82a`에서 `Get-TargetDefinitions`는 Claude를 `deploymentKind=Junction`으로 정의한다. 현재 contract 4 transaction은 Agents·Claude·AgyStandard에 canonical Junction을 만든다.
2. [배포 계약](../MULTIVENDOR_SKILL_DISTRIBUTION.md)은 `Healthy`를 path·manifest·transaction 정합으로 정의하며, [Goal 8 감사](../audits/multivendor-install-smoke-2026-07-30.md)는 파일시스템 `Healthy`가 vendor runtime discovery 성공을 뜻하지 않는다고 이미 기록했다.
3. MOVA dogfood evidence `ea1a0422b93fc1115b82f677b1b33e320e153a3d:docs/context/2026-08-26-agent-kit-promotion-handoff.md`에 따르면 Claude Code `2.1.246` fresh `--bare` 재시도는 model turn과 비용이 발생하기 전에 `Unknown command: /agent-team-operations`로 끝났다. 설치 leaf는 Node `Dirent`·`lstat`에서 directory가 아니라 symbolic-link 계열로 보이는 Windows Junction이었다.
4. Claude 공식 문서는 personal skill의 위치를 `~/.claude/skills/<skill-name>/SKILL.md`로 명시하고 `/skill-name` 호출을 설명한다. 같은 문서는 이 위치의 entry가 다른 디렉터리를 가리키는 directory symlink일 수 있다고도 명시한다. 확인일은 2026-08-26이다: [Extend Claude with skills](https://code.claude.com/docs/en/slash-commands#where-skills-live).
5. 현재 manager의 schema 4는 AGY CLI fallback에 봉인된 physical adapter를 이미 지원한다. source commit·manifest digest·adapter metadata를 deterministic digest에 묶고, staging directory를 검증한 뒤 `Directory.Move`로 활성화하며, drift와 stale PlanDigest를 fail-closed한다.
6. 현재 Restore는 transaction schema 3·4의 target definition을 다시 계산한다. 따라서 contract 4의 Claude 의미를 in-place로 Junction에서 Adapter로 바꾸면 이미 존재하는 schema 4 BackupId가 deployment binding mismatch로 복원 불가능해진다.

“Claude loader가 모든 Windows Junction을 무시한다” 또는 “`--bare`가 모든 personal skill을 끈다”는 아직 확정 사실이 아니다. 관측된 사실은 `2.1.246 --bare`에서 이 canonical Junction skill이 발견되지 않았다는 것이며, loader 원인은 추론으로 남긴다.

## 결정 동인과 제약

- fresh Claude에서 `/agent-team-operations`가 repo-local skill이나 plugin shadow 없이 발견되어야 한다.
- Git 정본과 배포 copy의 drift를 자동 덮어쓰지 않고 명시적으로 검출해야 한다.
- Check는 계속 read-only여야 하고, Install·Restore는 최신 PlanDigest와 사용자 홈 쓰기 승인 없이는 실행되지 않아야 한다.
- 기존 schema 3·4 BackupId와 seal 계산은 byte-compatible하게 복원 가능해야 한다.
- migration 실패 시 원래 Claude Junction을 되살릴 수 있어야 하며, 가능하면 원래 NTFS 객체 identity도 보존해야 한다.
- Windows primary 환경에서 관리자 권한이나 Developer Mode를 새 전제로 만들지 않아야 한다.
- 특정 PC 절대경로, 현재 session ID, patch 버전을 범용 source에 하드코딩하지 않는다.

## 대안 비교

| 대안 | discovery 신뢰성 | source drift | Check·Install·Restore transaction | PlanDigest | rollback | portability |
| --- | --- | --- | --- | --- | --- | --- |
| A. Claude 전용 봉인 physical copy | 공식 personal path에 ordinary directory를 두므로 현재 실패 형태를 제거한다. 실제 신뢰성은 `2.1.246` 이상 fresh `--bare` smoke로 승인 전 검증한다. | live link가 아니므로 drift 가능성은 있으나 source commit·source manifest·전체 adapter digest를 `.yohan-adapter.json`과 Check에 봉인한다. 불일치 시 덮어쓰지 않고 Conflict로 중단한다. | 기존 AGY adapter의 staging·digest·atomic move를 일반화한다. 새 schema 5가 Claude Adapter를 정의하고 schema 3·4 Restore는 옛 Junction 의미를 유지한다. | contract version, role, materialization kind, source commit/digest, expected adapter digest, 현재 leaf kind·target·file ID·digest, action을 묶는다. | schema 5 migration은 기존 Junction을 transaction의 deterministic removal path로 exact move한 뒤 adapter를 활성화한다. Restore는 같은 Junction 객체를 되돌려 file ID를 보존한다. | 관리자 권한 없이 동작하고 Claude가 지원하는 ordinary personal directory만 요구한다. 대신 source 변경마다 Restore→새 Check/승인→Install이 필요하다. |
| B. 공식 지원 directory symbolic link | Claude 문서가 명시한 방식이라 의미상 가장 직접적이다. 다만 Windows directory symlink와 Junction은 다른 reparse kind이고, 현재 환경에서 symlink fresh smoke 증거는 없다. | 정본을 live로 읽어 copy drift가 작다. 반대로 source working tree 변경이 배포 leaf에 즉시 노출되어 승인된 PlanDigest와 실행 bytes의 시간적 결합이 약해진다. | 현재 `Get-PathEntryInfo`는 Junction 이외 reparse point를 Conflict로 처리한다. symlink identity·target·ancestor 안전성·atomic move·Restore를 새로 설계해야 한다. | link kind·target·object identity와 source bytes를 함께 묶어야 한다. source가 설치 후 바뀌면 PlanDigest 승인 없이 runtime 내용이 변할 수 있다. | 정확한 symlink 객체를 보존하거나 재생성해야 한다. Windows 권한·Developer Mode 차이도 복구 경로에 포함된다. | Unix 계열에는 자연스럽지만 이 저장소의 Windows primary·무관리자 설치 제약과 충돌할 수 있다. |
| C. 현 Junction 유지 | Agent Kit Check에는 안정적이지만 핵심 fresh `--bare` smoke가 이미 실패했으므로 runtime discovery 신뢰성이 부족하다. | live 정본이라 copy drift가 없고 기존 manifest 검증을 그대로 쓴다. | 현재 schema 3·4와 233-assertion 계열 회귀를 그대로 유지할 수 있다. | 현재 contract 4 PlanDigest를 그대로 쓴다. | 현재 exact BackupId Restore와 junction identity 검사가 유지된다. | Windows에서 무관리자 생성이 쉽지만 Claude loader 동작에 의존하며 현재 acceptance를 충족하지 못한다. |

Claude plugin skill은 공식 배포 방식이지만 `/plugin-name:skill-name` namespace가 되어 `/agent-team-operations` acceptance를 바꾸고, 범용 skill을 `plugins/`에 중복 복사하지 않는 저장소 규칙과 충돌하므로 본 결정의 대체재로 채택하지 않는다.

## 권고 결정

승인된 결정으로 대안 A를 채택한다.

1. Git 정본과 `distribution/manifests/<name>.json`은 계속 유일한 source of truth다.
2. Claude의 active leaf는 canonical files와 deterministic `.yohan-adapter.json`을 가진 ordinary directory다. metadata는 최소한 `schemaVersion`, `adapterKind=claude-code-personal-physical-copy`, `skill`, `sourcePath`, `sourceCommit`, `sourceDigest`를 포함하며 timestamp와 현재 Claude patch version은 넣지 않는다.
3. Claude patch version은 adapter identity가 아니라 fresh smoke receipt에 기록한다. 자동 업데이트가 잦은 CLI patch를 metadata에 묶어 불필요한 전역 재설치를 만들지 않는다.
4. adapter 내부 reparse point, metadata drift, payload drift, 다른 source, 잘못된 adapter kind는 Conflict다. manager는 이를 자동 채택하거나 덮어쓰지 않는다.
5. source가 바뀌어 기존 sealed copy가 현재 expected digest와 달라지면 기존 계약처럼 자동 update하지 않는다. 정확한 이전 BackupId로 Restore한 뒤 새 Check·PlanDigest 승인·Install을 수행한다.
6. 새 Install transaction은 schema 5를 사용한다. `Get-TargetDefinitions`의 schema 3·4 분기는 Claude Junction을 유지하고 schema 5만 Claude Adapter로 해석한다. Restore는 3·4·5를 모두 읽는다.
7. matching canonical Claude Junction migration은 `ReplaceJunctionWithAdapter`로 계획한다. Install은 Junction을 삭제하지 않고 transaction 내부로 exact move하여 original target과 NTFS file ID를 보존하고, verified adapter를 active leaf로 atomic move한다.
8. migration transaction이 반환한 exact BackupId가 rollback 단위다. Restore Check도 active adapter digest, 보존 Junction identity, staging/removal 상태를 새 Restore PlanDigest에 묶는다.

## 결과와 비용

### 기대 효과

- 현재 재현된 Junction discovery 실패 형태를 제거하면서 unqualified personal command 이름을 유지한다.
- source provenance와 runtime materialization을 분리해 “Git 정본은 하나, vendor view는 검증된 생성물”이라는 기존 AGY 패턴을 재사용한다.
- stale copy와 사람이 수정한 home copy를 구분하지 못하는 경우에도 덮어쓰기 대신 Conflict로 멈춘다.
- 새 schema가 이전 transaction의 의미를 바꾸지 않아 기존 Restore 계약을 보존한다.

### 비용과 운영 부담

- source 변경이 home에 즉시 반영되지 않으며 Restore→Check→승인→Install 순서가 필요하다.
- manager의 adapter helper·seal·Restore 상태 기계가 AGY 전용 표현에서 vendor-neutral 표현으로 확장된다.
- schema 5와 이전 schema fixture, preserved-junction interruption, adapter drift, full `All` target 기대값의 회귀 테스트가 추가된다.
- physical directory의 파일 수만큼 사용자 홈 저장 공간이 중복된다.
- ordinary directory가 discovery를 보장한다는 최종 증거는 구현·격리 회귀 후 실제 fresh Claude smoke에서만 얻어진다.

## 구현 전제와 사람 게이트

- 구현 순서와 acceptance는 [Goal 17 구현 계획](../plans/goal-17-claude-skill-deployment.md)을 따른다.
- 이 ADR과 구현 Plan은 승인되어 repo-local 구현·fixture 회귀를 진행한다.
- Git 통합, 실제 홈 read-only Check 결과와 새 PlanDigest 승인, 전역 Install, 유료 fresh smoke, PR Ready·merge는 각각 이름이 보존된 사람 게이트다.
- 이번 구현 승인으로 실제 HomeRoot 쓰기, 기존 실홈 Junction 교체, commit·push·PR·merge를 수행하지 않는다.

## 미해결 위험

- ordinary physical directory도 향후 Claude 버전에서 `--bare` discovery 정책이 바뀌면 다시 실패할 수 있다.
- fresh smoke가 physical copy에서 성공해도 그 결과만으로 모든 canonical skill과 자동 routing을 증명하지는 않는다.
- 기존 schema 4 transaction과 새 schema 5 migration의 중첩 rollback은 최신 migration BackupId부터 역순으로 수행해야 한다. 순서를 어기면 identity 검사가 의도적으로 fail-closed할 수 있다.
- Windows file move는 프로세스 중단 원자성을 제공하지만 전원 손실까지 완전한 내구성을 보장하지 않는 기존 운영 한계가 남는다.
