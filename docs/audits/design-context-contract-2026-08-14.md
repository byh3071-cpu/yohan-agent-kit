# DesignContext contract verification — 2026-08-14

## Dependency identity

- Contract repository: `yohan-brain`
- Contract branch: `feat/design-notion-restart-2026-08-14`
- Pinned implementation input: `f7615ac2fce83bd93c37801c14640c20dede5980`
- Published branch HEAD observed: `fe2da4e82d7a90cc223411c06b1fdcc324087142`
- Dependency: yohan-brain Draft PR #191
- Required merge order: PR #191 first, this repository's Draft PR second

The implementation intentionally pins the contract commit rather than the later branch HEAD.

## Independent Git-object checks

At the pinned commit:

- `docs/adr/ADR-023-design-intelligence-ownership-boundaries.md` has `Accepted` in frontmatter and body.
- `goals/20-design-intelligence-foundation.md` is `DONE`.
- `memory/design-intelligence/index.yaml` assigns metadata/schema/index/evidence to yohan-brain, resolver/recording execution to yohan-cc-skills, and artifacts/verification assets to project Git.
- Stable automatic promotion is `false`; stable promotion requires a human; corrections are append-only.

`Resolve-DesignContext.ps1` and browser QA read the exact Git objects with a command-scoped safe-directory setting. They do not read or modify the yohan-brain working tree.

## Source identity

The approved 432px PNG verifies directly against its Git blob SHA-256:

`688212d5c2c651db759dd20fd292d4017492925b253057bb301ac8bcca87a7f5`

Two text entries in the pinned index carry hashes of their Windows CRLF checkout bytes rather than their LF Git blob bytes. The resolver records `git-checkout-crlf` for those entries and accepts them only after deterministic LF→CRLF normalization; the PNG remains `git-blob`. This distinction is explicit in `fixtures/design-context-html-slice/evidence/resolved-design-context.json` rather than being silently ignored.

## Ownership outcome

- Brain metadata/schema/index/evidence: unchanged by resolver and tests.
- Resolver/recorder implementation: this repository.
- HTML, screenshots, comparison, and QA reports: project-relative paths in this repository.
- Stable automatic promotion: absent and rejected by policy.
