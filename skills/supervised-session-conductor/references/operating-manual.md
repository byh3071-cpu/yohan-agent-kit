# Session operations manual

Use this manual to run a repeatable multi-role session without making chat history, one terminal, or one provider the source of truth. Project-owned evidence is authoritative; live surfaces provide current observations and delivery channels.

## Responsibility map

| Responsibility | Owner | Does not authorize |
| --- | --- | --- |
| user dialogue, work ledger, report reconciliation, final gate | active conductor | worker self-approval or release |
| bounded production or review result | named worker | takeover, user interview, or final acceptance |
| restart bundle, receipt, and guarded ownership transfer | `restart-safe-handoff` | root-cause conclusions |
| read-only failure timeline and hypotheses | `runtime-incident-investigator` | remediation or ownership transfer |
| domain approval and artifact semantics | installed domain skill, such as `design-team` | replacing the generic ownership contract |
| approval at a named hard gate | named human decision maker | authority beyond the stated scope |

One incident may invoke several skills, but each claim keeps its owner. An incident report does not become a handoff receipt, a handoff acknowledgement does not verify the deliverable, and a worker lifecycle signal does not replace content review.

## Start the run

1. Read the nearest project rules, stop files, active work record, allowed writes, and current evidence.
2. Declare one active conductor and one ownership epoch for the supervised scope.
3. Give each work item a stable ID, outcome, bounded scope, owner, promised report, expected lifecycle signal, validation contract, and prohibited actions.
4. Record the one next human gate. A backlog is not a gate.
5. Prefer separate workspaces when local rules require isolation. Never create concurrent writers in the same mutable scope merely to increase throughput.

If another conductor appears active, stop at read-only reconciliation. Route evidence to that owner or use the guarded transfer contract; do not race it.

## Operate the evidence ledger

Observe these channels independently:

- **content** — report, artifact, revision, validation, and residual risk;
- **lifecycle** — running, waiting, exited, failed, or an observed completion signal;
- **delivery** — prepared, sent, acknowledged, or failed for a named target;
- **ownership** — active writer, epoch, liveness evidence, and transfer authority;
- **approval** — exact artifact or decision, consequence, decider, and scope.

Every update cites a stable work item and evidence reference. Silence preserves the last supported state; it does not promote or demote the item by itself.

| Content | Lifecycle | Supported conclusion | Next action |
| --- | --- | --- | --- |
| present and verified | completion signal matched | result is ready for conductor synthesis | review conflicts and open the named gate |
| present | completion unresolved | content can be reviewed; worker state is open | inspect the smallest lifecycle source |
| absent | completion observed | process state is known; promised result is missing | obtain a stable result or failure report |
| absent | unresolved | no completion claim is supported | distinguish wait, loss, and failure read-only |

## Handle conflict and interruption

For competing design, QA, implementation, or investigation findings, preserve both claims with their criteria, revisions, and risks. The conductor presents one human gate with explicit alternatives and consequences. Do not average incompatible findings or let the latest message win.

When a local resource or runtime guard requires interruption:

1. stop adding workers or retries;
2. preserve the current project-owned bundle, source reference, dirty state, and validation evidence;
3. checkpoint authorized changes when safe, or record exact uncommitted paths when it is not;
4. close only the session whose work is durably accounted for;
5. keep unrelated live sessions untouched;
6. resume through `restart-safe-handoff` if ownership or delivery crosses a session boundary.

A process exit, timeout, terminal closure, runtime restart, or failed send does not grant takeover. If failure cause is unclear, switch to `runtime-incident-investigator` and keep remediation outside diagnosis until separately authorized.

## Resume after a restart

The receiver reads current project rules and stop files, verifies the source reference and dirty state, resolves the active writer and ownership epoch, and validates the content and delivery receipts separately. It then acknowledges the owner scope, current gate, and first useful action.

If the bundle and live evidence conflict, preserve both and report the contradiction. Do not blend branches, revisions, approval states, or liveness claims. Takeover requires the authority and receipt defined by `restart-safe-handoff`.

## Close the run

Close only when every work item is one of:

- verified result with matched evidence;
- evidence-backed failure with a bounded next recovery action;
- explicit unresolved conflict at one human gate;
- intentionally deferred item with owner and freshness trigger.

The final report states active owner, source reference, verified results, missing evidence, conflicts, residual risk, delivery state, and exactly one next gate. Commit, push, release, deployment, publication, production mutation, credentials, paid calls, and external transmission remain governed by the nearest project rules and explicit authority.

## Portable live-operation boundary

This manual stores no terminal commands, provider versions, machine paths, or private session text. When live coordination is required, load the installed runtime-specific guide named by the owning skill and use only observed handles and receipts. If that guide or runtime is unavailable, continue from project-owned evidence and report live state as unknown.
