# DesignContext contract

Design Team maintains context in two layers so the operating method can travel without leaking or freezing project-specific facts.

## Layer A — shared method

The skill repository owns reusable workflow, role definitions, report formats, and validated cross-project patterns. A project run may nominate a learning, but it must not rewrite shared guidance automatically. Promotion requires evidence that the pattern generalizes and a human review in the shared owner repository.

## Layer B — project context

The owner project owns its users, domain constraints, decisions, design system, references, generated assets, and production evidence. Reuse an existing versioned documentation convention. Git-backed projects may use:

```text
docs/design/<workstream>/design-context.md
docs/design/<workstream>/decision-log.md
docs/design/<workstream>/research.md
docs/design/<workstream>/directions/
docs/design/<workstream>/design-spec.md
docs/design/<workstream>/handoff.md
```

For non-Git work, use the project's approved versioned workspace, document control, asset management, or quality system and keep stable identifiers there. Do not create parallel sources of truth. Link to existing briefs, requirements, decision records, issue trackers, design files, asset catalogs, vendor proofs, or controlled documents instead of copying their full content.

## Required context fields

Maintain a readable DesignContext snapshot in the owner's approved documentation format, using Markdown where permitted, with these equivalent fields:

```markdown
# DesignContext: <project or workstream>

- Context version:
- State: discovery | exploring | selected | specified | implemented | verified
- Owner workspace or repository and source version/ref:
- Last verified at:
- Design owner / final approver:

## Outcome and non-goals
## Users and jobs to be done
## Domain and risk level
## Surfaces, media, platforms, dimensions, and environmental context
## Current product state
## Existing design system and assets
## Information and content contracts
## Technical and operational constraints
## Approval and safety boundaries
## Evidence ledger
## Accepted decisions
## Rejected or deferred decisions
## Open questions and contradictions
## Freshness and next verification
```

Every material statement carries one state:

- **Observed** — directly verified in code, artifact, interview, analytics, or authoritative source.
- **Inferred** — a reasoned conclusion that still needs confirmation.
- **Proposed** — an option awaiting the design director.
- **Approved** — explicitly selected by an authorized human, with date and evidence.
- **Rejected** — explicitly declined, with the reason needed to avoid repeating it.
- **Stale** — previously valid but past its stated freshness or contradicted by newer evidence.

## Evidence ledger

For each source record:

- stable source identifier or project-relative path;
- source owner and type;
- Git ref, content hash, version, or retrieval date when available;
- what claim the source supports;
- access/privacy class;
- freshness or recheck condition.

Never persist secrets, credentials, private raw customer data, hidden prompts, or unredacted configuration. Record only the minimum safe reference needed to re-resolve context.

## Decision log

Record one decision event per human decision in the project's approved audit trail, append-only where supported:

```markdown
## YYYY-MM-DD — <decision>

- Status: approved | rejected | deferred | superseded
- Decider:
- Options considered:
- Decision and rationale:
- Evidence:
- Consequences:
- Revisit trigger:
```

Update the current snapshot after appending the event. Never erase a rejected direction merely because a later direction wins.

## Session continuity

At the beginning of each design session:

1. Resolve the closest current snapshot and decision log.
2. Re-check rules, active work, source refs, and any freshness triggers.
3. Summarize what is known, what changed, and what still needs a human decision.

At the end:

1. Save only verified observations, explicit decisions, and clearly labeled open questions.
2. Link generated artifacts and verification evidence from the owner project.
3. Record the next gate and exact continuation point.

This is the skill's durable project memory. Conversation history is a convenience, never the source of truth. Git is preferred where the project already uses Git, but Git is not imposed on physical, service, regulated, or vendor-controlled work.
