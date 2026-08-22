---
name: morning-merge-check
description: >-
  Morning merge checklist skill. Reads MORNING_MERGE_CHECKLIST.md and advises.
  May delegate to merge-advisor. Never merges. Triggers - 아침 머지, morning
  merge, 머지해도.
---

# morning-merge-check

## SoT
`<개발 루트>/.agents/MORNING_MERGE_CHECKLIST.md`

> 개발 루트 = `.agents/` 디렉터리를 품은 상위 폴더. 확정할 수 없으면 사용자에게 묻는다.

## Steps
1. Read checklist
2. Optionally launch **merge-advisor** (readonly)
3. Report 권고 only
4. **Never** `gh pr merge` / merge to main|master
