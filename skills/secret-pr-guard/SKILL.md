---
name: secret-pr-guard
description: >-
  Pre-commit/PR secret gate. Scans for _env_backup, tokens, .env, cookies before
  push/PR. Triggers - PR 전, 시크릿, secret check, before auto_pr. Inspired by
  #131 incident.
---

# secret-pr-guard

## Before commit/push/PR
1. `git status` / diff staged+unstaged
2. Fail if paths match `_env_backup`, `.env`, `credentials`, raw token files
3. Grep diff for high-risk patterns: `Bearer `, `sk-`, `PLAYWRIGHT_MCP`, `api_key`, `BEGIN PRIVATE KEY`
4. Confirm `.agents/_env_backup` not tracked

## Result
`PASS` or `BLOCK` with file:line hints. Never print full secrets.
