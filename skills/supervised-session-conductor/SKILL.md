---
name: supervised-session-conductor
description: Use when one active session must supervise multiple workers or producers, reconcile ownership, reports, completion signals, and conflicts, then present one final human gate. Do not use for solo task tracking, terminal control, restart handoff, or root-cause investigation.
---

# Supervised session conductor

Own the dialogue and evidence ledger for one supervised run. Workers may produce evidence; only the active conductor synthesizes it for the user.

## Establish ownership

Read the nearest project rules, stop files, allowed writes, and current run evidence before dispatching or accepting work. Record one active conductor, the supervision scope, and an ownership epoch. A worker report, terminal stream, or prior transcript is evidence, not a second conductor.

Keep a ledger with enough stable identifiers to reconcile independent channels:

| Field | Required meaning |
| --- | --- |
| work item | stable ID, requested outcome, bounded scope |
| ownership | active owner, conductor, ownership epoch |
| attempt | dispatch or contact attempt and its observed result |
| report | stable report or artifact reference, revision, and review state |
| completion signal | observed lifecycle signal such as `worker_done`, with source |
| freshness | last observation and the trigger that makes it stale |
| conflict | competing claims, evidence, and unresolved decision |
| next gate | one next operator or human decision |

Do not create a second writer while the recorded coordinator is alive. If ownership is unclear, inspect read-only evidence and preserve the lower claim. A restart or takeover belongs to `restart-safe-handoff`, not to ordinary supervision.

When a run spans multiple roles, interruption recovery, or a final decision conflict, read the [session operations manual](references/operating-manual.md) for the end-to-end routing and closure flow. Keep this skill as the dialogue owner; the manual does not merge worker responsibilities.

## Reconcile reports and lifecycle signals

Treat content and runtime state as independent:

- A report without `worker_done` may be reviewed, but worker lifecycle and final completion remain unresolved. Do not redispatch blindly.
- `worker_done` without a report proves only that a lifecycle signal was observed. Require the promised result or a stable failure report before closing the work item.
- When both exist, match work ID, owner, revision, scope, and timestamps before accepting them as one outcome.
- When neither exists, retain the last supported state and choose the smallest read-only check that distinguishes waiting, loss, and failure.

Report the highest state supported by both the ledger and current evidence. Never translate silence, a successful send, or an unreviewed report into completion.

## Resolve conflicts at one final gate

Record conflicting findings without averaging them. For example, if a design result and a QA result disagree, keep each artifact, criterion, evidence source, and residual risk. The conductor presents one compact final gate containing the exact alternatives, consequences, and stable references. Only the named human decision closes that conflict.

Workers do not interview the user independently, issue competing final answers, or self-approve their work. After the gate, record the decision and propagate it to the ledger.

## Use live coordination conditionally

When structured live coordination is required and the installed `orchestration` skill is available, load its version-matched live guide before any call. Do not cache or invent its commands. Route ownership transfer or managed terminal/worktree operations to the installed `orca-cli` skill and its live guide instead. If the relevant live skill or runtime evidence is unavailable, continue only with project-owned evidence and mark runtime state unknown.

Stop supervision when the ledger is reconciled and the next state is either a verified result, an evidence-backed failure, or one explicit human gate. Do not mutate production, release, or external systems unless the user separately authorized that action.
