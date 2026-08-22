---
name: master-orchestrator
description: Owner one-line orchestrator. Triggers - sync env, import env, goal PR, MCP list, tools list, system status.
---

# Master Orchestrator — one-line control skill

Respond to these natural-language triggers.

> 개발 루트 = `.agents/` 디렉터리를 품은 상위 폴더. 아래 `<개발 루트>`는 전부 그 경로로 해석한다.
> 확정할 수 없으면 추측하지 말고 사용자에게 묻는다.

## Triggers

### 1. "환경 동기화해줘" / "sync env" / "동기화"
- Run: powershell -NoProfile -File `<개발 루트>/scripts/sync_env.ps1` -Export
- Purpose: backup MCP configs for laptop restore

### 2. "환경 복원해줘" / "import env" / "노트북 세팅"
- Run: powershell -NoProfile -File `<개발 루트>/scripts/sync_env.ps1` -Import
- Purpose: restore MCP configs on this PC
- After import: NotebookLM may need **npx -y @m4ykeldev/notebooklm-mcp auth** once

### 3. "골 모드로 PR까지 생성해" / "goal pr" / "자동 PR"
- Run: scripts/auto_pr_goal.ps1 on the active git repo (NOT the `<개발 루트>` itself)
- Result: Commit -> Push -> PR. **Never merge.**

### 4. "MCP 레지스트리 보여줘" / "MCP 목록"
- Summarize: `<개발 루트>/.agents/mcp_registry.md`

### 5. "설치된 스킬 보여줘" / "tools list"
- Summarize: `<개발 루트>/.agents/tools_and_skills.md`

### 6. "시스템 상태 보여줘" / "컨텍스트"
- Summarize: `<개발 루트>/.agents/system_context.md`

## Paths
- SoT root: `<개발 루트>`
- AGENTS.md: `<개발 루트>/AGENTS.md`
- sync: `<개발 루트>/scripts/sync_env.ps1`
- auto PR: `<개발 루트>/scripts/auto_pr_goal.ps1`
