---
name: restart-safe-handoff
description: Use when work must survive a session, process, machine, or conductor restart with a durable bundle, separate content and delivery receipts, and guarded writer takeover. Do not use for live worker supervision, routine status summaries, or incident root-cause analysis.
---

# Restart-safe handoff

Preserve enough project-owned state for a receiver to resume at the exact next gate without trusting chat history or creating a second writer. This minimum contract is complete even when this is the only installed skill.

## Prepare the durable bundle

Use the owner's existing versioned documentation convention rather than creating a parallel source of truth. A bundle resolves:

- owner scope, workstream, source reference, branch or artifact revision, and dirty state;
- current state, verified results, open conflicts, stale claims, and freshness triggers;
- exact next human or operator gate and the first useful action;
- allowed writes, forbidden actions, external boundaries, and required approvals;
- stable pointers to decisions, reports, artifacts, and validation evidence;
- active writer, ownership epoch, receiver, and handoff receipt state.

Point to durable project records instead of copying private conversation or large artifacts. Include only the context the receiver is authorized to access.

## Keep attempts and receipts distinct

A handoff attempt is an event, never proof of receipt. Record attempts separately, including target, channel or mechanism, observed response, and failure evidence.

Maintain two independent receipts:

1. **Content receipt** — bundle ID, source reference, revision or digest, scope, preparer, and whether the content was verified current.
2. **Delivery receipt** — named target, accepted channel event, receiver acknowledgement, acknowledgement evidence, and acknowledged next gate.

Content may be `absent`, `prepared`, `verified`, `stale`, or `conflicted`. Delivery may be `not-sent`, `sent`, `acknowledged`, or `failed`. A channel accepting a payload supports `sent`, not `acknowledged`. The receiver acknowledgement must identify the owner scope, source reference, current gate, and exact next action.

Do not resend blindly after a failed attempt. Re-resolve the target and preserve the failed attempt so duplicate delivery cannot masquerade as recovery.

## Block duplicate writers and unsafe takeover

Before writing, resolve the active writer, ownership epoch, and current liveness evidence.

- If the coordinator is alive, do not take over. Route evidence to the current owner or wait at the recorded gate.
- If liveness is unknown, inspect read-only sources and keep ownership unresolved.
- Take over only with explicit authority and evidence that the prior writer is stale, unreachable, or has yielded. Persist a takeover receipt and increment the ownership epoch before the new writer mutates shared state.
- After takeover, the prior writer is read-only. If it resumes or produces conflicting updates, preserve both revisions and open a conflict instead of overwriting either one.

No timeout, process disappearance, send failure, or terminal closure alone grants takeover authority.

## Resume and acknowledge

The receiver reads the nearest rules and stop files, resolves every stable pointer needed for the next gate, verifies source and dirty state, separates inherited decisions from stale claims, and then acknowledges the owner scope, source reference, active writer and epoch, current gate, and exact next action. If live evidence contradicts the bundle, report the contradiction and do not blend the states.

When delivery uses a managed session, worktree, or terminal and the installed `orca-cli` skill is available, load its version-matched live guide before any call. For a supervised coordination graph, use the installed `orchestration` skill instead. Do not store commands or versions here, and do not claim delivery beyond the observed receipt.

## Domain extensions

When the `design-team` skill is also available, read its [design session continuity contract](../design-team/references/session-continuity.md) as a domain extension. It adds design approval, taste, artifact visibility, and production-boundary semantics; it does not replace this skill's generic bundle, ownership, or receipt rules.
