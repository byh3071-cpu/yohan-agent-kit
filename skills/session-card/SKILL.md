---
name: session-card
description: >-
  Thin live status card for home CLI start. Shows repo/branch/dirty, SoT
  pointers and next actions. No Notion lookup or automatic logging. Triggers - 세션 카드,
  집 도착, 이어갈 준비, session status. Not handoff. Not SnapContext context-pack.
---

# session-card

## Default (thin)
- Repo path, branch, dirty yes/no
- SoT pointers only (paths): AGENTS.md, `.agents/system_context.md`, active goal
- Next actions ≤3 lines
- Timestamp

## Detail mode
Only if owner says 자세히: open PRs ≤5, recent commits ≤3

## Anti-contamination
- No full prompts/specs, no secrets, no speculation
- One card per session; overwrite; **do not commit** (`.session-card.md` gitignore if written)
- Refresh only when the user requests current status; no timer or inbox polling.

## Not this skill
- Session end / laptop transfer → `handoff`
- Product SnapContext context-pack schemas
