---
name: agent-team-operations
description: Use when one conductor must coordinate or hand off a multi-session, multi-vendor team with shared work items, project-owned context, model/resource routing, stable artifacts, and explicit human gates. Use for deep planning lanes, team skills, worktree writers, and independent reviewers. Do not use for a solo bounded task, provider-native team configuration, or direct terminal control.
---

# Agent Team Operations

Operate a vendor-neutral team in which sessions and models are replaceable, project context is durable, and the user handles goals and meaningful gates instead of session mechanics.

## Resolve the source-of-truth layers

Before assigning work, find and distinguish:

1. the ecosystem policy and active model/resource roster;
2. the shared operating method and reusable role definitions;
3. the owner project's current goal, source ref, decisions, artifacts, and gates;
4. the provider runtime's actual Run, Task, Attempt, session, and receipt state.

Do not copy project facts into this skill or treat provider runtime files as the durable project record. If sources disagree, report the difference and defer to the owner project's rules for current execution state.

## Restore ownership before work

1. Read the nearest project instructions and stop file.
2. Read the project compact, active-work record, latest handoff, and current Goal or equivalent.
3. Re-measure Git, runtime, roster, resource admission, and dirty workspaces read-only.
4. ACK `ownerScope`, `sourceReference`, `activeConductor/ownershipEpoch`, `currentGate`, and `firstUsefulAction`.
5. Hold write ownership when an ownership-critical fact differs.

Use a restart-safe handoff method when the active conductor changes. A sent prompt, terminal title, or last lifecycle ID is not ownership.

## Classify the route

Declare one route before execution:

- `S` — one conductor can finish the bounded task safely;
- `M` — one or more independent bounded workers or a reviewer add clear value;
- `L` — new architecture, cross-project impact, high uncertainty, or high reversal cost.

Read exact model aliases, quotas, provider readiness, and hard gates from the active ecosystem roster. Select the smallest sufficient model and effort at runtime. Do not encode a permanent vendor ranking here.

If structured provider coordination is unavailable, downgrade honestly to `plan_only` or conductor-only work. Do not create imitation worker states or claim a dispatch occurred.

## Choose the work mode

- **Conductor-only** — one writer, one context, no coordination overhead.
- **Deep dialogue** — an independent top-level planning or design session talks with the user and returns a stable artifact after the design is mature.
- **Supervised team** — the conductor owns a Task DAG and waits for bounded workers.
- **Independent review** — a read-only reviewer evaluates a stable writer artifact, preferably with another verified model family.
- **Full handoff** — ownership moves to a new conductor; the previous owner stops supervising and writing after ACK.

Do not treat a deep dialogue session as a child worker. Do not mix a supervised lifecycle with a full-ownership handoff.

## Build the smallest useful team

For every role, record:

- role and owner;
- Task and acceptance criteria;
- dependencies;
- workspace and write scope;
- input context and excluded context;
- expected artifact;
- model/effort class and provider readiness;
- current status and next gate.

Use a Team Skill when a domain needs a repeatable adaptive method. Use a specialist worker when one bounded responsibility is enough. Keep one writer per workspace and run writer then reviewer serially when they touch the same artifact.

## Use the shared message contract

Only these structured message kinds change shared understanding:

- `task` — assignment, scope, acceptance, dependency;
- `result` — completed outcome and verification;
- `question` — a decision needed from the conductor or user;
- `blocker` — a condition preventing safe progress;
- `decision` — an approved choice, owner, and consequence;
- `artifact` — stable owner-project path, ref or digest, and approval state.

Direct peer messages are evidence, not authority. They cannot grant user consent, expand scope, or authorize production.

## Execute through the right adapter

When Orca or another structured runtime is ready, use its actual lifecycle:

`Run → Task → Attempt/Dispatch → result or question → completion receipt → release`

Record requested and observed provider/model identities separately. Preserve exact runtime receipts without making them the only durable copy of the result.

Use an applicable domain skill for the work itself. Compose rather than duplicate:

- a supervised-session conductor for live Task and lifecycle ledgers;
- restart-safe handoff for ownership transfer;
- a design or research team skill for domain discovery;
- provider orchestration for actual worker dispatch;
- project-specific Goal, VHK, Git, verification, and release contracts.

Use VHK only when the owner project has adopted it and its Goal or verification receipts add value. Do not turn VHK into a universal team runtime or require it in projects that use another contract.

## Converge through artifacts

A worker or deep dialogue lane is complete only when the next owner can consume a stable artifact without reconstructing the entire conversation. The packet includes:

- selected or implemented result;
- approved, rejected, deferred, and unresolved decisions;
- owner-project artifact path and immutable reference;
- constraints and forbidden changes;
- verification evidence and unverified scope;
- open severity-ranked issues;
- next owner and exact human gate.

The conductor reads the artifact, compares it with the current project state, and records a consumption ACK before implementation or the next team begins.

## Close and improve

At each wave end:

1. verify results and receipts;
2. update Task and artifact ownership;
3. release completed resources or retain them with a reason and expiry;
4. leave only the next one to three actions;
5. record friction, duplication, recovery time, and avoidable cost.

Keep project-specific learning in the owner project. Nominate a pattern for shared promotion only after it repeats across at least two independent project flows and can be stated without local paths, current session IDs, secrets, or project facts.

See [operating-manual.md](references/operating-manual.md) for the full start, dialogue, worker, review, handoff, and promotion procedure.
