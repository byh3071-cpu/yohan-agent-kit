# Context Contract

## Source of truth

Resolve conflicts in this order; a lower-priority source cannot override a higher-priority source.

1. Current request
2. Project Git
3. yohan-brain design context
4. Notion view

Use repository-relative paths, Git refs, stable links, or source names in tracked files. Do not record absolute machine paths.

## Required context record

Display this `WorkContext` before implementation:

```markdown
## 작업 컨텍스트 요약
- goal:
- user and target screen:
- approved visual source:
- selected source of truth:
- applicable project rules:
- acceptance criteria:
```

`WorkContext` is the structured record used to resolve sources and constraints. `검증 리포트` is the handoff record containing the viewport checks, same-state comparison, unresolved P0/P1/P2 items, `design-qa.md` result, and commit SHA.

## Same branch on two PCs

For one branch, finish work on the first PC with commit and push. On the second PC, pull and continue only after that push is available. Do not edit the same branch concurrently on two PCs, especially the same files.

## Three independent promises

| Promise | Must remain true | Evidence |
| --- | --- | --- |
| File identity | The approved source, implementation, and evidence identify the exact files or stable refs used. | Source and output paths or refs in the 검증 리포트 |
| Design consistency | The implementation matches the approved source at the compared viewport and UI state. | Same-state source and implementation captures |
| Creative consistency | Decisions not explicit in the source stay intentional and consistent across related screens and states. | Reused decision rule recorded in the 검증 리포트 |
