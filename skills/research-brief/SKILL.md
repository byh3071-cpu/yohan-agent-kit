---
name: research-brief
description: >-
  Lightweight competitor/market research to Notion (not yohan-brain by default).
  Uses agent-reach/WebSearch; optional parallel research-scout. Triggers - 경쟁사,
  리서치 브리프, 비교해줘, 시장 조사. Say 병렬 for scouts (max 4).
---

# research-brief

## Default path
1. Normalize question + axes
2. If owner said 병렬 / 경쟁사 각각 → spawn **research-scout** ≤4 (readonly)
3. Else gather with agent-reach / WebSearch
4. Write Notion row (Research Pipeline `8b0690cc` preferred, or Copilot Session `7697d25a` if inbox-only)
5. Leave empty **판정** field for owner
6. **Do not** open brain PR / research-loop full pipe in v1

## Requires
Notion MCP authenticated (Cursor OAuth). If needsAuth → tell owner to auth; offer paste block for manual Notion entry.

## Output
- Notion URL or page id
- Summary table
- Empty 판정란 reminder
