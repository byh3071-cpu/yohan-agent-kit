# Goal 17 repo-local implementation result

Date: 2026-08-26 (Asia/Seoul)
Source: `origin/main@e8717e2c2e55cf43b530db584a0f2b9d06f3d82a`
Owner scope: Yohan Agent Kit Goal 17 implementation and fixture verification, single writer
Conductor: `term_423c2554-69e9-417b-9588-4bde46065086`, ownership epoch 4

## Status transitions

- ADR frontmatter and body now agree on `Accepted`.
- The implementation plan is `IN_PROGRESS`; Goal 17 remains `IN_PROGRESS`.
- Actual HomeRoot, Git delivery, paid smoke, rollout, and Goal completion remain human-gated.

## Stable diff

- `scripts/Manage-MultivendorSkills.ps1`: contract/transaction schema 5; Claude-only `claude-code-personal-physical-copy`; deterministic provenance and installed-tree digest; source/drift/PlanDigest binding; schema 3/4/5 Restore; exact-move preservation and recovery of a matching Junction.
- `tests/Manage-MultivendorSkills.Tests.ps1`: contract 5 red assertion, Claude adapter planning and sealing, drift/no-overwrite, schema 3/4/5 Restore, exact Junction identity, and interrupted migration rollback.
- Distribution docs, Goal 8, and the two-machine runbook now distinguish filesystem `Healthy` from fresh Claude discovery.
- `scripts/check-goal-17.mjs`, `registry/assets.yaml`, and `distribution/asset-catalog.json` add and publish the deterministic Goal 17 gate.
- No file under `skills/` or `distribution/manifests/` changed; no historical audit changed.

## Red to green

- Red receipt: `tests/.work/run-20260826-225427854-36724`; the unmodified manager reported contract 4 where the new assertion required contract 5.
- Green receipt: `tests/.work/run-20260826-231634162-11776`; the full manager suite passed 275 assertions.
- Fixture coverage includes Install, Restore, internal rollback, interrupted Junction quarantine, deterministic metadata, and exact NTFS Junction identity preservation.

## Compatibility evidence

Origin/main and the changed manager produced identical compatibility values:

| Contract surface | SHA-256 |
| --- | --- |
| AGY adapter digest | `85D9245406071A35B56476CFDF76556BDDBF3C767C7EFAA804C32AE1C4D20538` |
| schema 3 install seal | `126755DF9FBB143CFF87F57B4D6336F1090C8D324BBE0738FA46BDEFB4886AF8` |
| schema 3 commit seal | `E7570C03B10BB44772421D5822A9D6E5AB0D8EB522AB6D04C8D65B153A7C38AD` |
| schema 4 install seal | `FBE0FB1825F12674EC466070CBDAD8482C31C8C694A00F2C1B2E1A3E338DA6EF` |
| schema 4 commit seal | `D5F602EC0DA9E3F142DC542DEE12BCF768EA9702E6BC6A644F05BFBAF6651122` |

AGY deterministic metadata bytes were also identical.

## Verification

| Gate | Result |
| --- | --- |
| PowerShell parser | PASS |
| Full manager tests | PASS, 275 assertions |
| Goal 1 | PASS |
| Goal 8 `--local` | FAIL, isolated environment contract mismatch described below |
| Goal 15 | PASS |
| Goal 17 | PASS |
| Asset catalog self-test and validator | PASS, 220 assets, catalog digest `24308392fcd112251358038e252d4394f7e1fba6f966d885e1022ee956942c4b` |
| Agent Kit repo-local fixture build | PASS, 289 files, manifest digest `712c5341a527baccb0bd8fff860cc036833851a85a72c2715ae80d69aea5426b` |
| `git diff --check` | PASS |

Goal 8 static checks and its vendor smoke runner passed 101 assertions. Its local evidence contract then failed only at `vendor CLI versions match the release contract` (`Expected=[PASS] Actual=[FAIL]`), which reflects installed tool-version drift rather than the Goal 17 manager changes; the test and compatibility contract were not weakened.

## Boundaries and remaining work

- No actual user HomeRoot was passed to the multivendor manager, and no actual HomeRoot Check, Install, or Restore was performed.
- No commit, push, PR, merge, tag, deployment, publish, external provider call, paid smoke, recursive deletion, or worktree deletion was performed.
- Independent read-only review remains outstanding.
- After primary merge, the remaining discovery risk must be resolved by an approved actual-home canary and a fresh `--bare` Claude smoke with repository/plugin shadow excluded.
