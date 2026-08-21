# Agent Asset Intake

## 원칙

새 Skill·Agent·Command·Hook·Rule·MCP·Script·Template·Plugin은 자동 push하지 않는다. 발견 즉시 Git에 넣으면 취향과 노하우가 축적되는 대신 시크릿, 라이선스 불명 자산, 벤더 cache, 중복 사본까지 정본이 된다.

```text
local discovery
  → ~/.yohan-agent-kit/inbox/<candidate-id>/raw
  → duplicate / secret / absolute-path / license checks
  → candidate
  → reviewed
  → Draft PR bundle
  → 사람의 diff·license·eval 승인
  → repository PR에서 approved
  → release gate에서 released
```

Intake 도구가 만들 수 있는 lifecycle의 상한은 `reviewed`다. `approved`, `released`, push 권한은 만들 수 없다.

## 사용

```powershell
.\scripts\Manage-AgentIntake.ps1 -Mode Scan `
  -SourcePath <asset> -Kind skill -CanonicalId skill.example `
  -Provenance 'external:https://example.com/repo@sha' -License MIT `
  -ApproveInboxWrite

.\scripts\Manage-AgentIntake.ps1 -Mode Check -CandidateId <id>
.\scripts\Manage-AgentIntake.ps1 -Mode Review -CandidateId <id> -ApproveInboxWrite
.\scripts\Manage-AgentIntake.ps1 -Mode ExportDraft -CandidateId <id> -ApproveInboxWrite
```

raw에는 로컬 source를 보존할 수 있지만 candidate metadata에는 원본 절대경로를 넣지 않는다. `.env`, private key, token-like value, Windows·UNC·Unix home 절대경로를 발견하면 후보는 차단된다. license가 allowlist에 없거나 `UNKNOWN`이면 차단된다. Registry 또는 Inbox에서 같은 canonical ID나 content digest가 발견돼도 차단된다.

Draft bundle은 local Inbox 안에만 생성되며 `pushAuthorized: false`다. 외부 HTML/디자인 Skill은 provenance, version/ref, license, digest를 먼저 고정하고, 라이선스가 허용되는 경우에만 fork 후보로 검토한다. 요한 취향은 가능하면 별도의 Rule, Reference, Golden Example, Anti-pattern, Eval로 축적한다.

프로젝트 전용 Subagent는 소유 프로젝트에 남긴다. 두 개 이상의 프로젝트에서 같은 역할과 완료 조건이 반복 검증된 경우에만 Intake 후보로 올린다.
