# Yohan Agent Kit release store

## 결론

GitHub의 tracked source와 `registry/assets.yaml`이 정본이다. `dist/`는 빌드 결과이며 직접 수정·커밋하지 않는다. 설치 입력은 Git checkout이 아니라 파일별 SHA-256으로 봉인된 release artifact다.

```text
Git tag / exact commit
  → Build-AgentKit.mjs
  → dist/releases/<release-id>/
     ├─ release-manifest.json
     └─ packages/
        ├─ agent-plugins/
        ├─ claude-code/
        ├─ codex/
        ├─ cursor/
        └─ antigravity/
  → Manage-AgentKit.ps1
  → ~/.yohan-agent-kit/releases/<release-id>/
  → active + vendor discovery junctions
```

## 패키지 경계

| package | manifest | 포함 | 설치 방식 |
|---|---|---|---|
| Agent Plugins 1.0 | `plugin.json` | portable Skills, `mcp.json` | `~/.agents/plugins/yohan-agent-kit` junction |
| Claude Code | `.claude-plugin/marketplace.json` | 기존 네 plugin + `yohan-agent-kit` portable plugin | Claude Marketplace가 관리 |
| Codex | `.codex-plugin/plugin.json` | Skills, 일반 Agent, Hook, Script, MCP | `~/plugins/yohan-agent-kit` junction |
| Cursor | `.cursor-plugin/plugin.json` | Skills, Agent, Rule, Hook, Script, MCP | `~/.cursor/plugins/local/yohan-agent-kit` junction |
| Antigravity | `plugin.json` | Skills, Agents, Rules, Hooks, MCP | IDE `~/.gemini/config/plugins/…` + CLI `~/.gemini/antigravity-cli/plugins/…` junction |

Agent Plugins v1은 Skills와 MCP만 표준화하므로 Agents, Commands, Hooks, Rules를 넣지 않는다. 네이티브 Hook은 벤더별 설정이 공통 무상태 `agent-kit-hook.mjs`를 호출한다. Antigravity IDE와 CLI는 발견 경로와 Agent 지원 범위가 달라 두 공식 경로에 같은 superset 패키지를 연결한다. CLI의 일반 Agent는 실제 `agy` 세션으로 검증하고, IDE는 지원하는 구성요소만 읽는다.

Claude Code는 자체 Marketplace가 cache, installed state, scope를 관리한다. release manager가 `~/.claude/plugins/cache`나 `installed_plugins.json`을 직접 수정하지 않는다. 첫 호환 release에서는 Marketplace namespace `yohan-cc-skills`를 유지하고 GitHub source만 `byh3071-cpu/yohan-agent-kit`을 사용한다.

## 빌드

release는 clean checkout과 full Git SHA에서 만든다.

```powershell
node .\scripts\Build-AgentKit.mjs `
  --release v0.1.0-<short-sha> `
  --output-root dist\releases
```

같은 release ID가 이미 있으면 덮어쓰지 않는다. manifest에는 release ID, kit version, exact Git commit, catalog digest, catalog file digest, 다섯 package 계약, 모든 payload 파일의 bytes·SHA-256, rollback 명령이 들어간다.

`--allow-dirty --allow-test-output --source-commit`은 자동 테스트 전용이다. dirty artifact는 실제 사용자 홈에 설치할 수 없다.

## Check, Install, Update, Restore

Check는 HomeRoot를 만들지 않는다. mutation은 바로 앞 Check의 digest와 명시적 사용자 홈 쓰기 승인 둘 다 필요하다.

```powershell
.\scripts\Manage-AgentKit.ps1 -Mode Check -Release <id> -Targets All

.\scripts\Manage-AgentKit.ps1 -Mode Install -Release <id> -Targets All `
  -PlanDigest <digest> -ApproveGlobalHomeWrite

.\scripts\Manage-AgentKit.ps1 -Mode Update -Release <id> -Targets All `
  -PlanDigest <digest> -ApproveGlobalHomeWrite

.\scripts\Manage-AgentKit.ps1 -Mode Check -BackupId <exact-id>
.\scripts\Manage-AgentKit.ps1 -Mode Restore -BackupId <exact-id> `
  -PlanDigest <digest> -ApproveGlobalHomeWrite
```

기존 경로가 ordinary directory, file, 다른 reparse point이면 Conflict다. Agent Kit release store를 향한 junction만 교체 후보이며, 실제 제거·복원에는 transaction에 기록한 target과 NTFS file ID가 모두 일치해야 한다. 설치·업데이트 부분 실패는 역순 rollback하고 release directory 자체는 삭제하지 않는다. Restore는 항목별 현재 지문을 `Installed`, `Recoverable`, `Restored`, `Conflict`로 판정하므로 중단돼도 같은 exact BackupId와 안정된 PlanDigest로 재개할 수 있다.

## 저수준 Skill 설치기

`Manage-MultivendorSkills.ps1`은 계속 개별 portable Skill의 발견 경로와 AGY fallback을 관리한다. `Manage-AgentKit.ps1`은 release artifact와 plugin package 활성화를 관리한다. 두 스크립트의 책임을 합치지 않는다.
