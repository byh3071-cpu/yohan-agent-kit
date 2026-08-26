# Agent Team Operations 승격 감사 — 2026-08-26

## 결론

MOVA의 승인된 `agent-team-operations` 후보를 Yohan Agent Kit의 portable source와 distribution manifest로 바이트 동일 승격했다. 배포 도구의 개별 선택과 `All` 선택, 자산 Registry와 생성 catalog, 비파괴 repo-local validator를 함께 연결했다. 사용자 홈 `Install`·`Restore`, Git commit·push·PR·merge, MOVA 파일 수정은 수행하지 않았다.

## 소유권과 입력 영수증

- owner scope: Yohan Agent Kit `agent-team-operations` source·manifest 승격과 repo-local 검증
- Agent Kit 기준선: `origin/main@38bdd9d5d242e5f20d2541d9acb138da424cc2cb`
- 승인 bundle reference digest: `5c6e657f83615046563bd55b979193797bdf35e396153a5f3c27aa6dcd1731e5`
- 재현 가능한 후보 tree digest: `8cf1276e3dc429bdbc6c044107acab78abe0b8ecd4f45914de5416db4acd7d60`
- active writer: `term_05c82590-82e8-487f-92b7-60e6391aad91`, ownership epoch `1`
- route와 mode: `L`, full-handoff 수신 뒤 이 worktree의 conductor-only single writer
- 작업 위치: 독립 branch `byh3071-cpu/agent-team-operations-promotion`; primary checkout, `yohan-core-codex-hook-compat`, locked `kno-002` worktree는 읽기 전용 재실측 외에 건드리지 않음

시작 시 `.vhk/HARD_STOP`은 없었고 target worktree는 기준선과 같은 HEAD에서 clean이었다. VHK context snapshot은 오래됐지만 live `vhk status`, `vhk goal list`, `vhk check`와 이번 승인 Task의 source reference·scope·gate 사이에 ownership-critical 충돌은 없었다. 새 Goal은 만들지 않았다.

## 승격 자산

| 자산 | 역할 | 상태 |
|---|---|---|
| `skills/agent-team-operations/SKILL.md` | 정본 entrypoint와 routing·ownership·artifact 계약 | 후보와 byte-identical |
| `skills/agent-team-operations/references/operating-manual.md` | start·lane·worker·review·handoff·promotion 절차 | 후보와 byte-identical |
| `skills/agent-team-operations/agents/openai.yaml` | UI metadata와 implicit invocation | 후보와 byte-identical |
| `distribution/manifests/agent-team-operations.json` | 세 파일의 bytes·SHA-256·전체 digest | digest `C321E4C231EACE51D4F84A99BB1CBD5942708B1894D72A3723D4A0F1B66D54BD` |
| `scripts/Manage-MultivendorSkills.ps1` | 개별/`All` Check·Install·Restore 선택과 transaction allowlist | 8번째 canonical skill로 연결 |
| `registry/assets.yaml`·`distribution/asset-catalog.json` | portable reviewed source·manifest·validator 색인 | 219 assets, catalog digest `4f9727a8901abc6288f86c3a3b433b72ae28af79a336377d6323d287eb8cf807` |
| `scripts/check-agent-team-operations.mjs` | source/manifest/portability/manager/registry/catalog 비파괴 gate | repo-local validator |

후보와 승격 source의 세 파일 SHA-256 manifest와 tree digest는 모두 같았다. 스킬에는 로컬 절대경로, 현재 terminal·Run·Task·Attempt ID, exact 모델 ID, 시크릿이나 provider-local runtime 상태가 없다.

## 기존 스킬과의 경계 판단

| 기존 자산 | 판단 | 이유 |
|---|---|---|
| `design-team` | 연결 | 도메인별 deep dialogue·선택·spec·handoff를 소유한다. 새 스킬은 어떤 domain skill을 언제 팀 lane으로 쓰는지만 조율한다. |
| `supervised-session-conductor` | 연결 | live Task DAG, report와 lifecycle receipt, 단일 final gate는 기존 스킬이 계속 소유한다. 새 스킬은 supervised mode를 선택하고 상위 workstream·routing을 연결한다. |
| `restart-safe-handoff` | 연결 | ownership transfer와 content/delivery receipt의 정본이다. 새 스킬은 full handoff를 선택하고 5-field ACK를 요구할 뿐 takeover 절차를 복제하지 않는다. |
| `orchestration` | 연결 | 실제 provider dispatch는 설치된 version-matched adapter guide가 소유한다. 새 source에는 Orca 명령이나 provider 버전을 고정하지 않았다. |
| `session-card` | 보존 | 얇고 휘발성인 로컬 상태 카드이며 handoff가 아니다. durable workstream·artifact 계약을 대신하지 않는다. |
| `master-orchestrator` | 보류 | 특정 자연어 trigger와 로컬 도구 라우팅을 소유하는 기존 자산이다. 이름 유사성만으로 교체·폐기하지 않으며 이번 portable 팀 운영 승격 범위 밖에 둔다. |

따라서 이번 변경에서 기존 스킬을 교체·삭제하지 않는다. `agent-team-operations`는 상위 mode·team·artifact 조율 계층이고, 기존 자산은 domain·live supervision·handoff·runtime adapter·thin status·legacy trigger 역할을 유지한다.

## 검증 결과

- `skill-creator`의 `quick_validate.py` — `Skill is valid!`
- 후보와 승격 source tree digest 재계산 — 양쪽 모두 `8cf1276e3dc429bdbc6c044107acab78abe0b8ecd4f45914de5416db4acd7d60`
- `node scripts/Build-AssetCatalog.mjs --write` — 219 assets, catalog digest `4f9727a8901abc6288f86c3a3b433b72ae28af79a336377d6323d287eb8cf807`
- `node scripts/check-agent-team-operations.mjs` — PASS, 20 gates. frontmatter, source/manifest 전체 파일과 digest, portability, UI metadata, manager selection, Registry와 catalog를 검증했다.
- `node scripts/check-goal-15.mjs` — PASS. 기존 session-operations 계약과 Goal 11–14 회귀가 유지됐다.
- PowerShell parser와 `node --check` — 변경된 manager·manager test·새 validator 모두 PASS.
- `Manage-MultivendorSkills.ps1 -Mode Check -Skill All` — 8개 canonical source를 선택했다. 새 source가 아직 untracked라 전체 상태는 예상대로 `SourceInvalid`였다.
- commit 전 `tests/Manage-MultivendorSkills.Tests.ps1` full regression 시도 — FAIL receipt: manager가 `SourceInvalid`와 exit `3`을 반환해 30 assertions에서 중단됐다. 원인은 새 `skills/agent-team-operations/`와 manifest가 이번 session의 commit·staging 금지에 따라 untracked인 상태여서 clean tracked source gate를 통과할 수 없었기 때문이다. 독립 검토에서 별도로 발견한 `All` target 기대값도 기존 7 skills 기준 `21`에 머물러 있었으며, 8 skills × 3 canonical junctions에 맞게 `24`로 보정했다. full regression은 clean tracked ref에서 다시 실행해야 한다.
- `git diff --check` — PASS.

저장소의 정식 `scripts/New-SkillManifest.ps1`은 source가 Git index·HEAD와 동일한 clean tracked 상태일 때만 manifest를 생성한다. 이번 session은 commit이 명시적으로 금지되어 있으므로 read-only 실행은 `Untracked skill file: skills/agent-team-operations/SKILL.md`에서 fail-closed됐다. manifest는 같은 bytes·SHA-256·정렬·digest 알고리즘으로 생성하고 repo-local validator로 재계산 검증했다. Git 통합 뒤 clean ref에서 정식 generator 출력을 다시 대조해야 한다.

## Distribution Check와 PlanDigest

읽기 전용 Check를 두 방식으로 실행했다.

1. 현재 sandbox 기본 HomeRoot에서는 source가 아직 uncommitted/untracked이므로 `SourceInvalid`였다. 계산된 `planDigest=1D5A2243E7AAB2ACDAF25B6536FDAF1DBBA501E9419C60E4B079D91322274620`은 target plan이 비어 있는 진단 digest이며 Install 승인에 사용할 수 없다.
2. 실제 `C:\Users\user`를 명시한 read-only Check는 현재 sandbox가 HomeRoot 자체의 열람을 거부해 `Access to the path 'C:\Users\user' is denied.`로 중단됐다.

따라서 현재 artifact에는 실제 홈 대상별 exact diff와 actionable PlanDigest가 없다. 이는 source·manifest 무결성 실패가 아니라 두 개의 독립된 gate, 즉 clean tracked Git source 필요와 현재 process의 실제 HomeRoot read 권한 부재 때문이다. 이 상태에서 `Install`을 시도하지 않았다.

## 재현 명령

```powershell
python -B -X utf8 <skill-creator>/scripts/quick_validate.py skills/agent-team-operations
node scripts/check-agent-team-operations.mjs
node scripts/Build-AssetCatalog.mjs
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/New-SkillManifest.ps1 -Skill agent-team-operations
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts/Manage-MultivendorSkills.ps1 -Mode Check -Skill agent-team-operations -HomeRoot <actual-home> -OutputFormat Json
git diff --check
```

`<skill-creator>`와 `<actual-home>`은 실행 환경이 제공하는 경로이며 저장소 계약에 machine-specific 절대경로로 고정하지 않는다.

## 다음 사람 게이트와 잔존 위험

현재 session의 완료 지점은 source·manifest·distribution wiring과 repo-local 검증이다. 다음 순서는 별도 권한 아래에서 진행한다.

1. 현재 diff를 사람 검토하고 Git commit·push·PR 여부를 결정한다.
2. clean tracked ref에서 정식 manifest generator와 repo-local gate를 다시 통과한다.
3. 실제 HomeRoot를 읽을 수 있는 환경에서 `Check`를 재실행해 target별 exact diff와 actionable PlanDigest를 만든다.
4. 그 diff와 PlanDigest를 사람이 별도로 승인한 뒤에만 전역 `Install`을 실행한다.
5. 설치 뒤 새 세션 smoke는 또 다른 delivery/behavior receipt로 남긴다.

정적 검증은 실제 벤더의 새 세션 discovery나 자동/명시/부정 호출을 증명하지 않는다. `reviewed` lifecycle은 release 또는 설치 완료가 아니다.

## 보고 전달 영수증

- content receipt: `verified` — 이 문서, 기준선·후보 tree digest·manifest digest·검증 결과가 현재 worktree와 일치한다.
- delivery target: MOVA main conductor `term_423c2554-69e9-417b-9588-4bde46065086`
- delivery state: `not-sent`
- attempt evidence: version-matched `orca-cli` 안내를 읽은 뒤 `orca status --json`을 두 번 확인했으나 app은 실행 중이고 runtime·graph는 계속 `starting`, `reachable=false`, runtime ID `null`이었다. 이어진 target `terminal show`는 `runtime_unavailable`이었다.
- handling: target 상태를 읽지 못해 `terminal send`를 실행하지 않았다. runtime이 `reachable=true`가 되고 exact target terminal을 다시 식별할 수 있을 때만 이 artifact를 한 번 전달한다.
