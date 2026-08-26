---
type: implementation-plan
goal: 17
status: IN_PROGRESS
updated: 2026-08-26
decision: ../decisions/2026-08-26-claude-personal-skill-materialization.md
---

# Goal 17 — Claude skill deployment 구현 계획

## 상태와 선행 게이트

- 라우팅: **L** — 전역 skill materialization, transaction schema, rollback 계보를 바꾸는 되돌리기 비용이 큰 변경이다.
- execution provider: `orca-ready`; `automatic_fallback=false`.
- 현재 단계: ADR·구현 Plan 승인 완료, **repo-local TDD 구현과 fixture 회귀 진행 중**.
- 구현 범위: [관련 ADR](../decisions/2026-08-26-claude-personal-skill-materialization.md)의 `Accepted` 결정에 따라 아래 1~4단계를 진행한다. 실제 HomeRoot·Git delivery·유료 smoke는 후속 사람 게이트다.

## 성공 정의와 악수

성공은 manager Check의 `Healthy`만이 아니다. clean canonical source로부터 승인된 PlanDigest가 만든 Claude physical adapter의 bytes와, repo/plugin shadow가 없는 Claude Code fresh `--bare`가 읽은 personal skill bytes가 같은 배포 세대를 뜻해야 한다.

악수: `source commit + source manifest + adapter digest + PlanDigest + BackupId`가 install receipt를 소유하고, `exact Claude version + bare command + resolved personal skill path + transcript`가 discovery receipt를 소유한다.

## 영향면

| 파일·표면 | 계획된 변경 | 지켜야 할 회귀 |
| --- | --- | --- |
| `scripts/Manage-MultivendorSkills.ps1` | Claude Adapter 정의, vendor-neutral sealed adapter helper, contract/transaction schema 5, preserved Junction migration | Check read-only, mutex, path containment, atomic JSON, schema 3·4 seals byte compatibility, AGY adapter output 불변 |
| `tests/Manage-MultivendorSkills.Tests.ps1` | Claude red tests, schema 5 interruption·rollback, full `All` target 기대값 | 기존 233 assertions 계열 전부 유지, 실제 HomeRoot 미사용 |
| `docs/MULTIVENDOR_SKILL_DISTRIBUTION.md` | Claude physical adapter, migration·update·Restore·fresh smoke 계약 | Agents·Agy·legacy 경로와 approval/PlanDigest 계약 불변 |
| `scripts/check-goal-17.mjs` | Goal 17의 결정론적 문서·manager·test gate | `.vhk/HARD_STOP`, 관련 ADR 상태와 구현 차단 규칙 명시 |
| `goals/8-two-machine-four-vendor-validation.md`, `docs/AGENT_KIT_TWO_MACHINE_RUNBOOK.md` | filesystem health와 personal discovery receipt 분리, Goal 17 연결 | Goal 8의 기존 seven-capability plugin/release smoke 의미를 바꾸지 않음 |
| `docs/audits/`의 Goal 17 closeout | source ref, test receipts, Check JSON digest, PlanDigest, BackupId, smoke 결과 | raw home path·secret·전체 transcript의 불필요한 Git 저장 금지 |

범용 skill bytes와 `distribution/manifests/*.json`은 바꾸지 않는다. manager·test·문서 변경만으로 해결하므로 skill manifest 갱신은 예상하지 않는다.

## 실행 순서

### 0. ADR·Plan 사람 게이트

1. ADR의 frontmatter와 본문이 모두 `Accepted`인지 확인한다.
2. 확정 결정, schema 3·4 호환성, schema 5 rollback, 실제 홈·유료 smoke 게이트가 이 계획과 일치하는지 대조한다.
3. 구현 Plan 승인을 받은 뒤에만 red test를 작성한다. ADR 승인과 실제 홈 승인은 합치지 않는다.

### 1. failing tests를 먼저 고정한다

현재 구현에서 실패하는 다음 assertions를 먼저 추가한다.

1. empty fixture HomeRoot의 `All`은 8 skills에 대해 Agents·AgyStandard `CreateJunction` 16건과 Claude `CreateAdapter` 8건을 계획하고 총 24 canonical deploy target을 유지한다.
2. Claude missing leaf는 `CreateAdapter`, matching canonical Junction은 `ReplaceJunctionWithAdapter`, source-identical unmanaged directory는 `BackupAndAdapt`로 판정한다.
3. exact sealed Claude adapter는 `Healthy`; metadata·payload·추가 파일·nested reparse drift는 `Conflict`이고 Install은 아무것도 쓰지 않는다.
4. Claude metadata는 timestamp와 patch version 없이 deterministic하며 source path·commit·digest와 `adapterKind`를 봉인한다.
5. stale PlanDigest, wrong source target, non-Junction reparse point, recreated Junction identity는 mutation 전에 실패한다.
6. schema 5 migration은 canonical Junction을 delete/recreate하지 않고 transaction removal path로 exact move하며, internal install rollback과 approved Restore가 원래 target·file ID를 되돌린다.
7. adapter activation 직전·직후, Junction quarantine 직후, transaction journal update 직전 중단 fixture가 `InstallRollback` 또는 `RestoreReady`로 수렴한다.
8. schema 3·4 fixture의 installSeal·commitSeal·Restore 결과가 기존 bytes와 의미를 유지한다. contract 4의 Claude는 계속 Junction으로 해석된다.
9. source가 바뀐 뒤 old sealed adapter는 자동 갱신되지 않고 Conflict다. 정확한 이전 BackupId Restore 뒤 새 Check를 요구한다.
10. AGY fallback metadata와 adapter digest, evidence gate, Restore assertions는 변경 전과 동일하다.

Red receipt에는 실패 assertion 이름과 현재 원인을 기록한다. source/manifest invalid처럼 잘못된 이유로 실패한 test는 red acceptance로 인정하지 않는다.

### 2. 최소 구현

1. `Get-TargetDefinitions`가 contract 3·4와 5를 분리하도록 확장한다. 3·4의 Claude는 `Junction`, 5의 Claude는 `Adapter`다.
2. 현재 AGY 전용 adapter 계산·materialization을 vendor-neutral sealed directory primitive로 추출하되, AGY wrapper가 생성하는 metadata bytes와 digest는 바꾸지 않는다.
3. Claude adapter metadata를 deterministic하게 만들고 canonical payload와 metadata를 합친 expected manifest를 Check JSON에 노출한다.
4. Install plan contract를 5로 올리고 PlanDigest에 role, deployment kind, adapter kind, source commit/digest, expected adapter digest, current kind/target/junction identity/current digest, action, recovery IDs를 묶는다.
5. transaction schema 5에 `adapterKind`, deterministic adapter staging/removal path, preserved Junction path·identity·state flag를 seal한다. schema 3·4 seal 분기는 그대로 둔다.
6. `ReplaceJunctionWithAdapter`는 active Junction을 exact move로 보존한 다음 staged adapter를 `Directory.Move`로 활성화한다. post-Check가 `Healthy`가 아니면 같은 transaction 안에서 원복한다.
7. Restore는 schema 3·4·5를 허용하고 schema 5의 active/staged/removed adapter digest와 preserved Junction identity를 Restore PlanDigest에 묶는다. unowned 객체는 이동·삭제하지 않는다.
8. 오류 메시지와 helper 이름의 AGY 전용 표현을 일반화하되 external JSON field와 이전 transaction parser는 호환 유지한다.

코드는 이 범위를 넘는 auto-update, symlink 지원, plugin 배포, 다른 vendor materialization 변경을 하지 않는다.

### 3. 전체 regression

아래 순서로 검증하고 첫 실패 원인을 승인 범위 안에서 보정한다.

```powershell
# PowerShell 5.1 parser
$tokens = $null
$parseErrors = $null
$null = [Management.Automation.Language.Parser]::ParseFile(
  (Resolve-Path 'scripts/Manage-MultivendorSkills.ps1'),
  [ref]$tokens,
  [ref]$parseErrors
)

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File tests/Manage-MultivendorSkills.Tests.ps1

node scripts/check-goal-1.mjs
node scripts/check-goal-8.mjs --local
node scripts/check-goal-15.mjs
node scripts/check-goal-17.mjs
git diff --check
```

Goal 8의 외부 actual-home evidence는 이 단계에서 만들지 않는다. full regression은 `tests/.work/` fixture와 repo-local static gate만 사용한다.

### 4. 격리 HomeRoot install·restore

ignored `tests/.work/goal-17-*` 아래에 현재 실홈 모양을 재현한다.

1. Agents·Claude·AgyStandard가 같은 clean canonical source를 가리키는 Junction인 fixture를 만든다.
2. read-only Check가 Agents·AgyStandard는 `None`, Claude만 `ReplaceJunctionWithAdapter`, conflict `0`으로 보고하는지 확인한다.
3. fixture PlanDigest로 Install하고 Claude leaf가 ordinary directory인지, metadata·payload digest가 expected와 같은지, post-Check가 `Healthy`인지 확인한다.
4. exact BackupId의 Restore Check와 Restore PlanDigest를 만든다.
5. Restore 뒤 세 target이 설치 전 상태와 같고 Claude Junction target·NTFS file ID가 migration 전 값과 같은지 확인한다.
6. 같은 fixture에서 internal failure rollback과 repeated Check/Install/Restore idempotency를 재실행한다.

격리 검증은 actual Claude runtime discovery 증거로 확대 해석하지 않는다.

### 5. clean primary ref 통합 게이트

실제 홈 Check는 temporary worktree를 canonical source로 삼으면 기존 primary-target Junction을 잘못된 source로 판정한다. 따라서 검증된 변경이 사람의 Git 통합·merge 게이트를 통과하고 `C:\Users\Public\dev\automation\yohan-cc-skills`가 새 clean `origin/main`과 일치한 뒤에만 다음 단계로 간다.

commit·push·PR Ready·merge는 각각 당시 승인 계약을 따른다. 이 계획은 자동 merge 권한을 부여하지 않는다.

### 6. 실제 HomeRoot의 새 Check·PlanDigest 승인

primary checkout에서 먼저 canary skill만 read-only Check한다.

```powershell
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
  -File scripts/Manage-MultivendorSkills.ps1 `
  -Mode Check -Skill agent-team-operations `
  -HomeRoot <actual-home> -OutputFormat Json
```

승인 요청에는 다음을 그대로 제시한다.

- clean source commit·manifest digest
- Claude target exact path와 현재 kind·canonical target·junction identity
- `ReplaceJunctionWithAdapter` 한 건, expected adapter digest, Agents·AgyStandard `None`
- conflicts/recovery IDs가 0인지
- 새 PlanDigest
- 예상 transaction 경로 규칙, rollback 의미, 실제 쓰기 대상

이전 contract 4 PlanDigest나 promotion 당시 PlanDigest는 재사용하지 않는다. 사람이 이 exact diff와 새 PlanDigest를 승인해야만 Install한다.

### 7. 승인된 canary Install과 post-Check

1. approved PlanDigest와 `-ApproveGlobalHomeWrite`로 `agent-team-operations`만 Install한다.
2. returned BackupId와 transaction path를 즉시 기록한다.
3. post-Check `Healthy`, active Claude ordinary directory, adapter digest, Agents·AgyStandard 불변을 확인한다.
4. exact BackupId Restore Check가 `RestoreReady`인지 확인하되 smoke 전에 Restore하지 않는다.
5. Install 내부 오류는 transaction rollback에 맡긴다. post-Install smoke 실패는 파일 transaction 실패가 아니므로 자동 Restore하지 않는다.

나머지 canonical Claude skills의 migration은 canary smoke 성공 뒤 별도의 `-Skill All` Check·PlanDigest 사람 승인으로 수행한다.

### 8. fresh Claude `--bare` smoke

유료 호출 승인을 확인한 뒤 한 번 실행한다.

- exact Claude executable identity와 reported version을 먼저 기록한다.
- working directory는 모든 Agent Kit checkout 밖의 새 빈 디렉터리다.
- actual user profile을 사용하되 `--add-dir`, `--plugin-dir`, project `.claude/skills`, synced skill을 사용하지 않는다.
- `--bare`, non-persistent, read-only/plan, low-cost model·effort와 승인된 budget cap을 사용한다.
- prompt의 첫 동작은 `/agent-team-operations` 명시 호출이며, skill 계약의 고유 marker와 실제 personal `SKILL.md` 경로를 출력하게 한다.
- command line, stdout, stderr, exit code, model turn, cost, resolved path, workdir before/after snapshot을 file-first receipt로 남긴다.

PASS 조건은 `Unknown command`가 없다는 것만이 아니다. resolved path가 exact `~/.claude/skills/agent-team-operations/SKILL.md` 아래이고 ordinary adapter payload와 source digest가 맞으며, expected skill behavior marker가 있고 작업 디렉터리 쓰기가 없어야 한다.

실패하면 유료 호출을 반복하지 않는다. active adapter와 transaction을 그대로 보존하고 read-only Check·Restore Check 결과를 보고한 뒤, exact BackupId Restore 여부를 별도 승인받는다.

### 9. closeout과 후속 rollout

1. `docs/audits/`에 source ref, ADR, test counts, fixture BackupId, actual Check summary·PlanDigest, actual BackupId, post-Check, smoke receipt 경로와 잔존 위험을 기록한다.
2. raw transcript에 secret·private path가 없는지 확인하고 Git에는 최소 redacted receipt만 보존한다.
3. Goal 17 Completion Check를 실제 증거에 맞게 갱신하되, 사람이 Goal 완료를 판정하기 전 `DONE`으로 바꾸지 않는다.
4. canary PASS 뒤 나머지 Claude canonical skill migration을 새 Check·PlanDigest 승인 배치로 제안한다.
5. Goal 8의 seven-capability plugin/release smoke와 전체 four-vendor final evidence는 별도 진행 상태를 유지한다.

## Builder·Validator 분리

- Builder는 manager·test·contract 구현과 fixture receipt를 소유한다.
- Validator는 stable diff에서 schema 3·4 seal 호환성, PlanDigest completeness, preserved Junction ownership, drift/tamper tests, Goal 8 의미 보존을 read-only로 검수한다.
- actual HomeRoot Check와 fresh smoke는 구현 검수의 대체물이 아니며, validator 승인도 ADR·Plan·merge·전역 쓰기 사람 게이트를 대신하지 않는다.

## 중단 조건

- ADR 상태가 `Accepted`가 아니거나 본문과 frontmatter가 다름
- source ref·active conductor·ownership epoch·current gate가 handoff와 다름
- `.vhk/HARD_STOP` 존재, dirty/unexpected primary source, pending recovery transaction
- schema 3·4 Restore fixture 또는 AGY adapter digest 회귀
- actual Check에 Claude canary 이외 action, conflict, 다른 source path가 나타남
- 새 PlanDigest 승인 없음, 유료 smoke 승인 없음, smoke가 repo/plugin shadow를 배제하지 못함

같은 blocker가 해소되지 않으면 범위를 넓히거나 home을 수동 수정하지 않고 구조화 `BLOCKED`로 보고한다.
