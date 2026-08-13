# Context Contract

## Source of truth

Resolve conflicts in this order; a lower-priority source cannot override a higher-priority source.

1. Current request
2. Project Git
3. Approved media
4. Common taste rules
5. Golden references

The resolver execution contract is pinned to yohan-brain commit `f7615ac2fce83bd93c37801c14640c20dede5980`. The yohan-brain design context is the metadata/schema/index authority. A Notion view may aid discovery, but it is not a resolution tier and cannot override an approved Git source.

Use repository-relative paths, Git refs, stable links, or source names in tracked files. Do not record absolute machine paths.

## Minimal DesignContext envelope

Place a minimal `DesignContext` before the existing `WorkContext`. It identifies the pinned contract, the five-tier resolution order, resolved constraints, and approved source refs. Keep unresolved tiers explicit and empty; never invent taste, media, or golden records and never promote a candidate automatically.

```json
{
  "contract": { "repo": "yohan-brain", "ref": "<40-hex commit>", "path": "memory/design-intelligence/index.yaml" },
  "resolutionOrder": ["current-request", "project-git", "media", "common-taste", "golden"],
  "constraints": {},
  "approvedSources": []
}
```

`Resolve-DesignContext.ps1` is read-only and resolves Git objects instead of a dirty checkout. `Record-DesignDecision.ps1` records only `reuse`, `adapt`, `remix`, or `create` as append-only evidence. Stable promotion always remains a human gate.

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
