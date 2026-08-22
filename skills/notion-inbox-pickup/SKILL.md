---
name: notion-inbox-pickup
description: >-
  Home CLI pickup of Notion AI Copilot Session rows with 상태=미정제 into local
  docs/brain paths. Triggers - 세션 줍기, Notion 인박스, 미정제 줍기. Needs Notion MCP auth.
---

# notion-inbox-pickup

## Target DB
- AI 코파일럿 세션 `7697d25a`
- URL: https://app.notion.com/p/7697d25a44d6485a920135968491e024
- Data source: `collection://7d904867-525a-44f3-ab2e-88d84e5b318d`

## Pickup filter (SoT)
- **줍기 대상:** `상태 = 미정제` only
- **용어:** 「미승격」 쓰지 말 것 (= 폐기된 문서 용어)
- kind는 DB 컬럼 아님 → 페이지 본문/`핸드오프 노트`의 `kind:` 줄 또는 **트리거**로 추론

## Steps
1. If Notion MCP needsAuth → stop and ask owner to authenticate (`notion` ready; ignore duplicate `Notion` if needsAuth)
2. SQL/list: `WHERE 상태 = '미정제'` → title + url only for session-card; fetch body/`핸드오프 노트` for promote
3. Write to active repo `docs/inbox/` or brain `docs/` as owner agrees
4. After successful local write, set Notion **상태 → 요약중** (or 요약완료 if fully filed) — do not leave silent dupes
5. Never write into legacy Prompt DB `3349740a…`

## Anti-contamination
- No secrets in local files
- No auto-commit
- Card shows count + titles/links only until owner asks to promote
