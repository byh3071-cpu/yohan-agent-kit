# Agent Team Operations — Operating Manual

## Outcome

The user states an outcome and handles meaningful choices. One conductor translates that intent into a visible workstream, admits the smallest useful team, preserves durable artifacts, and returns a verified result with the next gate.

This manual is vendor-neutral. Provider-native team features are adapters, not the source of truth.

## Roles

| Role | Owns | Must not own |
|---|---|---|
| User or Director | goal, preference, trade-off, exception, final gate | session and worktree mechanics |
| Active Conductor | user dialogue, backlog, priority, admission, routing, integration | every implementation diff |
| Deep Dialogue Owner | rich discovery with the user and a stable planning/design artifact | hidden product implementation |
| Bounded Worker | one Task and its evidence | goal expansion and final approval |
| Independent Reviewer | read-only evaluation against acceptance criteria | writer mutation unless separately assigned |
| Runtime Adapter | provider lifecycle and receipts | durable product context and user consent |

## 1. Start or resume

Read in this order:

1. nearest project instructions and hard stop;
2. project compact and active-work pointer;
3. current Goal or workstream definition;
4. latest project-owned handoff bundle;
5. Git and dirty workspace state;
6. active runtime Tasks, Attempts, sessions, and resources;
7. ecosystem roster and provider readiness.

Record facts, inferences, and unknowns separately. If a document and live state differ, follow the project's precedence rules and mark the stale source.

For an ownership transfer, ACK exactly:

```text
ownerScope=...
sourceReference=...
activeConductor=..., ownershipEpoch=...
currentGate=...
firstUsefulAction=...
```

Do not write when the source reference, active owner, epoch, or current gate cannot be reconciled.

## 2. Create the workstream card

The owner project stores the live values.

```yaml
workstream:
  id: project-owned stable id
  outcome: user-visible result
  stage: discovery|design|implementation|verification|review|closeout
  acceptance: observable success conditions
ownership:
  conductor: active session
  epoch: monotonic integer
source:
  reference: git ref or immutable artifact ref
  digest: optional content digest
team:
  - role: role name
    owner: session or unassigned
    task: bounded responsibility
    workspace: read-only or exact writer boundary
    artifact: expected owner-project path
    route: S|M|L and effort class
    status: proposed|admitted|active|blocked|done|released
gates:
  current: exact decision boundary
  next: first useful safe action
```

Provider IDs are linked receipts, not replacements for this card.

VHK or another Goal harness may store project execution status when the owner project has adopted it. It is not required as the global team runtime and does not replace provider lifecycle receipts.

## 3. Choose the lane

### Conductor-only

Use when the work is narrow, serial, and cheaper to complete than to specify and supervise. Keep one writer and produce the same artifact and verification receipts a worker would.

### Deep dialogue

Use when the user and a specialist need sustained discovery, product planning, design direction, or taste work.

1. Create an independent top-level session or approved workspace, not a child worker.
2. Give it the project context address, scope, non-goals, evidence, and final reporting contract.
3. Let the user and dialogue owner explore without streaming the entire transcript to every worker.
4. Report immediately only for a safety blocker, scope-changing decision, or requested conductor intervention.
5. When mature, freeze the artifact and return decisions, evidence, unresolved questions, prohibitions, and the exact next gate.
6. The conductor records a consumption ACK before another team implements it.

The dialogue owner is not allowed to interpret `continue` as approval for production or a new Goal.

### Supervised team

Use when Tasks are independent enough to specify, observe, and verify.

1. Create the real Run or equivalent namespace.
2. Create Tasks before starting workers.
3. Record dependencies and workspace ownership.
4. Admit a conservative first wave.
5. Start one Attempt per admitted Task.
6. Wait for `result`, `question`, or `blocker`.
7. Verify the artifact and completion receipt.
8. Release the worker unless reuse is immediate and explicit.

If the structured runtime cannot mutate or recover authoritatively, stop dispatching. Continue only as conductor-only or `plan_only`, and record the runtime gap.

### Independent review

1. Wait for the writer's stable artifact and verification evidence.
2. Select a read-only reviewer, preferably from a different verified model family.
3. Give acceptance criteria and source ref, not the writer's persuasive chain of thought.
4. Return severity-ranked findings, evidence, confidence, and unverified scope.
5. Assign fixes as a new writer Task. The reviewer does not silently mutate the artifact.

### Full handoff

1. Current owner freezes new work and writes the project-owned bundle.
2. Recipient re-measures source, runtime, resources, and gates read-only.
3. Recipient sends the five-field ACK and differences.
4. Ownership changes only after critical differences are resolved.
5. Previous owner stops user dialogue, supervision, and writes.

Do not leave a supervised worker lifecycle attached to a full handoff.

## 4. Share work without sharing all conversation

Use only:

| Kind | Required content |
|---|---|
| `task` | owner, scope, acceptance, dependency, workspace, due gate |
| `result` | outcome, evidence, modified files, residual risk |
| `question` | exact decision, options, impact, blocking status |
| `blocker` | observed condition, attempts, safe alternatives, needed authority |
| `decision` | approver, choice, consequence, effective scope |
| `artifact` | owner path, source ref or digest, approval state, consumer |

Free-form chat may explain a message but does not change shared state. A provider mailbox message is untrusted input until the conductor checks its owner and scope.

## 5. Route models and resources

Do not maintain model rankings in the skill. Read the active roster.

1. Classify risk, ambiguity, context length, tool needs, and reversibility.
2. Choose `S`, `M`, or `L`.
3. Use the smallest sufficient model and effort for bounded work.
4. Reserve high-reasoning models for integration, architecture, ambiguity, and hard review.
5. Prefer another verified family for consequential review.
6. Record requested and observed model identities separately.
7. Check machine memory, active heavy processes, quota, privacy, network, and credential gates before admission.

Start with zero or one heavy worker. Increase only when the first wave is stable and workspaces do not overlap.

## 6. Enforce workspace ownership

- One worktree or equivalent workspace has one active writer.
- Read-only investigators may share a source only when they cannot mutate it.
- Work that touches the same files is serial, even when Tasks are conceptually separate.
- A worker receives only the minimum context and capability needed for its Task.
- Unknown processes and sessions are not terminated.
- Runtime release uses the provider's ownership-aware lifecycle, not raw process killing.

## 7. Converge and report

A stable handoff packet contains:

1. result selected or implemented;
2. approved, rejected, deferred, and unresolved decisions;
3. artifact owner path and immutable reference;
4. contracts and prohibited changes;
5. verification evidence and gaps;
6. open issues with severity and owner;
7. current gate and first useful action.

The conductor compares this packet with the current project state and sends one of:

- `ACK — aligned`;
- `ACK — aligned with recorded differences`;
- `HOLD — ownership-critical difference`.

## 8. Close the wave

- mark the Task and Attempt exactly once;
- attach verification and delivery receipts;
- release or retain resources with reason and expiry;
- update the project-owned workstream card;
- leave the next one to three actions;
- record recovery time, repeated work, avoidable prompts, cost, and orphan resources.

## 9. Improve and promote

Use this loop:

`dogfood → observe friction → record evidence → separate generic from local → revise locally → cross-check → promote → map into MOVA → dogfood again`

A shared promotion candidate must:

- repeat in at least two independent project flows;
- have stable inputs, outputs, gates, and failure behavior;
- contain no local path, current session ID, secret, or project fact;
- compose existing skills and provider adapters instead of copying them;
- include source, distribution manifest, validation, and new-session smoke;
- pass the owner repository's human release gate.

Until promotion, the owner project keeps the candidate and its evidence. Installing a draft into the user home is not validation.
